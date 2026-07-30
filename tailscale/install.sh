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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# 官方一键安装脚本
OFFICIAL_INSTALLER="https://tailscale.com/install.sh"

# 检查操作系统与依赖
preflight() {
    detect_os
    case "$OS_TYPE" in
        linux)  check_commands curl ;;
        darwin)
            if ! command_exists brew; then
                error "macOS 上需要先安装 Homebrew：https://brew.sh/"
                exit 1
            fi
            ;;
    esac
}

# 安装 Tailscale
install_tailscale() {
    preflight
    info "🚀 开始安装 Tailscale"

    if command_exists tailscale; then
        local cur
        cur=$(tailscale version 2>/dev/null | head -1 || echo "未知版本")
        warn "检测到已安装 Tailscale（$cur）"
        if ! yes_no "是否继续并尝试更新？"; then
            info "已取消"
            return 0
        fi
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        info "使用官方一键安装脚本（适用于 apt/yum/dnf 等发行版）..."
        require_sudo
        if ! curl -fsSL "$OFFICIAL_INSTALLER" | sudo sh; then
            error "官方安装脚本执行失败，请检查网络或手动安装"
            exit 1
        fi
        sudo systemctl enable --now tailscaled || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 Tailscale..."
        brew install tailscale
        # macOS 上 tailscaled 由 brew services 管理
        brew services start tailscale || true
    fi

    if ! command_exists tailscale; then
        error "安装后仍找不到 tailscale 命令，请检查 PATH 或重新打开终端"
        exit 1
    fi

    success "Tailscale 安装完成！"
    echo
    info "下一步：登录并启用节点"
    echo "  sudo tailscale up"
    echo
    info "常用命令："
    echo "  tailscale status        # 查看节点与连接状态"
    echo "  tailscale ip            # 查看本机 Tailscale IP"
    echo "  sudo tailscale down     # 断开"
    echo "  sudo tailscale up       # 重新连接 / 登录"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status tailscaled"
        echo "  sudo journalctl -u tailscaled -f"
    fi
}

# 卸载 Tailscale
uninstall_tailscale() {
    preflight
    warn "即将卸载 Tailscale。"
    if ! yes_no "确认卸载？"; then
        info "已取消"
        return 0
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        require_sudo
        sudo systemctl disable --now tailscaled 2>/dev/null || true
        detect_pkg_manager
        case "$PKG_MANAGER" in
            apt-get) sudo apt-get remove --purge -y tailscale ;;
            dnf)     sudo dnf remove -y tailscale ;;
            yum)     sudo yum remove -y tailscale ;;
            *)
                error "无法识别包管理器，请手动卸载 tailscale"
                exit 1
                ;;
        esac
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop tailscale 2>/dev/null || true
        brew uninstall tailscale
    fi

    success "Tailscale 已卸载。"
}

# 状态检查（供主菜单“查看状态”调用，输出一行结论）
status_tailscale() {
    if ! command_exists tailscale; then
        echo -e "${RED}❌ 未安装${NC}"
        return
    fi
    local running=false
    if [[ "$OS_TYPE" == "linux" ]]; then
        systemctl is-active --quiet tailscaled 2>/dev/null && running=true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        brew services list 2>/dev/null | grep -q "tailscale.*started" && running=true
    fi
    if $running; then
        echo -e "${GREEN}✅ 已安装并运行${NC}"
    else
        echo -e "${YELLOW}⚠️  已安装但服务未运行${NC}"
    fi
}

# 用法
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status}

  install     安装或更新 Tailscale
  uninstall   卸载 Tailscale
  status      查看安装与运行状态
  help        显示本帮助
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
