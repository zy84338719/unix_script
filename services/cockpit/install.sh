#!/usr/bin/env bash
#
# cockpit/install.sh
#
# 安装与管理 Cockpit —— Linux 的 Web 服务器管理图形面板。
# 仅 Linux（依赖 systemd）。提供 Web UI（默认 9090 端口）管理系统。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

COCKPIT_PORT=9090

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_tf 'Cockpit is Linux-only (requires systemd). Current: %s' "$OS_TYPE")"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "$(_t 'systemctl (systemd) is required.')"
        exit 1
    fi
}

install_cockpit() {
    preflight
    require_sudo
    detect_pkg_manager
    info "$(_t 'Starting Cockpit installation (package manager: ')${PKG_MANAGER}$(_t ')')"

    if command_exists cockpit-bridge 2>/dev/null || rpm -q cockpit >/dev/null 2>&1 || dpkg -s cockpit >/dev/null 2>&1; then
        warn "$(_t 'Detected Cockpit installed')"
        if ! yes_no "$(_t 'Continue and reinstall/update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    info "$(_t 'Installing cockpit...')"
    if ! pkg_install cockpit; then
        error "$(_t 'cockpit install failed (package manager: ')${PKG_MANAGER}$(_t ')')"
        exit 1
    fi

    if ! command_exists cockpit-bridge 2>/dev/null; then
        error "$(_t 'Install failed: cockpit-bridge not found')"
        exit 1
    fi

    info "$(_t 'Enabling and starting cockpit.socket (on-demand activation socket, more secure)...')"
    uxs_svc enable-now cockpit.socket 2>/dev/null || uxs_svc enable-now cockpit 2>/dev/null || true

    # 放行防火墙（若存在）
    if command_exists firewall-cmd; then
        sudo firewall-cmd --add-service=cockpit --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        success "$(_t 'Firewall cockpit service allowed')"
    fi
    if command_exists ufw; then
        sudo ufw allow "$COCKPIT_PORT"/tcp 2>/dev/null || true
        success "$(_tf 'Allowed ufw %s/tcp' "$COCKPIT_PORT")"
    fi

    info "$(_t 'Verifying...')"
    sleep 2
    if uxs_svc is-active cockpit.socket 2>/dev/null || uxs_svc is-active cockpit 2>/dev/null; then
        success "$(_t 'Cockpit socket/service running normally')"
    else
        warn "$(_t 'Cockpit service not running (normal in socket mode, activates on first visit)')"
    fi

    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "$(_t 'Cockpit installation complete!')"
    info "$(_tf 'Access URL: https://%s:%s' "${ip_addr}" "${COCKPIT_PORT}")"
    warn "$(_t 'Log in with a system user account (the user needs sudo privileges for management operations).')"
    info "$(_t 'Common commands:')"
    echo "  sudo systemctl status cockpit.socket"
    echo "  sudo journalctl -u cockpit -f"
}

uninstall_cockpit() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! yes_no "$(_t 'Confirm uninstall of Cockpit?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    uxs_svc disable-now cockpit.socket 2>/dev/null || true
    uxs_svc disable-now cockpit 2>/dev/null || true
    pkg_remove cockpit 2>/dev/null || warn "$(_t 'Failed to remove cockpit package, uninstall it manually')"
    if command_exists firewall-cmd; then
        sudo firewall-cmd --remove-service=cockpit --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
    fi
    success "$(_t 'Cockpit uninstalled.')"
}

status_cockpit() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  $(_t 'Not applicable (Linux only)')${NC}"; return
    fi
    if ! command_exists cockpit-bridge 2>/dev/null && ! rpm -q cockpit >/dev/null 2>&1 && ! dpkg -s cockpit >/dev/null 2>&1; then
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"; return
    fi
    if uxs_svc is-active cockpit.socket 2>/dev/null || uxs_svc is-active cockpit 2>/dev/null; then
        emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed (socket mode, activates on access)')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Cockpit (Web management panel, Linux only, default port 9090)')
  uninstall   $(_t 'Uninstall Cockpit')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_cockpit ;;
        uninstall) uninstall_cockpit ;;
        status)    status_cockpit ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
