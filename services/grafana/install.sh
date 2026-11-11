#!/usr/bin/env bash
set -euo pipefail

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 全局变量
GRAFANA_PORT=3000
GRAFANA_PLIST="/Library/LaunchDaemons/com.grafana.grafana.plist"
GRAFANA_PLIST_LABEL="com.grafana.grafana"

# --- 添加 Grafana APT 仓库 ---
setup_apt_repo() {
    info "$(_t 'Adding the Grafana APT repository...')"

    # 安装依赖
    pkg_install apt-transport-https software-properties-common wget gnupg2 2>/dev/null || true

    # 添加 GPG 密钥
    if [[ ! -f /etc/apt/keyrings/grafana.gpg ]]; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg >/dev/null
        success "GPG $(_t 'The key was added')"
    fi

    # 添加仓库
    if [[ ! -f /etc/apt/sources.list.d/grafana.list ]]; then
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list >/dev/null
        success "APT $(_t 'The repository was added')"
    fi

    sudo apt-get update -y
}

# --- 添加 Grafana YUM/DNF 仓库 ---
setup_yum_repo() {
    info "$(_t 'Adding the Grafana YUM/DNF repository...')"

    if [[ ! -f /etc/yum.repos.d/grafana.repo ]]; then
        sudo tee /etc/yum.repos.d/grafana.repo >/dev/null <<'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=0
enabled=1
gpgcheck=0
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
        success "YUM/DNF $(_t 'The repository was added')"
    fi

    if os_has_cmd dnf; then
        sudo dnf makecache
    else
        sudo yum makecache
    fi
}

# --- 安装 Grafana（Linux APT/YUM） ---
install_grafana_linux() {
    detect_pkg_manager

    case "$PKG_MANAGER" in
        apt-get)
            setup_apt_repo
            info "$(_t 'Installing Grafana...')"
            sudo apt-get install -y grafana
            ;;
        dnf|yum)
            setup_yum_repo
            info "$(_t 'Installing Grafana...')"
            if os_has_cmd dnf; then
                sudo dnf install -y grafana
            else
                sudo yum install -y grafana
            fi
            ;;
        *)
            error "$(_tf 'Unsupported package manager: %s' "$PKG_MANAGER")"
            error "Grafana Linux $(_t 'The install only supports APT and DNF/YUM')"
            return 1
            ;;
    esac

    success "Grafana $(_t 'The package installation is complete')"

    # 启动服务
    info "$(_t 'Starting the Grafana service...')"
    uxs_svc daemon-reload
    uxs_svc enable-now grafana-server
    success "Grafana $(_t 'The service is running and enabled on boot')"
}

# --- 安装 Grafana（macOS brew） ---
install_grafana_macos() {
    if ! os_has_cmd brew; then
        error "macOS $(_t 'Homebrew is required on macOS, install it first')"
        return 1
    fi

    info "$(_t 'Installing Grafana via Homebrew...')"
    brew install grafana

    info "$(_t 'Starting the Grafana service...')"
    brew services start grafana
    success "Grafana $(_t 'The service is running')"
}

# --- 验证安装 ---
verify_install() {
    info "$(_t 'Verifying the installation...')"
    sleep 4

    local is_running=false
    if service_is_active grafana-server "$GRAFANA_PLIST_LABEL"; then
        is_running=true
    fi

    if $is_running; then
        success "$(_t 'The service is running normally')"
        if curl -s "http://localhost:${GRAFANA_PORT}/api/health" >/dev/null; then
            success "$(_tf 'Port %s responds normally' "${GRAFANA_PORT}")"
        else
            warn "$(_tf 'Port %s does not respond yet, it may take a few seconds' "${GRAFANA_PORT}")"
        fi
    else
        error "$(_t 'The service is not running normally')"
        if [[ "$OS_TYPE" == "linux" ]]; then
            info "$(_t 'View the logs: sudo journalctl -u grafana-server -f')"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            info "$(_t 'View the logs: brew services log grafana')"
        fi
    fi
}

# --- 打印安装结果 ---
print_install_summary() {
    local ip_addr
    ip_addr=$(get_local_ip)

    echo
    echo "========================================"
    success "Grafana $(_t 'Installation complete!')"
    echo
    info "$(_t 'Access URL:')"
    echo "  - Web UI$(_tf ': http://%s:%s' "${ip_addr}" "${GRAFANA_PORT}")"
    echo
    info "$(_t 'Default login credentials:')"
    echo "  - $(_t 'User name: admin')"
    echo "  - $(_t 'Password: admin')"
    echo "  $(_t '(you are asked to change the password after the first login)')"
    echo
    info "$(_t 'Add a Prometheus data source:')"
    echo "  1. $(_t 'After logging in to Grafana, go to Configuration -> Data Sources')"
    echo "  2. $(_t 'Click "Add data source" and pick Prometheus')"
    echo "  3. URL $(_t 'Fill in: http://localhost:9090')"
    echo "  4. $(_t 'Click "Save & Test" to verify the connection')"
    echo
    info "$(_t 'Common commands:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - $(_t 'Service status: sudo systemctl status grafana-server')"
        echo "  - $(_t 'View the logs: sudo journalctl -u grafana-server -f')"
        echo "  - $(_t 'Restart the service: sudo systemctl restart grafana-server')"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - $(_t 'Service status: brew services info grafana')"
        echo "  - $(_t 'View the logs: brew services log grafana')"
        echo "  - $(_t 'Restart the service: brew services restart grafana')"
    fi
}

# --- 安装主逻辑 ---
install_grafana() {
    detect_os

    info "Grafana $(_t 'Cross-platform install script')"
    echo "=========================================="

    # 检查是否已安装
    if os_has_cmd grafana-server || os_has_cmd grafana; then
        warn "$(_t 'Grafana detected')"
        if ! yes_no "$(_t 'Continue and overwrite the installation?')"; then
            info "$(_t 'The installation was cancelled')"
            return 0
        fi
    fi

    require_sudo

    # 确认安装
    echo
    info "$(_t 'About to install Grafana')"
    info "$(_tf 'Service port: %s' "$GRAFANA_PORT")"
    echo
    if ! yes_no "$(_t 'Continue with the installation?')"; then
        info "$(_t 'The installation was cancelled')"
        return 0
    fi

    # 根据平台安装
    if [[ "$OS_TYPE" == "darwin" ]]; then
        install_grafana_macos || return 1
    else
        install_grafana_linux || return 1
    fi

    # 验证
    verify_install

    # 打印结果
    print_install_summary
}

# 卸载
uninstall_grafana() {
    detect_os
    require_sudo
    info "$(_t 'Uninstalling Grafana...')"

    # 停止服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop grafana-server &>/dev/null || true
        uxs_svc disable grafana-server &>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if os_has_cmd brew; then
            brew services stop grafana 2>/dev/null || true
        fi
    fi

    # 卸载软件包
    if [[ "$OS_TYPE" == "linux" ]]; then
        pkg_remove grafana 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/grafana.list
        sudo rm -f /etc/apt/keyrings/grafana.gpg
        sudo rm -f /etc/yum.repos.d/grafana.repo
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if os_has_cmd brew; then
            brew uninstall grafana 2>/dev/null || true
        fi
        sudo rm -f "$GRAFANA_PLIST"
    fi

    if yes_no "$(_t 'Delete the Grafana data directory (/var/lib/grafana, the dashboards and the data source configurations are lost)?')"; then
        sudo rm -rf /var/lib/grafana
        sudo rm -rf /etc/grafana
        success "$(_t 'Data directory deleted')"
    else
        info "$(_t 'Keeping the data directory')"
    fi

    success "Grafana $(_t 'Uninstalled successfully!')"
}

# 状态
status_grafana() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v grafana-server &>/dev/null; then
        is_installed=true
        version=$(grafana-server --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || printf '%s\n' "$(_t 'Unknown version')")
    elif command -v grafana &>/dev/null; then
        is_installed=true
        version=$(grafana --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || printf '%s\n' "$(_t 'Unknown version')")
    elif [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew && brew list grafana &>/dev/null; then
        is_installed=true
        version=$(brew info grafana 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || printf '%s\n' "$(_t 'Unknown version')")
    fi
    if service_is_active grafana-server "$GRAFANA_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            uxs_emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC} (v$version)"
        else
            uxs_emit_status "installed:stopped" "${YELLOW}$(_t '⚠️  Installed but not running')${NC} (v$version)"
        fi
        uxs_emit_version "$version"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install or update Grafana (default action)')
  uninstall   $(_t 'Uninstall Grafana')
  status      $(_t 'View the install and run status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_grafana ;;
        uninstall) uninstall_grafana ;;
        status)    status_grafana ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
