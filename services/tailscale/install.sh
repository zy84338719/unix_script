#!/usr/bin/env bash
#
# tailscale/install.sh
#
# 安装与管理 Tailscale（基于官方一键安装脚本）。
# 支持 Linux（apt/yum/dnf，由官方脚本处理）与 macOS（Homebrew）。
#
# 子命令（可被主菜单非交互调用）：
#   install           安装/更新 Tailscale
#   uninstall         卸载 Tailscale
#   status            查看状态
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 官方一键安装脚本
OFFICIAL_INSTALLER="https://tailscale.com/install.sh"

# 检查操作系统与依赖
preflight() {
    detect_os
    case "$OS_TYPE" in
        linux)  check_commands curl ;;
        darwin)
            if ! os_has_cmd brew; then
                error "macOS $(_t 'requires Homebrew to be installed first: https://brew.sh/')"
                exit 1
            fi
            ;;
    esac
}

# 安装 Tailscale
install_tailscale() {
    preflight
    info "$(_t '🚀 Starting the Tailscale installation')"

    if os_has_cmd tailscale; then
        local cur
        cur=$(tailscale version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
        warn "$(_tf 'Tailscale detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and try to update?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        info "$(_t 'Using the official one-line install script (works on apt/yum/dnf distributions)...')"
        require_sudo
        if ! curl -fsSL "$OFFICIAL_INSTALLER" | sudo sh; then
            error "$(_t 'The official install script failed, check the network or install it manually')"
            exit 1
        fi
        uxs_svc enable-now tailscaled || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing Tailscale via Homebrew...')"
        brew install tailscale
        # macOS 上 tailscaled 由 brew services 管理
        brew services start tailscale || true
    fi

    if ! os_has_cmd tailscale; then
        error "$(_t 'The tailscale command is still not found after the install, check PATH or open a new terminal')"
        exit 1
    fi

    success "Tailscale $(_t 'Installation complete!')"
    echo
    info "$(_t 'Next step: log in and enable the node')"
    echo "  sudo tailscale up"
    echo
    info "$(_t 'Common commands:')"
    echo "  tailscale status        # $(_t 'Show the nodes and the connection status')"
    echo "  tailscale ip            # $(_t 'Show the Tailscale IP of this machine')"
    echo "  sudo tailscale down     # $(_t 'Disconnect')"
    echo "  sudo tailscale up       # $(_t 'Reconnect / log in')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status tailscaled"
        echo "  sudo journalctl -u tailscaled -f"
    fi
}

# 卸载 Tailscale
uninstall_tailscale() {
    preflight
    warn "$(_t 'About to uninstall Tailscale.')"
    if ! yes_no "$(_t 'Confirm uninstall?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        require_sudo
        uxs_svc disable-now tailscaled 2>/dev/null || true
        detect_pkg_manager
        if ! pkg_remove tailscale; then
            warn "$(_tf 'The automatic uninstall failed (%s), uninstall tailscale manually' "${PKG_MANAGER}")"
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop tailscale 2>/dev/null || true
        brew uninstall tailscale
    fi

    success "Tailscale $(_t 'Uninstalled.')"
}

# 状态检查（供主菜单“查看状态”调用，输出一行结论）
status_tailscale() {
    if ! os_has_cmd tailscale; then
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
        return
    fi
    local running=false
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc is-active tailscaled 2>/dev/null && running=true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        # 不用 `| grep -q`：grep 命中即退会给上游 SIGPIPE(141)，pipefail 下整条管道非 0，
        # 会把「已启动」误判成「未运行」。先把输出收进变量，再用读完整个输入的 grep 匹配。
        local brew_svcs
        brew_svcs=$(brew services list 2>/dev/null) || brew_svcs=""
        printf '%s\n' "$brew_svcs" | grep "tailscale.*started" >/dev/null && running=true
    fi
    local ver
    # 不用 `| head -1`：head 命中即退会给上游 SIGPIPE(141)；grep 无匹配时退出 1。
    # 两者在 pipefail 下都会让整条管道非 0，set -e 会让 status 子命令整体中止
    # （违反「状态子命令恒 0」契约）。改用 sed 取首行（sed 读完整个输入才退出），
    # 取不到版本号就回落成空值。
    ver=$(tailscale version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | sed -n '1p') || ver=""
    if $running; then
        uxs_emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC}"
    else
        uxs_emit_status "installed:stopped" "${YELLOW}$(_t '⚠️ Installed but the service is not running')${NC}"
    fi
    # 收尾用 if 而不是 `[[ -n "$ver" ]] && ...`：后者在版本号为空时返回 1，
    # 会让 status 子命令整体退出 1（同样是「status 恒 0」契约）。
    if [[ -n "$ver" ]]; then
        uxs_emit_version "$ver"
    fi
    return 0
}

# 用法
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status}

  install     $(_t 'Install or update Tailscale')
  uninstall   $(_t 'Uninstall Tailscale')
  status      $(_t 'View the install and run status')
  help        $(_t 'Show this help')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_tailscale ;;
        uninstall) uninstall_tailscale ;;
        status)    status_tailscale ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
