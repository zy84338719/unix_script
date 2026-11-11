#!/usr/bin/env bash
#
# bbr/install.sh
#
# 开启 TCP BBR 拥塞控制算法，提升网络吞吐（尤其高延迟/丢包链路）。仅 Linux。
# 要求内核 >= 4.9（BBR 自 4.9 起内置）。
#
# 子命令：install(enable) | uninstall(disable) | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

SYSCTL_FILE=/etc/sysctl.d/99-bbr.conf

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "BBR $(_tf 'Linux only (kernel feature). Current: %s' "$OS_TYPE")"
        exit 1
    fi
}

check_kernel() {
    local kver
    kver=$(uname -r | cut -d. -f1-2)
    local major minor
    major=$(echo "$kver" | cut -d. -f1)
    minor=$(echo "$kver" | cut -d. -f2)
    if [[ "$major" -lt 4 ]] || { [[ "$major" -eq 4 ]] && [[ "$minor" -lt 9 ]]; }; then
        error "$(_tf 'The kernel version %s is too old, BBR needs a kernel >= 4.9' "$kver")"
        exit 1
    fi
}

enable_bbr() {
    preflight
    require_sudo
    check_kernel
    info "$(_t '🚀 Enabling the TCP BBR congestion control')"

    # 检查内核是否支持 bbr 模块
    if ! modprobe tcp_bbr 2>/dev/null && ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
        warn "tcp_bbr $(_t 'The module failed to load, the kernel may not have been built with BBR support. It will try to write the configuration and reload.')"
    fi

    sudo tee "$SYSCTL_FILE" >/dev/null <<'EOF'
# 由 unix_script bbr 模块生成 —— 开启 BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true

    local algo
    algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$algo" == "bbr" ]]; then
        success "BBR $(_t 'It has been enabled (the current congestion control algorithm: bbr)')"
    else
        error "BBR $(_tf 'The enabling failed, the current algorithm is still: %s' "$algo")"
        return 1
    fi
    info "$(_t 'Queue rule:')$(sysctl -n net.core.default_qdisc 2>/dev/null)"
}

disable_bbr() {
    preflight
    require_sudo
    if [[ ! -f "$SYSCTL_FILE" ]]; then
        warn "$(_t 'The BBR configuration file was not found, BBR may not be enabled')"
        return 0
    fi
    sudo rm -f "$SYSCTL_FILE"
    # 恢复默认算法（cubic 是大多数发行版默认）
    sudo sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1 || true
    sudo sysctl -w net.core.default_qdisc=pfifo_fast >/dev/null 2>&1 || \
        sudo sysctl -w net.core.default_qdisc=fq_codel >/dev/null 2>&1 || true
    success "BBR $(_t 'It has been disabled (the default congestion control is restored)')"
}

status_bbr() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        uxs_emit_status "n/a" "${YELLOW}$(_t '⚠️  Not applicable (Linux only)')${NC}"; return
    fi
    local algo qdisc
    algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
    if [[ "$algo" == "bbr" ]]; then
        uxs_emit_status "configured" "${GREEN}$(_t '✅ BBR is enabled')${NC}$(_tf '(qdisc=%s)' "${qdisc}")"
        uxs_emit_extra "qdisc=$qdisc"
        uxs_emit_extra "algorithm=$algo"
    else
        uxs_emit_status "not_configured" "${YELLOW}$(_t '⚠️  BBR is not enabled')${NC}$(_tf '(the current algorithm: %s)' "${algo}")"
        uxs_emit_extra "qdisc=$qdisc"
        uxs_emit_extra "algorithm=$algo"
    fi
}

usage() {
    cat <<EOF
用法: $0 {enable|disable|status|help}  (仅 Linux, 内核 >= 4.9)

  enable, install    $(_t 'Enable the TCP BBR')
  disable, uninstall $(_t 'Disable BBR (restore the default)')
  status             $(_t 'View the current congestion control algorithm')
EOF
}

main() {
    local action="${1:-enable}"
    detect_os
    case "$action" in
        enable|install)    enable_bbr ;;
        disable|uninstall) disable_bbr ;;
        status)            status_bbr ;;
        help|--help|-h)    usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
