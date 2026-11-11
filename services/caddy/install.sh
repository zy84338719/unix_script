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
    info "$(_t 'Installing dependencies and adding Caddy GPG key...')"
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg

    curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

    curl -1fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null

    info "$(_t 'Installing Caddy...')"
    pkg_update
    apt-get install -y caddy
}

# --- 通过 DNF/YUM 安装（RHEL/CentOS/Fedora） ---
install_caddy_rpm() {
    require_sudo
    local pm="$1"
    info "$(_t 'Adding Caddy COPR repository...')"
    if [[ "$pm" == "dnf" ]]; then
        dnf install -y 'dnf-command(copr)' 2>/dev/null || true
        dnf copr enable -y @caddy/caddy 2>/dev/null || {
            warn "$(_t 'COPR method failed, trying direct caddy install...')"
        }
        dnf install -y caddy
    else
        # yum 不支持 copr，使用 COPR repo 文件
        yum install -y yum-plugin-copr 2>/dev/null || true
        yum copr enable -y @caddy/caddy 2>/dev/null || {
            warn "$(_t 'COPR method failed, please add the Caddy repository manually')"
            exit 1
        }
        yum install -y caddy
    fi
}

# --- 安装 Caddy ---
install_caddy() {
    detect_os
    info "$(_t 'Caddy Web server install script')"
    echo "=========================================="

    if command_exists caddy; then
        local cur
        cur=$(caddy version 2>/dev/null | head -1 || printf '%s' "$(_t 'Unknown version')")
        warn "$(_t 'Detected Caddy installed (')${cur}$(_t ')')"
        if ! yes_no "$(_t 'Continue and try to update?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! command_exists brew; then
            error "$(_t 'Homebrew is required on macOS:') https://brew.sh/"
            exit 1
        fi
        info "$(_t 'Installing Caddy via Homebrew...')"
        brew install caddy
        brew services start caddy 2>/dev/null || true
    else
        detect_pkg_manager
        case "$PKG_MANAGER" in
            apt-get) install_caddy_apt ;;
            dnf)     install_caddy_rpm dnf ;;
            yum)     install_caddy_rpm yum ;;
            *)
                error "$(_t 'Current package manager (')${PKG_MANAGER}$(_t ') does not support automatic Caddy installation')"
                info "$(_t 'Please install manually per the official docs:')https://caddyserver.com/docs/install"
                exit 1
                ;;
        esac
        # 确保服务已启动
        uxs_svc enable-now caddy 2>/dev/null || true
    fi

    if ! command_exists caddy; then
        error "$(_t 'caddy command not found after install, check PATH')"
        exit 1
    fi

    local version
    version=$(caddy version 2>/dev/null | head -1 || printf '%s' "$(_t 'Unknown')")
    local caddyfile
    caddyfile=$(get_caddyfile_path)
    local ip_addr
    ip_addr=$(get_local_ip)

    echo
    echo "=========================================="
    success "$(_t 'Caddy installation complete!')"
    echo
    info "$(_t 'Version info: ')$version"
    echo
    info "$(_t 'Service info:')"
    echo "  - $(_t 'Access URL:')http://${ip_addr} $(_t '(ports 80/443)')"
    echo "  - $(_t 'Config file:')$caddyfile"
    echo
    info "$(_t 'Quick start:')"
    echo "  # $(_t 'Edit Caddyfile')"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  sudo nano $caddyfile"
    else
        echo "  sudo nano $caddyfile"
    fi
    echo
    echo "  # $(_t 'Example: reverse proxy')"
    echo "  example.com {"
    echo "      reverse_proxy localhost:8080"
    echo "  }"
    echo
    echo "  # $(_t 'Reload config')"
    echo "  sudo caddy reload --config $caddyfile"
    echo
    info "$(_t 'Common commands:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - $(_t 'Service status:')sudo systemctl status caddy"
        echo "  - $(_t 'View logs:')sudo journalctl -u caddy -f"
        echo "  - $(_t 'Reload config:')sudo caddy reload --config $caddyfile"
        echo "  - $(_t 'Restart service:')sudo systemctl restart caddy"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - $(_t 'Service status:')brew services info caddy"
        echo "  - $(_t 'View logs:')brew services log caddy"
        echo "  - $(_t 'Reload config:')sudo caddy reload --config $caddyfile"
        echo "  - $(_t 'Restart service:')brew services restart caddy"
    fi
}

# --- 卸载 Caddy ---
uninstall_caddy() {
    detect_os
    warn "$(_t 'About to uninstall Caddy.')"
    if ! yes_no "$(_t 'Confirm uninstall?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        require_sudo
        uxs_svc stop caddy 2>/dev/null || true
        uxs_svc disable caddy 2>/dev/null || true
        detect_pkg_manager
        pkg_remove caddy 2>/dev/null || true
        uxs_svc daemon-reload 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop caddy 2>/dev/null || true
        brew uninstall caddy 2>/dev/null || true
    fi

    success "$(_t 'Caddy uninstalled.')"
}

# --- 状态检查 ---
status_caddy() {
    detect_os
    if ! command_exists caddy; then
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"
        return
    fi
    local version
    version=$(caddy version 2>/dev/null | head -1 || printf '%s' "$(_t 'Unknown version')")
    local running=false
    if service_is_active caddy "$CADDY_PLIST_LABEL"; then
        running=true
    fi
    if $running; then
        emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC} ($version)"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed but service not running')${NC} ($version)"
    fi
    emit_version "$version"
}

# --- 用法 ---
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install or update Caddy (default action)')
  uninstall   $(_t 'Uninstall Caddy')
  status      $(_t 'View install and running status')
  help        $(_t 'Show this help')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
