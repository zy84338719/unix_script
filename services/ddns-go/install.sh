#!/usr/bin/env bash
set -euo pipefail

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 全局变量
OS_TYPE=""
DDNS_DIR="/opt/ddns-go"
DDNS_BIN="$DDNS_DIR/ddns-go"
DDNS_PLIST="/Library/LaunchDaemons/jeessy.ddns-go.plist"
DDNS_PLIST_LABEL="jeessy.ddns-go"

check_os() {
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then info "$(_t 'Detected OS: macOS')"; fi
    if [[ "$OS_TYPE" == "linux" ]];  then info "$(_t 'Detected OS: Linux')"; fi
}

check_permissions() { require_sudo; }
check_dependencies() { check_commands curl tar; }

check_existing_installation() {
    if [ -f "$DDNS_BIN" ]; then
        local current_version
        current_version=$("$DDNS_BIN" --version 2>&1)
        warn "$(_tf 'Detected ddns-go %s installed' "$current_version")"
        read -r -p "$(_t 'Continue and overwrite-install the latest version? [y/N]: ')" -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "$(_t 'Install cancelled')"; exit 0
        fi
        info "$(_t 'Stopping and uninstalling existing service...')"
        if [[ "$OS_TYPE" == "linux" ]]; then
            uxs_svc stop ddns-go &>/dev/null || true
        fi
        sudo "$DDNS_BIN" -s uninstall &>/dev/null || true
    fi
}

install_ddns_go() {
    check_os
    check_permissions
    check_dependencies
    check_existing_installation

    info "$(_t 'ddns-go cross-platform install script')"
    echo "=========================================="

    info "$(_t 'Fetching latest version info...')"
    # 复用 common.sh 的 github_latest_tag（jq 优先 + grep 回退 + GH_TOKEN 认证）
    latest_tag=$(github_latest_tag "jeessy2/ddns-go")
    if [[ -z "$latest_tag" ]]; then
        error "$(_t 'Unable to fetch latest version info, check network connection or API rate limit')"
        exit 1
    fi
    success "$(_tf 'Latest version: %s' "$latest_tag")"

    arch=$(uname -m)
    arch_suffix=""
    case "$OS_TYPE" in
      "linux")
        case "$arch" in
          x86_64) arch_suffix=linux_x86_64;;
          aarch64|arm64) arch_suffix=linux_arm64;;
          armv7l) arch_suffix=linux_armv7;;
          *) error "$(_tf 'Unsupported Linux architecture: %s' "$arch")"; exit 1;;
        esac
        ;;
      "darwin")
        case "$arch" in
          x86_64) arch_suffix=darwin_amd64;;
          arm64) arch_suffix=darwin_arm64;;
          *) error "$(_tf 'Unsupported macOS architecture: %s' "$arch")"; exit 1;;
        esac
        ;;
    esac

    # 复用 common.sh 的 github_release_asset_url（jq 优先，回退 grep+sed，
    # 替代脆弱的 cut -d'"' -f4 字段下标）
    download_url=$(github_release_asset_url "jeessy2/ddns-go" "$arch_suffix.tar.gz")
    if [[ -z "$download_url" ]]; then
        error "$(_tf 'No download link found for %s' "$arch_suffix")"; exit 1
    fi

    echo
    info "$(_tf 'About to install ddns-go %s' "$latest_tag")"
    info "$(_tf 'Install location: %s' "$DDNS_DIR")"
    info "$(_t 'Service port: 9876')"
    echo
    read -r -p "$(_t 'Confirm continue installation? [y/N]: ')" -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "$(_t 'Install cancelled')"; exit 0
    fi

    info "$(_t 'Downloading and extracting...')"
    tmpdir=$(mktemp -d)
    if ! curl -SL "$download_url" -o "$tmpdir/ddns-go.tar.gz"; then
        error "$(_t 'Download failed')"; rm -rf "$tmpdir"; exit 1
    fi
    if ! tar -xzf "$tmpdir/ddns-go.tar.gz" -C "$tmpdir"; then
        error "$(_t 'Extract failed')"; rm -rf "$tmpdir"; exit 1
    fi
    success "$(_t 'Download and extract complete')"

    info "$(_t 'Installing ddns-go...')"
    sudo mkdir -p "$DDNS_DIR"
    sudo mv "$tmpdir/ddns-go" "$DDNS_DIR/"
    sudo mv "$tmpdir/README.md" "$DDNS_DIR/" 2>/dev/null || true
    sudo mv "$tmpdir/LICENSE" "$DDNS_DIR/" 2>/dev/null || true
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown -R root:wheel "$DDNS_DIR"
    elif [[ "$OS_TYPE" == "linux" ]]; then
        sudo chown -R root:root "$DDNS_DIR"
    fi
    sudo chmod +x "$DDNS_BIN"
    success "$(_t 'Files installed')"

    info "$(_t 'Installing service...')"
    if sudo "$DDNS_BIN" -s install; then
        success "$(_t 'Service installed successfully')"
    else
        error "$(_t 'Service install failed')"; rm -rf "$tmpdir"; exit 1
    fi

    info "$(_t 'Starting service...')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc enable-now ddns-go; then
            success "$(_t 'ddns-go service started and enabled on boot')"
        else
            error "$(_t 'Service start failed')"; rm -rf "$tmpdir"; exit 1
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if sudo launchctl list | grep -q "$DDNS_PLIST_LABEL"; then
            info "$(_t 'Service already running')"; success "$(_t 'ddns-go service started and enabled on boot')"
        else
            if sudo launchctl bootstrap system "$DDNS_PLIST"; then
                success "$(_t 'ddns-go service started and enabled on boot')"
            else
                warn "$(_t 'bootstrap failed, trying load')"
                if sudo launchctl load "$DDNS_PLIST" 2>/dev/null; then
                    success "$(_t 'ddns-go service started (load)')"
                else
                    warn "$(_t 'Auto-start failed, service file installed')"
                fi
            fi
        fi
    fi

    rm -rf "$tmpdir"

    info "$(_t 'Verifying installation...')"
    sleep 3
    if service_is_active ddns-go "$DDNS_PLIST_LABEL"; then
        success "$(_t 'Service running normally')"
    else
        error "$(_t 'Service not running normally')"
        info "$(_t 'View logs:')"
        if [[ "$OS_TYPE" == "linux" ]]; then
            echo "  sudo systemctl status ddns-go"
            echo "  sudo journalctl -u ddns-go -f"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            echo "  sudo launchctl list | grep ddns-go"
        fi
    fi

    ip_addr=$(get_local_ip)
    echo
    echo "=========================================="
    success "$(_tf 'ddns-go %s installation complete!' "$latest_tag")"
    echo
    info "$(_t 'Service info:')"
    echo "  - $(_t 'Access URL:') http://${ip_addr}:9876"
    echo "  - $(_t 'Install directory:') $DDNS_DIR"
    echo "  - $(_t 'Config file:') $DDNS_DIR/.ddns_go_config.yaml $(_t '(auto-created after first visit)')"
    echo
    info "$(_t 'Common commands:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - $(_t 'Service status:') sudo systemctl status ddns-go"
        echo "  - $(_t 'View logs:') sudo journalctl -u ddns-go -f"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - $(_t 'Service status:') sudo launchctl list | grep ddns-go"
        echo "  - $(_t 'Start service:') sudo launchctl bootstrap system $DDNS_PLIST"
    fi
    echo
    warn "$(_t 'Be sure to set your DNS provider info and the domain to update in the Web UI!')"
}

uninstall_ddns_go() {
    detect_os
    require_sudo
    info "$(_t 'Uninstalling DDNS-GO...')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop ddns-go &>/dev/null || true
        uxs_svc disable ddns-go &>/dev/null || true
        uxs_svc daemon-reload
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$DDNS_PLIST" &>/dev/null || true
        sudo rm -f "$DDNS_PLIST"
    fi
    sudo rm -rf "$DDNS_DIR"
    success "$(_t 'DDNS-GO uninstalled successfully!')"
}

status_ddns_go() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v ddns-go &>/dev/null || [[ -f "$DDNS_BIN" ]]; then
        is_installed=true
        if [[ -x "$DDNS_BIN" ]]; then
            version=$("$DDNS_BIN" --version 2>&1 | head -1 || echo "")
        fi
    fi
    if service_is_active ddns-go "$DDNS_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC} ($version)"
        else
            emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed but not running')${NC} ($version)"
        fi
        emit_version "$version"
    else
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install or update DDNS-GO (default action)')
  uninstall   $(_t 'Uninstall DDNS-GO')
  status      $(_t 'View install and running status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_ddns_go ;;
        uninstall) uninstall_ddns_go ;;
        status)    status_ddns_go ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
