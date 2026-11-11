#!/usr/bin/env bash
#
# ufw/install.sh
#
# 安装与配置 UFW 防火墙（仅 Linux）。macOS 自带防火墙，跳过并提示。
#
# 功能：
#   - 通过 apt/yum/dnf 安装 ufw
#   - 配置默认策略：deny incoming / allow outgoing
#   - 放行 SSH（22 端口，防止锁定）
#   - 可选放行 HTTP（80）/ HTTPS（443）
#   - 启用防火墙
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "macOS $(_t 'macOS ships with an application firewall, so UFW does not apply.')"
        info "$(_t 'To configure the macOS firewall: System Settings > Network > Firewall')"
        exit 0
    fi
}

install_ufw() {
    preflight
    require_sudo
    detect_pkg_manager
    info "$(_tf 'Starting the UFW firewall installation (package manager: %s)' "${PKG_MANAGER}")"

    if command_exists ufw; then
        local cur
        cur=$(ufw version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
        warn "$(_tf 'UFW detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reconfigure the default rules?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi

    info "$(_t 'Installing ufw...')"
    if ! pkg_install ufw; then
        error "ufw $(_tf 'Installation failed (package manager: %s)' "${PKG_MANAGER}")"
        exit 1
    fi

    if ! command_exists ufw; then
        error "$(_t 'Installation failed: the ufw command was not found')"
        exit 1
    fi

    # 配置默认策略
    info "$(_t 'Configuring the default policy...')"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # 放行 SSH —— 关键步骤，防止锁定
    warn "$(_t '[IMPORTANT] Allow SSH (port 22) so remote access is not lost once the firewall is enabled')"
    sudo ufw allow ssh

    # 可选：放行 HTTP / HTTPS
    echo
    info "$(_t 'Optional: allow the common web ports')"
    if yes_no "$(_t 'Allow HTTP (80) and HTTPS (443)?')"; then
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        info "$(_t 'Allowed 80/tcp and 443/tcp')"
    else
        info "$(_t 'Skipped allowing the web ports (add them later with: sudo ufw allow 80/tcp)')"
    fi

    # 启用防火墙
    echo
    info "$(_t 'Enabling the UFW firewall...')"
    sudo ufw --force enable

    success "UFW $(_t 'The firewall has been enabled')"
    echo
    info "$(_t 'Current rules:')"
    sudo ufw status verbose
    echo
    info "$(_t 'Common management commands:')"
    echo "  sudo ufw status              # $(_t 'View the status')"
    echo "  sudo ufw status verbose      # $(_t 'Detailed status (including the rules)')"
    echo "  sudo ufw allow <port>/tcp    # $(_t 'Allow a port')"
    echo "  sudo ufw deny <port>/tcp     # $(_t 'Deny a port')"
    echo "  sudo ufw delete allow <port> # $(_t 'Delete a rule')"
    echo "  sudo ufw reload              # $(_t 'Reload the rules')"
}

uninstall_ufw() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! yes_no "$(_t 'Uninstall the UFW firewall? All firewall rules will be lost afterwards.')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    info "$(_t 'Disabling UFW...')"
    sudo ufw disable 2>/dev/null || true

    info "$(_t 'Removing the ufw package...')"
    pkg_remove ufw 2>/dev/null || warn "ufw $(_t 'Failed to remove the package, uninstall it manually')"

    success "UFW $(_t 'The firewall has been uninstalled and disabled.')"
    warn "$(_t 'Note: after the uninstall the system has no firewall protection, make sure you have other safeguards.')"
}

status_ufw() {
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then
        emit_status "n/a" "${YELLOW}$(_t 'Not applicable (macOS ships with an application firewall)')${NC}"
        if ! uxs_is_machine_mode; then
            printf '%s\n' "$(_t 'Configuration path: System Settings > Network > Firewall')"
        fi
        return
    fi
    if ! command_exists ufw; then
        emit_status "not_installed" "${RED}$(_t 'Not installed')${NC}"
        return
    fi
    # 三级降级：sudo -n ufw status → systemctl is-active ufw → 兜底 installed。
    # 防 set -e/pipefail 中止：所有命令替换带 || true，任何路径必须落到一个 emit_status。
    local ufw_status sysd
    ufw_status=""
    if ufw_status=$(sudo -n ufw status 2>/dev/null | head -1 || true) && [[ -n "$ufw_status" ]]; then
        # 精确匹配 active（排除 inactive 子串误匹配——"Status: inactive" 含 "active"）
        if [[ "$ufw_status" == *"active"* && "$ufw_status" != *"inactive"* ]]; then
            emit_status "configured" "${GREEN}$(_t 'Installed and enabled')${NC}"
            if ! uxs_is_machine_mode; then
                echo
                sudo -n ufw status verbose 2>/dev/null || sudo ufw status verbose
            fi
        else
            emit_status "not_configured" "${YELLOW}$(_t 'Installed but not enabled')${NC}"
        fi
        return
    fi
    # sudo 不可用（无凭据/无 TTY）：降级 systemd 单元状态
    if command_exists systemctl && sysd=$(systemctl is-active ufw 2>/dev/null || true); then
        if [[ "$sysd" == "active" ]]; then
            emit_status "installed:running" "${GREEN}$(_t 'Installed and the service is running (degraded detection)')${NC}"
        else
            emit_status "installed" "${YELLOW}$(_t 'Installed (sudo unavailable, degraded detection)')${NC}"
        fi
        return
    fi
    # systemctl 也没有：命令存在即视为已装
    emit_status "installed" "${YELLOW}$(_t 'Installed (the detailed status cannot be read)')${NC}"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install and enable the UFW firewall (set the default policy and allow SSH)')
  uninstall   $(_t 'Disable and uninstall UFW')
  status      $(_t 'View the firewall status and rules')
  help        $(_t 'Show the help')

$(_t '⚠️  Security note: SSH (port 22) is allowed automatically before the firewall is enabled, so remote access is not locked out.')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_ufw ;;
        uninstall) uninstall_ufw ;;
        status)    status_ufw ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
