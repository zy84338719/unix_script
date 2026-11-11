#!/usr/bin/env bash
#
# fail2ban/install.sh
#
# 安装与配置 Fail2ban（仅 Linux）。macOS 不适用（依赖 iptables/systemd）。
#
# 功能：
#   - 通过 apt/yum/dnf 安装 fail2ban
#   - 写入一份保护 sshd 的默认 /etc/fail2ban/jail.local
#   - 启用并启动 systemd 服务
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

JAIL_LOCAL="/etc/fail2ban/jail.local"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_tf 'Fail2ban is Linux-only (depends on iptables/systemd). Current system: %s' "$OS_TYPE")"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "$(_t 'systemctl (systemd) is required. The current system may not support it.')"
        exit 1
    fi
}

# 生成默认 jail.local 内容
gen_jail_local() {
    cat <<EOF
# 由 unix_script fail2ban 模块生成
# 参考：https://github.com/fail2ban/fail2ban

[DEFAULT]
# 封禁时长（秒）。1h = 3600，1d = 86400
bantime  = 3600
# 统计窗口（秒）
findtime = 600
# 窗口内失败次数达到即封禁
maxretry = 5
# 不封禁本机与内网（按需调整）
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

[sshd]
enabled = true
backend = systemd
EOF
}

install_fail2ban() {
    preflight
    require_sudo
    detect_pkg_manager
    info "🚀 $(_tf 'Starting the Fail2ban installation (package manager: %s)' "$PKG_MANAGER")"

    if command_exists fail2ban-client; then
        local cur
        cur=$(fail2ban-client --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
        warn "$(_tf 'Detected Fail2ban installed (%s)' "$cur")"
        if ! yes_no "$(_t 'Continue and rewrite the default jail.local?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi

    info "$(_t 'Installing fail2ban...')"
    ensure_epel
    if ! pkg_install fail2ban; then
        error "$(_tf 'fail2ban install failed (package manager: %s)' "$PKG_MANAGER")"
        exit 1
    fi

    if ! command_exists fail2ban-client; then
        error "$(_t 'Install failed: fail2ban-client not found')"
        exit 1
    fi

    # 写入默认 jail.local（如已存在则备份）
    if [[ -f "$JAIL_LOCAL" ]]; then
        sudo cp -a "$JAIL_LOCAL" "$JAIL_LOCAL.bak.$(date +%s)"
        warn "$(_tf 'Backed up the existing %s to .bak.*' "$JAIL_LOCAL")"
    fi
    info "$(_tf 'Writing the default %s (it protects sshd)...' "$JAIL_LOCAL")"
    gen_jail_local | sudo tee "$JAIL_LOCAL" >/dev/null

    info "$(_t 'Enabling and starting fail2ban...')"
    uxs_svc enable-now fail2ban
    uxs_svc restart fail2ban

    # 验证
    info "$(_t 'Verifying...')"
    sleep 2
    if uxs_svc is-active fail2ban; then
        success "$(_t 'The fail2ban service is running normally')"
    else
        error "$(_t 'The fail2ban service is not running normally; check the logs:')"
        echo "  sudo systemctl status fail2ban"
        echo "  sudo journalctl -u fail2ban -f"
        return 1
    fi

    echo
    success "🎉 $(_t 'Fail2ban installation complete!')"
    info "$(_t 'View the ban status:')"
    echo "  sudo fail2ban-client status"
    echo "  sudo fail2ban-client status sshd"
    echo "  sudo tail -f /var/log/fail2ban.log"
    echo
    info "$(_tf 'To tune the policy, edit %s, then:' "$JAIL_LOCAL")"
    echo "  sudo systemctl restart fail2ban"
}

uninstall_fail2ban() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! yes_no "$(_t 'Confirm uninstall of Fail2ban?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    uxs_svc disable-now fail2ban 2>/dev/null || true
    pkg_remove fail2ban 2>/dev/null || warn "$(_t 'Failed to remove the fail2ban package, uninstall it manually')"

    if [[ -f "$JAIL_LOCAL" ]]; then
        if yes_no "$(_tf 'Delete %s (the .bak.* backup is kept)?' "$JAIL_LOCAL")"; then
            sudo rm -f "$JAIL_LOCAL"
            success "$(_tf '%s deleted.' "$JAIL_LOCAL")"
        fi
    fi
    success "$(_t 'Fail2ban uninstalled.')"
}

status_fail2ban() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  $(_t 'Not applicable (Linux only)')${NC}"
        return
    fi
    if ! command_exists fail2ban-client; then
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"
        return
    fi
    if uxs_svc is-active fail2ban 2>/dev/null; then
        emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed but service not running')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Fail2ban and write the default config that protects sshd')
  uninstall   $(_t 'Uninstall Fail2ban')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_fail2ban ;;
        uninstall) uninstall_fail2ban ;;
        status)    status_fail2ban ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
