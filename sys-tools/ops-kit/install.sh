#!/usr/bin/env bash
#
# sys-tools/ops-kit/install.sh
# 用法: ops-kit {inspect|log|svc|audit|install|uninstall|status|help}
#
# 运维工具箱 —— inspect 聚合巡检 + log/svc/audit 三组日常运维（仅 Linux）。
# 只读优先；写操作 = 显式参数 + 交互确认 + 全局 --dry-run。
#
# 子命令:
#   inspect [--json]     聚合巡检：磁盘/SMART/失败服务/journal/SSH/公网端口/更新/登录失败
#   log status|vacuum <200M|2weeks>|rotate list|show|apply <app>
#   svc failed|status <unit>|logs <unit> [n]|start|stop|restart|enable|disable <unit>
#   audit ssh|ports|updates|all
#   status | help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OPS_OK='✅'; OPS_WARN='⚠️ '; OPS_CRIT='🔴'; OPS_SKIP='⬜'
OPS_LOGROTATE_DIR="${OPS_LOGROTATE_DIR:-/etc/logrotate.d}"

# ============================================================
# 平台（仅执行路径；source 时不触发，单测可复用纯函数）
# ============================================================
_ops_platform_check() {
    if [[ "${OS_TYPE:-}" == "darwin" ]]; then
        info "ops-kit 运维工具箱仅支持 Linux（依赖 systemd），macOS 不适用。"
        exit 0
    fi
}

# ============================================================
# 纯函数区（参数进、stdout 出；不调用采集命令，macOS 可单测）
# ============================================================

_ops_size_to_mb() {
    local s="${1:-}" num unit
    [[ "$s" =~ ^([0-9]+(\.[0-9]+)?)([KMGTP]?)(B?)$ ]] || { echo 0; return; }
    num="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[3]}"
    case "$unit" in
        ""|B) num=$(awk "BEGIN{printf \"%d\", $num/1048576}") ;;
        K)    num=$(awk "BEGIN{printf \"%d\", $num/1024}") ;;
        M)    num=$(awk "BEGIN{printf \"%d\", $num}") ;;
        G)    num=$(awk "BEGIN{printf \"%d\", $num*1024}") ;;
        T)    num=$(awk "BEGIN{printf \"%d\", $num*1048576}") ;;
        P)    num=$(awk "BEGIN{printf \"%d\", $num*1073741824}") ;;
    esac
    echo "$num"
}

_ops_df_parse() {
    # df -P 输出 → "挂载点|使用率整数"；剔除伪文件系统
    echo "$1" | awk 'NR>1 && $1 !~ /^(tmpfs|devtmpfs|overlay|loop|squashfs|udev|none)$/ && NF>=6 {gsub(/%/,"",$5); print $6"|"$5}' | grep -v '|$' || true
}

_ops_journal_usage_parse() {
    # "Archived and active journals take up 3.9G in the file system." → 3.9G
    echo "$1" | grep -oE 'take up [0-9]+(\.[0-9]+)?[KMGT]' | awk '{print $3}' || true
}

_ops_ss_parse() {
    # ss -tulpn 输出 → "proto|本地地址|进程"，仅 LISTEN。
    # 地址列兼容完整表头与极简输出；进程优先 users:(( 提取。不用 \( 转义 regex——macOS BWK awk 报 extra )
    echo "$1" | awk 'NR>1 && $2=="LISTEN" {
        addr="";
        for (i=3;i<=NF;i++) if ($i ~ /:/ && $i !~ /^[0-9]+$/) { addr=$i; break }
        proc="unknown";
        i=index($0, "users:((\"");
        if (i>0) { rest=substr($0, i+9); q=index(rest, "\""); if (q>1) proc=substr(rest, 1, q-1) }
        else if (NF>=4) proc=$NF;
        print $1"|"addr"|"proc}' | grep -v '||' || true
}

_ops_is_public_addr() {
    # 公网监听地址 → 0（是）；回环/私网/空/非地址 token → 1
    local a="$1"
    [[ -z "$a" ]] && return 1
    case "$a" in
        127.*|::1*|\[::1\]*|\[::1\]:*) return 1 ;;
        0.0.0.0*|\[::\]*|\[::\]:*) return 0 ;;
        10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*|169.254.*|fe80*|\[fe80*) return 1 ;;
        *:*|*.*) return 0 ;;
        *) return 1 ;;
    esac
}

_ops_lastb_count() {
    printf '%s\n' "$1" | grep -cvE '^[[:space:]]*$|^btmp begins' || true
}

_ops_failed_units() {
    printf '%s\n' "$1" | awk 'NF && $1 ~ /\.(service|timer|socket|mount|target)$/ {print $1}' || true
}

_ops_sshd_one() {  # <小写文本> <键> → 值（空=未设置）
    printf '%s\n' "$1" | awk -v k="$2" '$1==k{print $2; exit}'
}

_ops_sshd_check() {
    # sshd -T / sshd_config 文本 → 每行 "级别|键=值"（ok|warn|crit）
    local val
    local low; low=$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g')
    val=$(_ops_sshd_one "$low" permitrootlogin)
    case "${val:-unset}" in
        prohibit-password|no|unset) echo "ok|permitrootlogin=${val:-unset}" ;;
        yes) echo "crit|permitrootlogin=yes" ;;
        *)   echo "warn|permitrootlogin=$val" ;;
    esac
    val=$(_ops_sshd_one "$low" passwordauthentication)
    case "${val:-no}" in
        no|unset) echo "ok|passwordauthentication=${val:-unset}" ;;
        yes) echo "warn|passwordauthentication=yes" ;;
        *)   echo "warn|passwordauthentication=$val" ;;
    esac
    val=$(_ops_sshd_one "$low" maxauthtries)
    if [[ -z "$val" ]]; then echo "ok|maxauthtries=unset(default 6)"
    elif (( val <= 5 )); then echo "ok|maxauthtries=$val"
    elif (( val <= 10 )); then echo "warn|maxauthtries=$val"
    else echo "crit|maxauthtries=$val"; fi
    val=$(_ops_sshd_one "$low" x11forwarding)
    case "${val:-no}" in
        no|unset) echo "ok|x11forwarding=${val:-unset}" ;;
        *) echo "warn|x11forwarding=$val" ;;
    esac
}

_ops_updates_count() {
    local n; n=$(printf '%s\n' "$1" | grep -oE '[0-9]+' | head -1)
    echo "${n:-0}"
}

_ops_json_escape() { printf '%s' "${1:-}" | tr -d '"\\' ; }

# ============================================================
# inspect 聚合巡检（只读）
# ============================================================
OPS_CHECKS=''; OPS_JSON=''; OPS_CRIT_N=0; OPS_WARN_N=0

_ops_check_add() {  # <级别 ok|warn|crit|skip> <名称> <详情>
    local lvl="$1" name="$2" detail="$3" icon
    case "$lvl" in
        ok)   icon="$OPS_OK" ;;
        warn) icon="$OPS_WARN"; OPS_WARN_N=$((OPS_WARN_N+1)) ;;
        crit) icon="$OPS_CRIT"; OPS_CRIT_N=$((OPS_CRIT_N+1)) ;;
        *)    icon="$OPS_SKIP"; lvl=skip ;;
    esac
    OPS_CHECKS+="${icon} ${name}：${detail}"$'\n'
    OPS_JSON+="${OPS_JSON:+,}{\"name\":\"$(_ops_json_escape "$name")\",\"level\":\"$lvl\",\"detail\":\"$(_ops_json_escape "$detail")\"}"
}

# 包管理器待更新计数 → "计数"（无包管理器输出空）
_ops_collect_updates() {
    if command -v apt-get >/dev/null 2>&1; then
        printf 'apt %s' "$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || true)"
    elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf %s' "$(dnf -q check-update 2>/dev/null | grep -cE '^\S+[[:space:]]' || true)"
    elif command -v yum >/dev/null 2>&1; then
        printf 'yum %s' "$(yum -q check-update 2>/dev/null | grep -cE '^\S+[[:space:]]' || true)"
    elif command -v pacman >/dev/null 2>&1; then
        printf 'pacman %s' "$(pacman -Qu 2>/dev/null | grep -c . || true)"
    elif command -v apk >/dev/null 2>&1; then
        printf 'apk %s' "$(apk version -l '<' 2>/dev/null | grep -c '^<' || true)"
    else
        echo ""
    fi
}

cmd_inspect() {
    local json=0
    [[ "${1:-}" == "--json" ]] && json=1
    OPS_CHECKS=''; OPS_JSON=''; OPS_CRIT_N=0; OPS_WARN_N=0

    # 1) 磁盘空间（>80 ⚠️ / >90 🔴）
    if command -v df >/dev/null 2>&1; then
        local dline mount pct worst=0 wline=''
        while IFS= read -r dline; do
            [[ -z "$dline" ]] && continue
            mount="${dline%%|*}"; pct="${dline##*|}"
            [[ "$pct" =~ ^[0-9]+$ ]] || continue
            (( pct > worst )) && { worst=$pct; wline="$mount"; }
            if   (( pct >= 90 )); then _ops_check_add crit "磁盘空间 $mount" "已用 ${pct}%"
            elif (( pct >= 80 )); then _ops_check_add warn "磁盘空间 $mount" "已用 ${pct}%"; fi
        done < <(_ops_df_parse "$(df -P 2>/dev/null)")
        (( worst > 0 && worst < 80 )) && _ops_check_add ok "磁盘空间" "最大使用率 ${worst}%（$wline）"
        (( worst == 0 )) && _ops_check_add ok "磁盘空间" "无真实文件系统可报"
    else
        _ops_check_add skip "磁盘空间" "df 不可用"
    fi

    # 2) SMART 总评（装了 smartmontools 才查）
    if command -v smartctl >/dev/null 2>&1; then
        local sdev sh
        for sdev in /dev/sd? /dev/nvme?; do
            [[ -e "$sdev" ]] || continue
            sh=$(sudo -n smartctl -H "$sdev" 2>/dev/null || smartctl -H "$sdev" 2>/dev/null || true)
            if [[ -z "$sh" ]]; then _ops_check_add skip "SMART $sdev" "读不到（权限/USB 桥/RAID 背板）"
            elif printf '%s' "$sh" | grep -q PASSED; then _ops_check_add ok "SMART $sdev" "PASSED"
            else _ops_check_add crit "SMART $sdev" "总评非 PASSED——详情: sudo smartctl -H $sdev"; fi
        done
        [[ -z "${sh:-}" && ! -e /dev/sda && ! -e /dev/nvme0 ]] && _ops_check_add skip "SMART" "未发现 sd/nvme 整盘"
    else
        _ops_check_add skip "SMART" "未安装 smartmontools"
    fi

    # 3) systemd 失败单元
    if command -v systemctl >/dev/null 2>&1; then
        local sysstate; sysstate=$(systemctl is-system-running 2>/dev/null || true)
        if [[ -z "$sysstate" ]]; then
            _ops_check_add skip "systemd" "不可用（容器/无 systemd）"
        else
            local fu; fu=$(_ops_failed_units "$(systemctl --failed --no-legend 2>/dev/null || true)")
            if [[ -z "$fu" ]]; then _ops_check_add ok "systemd" "无失败单元"
            else _ops_check_add crit "systemd 失败单元" "$(printf '%s ' $fu)——排查: ./install.sh ops-kit svc failed"; fi
        fi
    else
        _ops_check_add skip "systemd" "systemctl 不可用"
    fi

    # 4) journal 占用（>2G ⚠️）
    if command -v journalctl >/dev/null 2>&1; then
        local jmb; jmb=$(_ops_size_to_mb "$(_ops_journal_usage_parse "$(journalctl --disk-usage 2>/dev/null || true)")")
        if   (( jmb >= 2048 )); then _ops_check_add warn "journal 占用" "${jmb}MB——清理: ./install.sh ops-kit log vacuum 200M"
        else _ops_check_add ok "journal 占用" "${jmb}MB"; fi
    else
        _ops_check_add skip "journal" "journalctl 不可用"
    fi

    # 5) SSH 基线摘要
    local sshout=''
    if command -v sshd >/dev/null 2>&1; then
        sshout=$(sshd -T 2>/dev/null || sudo -n sshd -T 2>/dev/null || true)
    fi
    [[ -z "$sshout" ]] && sshout=$(grep -RhiE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication|MaxAuthTries|X11Forwarding)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null || true)
    if [[ -n "$sshout" ]]; then
        local sline sshlvl=ok
        while IFS= read -r sline; do
            case "${sline%%|*}" in
                crit) sshlvl=crit ;;
                warn) [[ "$sshlvl" != "crit" ]] && sshlvl=warn ;;
            esac
        done < <(_ops_sshd_check "$sshout")
        _ops_check_add "$sshlvl" "SSH 基线" "摘要见 ./install.sh ops-kit audit ssh"
    else
        _ops_check_add skip "SSH 基线" "读不到 sshd 配置"
    fi

    # 6) 公网监听
    if command -v ss >/dev/null 2>&1; then
        local sp addr pub_n=0
        while IFS= read -r sp; do
            [[ -z "$sp" ]] && continue
            addr="${sp#*|}"; addr="${addr%%|*}"
            _ops_is_public_addr "$addr" && pub_n=$((pub_n+1))
        done < <(_ops_ss_parse "$(ss -tulpn 2>/dev/null || true)")
        if   (( pub_n == 0 )); then _ops_check_add ok "公网监听" "无 0.0.0.0/[::] 监听"
        else _ops_check_add warn "公网监听" "${pub_n} 个——清单: ./install.sh ops-kit audit ports"; fi
    else
        _ops_check_add skip "公网监听" "ss 不可用"
    fi

    # 7) 待更新（>0 ⚠️ / >50 🔴）
    local upds; upds=$(_ops_collect_updates)
    if [[ -z "$upds" ]]; then
        _ops_check_add skip "待更新" "未识别包管理器"
    else
        local usrc="${upds%% *}"; local un="${upds##* }"
        un=$(_ops_updates_count "$un")
        if   (( un > 50 )); then _ops_check_add crit "待更新($usrc)" "${un} 个"
        elif (( un > 0 ));  then _ops_check_add warn "待更新($usrc)" "${un} 个"
        else _ops_check_add ok "待更新($usrc)" "0"; fi
    fi

    # 8) 登录失败
    if command -v lastb >/dev/null 2>&1 && [[ -e /var/log/btmp || -e /var/log/lastlog ]]; then
        local lbc; lbc=$(_ops_lastb_count "$(lastb -n 50 2>/dev/null | head -50 || true)")
        if (( lbc > 0 )); then _ops_check_add warn "登录失败" "近期 ${lbc}+ 条（lastb，失败登录爆破迹象）"
        else _ops_check_add ok "登录失败" "无记录"; fi
    else
        _ops_check_add skip "登录失败" "lastb/btmp 不可用"
    fi

    # 输出
    if (( json )); then
        printf '{"summary":{"crit":%d,"warn":%d},"checks":[%s]}\n' "$OPS_CRIT_N" "$OPS_WARN_N" "$OPS_JSON"
    else
        header "🩺 ops-kit 系统巡检报告（$(date '+%F %T')）"
        printf '%s' "$OPS_CHECKS"
        echo "-----------------------------------------------"
        if   (( OPS_CRIT_N > 0 )); then echo "${OPS_CRIT}巡检汇总：${OPS_CRIT_N} 项危险、${OPS_WARN_N} 项注意——优先处理 🔴 项"
        elif (( OPS_WARN_N > 0 )); then echo "${OPS_WARN}巡检汇总：${OPS_WARN_N} 项注意，无危险项"
        else echo "${OPS_OK}巡检汇总：全部通过"; fi
    fi
    return 0
}

# ============================================================
# log 日志运维
# ============================================================
_ops_log_status() {
    header "📜 日志占用"
    if command -v journalctl >/dev/null 2>&1; then
        info "journal：$(journalctl --disk-usage 2>/dev/null || echo '读取失败')"
    else
        info "journalctl 不可用"
    fi
    if [[ -d /var/log ]]; then
        info "/var/log 大户 TOP5："
        sudo du -x -m /var/log/* 2>/dev/null | sort -rn | head -5 | awk '{printf "  %6dMB  %s\n", $1, $2}' || true
    fi
    info "清理指路: ./install.sh ops-kit log vacuum 200M"
}

_ops_log_vacuum() {
    local arg="$1"
    [[ -z "$arg" ]] && { error "用法: ops-kit log vacuum <200M|2weeks>（大小或时长，必填）"; return 1; }
    if [[ "${UNIX_SCRIPT_DRY_RUN:-0}" == "1" ]]; then
        case "$arg" in *M|*G) info "[dry-run] journalctl --vacuum-size=$arg" ;; *) info "[dry-run] journalctl --vacuum-time=$arg" ;; esac
        return 0
    fi
    if [[ ! -t 0 ]]; then error "清理 journal 属写操作，仅允许在交互终端执行（或加 --dry-run 预览）"; return 1; fi
    case "$arg" in *M|*G) info "将执行: journalctl --vacuum-size=$arg" ;; *) info "将执行: journalctl --vacuum-time=$arg" ;; esac
    local a; read -r -p "确认清理 journal？输入 yes 继续: " a
    [[ "$a" == "yes" ]] || { info "已取消"; return 0; }
    case "$arg" in
        *M|*G) sudo journalctl --vacuum-size="$arg" ;;
        *)     sudo journalctl --vacuum-time="$arg" ;;
    esac
    info "✅ journal 清理完成"
}

_ops_log_rotate_tpl() {  # <app> → 模板文本（未知输出空）
    case "$1" in
        nginx) printf '/var/log/nginx/*.log {\n  daily\n  rotate 14\n  compress\n  delaycompress\n  missingok\n  notifempty\n  sharedscripts\n  postrotate\n    [ -f /var/run/nginx.pid ] && kill -USR1 "$(cat /var/run/nginx.pid)"\n  endscript\n}\n' ;;
        redis) printf '/var/log/redis/redis-server.log {\n  weekly\n  rotate 12\n  compress\n  missingok\n  notifempty\n  copytruncate\n}\n' ;;
        journal) printf '/var/log/journal/*.journal {\n  monthly\n  rotate 6\n  compress\n  missingok\n  notifempty\n}\n' ;;
        *) return ;;
    esac
}

_ops_log_rotate() {
    local action="${1:-list}" app="${2:-}"
    case "$action" in
        list)
            header "📋 $OPS_LOGROTATE_DIR 现有条目"
            ls -1 "$OPS_LOGROTATE_DIR" 2>/dev/null || info "（目录不存在）" ;;
        show)
            [[ -z "$app" ]] && { error "用法: ops-kit log rotate show <app>"; return 1; }
            if [[ -f "$OPS_LOGROTATE_DIR/$app" ]]; then cat "$OPS_LOGROTATE_DIR/$app"
            else error "无 $app 条目（list 查看现有）"; return 1; fi ;;
        apply)
            [[ -z "$app" ]] && { error "用法: ops-kit log rotate apply <app>（内置模板: nginx|redis|journal）"; return 1; }
            local tpl; tpl=$(_ops_log_rotate_tpl "$app")
            [[ -z "$tpl" ]] && { error "无内置模板: ${app}（可选 nginx|redis|journal）"; return 1; }
            printf '%s' "$tpl"
            if [[ "${UNIX_SCRIPT_DRY_RUN:-0}" == "1" ]]; then info "[dry-run] 写入 $OPS_LOGROTATE_DIR/$app"; return 0; fi
            if [[ ! -t 0 ]]; then error "写入 logrotate 属写操作，仅允许在交互终端执行（或加 --dry-run 预览）"; return 1; fi
            local a; read -r -p "写入 ${OPS_LOGROTATE_DIR}/${app}？输入 yes 继续: " a
            [[ "$a" == "yes" ]] || { info "已取消"; return 0; }
            [[ -f "$OPS_LOGROTATE_DIR/$app" ]] && sudo cp "$OPS_LOGROTATE_DIR/$app" "$OPS_LOGROTATE_DIR/$app.bak.$(date +%s)"
            printf '%s' "$tpl" | sudo tee "$OPS_LOGROTATE_DIR/$app" >/dev/null
            info "✅ 已写入；验证: sudo logrotate -d $OPS_LOGROTATE_DIR/$app" ;;
        *) error "用法: ops-kit log rotate list|show <app>|apply <app>"; return 1 ;;
    esac
}

cmd_log() {
    local action="${1:-status}"
    case "$action" in
        status) shift || true; _ops_log_status ;;
        vacuum) shift || true; _ops_log_vacuum "${1:-}" ;;
        rotate) shift || true; _ops_log_rotate "${1:-list}" "${2:-}" ;;
        *) error "用法: ops-kit log status|vacuum <200M|2weeks>|rotate list|show <app>|apply <app>"; return 1 ;;
    esac
}

# ============================================================
# svc systemd 服务运维
# ============================================================
cmd_svc() {
    local action="${1:-failed}"
    shift || true
    local unit="${1:-}"
    case "$action" in
        failed|logs|status|start|stop|restart|enable|disable) ;;
        *) error "用法: ops-kit svc failed|logs <unit>|status <unit>|start|stop|restart|enable|disable <unit>"; return 1 ;;
    esac
    # 参数校验先于 systemd 探测：无 unit 的用法错误在任何环境都应报错
    case "$action" in
        logs|status|start|stop|restart|enable|disable)
            [[ -z "$unit" ]] && { error "用法: ops-kit svc $action <unit>"; return 1; } ;;
    esac
    command -v systemctl >/dev/null 2>&1 || { info "本环境无 systemd，svc 子命令不可用"; return 0; }
    case "$action" in
        failed)
            header "🚨 systemd 失败单元"
            local fu; fu=$(_ops_failed_units "$(systemctl --failed --no-legend 2>/dev/null || true)")
            if [[ -z "$fu" ]]; then info "${OPS_OK} 无失败单元"; return 0; fi
            local u
            for u in $fu; do
                echo "---- $u ----"
                systemctl status "$u" --no-pager -l 2>/dev/null | grep -E 'Loaded:|Active:|Since:|Main PID:' || true
                journalctl -u "$u" -n 3 --no-pager 2>/dev/null || true
            done
            info "查看完整日志: ./install.sh ops-kit svc logs <unit> 100" ;;
        logs)
            journalctl -u "$unit" -n "${2:-50}" --no-pager ;;
        status)
            systemctl status "$unit" --no-pager -l ;;
        start|stop|restart|enable|disable)
            case "$action" in
                stop|restart|disable)
                    if [[ "${UNIX_SCRIPT_DRY_RUN:-0}" != "1" && -t 0 ]]; then
                        local a; read -r -p "确认对 ${unit} 执行 ${action}？输入 yes 继续: " a
                        [[ "$a" == "yes" ]] || { info "已取消"; return 0; }
                    fi ;;
            esac
            sudo systemctl "$action" "$unit"
            info "✅ systemctl $action $unit 完成" ;;
        *) error "用法: ops-kit svc failed|logs <unit>|status <unit>|start|stop|restart|enable|disable <unit>"; return 1 ;;
    esac
}

# ============================================================
# audit 安全基线（只读）
# ============================================================
_ops_audit_ssh() {
    header "🔐 SSH 基线自查"
    local out=''
    if command -v sshd >/dev/null 2>&1; then
        out=$(sshd -T 2>/dev/null || sudo -n sshd -T 2>/dev/null || true)
    fi
    [[ -z "$out" ]] && out=$(grep -RhiE '^[[:space:]]*(PermitRootLogin|PasswordAuthentication|MaxAuthTries|X11Forwarding)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null || true)
    if [[ -z "$out" ]]; then
        info "读不到 sshd 配置（未安装 OpenSSH server 或无权限），跳过"
        return 0
    fi
    local line icon
    while IFS= read -r line; do
        case "$line" in crit*) icon="$OPS_CRIT" ;; warn*) icon="$OPS_WARN" ;; *) icon="$OPS_OK" ;; esac
        echo "  ${icon} ${line#*|}"
    done < <(_ops_sshd_check "$out")
    info "加固指路: ./install.sh sys-setup ssh"
}

_ops_audit_ports() {
    header "🌐 公网监听端口"
    command -v ss >/dev/null 2>&1 || { info "ss 不可用，跳过"; return 0; }
    local sp addr pub_n=0
    while IFS= read -r sp; do
        [[ -z "$sp" ]] && continue
        addr="${sp#*|}"; addr="${addr%%|*}"
        if _ops_is_public_addr "$addr"; then
            pub_n=$((pub_n+1))
            echo "  $OPS_WARN ${sp%%|*}  ${addr}  进程: ${sp##*|}"
        fi
    done < <(_ops_ss_parse "$(ss -tulpn 2>/dev/null || true)")
    (( pub_n == 0 )) && info "${OPS_OK} 无 0.0.0.0/[::] 公网监听"
    info "收口指路: ./install.sh ufw"
}

_ops_audit_updates() {
    header "📦 待更新"
    local upds; upds=$(_ops_collect_updates)
    if [[ -z "$upds" ]]; then info "未识别包管理器，跳过"; return 0; fi
    local usrc="${upds%% *}"; local un; un=$(_ops_updates_count "${upds##* }")
    info "[$usrc] 待更新 ${un} 个；自动安装指路: ./install.sh sys-setup unattended"
}

cmd_audit() {
    local target="${1:-all}"
    case "$target" in
        ssh) _ops_audit_ssh ;;
        ports) _ops_audit_ports ;;
        updates) _ops_audit_updates ;;
        all) _ops_audit_ssh; _ops_audit_ports; _ops_audit_updates ;;
        *) error "用法: ops-kit audit ssh|ports|updates|all"; return 1 ;;
    esac
    return 0
}

# ============================================================
# 状态 / 安装 / 帮助
# ============================================================
_ops_tool_avail() { command -v "$1" >/dev/null 2>&1 && echo 1 || echo 0; }

status_ops_kit() {
    if [[ "${OS_TYPE:-}" == "darwin" ]]; then
        emit_status "n/a" "⏭️  ops-kit 运维工具箱（仅 Linux，本机不适用）"
        return 0
    fi
    emit_status "installed" "✅ ops-kit 运维工具箱就绪（inspect 巡检 / log 日志 / svc 服务 / audit 基线）"
    emit_extra "tools=systemctl:$(_ops_tool_avail systemctl),journalctl:$(_ops_tool_avail journalctl),smartctl:$(_ops_tool_avail smartctl),ss:$(_ops_tool_avail ss)"
}

cmd_install() {
    _ops_platform_check
    header "🧰 ops-kit 依赖检查"
    local t missing=0
    for t in systemctl journalctl ss logrotate; do
        if command -v "$t" >/dev/null 2>&1; then
            info "✔ $t 可用"
        else
            warn "✘ $t 缺失（相关子命令将降级）"
            missing=$((missing+1))
        fi
    done
    if (( missing == 0 )); then
        info "🎉 依赖齐备。试试: ./install.sh ops-kit inspect"
    else
        info "缺 $missing 项——ops-kit 不自动安装系统组件，缺啥用啥，其余子命令不受影响"
    fi
    return 0
}

cmd_uninstall() { info "ops-kit 为只读命令封装，不安装任何组件，无需卸载"; }

usage() {
    cat <<'EOF'
运维工具箱（仅 Linux）—— 一站式巡检与日常运维

用法: ops-kit {inspect|log|svc|audit|status|help} [参数...]

  inspect [--json]      聚合巡检：磁盘/SMART/失败服务/journal/SSH 基线/公网端口/更新/登录失败
  log status            journal 占用 + /var/log 大户 TOP5
  log vacuum <200M|2weeks>
                        清理 journald（写操作，需交互确认，支持 --dry-run）
  log rotate list|show <app>|apply <app>
                        查看/生成 /etc/logrotate.d 条目（内置模板: nginx|redis|journal）
  svc failed            systemd 失败单元汇总（unit/状态/journal 尾行）
  svc logs <unit> [n]   查看单元日志（默认 50 行）
  svc status|start|stop|restart|enable|disable <unit>
                        systemctl 透传（stop/restart/disable 交互确认）
  audit ssh|ports|updates|all
                        安全基线自查（只读，附修复指路）
  status                依赖齐备度（UXS_STATUS_MODE=machine 可读）
  help                  本帮助
EOF
}

# ---- 分发（inspect|log|svc|audit|install|uninstall|status|help）----
main() {
    local sub="${1:-inspect}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        inspect)   _ops_platform_check; cmd_inspect "$@" ;;
        log)       _ops_platform_check; cmd_log "$@" ;;
        svc)       _ops_platform_check; cmd_svc "$@" ;;
        audit)     _ops_platform_check; cmd_audit "$@" ;;
        install)   cmd_install ;;
        uninstall) cmd_uninstall ;;
        status)    status_ops_kit ;;
        help|-h|--help) usage ;;
        *) error "未知子命令: $sub"; usage; return 1 ;;
    esac
}

# source 守护：被 source（单测）时只提供函数，不执行分发
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
