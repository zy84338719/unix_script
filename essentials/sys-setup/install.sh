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
        error "$(_tf 'sys-setup only supports Linux. Current: %s' "$OS_TYPE")"
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
        error "$(_tf 'The platform file is missing (framework error): %s' "$plat")"
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
        warn "$(_t 'Unsupported distribution (unknown family), skipping the mirror switch')"
        return 0
    fi
    if [[ "$rc" != "0" ]]; then
        return 1
    fi

    # 严格档：换源属破坏性操作，非交互环境跳过不阻断（无逃生开关）
    if [[ ! -t 0 ]]; then
        warn "$(_t 'The mirror switch needs a confirmation, skipped (non-interactive)')"
        return 0
    fi

    info "$(_t '🌐 Switching the package sources to domestic mirrors')"
    local os_ver os_codename detect_line
    os_ver=$(os_release_field VERSION_ID)
    os_codename=$(os_release_field VERSION_CODENAME)
    detect_line="${DISTRO_NAME:-${DISTRO_ID:-$(_t 'Unknown')}} ${os_ver}"
    [[ -n "$os_codename" ]] && detect_line+=" (${os_codename})"
    detect_line+=" · $(uname -m) · ${PKG_MANAGER:-?}"

    echo "── $(_t 'Mirror switch preview') ──────────────────────────────"
    printf '%s\n' "$(_tf 'Detected: %s' "${detect_line}")"
    printf '%s\n' "$(_t 'Actions to be performed:')"
    plat_mirror_preview
    echo "──────────────────────────────────────────"
    if ! yes_no "$(_t 'Confirm the mirror switch?')"; then
        info "$(_t 'The mirror switch has been cancelled')"
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
    uxs_svc restart systemd-timesyncd 2>/dev/null || true
}

# 配置 chrony 的 NTP 服务器
_configure_chrony() {
    local servers="$1"
    local conf=""
    for conf in /etc/chrony/chrony.conf /etc/chrony.conf; do
        [[ -f "$conf" ]] && break
    done
    [[ -f "$conf" ]] || { warn "$(_t 'The chrony configuration file was not found')"; return 1; }

    sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true

    # 注释掉原有的 server/pool 行（含缩进）
    sudo sed -i 's/^\([[:space:]]*\(server\|pool\)\) /# &/' "$conf"

    # 追加新的 server 行
    local s
    for s in $servers; do
        echo "server $s iburst" | sudo tee -a "$conf" >/dev/null
    done

    uxs_svc restart chrony 2>/dev/null || uxs_svc restart chronyd 2>/dev/null || true
}

# 配置 ntpd 的 NTP 服务器
_configure_ntpd() {
    local servers="$1"
    local conf="/etc/ntp.conf"
    [[ -f "$conf" ]] || { warn "$(_t 'ntp.conf was not found')"; return 1; }

    sudo cp -a "$conf" "${conf}.bak.$(date +%s)" 2>/dev/null || true

    # 注释掉原有的 server 行（含缩进）
    sudo sed -i 's/^\([[:space:]]*server\) /# &/' "$conf"

    # 追加新的 server 行
    local s
    for s in $servers; do
        echo "server $s iburst" | sudo tee -a "$conf" >/dev/null
    done

    uxs_svc restart ntpd 2>/dev/null || true
}

# 设置 NTP 服务器（自动检测后端）
set_ntp_servers() {
    local servers="$1"
    detect_distro

    # 检测使用哪个 NTP 后端
    if uxs_svc is-active systemd-timesyncd 2>/dev/null || \
       uxs_svc list-unit-files 2>/dev/null | grep -q systemd-timesyncd; then
        if _configure_timesyncd "$servers"; then
            success "$(_tf 'systemd-timesyncd is configured: %s' "$servers")"
        else
            error "$(_t 'Configuring systemd-timesyncd failed')"; return 1
        fi
    elif uxs_svc is-active chrony 2>/dev/null || \
         uxs_svc is-active chronyd 2>/dev/null || \
         os_has_cmd chronyc; then
        if _configure_chrony "$servers"; then
            success "$(_tf 'chrony is configured: %s' "$servers")"
        else
            error "$(_t 'Configuring chrony failed')"; return 1
        fi
    elif uxs_svc is-active ntpd 2>/dev/null || \
         os_has_cmd ntpd; then
        if _configure_ntpd "$servers"; then
            success "$(_tf 'ntpd is configured: %s' "$servers")"
        else
            error "$(_t 'Configuring ntpd failed')"; return 1
        fi
    else
        # 没有 NTP 服务，尝试安装 chrony（unit 名是名词：debian 系 chrony、rhel 系 chronyd）
        warn "$(_t 'No NTP service detected, trying to install chrony...')"
        if pkg_install chrony; then
            local unit="chronyd"
            [[ "$DISTRO_FAMILY" == "debian" ]] && unit="chrony"
            if uxs_svc enable-now "$unit"; then
                if _configure_chrony "$servers"; then
                    success "$(_tf 'chrony is installed and configured: %s' "$servers")"
                else
                    error "$(_t 'Configuring chrony failed')"; return 1
                fi
            else
                error "$(_t 'Enabling the chrony service failed')"; return 1
            fi
        else
            error "$(_t 'Installing chrony failed, please install it manually')"
            return 1
        fi
    fi
}

# 查看当前 NTP 状态
show_ntp_status() {
    printf '%s\n' "$(_t 'Current NTP status:')"
    if os_has_cmd timedatectl; then
        timedatectl status 2>/dev/null | grep -E 'Local time|Time zone|NTP|synchronized' | sed 's/^/  /'
    fi
    # 显示实际使用的 NTP 服务器
    if uxs_svc is-active systemd-timesyncd 2>/dev/null; then
        echo "  $(_t 'Backend: systemd-timesyncd')"
        local conf="/etc/systemd/timesyncd.conf"
        if [[ -f "$conf" ]] && grep -q '^NTP=' "$conf"; then
            echo "  $(_t 'Config'): $(grep '^NTP=' "$conf")"
        else
            echo "  $(_t 'Config: (default)')"
        fi
    elif os_has_cmd chronyc 2>/dev/null; then
        echo "  $(_t 'Backend: chrony')"
        chronyc sources 2>/dev/null | head -8 | sed 's/^/  /'
    elif os_has_cmd ntpq 2>/dev/null; then
        echo "  $(_t 'Backend: ntpd')"
        ntpq -p 2>/dev/null | head -8 | sed 's/^/  /'
    else
        echo "  $(_t '(No NTP service detected)')"
    fi
}

# NTP 交互式设置
do_ntp() {
    preflight
    info "$(_t '🕐 Configuring the NTP time synchronization servers')"
    echo

    show_ntp_status
    echo

    menu "$(_t 'Please choose an NTP server option:')"
    echo "  1) $(_t 'Aliyun')     ($NTP_PRESET_ALIYUN)"
    echo "  2) $(_t 'Tsinghua TUNA')  ($NTP_PRESET_TUNA)"
    echo "  3) $(_t 'Huawei Cloud')     ($NTP_PRESET_HUAWEI)"
    echo "  4) $(_t 'China NTP')   ($NTP_PRESET_CSTTIME)"
    echo "  5) NTP Pool   ($NTP_PRESET_NTPPOOL)"
    echo "  6) Google     ($NTP_PRESET_GOOGLE)"
    echo "  7) $(_t 'Custom (enter the NTP server address manually)')"
    echo "  0) $(_t 'Cancel')"
    echo "========================================"

    local choice
    read -r -p "$(_t 'Please enter an option [0-7]: ')" choice

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
            info "$(_t 'Please enter the NTP server addresses (separate them with spaces):')"
            info "$(_t 'Example: ntp.aliyun.com ntp1.aliyun.com')"
            read -r -p "> " servers
            # 去除首尾空白
            servers=$(echo "$servers" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -z "$servers" ]]; then
                warn "$(_t 'No server entered, cancelled')"
                return 0
            fi
            # 基本校验：每个词应像合法主机名（含字母/数字/点/连字符）
            local word
            for word in $servers; do
                if [[ ! "$word" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
                    error "$(_tf 'Invalid server address: %s' "$word")"
                    info "$(_t 'Only letters, digits, dots and hyphens are allowed, e.g. ntp.aliyun.com')"
                    return 1
                fi
            done
            ;;
        0|*) info "$(_t 'Cancelled')"; return 0 ;;
    esac

    echo
    info "$(_tf 'About to configure the NTP servers: %s' "$servers")"
    if ! yes_no "$(_t 'Continue?')"; then
        info "$(_t 'Cancelled')"; return 0
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
    info "$(_tf '🕐 Setting the timezone to %s and enabling time synchronization' "$tz")"

    if os_has_cmd timedatectl; then
        sudo timedatectl set-timezone "$tz"
        success "$(_tf 'The timezone has been set to %s' "$tz")"
        # 优先启用 systemd-timesyncd
        if uxs_svc list-unit-files 2>/dev/null | grep -q systemd-timesyncd; then
            uxs_svc enable-now systemd-timesyncd 2>/dev/null || true
            sudo timedatectl set-ntp true 2>/dev/null || true
            success "$(_t 'systemd-timesyncd (NTP) has been enabled')"
        fi
    else
        sudo ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        success "$(_tf 'The timezone has been set to %s (symlink)' "${tz}")"
    fi

    # 没有 timesyncd 时回退装 chrony（unit 名是名词：debian 系 chrony、rhel 系 chronyd）
    if ! uxs_svc is-active systemd-timesyncd 2>/dev/null; then
        if pkg_install chrony 2>/dev/null; then
            local unit="chronyd"
            [[ "$DISTRO_FAMILY" == "debian" ]] && unit="chrony"
            uxs_svc enable-now "$unit" 2>/dev/null || true
            success "$(_t 'chrony time synchronization has been installed and enabled')"
        else
            warn "$(_t 'Installing chrony failed, skipping the time synchronization setup')"
        fi
    fi
}

# -------- 3. 系统参数优化 --------
do_optimize() {
    preflight
    info "$(_t '⚙️  Optimizing the system parameters (file descriptors, kernel)')"

    # 文件描述符上限
    local limits_file=/etc/security/limits.d/99-unix-script.conf
    sudo tee "$limits_file" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— 提升文件描述符上限
*               soft    nofile          65536
*               hard    nofile          65536
root            soft    nofile          65536
root            hard    nofile          65536
EOF
    success "$(_tf 'The file descriptor limit has been raised to 65536 (%s)' "${limits_file}")"

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
    success "$(_tf 'The kernel optimization parameters have been written (%s)' "${sysctl_file}")"
}

# -------- 4. SSH 加固 --------
do_ssh() {
    preflight
    info "$(_t '🔐 SSH hardening (disable password login and root login)')"

    local sshd_config
    for sshd_config in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/99-unix-script.conf; do
        if [[ -f "$sshd_config" ]]; then break; fi
    done
    # 优先用 sshd_config.d drop-in（更干净）
    local dropin=/etc/ssh/sshd_config.d/99-unix-script.conf
    sudo mkdir -p /etc/ssh/sshd_config.d

    warn "$(_t 'SSH hardening is sensitive: password and root login will be disabled.')"
    warn "$(_t 'Set up SSH key login first, otherwise you may not be able to log in!')"
    if ! yes_no "$(_t 'Continue (only if the key login is already set up)?')"; then
        info "$(_t 'SSH hardening has been skipped')"; return 0
    fi

    sudo tee "$dropin" >/dev/null <<'EOF'
# 由 unix_script sys-setup 生成 —— SSH 加固
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
    success "$(_tf 'The SSH hardening configuration has been written (%s)' "${dropin}")"

    if os_has_cmd systemctl; then
        uxs_svc reload sshd 2>/dev/null || uxs_svc reload ssh 2>/dev/null || true
        success "$(_t 'sshd has been reloaded (the configuration applies to new connections)')"
    fi
}

# -------- 5. 自动安全更新 --------
do_autoupdate() {
    preflight
    info "$(_t '🛡️  Enabling the automatic security updates')"
    local rc=0
    _load_platform || rc=$?
    if [[ "$rc" == "2" ]]; then
        warn "$(_t 'Unsupported distribution (unknown family), skipping the auto update')"
        return 0
    fi
    if [[ "$rc" != "0" ]]; then
        return 1
    fi
    plat_autoupdate
}

# -------- 全部执行 --------
do_all() {
    info "$(_t '🚀 Running all the essential system setups')"
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
    success "$(_t '🎉 All the essential system setups are complete')"
}

# -------- 状态 --------
status_sys_setup() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        uxs_emit_status "n/a" "${YELLOW}$(_t '⚠️  Not applicable (Linux only)')${NC}"; return
    fi

    # ---- 先计算各子项的事实，用于聚合并聚态与 uxs_emit_extra ----
    # 镜像源（现代 Ubuntu/Debian 的发行版源在 sources.list.d/*.sources，需一并检测）
    local mirror_ok=false mirror_val; mirror_val="$(_t 'Default source')"
    if grep -qs "tuna.tsinghua\|mirrors.aliyun\|mirrors.ustc" /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null; then
        mirror_ok=true; mirror_val="$(_t 'Domestic mirror source in use')"
    fi
    # 时区
    local tz_val
    tz_val=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
    # NTP 同步开关
    local ntp_sync
    ntp_sync=$(timedatectl show -p NTP --value 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
    # NTP 服务器（含后端）
    local ntp_servers ntp_backend="" ntp_val=""; ntp_servers="$(_t '(system default)')"
    if uxs_svc is-active systemd-timesyncd 2>/dev/null; then
        ntp_backend="timesyncd"
        local ntp_conf="/etc/systemd/timesyncd.conf"
        if [[ -f "$ntp_conf" ]] && grep -q '^NTP=' "$ntp_conf" 2>/dev/null; then
            ntp_servers=$(grep '^NTP=' "$ntp_conf" | sed 's/^NTP=//')
        fi
        ntp_val="$ntp_servers (timesyncd)"
    elif os_has_cmd chronyc 2>/dev/null; then
        ntp_backend="chrony"
        ntp_val="$(_t '(chrony, view with chronyc sources)')"
    elif os_has_cmd ntpq 2>/dev/null; then
        ntp_backend="ntpd"
        ntp_val="$(_t '(ntpd, view with ntpq -p)')"
    fi
    # 文件描述符（ulimit）
    local fd_ok=false fd_state; fd_state="$(_t 'Default')"
    if [[ -f /etc/security/limits.d/99-unix-script.conf ]]; then fd_ok=true; fd_state="$(_t '✅ Optimized')"; fi
    # SSH 加固
    local ssh_ok=false ssh_state; ssh_state="$(_t 'Default')"
    if [[ -f /etc/ssh/sshd_config.d/99-unix-script.conf ]]; then ssh_ok=true; ssh_state="$(_t '✅ Hardened')"; fi

    # ---- 聚合主状态：镜像源/fd/ssh 全部 ✅ → configured，否则 not_configured ----
    if $mirror_ok && $fd_ok && $ssh_ok; then
        uxs_emit_status "configured" "${GREEN}$(_t '✅ The system configuration is complete')${NC}"
    else
        uxs_emit_status "not_configured" "${YELLOW}$(_t '⚠️  The system configuration is not complete')${NC}"
    fi

    # ---- 机器模式 EXTRA 行（每个子项一条）----
    uxs_emit_extra "mirror=$mirror_val"
    uxs_emit_extra "timezone=$tz_val"
    uxs_emit_extra "ntp_sync=$ntp_sync"
    if [[ -n "$ntp_backend" ]]; then
        uxs_emit_extra "ntp_backend=$ntp_backend"
        uxs_emit_extra "ntp_servers=$ntp_servers"
    fi
    uxs_emit_extra "ulimit=$($fd_ok && echo optimized || echo default)"
    uxs_emit_extra "ssh=$($ssh_ok && echo hardened || echo default)"

    # ---- 人类模式：保留原始多行配置概览 ----
    if ! uxs_is_machine_mode; then
        printf '%s\n' "$(_t 'Package source mirror:')"
        if $mirror_ok; then
            echo -e "  ${GREEN}$(_t '✅ Domestic mirror source in use')${NC}"
        else
            echo -e "  ${YELLOW}$(_t '⚠️  Default source')${NC}"
        fi
        printf '%s\n' "$(_tf 'Timezone: %s' "$tz_val")"
        printf '%s\n' "$(_tf 'NTP sync: %s' "$ntp_sync")"
        if [[ -n "$ntp_val" ]]; then
            printf '%s\n' "$(_tf 'NTP servers: %s' "$ntp_val")"
        fi
        printf '%s\n' "$(_tf 'File descriptor limit: %s' "$fd_state")"
        printf '%s\n' "$(_tf 'SSH hardening: %s' "$ssh_state")"
    fi
}

usage() {
    cat <<EOF
用法: $0 {mirror|timezone|ntp|optimize|ssh|autoupdate|all|status|help}  (仅 Linux)

  mirror      $(_t 'Switch to domestic mirrors (Alma/Rocky/Fedora/openEuler/Anolis/deepin)')
  timezone    $(_t 'Set the timezone and enable NTP sync (default Asia/Shanghai)')
  ntp         $(_t 'Configure custom NTP servers (Aliyun/TUNA/Huawei/Google/custom)')
  optimize    $(_t 'Optimize system parameters (file descriptors, TCP, kernel)')
  ssh         $(_t 'SSH hardening (disable password and root login, set up keys first)')
  autoupdate  $(_t 'Enable the automatic security updates')
  all         $(_t 'Run all of the above')
  status      $(_t 'View the status of each configuration')
EOF
}

# 卸载：仅移除本工具写入的「增量 drop-in」配置（可逆），不动镜像源/NTP 等需手动还原项。
# 移除的文件均为 99-unix-script.conf 增量配置，删掉即恢复系统默认值。
uninstall_sys_setup() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        info "$(_t 'The sys-setup uninstall only applies to Linux, nothing to do here')"
        return 0
    fi
    info "$(_t 'Removing the incremental drop-in configs written by sys-setup...')"
    require_sudo
    local removed=0
    local f
    for f in \
        /etc/security/limits.d/99-unix-script.conf \
        /etc/sysctl.d/99-unix-script.conf \
        /etc/ssh/sshd_config.d/99-unix-script.conf; do
        if [[ -f "$f" ]]; then
            sudo rm -f "$f"
            success "$(_tf 'Removed: %s' "$f")"
            removed=$((removed + 1))
        fi
    done
    # 应用 sysctl 变更（drop-in 删除后重新加载系统默认）
    sudo sysctl --system >/dev/null 2>&1 || true
    if [[ $removed -eq 0 ]]; then
        info "$(_t 'No sys-setup drop-in config found (optimize/ssh may not have run)')"
    else
        success "$(_tf 'Removed %s drop-in configurations, the system defaults are restored' "$removed")"
    fi
    warn "$(_t 'The mirror/NTP changes have .bak.* backups, find them to restore:')"
    warn "  ls -t /etc/apt/sources.list.bak.* /etc/yum.repos.d/*.bak.* 2>/dev/null"
    warn "$(_tf 'The SSH service policy is restored, review it if you changed sshd: %s' "sudo sshd -t && sudo systemctl restart sshd")"
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
