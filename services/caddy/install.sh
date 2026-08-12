#!/usr/bin/env bash
#
# caddy/install.sh
#
# 安装与管理 Caddy Web 服务器。
# Linux：添加官方 APT/YUM 仓库后安装，自动配置 systemd 服务。
# macOS：通过 Homebrew 安装，brew services 管理。
#
# 子命令：
#   install           安装/更新 Caddy
#   uninstall         卸载 Caddy
#   status            查看状态
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

CADDY_PLIST="/Library/LaunchDaemons/com.caddyserver.caddy.plist"
CADDY_PLIST_LABEL="com.caddyserver.caddy"

# --- 获取 Caddyfile 路径 ---
get_caddyfile_path() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "/usr/local/etc/Caddyfile"
    else
        echo "/etc/caddy/Caddyfile"
    fi
}

# --- 通过 APT 安装（Debian/Ubuntu） ---
install_caddy_apt() {
    require_sudo
    info "安装依赖并添加 Caddy GPG 密钥..."
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg

    curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

    curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null

    info "正在安装 Caddy..."
    apt-get update -y
    apt-get install -y caddy
}

# --- 通过 DNF/YUM 安装（RHEL/CentOS/Fedora） ---
install_caddy_rpm() {
    require_sudo
    local pm="$1"
    info "添加 Caddy COPR 仓库..."
    if [[ "$pm" == "dnf" ]]; then
        dnf install -y 'dnf-command(copr)' 2>/dev/null || true
        dnf copr enable -y @caddy/caddy 2>/dev/null || {
            warn "COPR 方式失败，尝试直接安装 caddy..."
        }
        dnf install -y caddy
    else
        # yum 不支持 copr，使用 COPR repo 文件
        yum install -y yum-plugin-copr 2>/dev/null || true
        yum copr enable -y @caddy/caddy 2>/dev/null || {
            warn "COPR 方式失败，请手动添加 Caddy 仓库"
            exit 1
        }
        yum install -y caddy
    fi
}

# --- 安装 Caddy ---
install_caddy() {
    detect_os
    info "🚀 Caddy Web 服务器安装脚本"
    echo "=========================================="

    if command_exists caddy; then
        local cur
        cur=$(caddy version 2>/dev/null | head -1 || echo "未知版本")
        warn "检测到已安装 Caddy（${cur}）"
        if ! yes_no "是否继续并尝试更新？"; then
            info "已取消"
            return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! command_exists brew; then
            error "macOS 上需要先安装 Homebrew：https://brew.sh/"
            exit 1
        fi
        info "通过 Homebrew 安装 Caddy..."
        brew install caddy
        brew services start caddy 2>/dev/null || true
    else
        detect_pkg_manager
        case "$PKG_MANAGER" in
            apt-get) install_caddy_apt ;;
            dnf)     install_caddy_rpm dnf ;;
            yum)     install_caddy_rpm yum ;;
            *)
                error "当前包管理器（${PKG_MANAGER}）暂不支持自动安装 Caddy"
                info "请参考官方文档手动安装：https://caddyserver.com/docs/install"
                exit 1
                ;;
        esac
        # 确保服务已启动
        sudo systemctl enable --now caddy 2>/dev/null || true
    fi

    if ! command_exists caddy; then
        error "安装后找不到 caddy 命令，请检查 PATH"
        exit 1
    fi

    local version
    version=$(caddy version 2>/dev/null | head -1 || echo "未知")
    local caddyfile
    caddyfile=$(get_caddyfile_path)
    local ip_addr
    ip_addr=$(get_local_ip)

    echo
    echo "=========================================="
    success "🎉 Caddy 安装完成！"
    echo
    info "版本信息：$version"
    echo
    info "服务信息："
    echo "  - 访问地址：http://${ip_addr} (端口 80/443)"
    echo "  - 配置文件：$caddyfile"
    echo
    info "快速开始："
    echo "  # 编辑 Caddyfile"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  sudo nano $caddyfile"
    else
        echo "  sudo nano $caddyfile"
    fi
    echo
    echo "  # 示例：反向代理"
    echo "  example.com {"
    echo "      reverse_proxy localhost:8080"
    echo "  }"
    echo
    echo "  # 重载配置"
    echo "  sudo caddy reload --config $caddyfile"
    echo
    info "常用命令："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - 服务状态：sudo systemctl status caddy"
        echo "  - 查看日志：sudo journalctl -u caddy -f"
        echo "  - 重载配置：sudo caddy reload --config $caddyfile"
        echo "  - 重启服务：sudo systemctl restart caddy"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - 服务状态：brew services info caddy"
        echo "  - 查看日志：brew services log caddy"
        echo "  - 重载配置：sudo caddy reload --config $caddyfile"
        echo "  - 重启服务：brew services restart caddy"
    fi
}

# --- 卸载 Caddy ---
uninstall_caddy() {
    detect_os
    warn "即将卸载 Caddy。"
    if ! yes_no "确认卸载？"; then
        info "已取消"
        return 0
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        require_sudo
        sudo systemctl stop caddy 2>/dev/null || true
        sudo systemctl disable caddy 2>/dev/null || true
        detect_pkg_manager
        pkg_remove caddy 2>/dev/null || true
        sudo systemctl daemon-reload 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop caddy 2>/dev/null || true
        brew uninstall caddy 2>/dev/null || true
    fi

    success "Caddy 已卸载。"
}

# --- 状态检查 ---
status_caddy() {
    detect_os
    if ! command_exists caddy; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
        return
    fi
    local version
    version=$(caddy version 2>/dev/null | head -1 || echo "未知版本")
    local running=false
    if service_is_active caddy "$CADDY_PLIST_LABEL"; then
        running=true
    fi
    if $running; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC} ($version)"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装但服务未运行${NC} ($version)"
    fi
    emit_version "$version"
}

# --- 用法 ---
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装或更新 Caddy（默认动作）
  uninstall   卸载 Caddy
  status      查看安装与运行状态
  help        显示本帮助
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_caddy ;;
        uninstall) uninstall_caddy ;;
        status)    status_caddy ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
