#!/usr/bin/env bash
#
# sys-setup/install.sh
#
# 装机必设置：系统初始化配置集合。仅 Linux。
# 每个子命令对应一项常用装机配置：
#
#   mirror      —— 更换系统软件源为国内镜像（预览确认后执行）
#   timezone    —— 设置时区并启用 NTP 时间同步
#   optimize    —— 系统参数优化（文件描述符、TCP、内核）
#   ssh         —— SSH 加固（禁用密码登录、禁用 root 直登）
#   autoupdate  —— 启用自动安全更新
#   all         —— 依次执行以上全部
#   status      —— 查看各项配置状态
#   help        —— 帮助
#
# 平台差异下沉到 platform/<族>.sh（debian/rhel/suse/arch/alpine），
# 本文件只保留调度与平台无关逻辑；动词（pkg_install/uxs_svc）来自 lib。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "sys-setup 仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
    require_sudo
}

# -------- 平台实现加载 --------
# 加载当前发行版族的 platform 实现。
# 返回：0=已加载；2=发行版族未知（调用方 warn 跳过）；1=platform 文件缺失（框架错误）。
_load_platform() {
    detect_distro
    if [[ "$DISTRO_FAMILY" == "unknown" ]]; then
        return 2
    fi
    local plat="$SCRIPT_DIR/platform/${DISTRO_FAMILY}.sh"
    if [[ ! -f "$plat" ]]; then
        error "platform 文件缺失（框架错误）：$plat"
        return 1
    fi
    # shellcheck source=platform/debian.sh
    source "$plat"
}

# -------- 1. 换源（国内镜像，预览确认后执行） --------
do_mirror() {
    preflight
    detect_pkg_manager
    local rc=0
    _load_platform || rc=$?
    if [[ "$rc" == "2" ]]; then
        warn "暂不支持该发行版（族未知），跳过换源"
        return 0
    fi
    if [[ "$rc" != "0" ]]; then
        return 1
    fi

    # 严格档：换源属破坏性操作，非交互环境跳过不阻断（无逃生开关）
    if [[ ! -t 0 ]]; then
        warn "换源需交互确认，已跳过（非交互环境）"
        return 0
    fi

    info "🌐 更换软件源为国内镜像"
    local os_ver os_codename detect_line
    os_ver=$(uxs_os_release VERSION_ID)
    os_codename=$(uxs_os_release VERSION_CODENAME)
    detect_line="${DISTRO_NAME:-${DISTRO_ID:-未知}} ${os_ver}"
    [[ -n "$os_codename" ]] && detect_line+=" (${os_codename})"
    detect_line+=" · $(uname -m) · ${PKG_MANAGER:-?}"

    echo "── 换源预览 ──────────────────────────────"
    echo "检测到:  ${detect_line}"
    echo "执行动作:"
    plat_mirror_preview
    echo "──────────────────────────────────────────"
    if ! yes_no "确认执行换源？"; then
        info "已取消换源"
        return 0
    fi
    plat_mirror_apply
}

# -------- 2. 时区 + 时间同步 --------
# 预设 NTP 服务器
NTP_PRESET_ALIYUN="ntp.aliyun.com ntp1.aliyun.com ntp2.aliyun.com"
NTP_PRESET_TUNA="ntp.tuna.tsinghua.edu.cn"
NTP_PRESET_NTPPOOL="0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org"
NTP_PRESET_CSTTIME="cn.ntp.org.cn"
NTP_PRESET_GOOGLE="time1.google.com time2.google.com"
NTP_PRESET_HUAWEI="ntp.huaweicloud.com"

# 配置 systemd-timesyncd 的 NTP 服务器
_configure_timesyncd() {
    local servers="$1"
    local conf="/etc/systemd/timesyncd.conf"
    sudo mkdir -p /etc/systemd

    # 备份原配置
    if [[ -f "$conf" ]]; then
        sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true
    fi

    # 构建 NTP= 行（空格分隔）
    local ntp_line
    ntp_line=$(echo "$servers" | tr ' ' '\n' | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//')

    # 写入配置（保留其他设置，只更新 [Time] 段的 NTP 和 FallbackNTP）
    if [[ -f "$conf" ]] && grep -q '^\[Time\]' "$conf" 2>/dev/null; then
        # 已有 [Time] 段：替换或追加 NTP=
        if grep -q '^NTP=' "$conf"; then
            sudo sed -i "s|^NTP=.*|NTP=${ntp_line}|" "$conf"
        else
            sudo sed -i "/^\[Time\]/a NTP=${ntp_line}" "$conf"
        fi
    else
        # 没有 [Time] 段：追加
        {
            echo ""
            echo "[Time]"
            echo "NTP=${ntp_line}"
        } | sudo tee -a "$conf" >/dev/null
    fi

    # 重启 timesyncd 使配置生效
    sudo systemctl restart systemd-timesyncd 2>/dev/null || true
}

# 配置 chrony 的 NTP 服务器
_configure_chrony() {
    local servers="$1"
    local conf=""
    for conf in /etc/chrony/chrony.conf /etc/chrony.conf; do
        [[ -f "$conf" ]] && break
    done
    [[ -f "$conf" ]] || { warn "未找到 chrony 配置文件"; return 1; }

    sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true

    # 注释掉原有的 server/pool 行（含缩进）
    sudo sed -i 's/^\([[:space:]]*\(server\|pool\)\) /# &/' "$conf"

    # 追加新的 server 行
    local s
    for s in $servers; do
        echo "server $s iburst" | sudo tee -a "$conf" >/dev/null
    done

    sudo systemctl restart chrony 2>/dev/null || sudo systemctl restart chronyd 2>/dev/null || true
}

# 配置 ntpd 的 NTP 服务器
_configure_ntpd() {
    local servers="$1"
    local conf="/etc/ntp.conf"
    [[ -f "$conf" ]] || { warn "未找到 ntp.conf"; return 1; }

    sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true

    # 注释掉原有的 server 行（含缩进）
    sudo sed -i 's/^\([[:space:]]*server\) /# &/' "$conf"

    # 追加新的 server 行
    local s
    for s in $servers; do
        echo "server $s iburst" | sudo tee -a "$conf" >/dev/null
    done

    sudo systemctl restart ntpd 2>/dev/null || true
}

# 设置 NTP 服务器（自动检测后端）
set_ntp_servers() {
    local servers="$1"
    detect_distro

    # 检测使用哪个 NTP 后端
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null || \
       systemctl list-unit-files 2>/dev/null | grep -q systemd-timesyncd; then
        if _configure_timesyncd "$servers"; then
            success "已配置 systemd-timesyncd: $servers"
        else
            error "配置 systemd-timesyncd 失败"; return 1
        fi
    elif systemctl is-active --quiet chrony 2>/dev/null || \
         systemctl is-active --quiet chronyd 2>/dev/null || \
         command_exists chronyc; then
        if _configure_chrony "$servers"; then
            success "已配置 chrony: $servers"
        else
            error "配置 chrony 失败"; return 1
        fi
    elif systemctl is-active --quiet ntpd 2>/dev/null || \
         command_exists ntpd; then
        if _configure_ntpd "$servers"; then
            success "已配置 ntpd: $servers"
        else
            error "配置 ntpd 失败"; return 1
        fi
    else
        # 没有 NTP 服务，尝试安装 chrony（unit 名是名词：debian 系 chrony、rhel 系 chronyd）
        warn "未检测到 NTP 服务，尝试安装 chrony..."
        if pkg_install chrony; then
            local unit="chronyd"
            [[ "$DISTRO_FAMILY" == "debian" ]] && unit="chrony"
            if uxs_svc enable-now "$unit"; then
                if _configure_chrony "$servers"; then
                    success "已安装 chrony 并配置: $servers"
                else
                    error "配置 chrony 失败"; return 1
                fi
            else
                error "chrony 服务启用失败"; return 1
            fi
        else
            error "chrony 安装失败，请手动安装"
            return 1
        fi
    fi
}

# 查看当前 NTP 状态
show_ntp_status() {
    echo "当前 NTP 状态："
    if command_exists timedatectl; then
        timedatectl status 2>/dev/null | grep -E 'Local time|Time zone|NTP|synchronized' | sed 's/^/  /'
    fi
    # 显示实际使用的 NTP 服务器
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        echo "  后端: systemd-timesyncd"
        local conf="/etc/systemd/timesyncd.conf"
        if [[ -f "$conf" ]] && grep -q '^NTP=' "$conf"; then
            echo "  配置: $(grep '^NTP=' "$conf")"
        else
            echo "  配置: (默认)"
        fi
    elif command_exists chronyc 2>/dev/null; then
        echo "  后端: chrony"
        chronyc sources 2>/dev/null | head -8 | sed 's/^/  /'
    elif command_exists ntpq 2>/dev/null; then
        echo "  后端: ntpd"
        ntpq -p 2>/dev/null | head -8 | sed 's/^/  /'
    else
        echo "  (未检测到 NTP 服务)"
    fi
}

# NTP 交互式设置
do_ntp() {
    preflight
    info "🕐 配置 NTP 时间同步服务器"
    echo

    show_ntp_status
    echo

    menu "请选择 NTP 服务器方案："
    echo "  1) 阿里云     ($NTP_PRESET_ALIYUN)"
    echo "  2) 清华 TUNA  ($NTP_PRESET_TUNA)"
    echo "  3) 华为云     ($NTP_PRESET_HUAWEI)"
    echo "  4) 中国 NTP   ($NTP_PRESET_CSTTIME)"
    echo "  5) NTP Pool   ($NTP_PRESET_NTPPOOL)"
    echo "  6) Google     ($NTP_PRESET_GOOGLE)"
    echo "  7) 自定义（手动输入 NTP 服务器地址）"
    echo "  0) 取消"
    echo "========================================"

    local choice
    read -r -p "请输入选项 [0-7]: " choice

    local servers=""
    case "$choice" in
        1) servers="$NTP_PRESET_ALIYUN" ;;
        2) servers="$NTP_PRESET_TUNA" ;;
        3) servers="$NTP_PRESET_HUAWEI" ;;
        4) servers="$NTP_PRESET_CSTTIME" ;;
        5) servers="$NTP_PRESET_NTPPOOL" ;;
        6) servers="$NTP_PRESET_GOOGLE" ;;
        7)
            echo
            info "请输入 NTP 服务器地址（多个用空格分隔）："
            info "示例: ntp.aliyun.com ntp1.aliyun.com"
            read -r -p "> " servers
            # 去除首尾空白
            servers=$(echo "$servers" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -z "$servers" ]]; then
                warn "未输入任何服务器，已取消"
                return 0
            fi
            # 基本校验：每个词应像合法主机名（含字母/数字/点/连字符）
            local word
            for word in $servers; do
                if [[ ! "$word" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
                    error "无效的服务器地址: $word"
                    info "地址应只包含字母、数字、点、连字符，例如: ntp.aliyun.com"
                    return 1
                fi
            done
            ;;
        0|*) info "已取消"; return 0 ;;
    esac

    echo
    info "即将配置 NTP 服务器: $servers"
    if ! yes_no "确认继续？"; then
        info "已取消"; return 0
    fi

    set_ntp_servers "$servers"

    echo
    show_ntp_status
}

# 设置时区（支持参数，默认 Asia/Shanghai）
# shellcheck disable=SC2120  # 函数签名预留参数，当前未使用
do_timezone() {
    preflight
    detect_distro
    local tz="${1:-Asia/Shanghai}"
    info "🕐 设置时区为 $tz 并启用时间同步"

    if command_exists timedatectl; then
        sudo timedatectl set-timezone "$tz"
        success "时区已设置为 $tz"
        # 优先启用 systemd-timesyncd
        if systemctl list-unit-files 2>/dev/null | grep -q systemd-timesyncd; then
            sudo systemctl enable --now systemd-timesyncd 2>/dev/null || true
            sudo timedatectl set-ntp true 2>/dev/null || true
            success "已启用 systemd-timesyncd (NTP)"
        fi
    else
        sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        success "时区已设置为 ${tz}（符号链接）"
    fi

    # 没有 timesyncd 时回退装 chrony（unit 名是名词：debian 系 chrony、rhel 系 chronyd）
    if ! systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        if pkg_install chrony 2>/dev/null; then
            local unit="chronyd"
            [[ "$DISTRO_FAMILY" == "debian" ]] && unit="chrony"
            uxs_svc enable-now "$unit" 2>/dev/null || true
            success "已安装并启用 chrony 时间同步"
        else
            warn "chrony 安装失败，跳过时间同步服务配置"
        fi
    fi
}

# -------- 3. 系统参数优化 --------
do_optimize() {
    preflight
    info "⚙️  优化系统参数（文件描述符、内核）"

    # 文件描述符上限
    local limits_file=/etc/security/limits.d/99-unix-script.conf
    sudo tee "$limits_file" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— 提升文件描述符上限
*               soft    nofile          65536
*               hard    nofile          65536
root            soft    nofile          65536
root            hard    nofile          65536
EOF
    success "已提升文件描述符上限到 65536（${limits_file}）"

    # 内核参数（网络/内存）
    local sysctl_file=/etc/sysctl.d/99-unix-script.conf
    sudo tee "$sysctl_file" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— 内核参数优化
# TCP 快速回收与复用
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
# TCP keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
# 防 SYN flood
net.ipv4.tcp_syncookies = 1
# 内存
vm.swappiness = 10
vm.overcommit_memory = 1
EOF
    sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
    success "已写入内核优化参数（${sysctl_file}）"
}

# -------- 4. SSH 加固 --------
do_ssh() {
    preflight
    info "🔐 SSH 加固（禁用密码登录、禁用 root 直登）"

    local sshd_config
    for sshd_config in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/99-unix-script.conf; do
        if [[ -f "$sshd_config" ]]; then break; fi
    done
    # 优先用 sshd_config.d drop-in（更干净）
    local dropin=/etc/ssh/sshd_config.d/99-unix-script.conf
    sudo mkdir -p /etc/ssh/sshd_config.d

    warn "SSH 加固是敏感操作：将禁用密码登录与 root 直登。"
    warn "请确保你已配置好 SSH 密钥登录，否则可能无法登录服务器！"
    if ! yes_no "确认继续（仅当你已配置好密钥登录）？"; then
        info "已跳过 SSH 加固"; return 0
    fi

    sudo tee "$dropin" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— SSH 加固
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
    success "已写入 SSH 加固配置（${dropin}）"

    if command_exists systemctl; then
        sudo systemctl reload sshd 2>/dev/null || sudo systemctl reload ssh 2>/dev/null || true
        success "sshd 已 reload（配置在新连接生效）"
    fi
}

# -------- 5. 自动安全更新 --------
do_autoupdate() {
    preflight
    info "🛡️  启用自动安全更新"
    local rc=0
    _load_platform || rc=$?
    if [[ "$rc" == "2" ]]; then
        warn "暂不支持该发行版（族未知），跳过自动更新配置"
        return 0
    fi
    if [[ "$rc" != "0" ]]; then
        return 1
    fi
    plat_autoupdate
}

# -------- 全部执行 --------
do_all() {
    info "🚀 执行全部装机必设置"
    do_mirror
    echo
    do_timezone
    echo
    do_optimize
    echo
    do_autoupdate
    echo
    do_ssh
    echo
    success "🎉 全部装机必设置执行完成"
}

# -------- 状态 --------
status_sys_setup() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi

    # ---- 先计算各子项的事实，用于聚合并聚态与 emit_extra ----
    # 镜像源（现代 Ubuntu/Debian 的发行版源在 sources.list.d/*.sources，需一并检测）
    local mirror_ok=false mirror_val="默认源"
    if grep -qs "tuna.tsinghua\|mirrors.aliyun\|mirrors.ustc" /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null; then
        mirror_ok=true; mirror_val="已换国内源"
    fi
    # 时区
    local tz_val
    tz_val=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo '未知')
    # NTP 同步开关
    local ntp_sync
    ntp_sync=$(timedatectl show -p NTP --value 2>/dev/null || echo '未知')
    # NTP 服务器（含后端）
    local ntp_servers="(系统默认)" ntp_backend="" ntp_val=""
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
        ntp_backend="timesyncd"
        local ntp_conf="/etc/systemd/timesyncd.conf"
        if [[ -f "$ntp_conf" ]] && grep -q '^NTP=' "$ntp_conf" 2>/dev/null; then
            ntp_servers=$(grep '^NTP=' "$ntp_conf" | sed 's/^NTP=//')
        fi
        ntp_val="$ntp_servers (timesyncd)"
    elif command_exists chronyc 2>/dev/null; then
        ntp_backend="chrony"
        ntp_val="(chrony，用 chronyc sources 查看)"
    elif command_exists ntpq 2>/dev/null; then
        ntp_backend="ntpd"
        ntp_val="(ntpd，用 ntpq -p 查看)"
    fi
    # 文件描述符（ulimit）
    local fd_ok=false fd_state="默认"
    if [[ -f /etc/security/limits.d/99-unix-script.conf ]]; then fd_ok=true; fd_state="✅ 已优化"; fi
    # SSH 加固
    local ssh_ok=false ssh_state="默认"
    if [[ -f /etc/ssh/sshd_config.d/99-unix-script.conf ]]; then ssh_ok=true; ssh_state="✅ 已加固"; fi

    # ---- 聚合主状态：镜像源/fd/ssh 全部 ✅ → configured，否则 not_configured ----
    if $mirror_ok && $fd_ok && $ssh_ok; then
        emit_status "configured" "${GREEN}✅ 系统配置已完成${NC}"
    else
        emit_status "not_configured" "${YELLOW}⚠️  系统配置未完成${NC}"
    fi

    # ---- 机器模式 EXTRA 行（每个子项一条）----
    emit_extra "mirror=$mirror_val"
    emit_extra "timezone=$tz_val"
    emit_extra "ntp_sync=$ntp_sync"
    if [[ -n "$ntp_backend" ]]; then
        emit_extra "ntp_backend=$ntp_backend"
        emit_extra "ntp_servers=$ntp_servers"
    fi
    emit_extra "ulimit=$($fd_ok && echo optimized || echo default)"
    emit_extra "ssh=$($ssh_ok && echo hardened || echo default)"

    # ---- 人类模式：保留原始多行配置概览 ----
    if ! uxs_is_machine_mode; then
        echo "软件源镜像:"
        if $mirror_ok; then
            echo -e "  ${GREEN}✅ 已换国内源${NC}"
        else
            echo -e "  ${YELLOW}⚠️  默认源${NC}"
        fi
        echo "时区: $tz_val"
        echo "NTP 同步: $ntp_sync"
        if [[ -n "$ntp_val" ]]; then
            echo "NTP 服务器: $ntp_val"
        fi
        echo "文件描述符上限: $fd_state"
        echo "SSH 加固: $ssh_state"
    fi
}

usage() {
    cat <<EOF
用法: $0 {mirror|timezone|ntp|optimize|ssh|autoupdate|all|status|help}  (仅 Linux)

  mirror      更换软件源为国内镜像（预览确认后执行；Alma/Rocky/Fedora/openEuler/Anolis/deepin 已支持）
  timezone    设置时区并启用 NTP 时间同步（默认 Asia/Shanghai）
  ntp         配置自定义 NTP 服务器（阿里云/清华/华为/Google/自定义）
  optimize    优化系统参数（文件描述符、TCP、内核）
  ssh         SSH 加固（禁用密码登录、禁用 root 直登，需先配好密钥）
  autoupdate  启用自动安全更新
  all         依次执行以上全部
  status      查看各项配置状态
EOF
}

# 卸载：仅移除本工具写入的「增量 drop-in」配置（可逆），不动镜像源/NTP 等需手动还原项。
# 移除的文件均为 99-unix-script.conf 增量配置，删掉即恢复系统默认值。
uninstall_sys_setup() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        info "sys-setup 的卸载仅适用 Linux（drop-in 配置为 Linux 路径），当前平台无需卸载"
        return 0
    fi
    info "卸载 sys-setup 写入的增量配置（drop-in）..."
    require_sudo
    local removed=0
    local f
    for f in \
        /etc/security/limits.d/99-unix-script.conf \
        /etc/sysctl.d/99-unix-script.conf \
        /etc/ssh/sshd_config.d/99-unix-script.conf; do
        if [[ -f "$f" ]]; then
            sudo rm -f "$f"
            success "已移除：$f"
            removed=$((removed + 1))
        fi
    done
    # 应用 sysctl 变更（drop-in 删除后重新加载系统默认）
    sudo sysctl --system >/dev/null 2>&1 || true
    if [[ $removed -eq 0 ]]; then
        info "未发现 sys-setup 写入的 drop-in 配置（可能未执行过 optimize/ssh）"
    else
        success "已移除 $removed 个 drop-in 配置，系统已恢复默认值"
    fi
    warn "镜像源/NTP 等修改在安装时已生成 .bak.* 备份，如需还原请手动查找："
    warn "  ls -t /etc/apt/sources.list.bak.* /etc/yum.repos.d/*.bak.* 2>/dev/null"
    warn "SSH 服务策略已恢复默认，如修改过 sshd 建议复查：sudo sshd -t && sudo systemctl restart sshd"
}

main() {
    local action="${1:-help}"
    detect_os
    case "$action" in
        mirror)     do_mirror ;;
        timezone)   do_timezone ;;
        ntp)        do_ntp ;;
        optimize)   do_optimize ;;
        ssh)        do_ssh ;;
        autoupdate) do_autoupdate ;;
        all)        do_all ;;
        uninstall)  uninstall_sys_setup ;;
        status)     status_sys_setup ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
