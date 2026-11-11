#!/usr/bin/env bash
#
# gitea/install.sh
#
# 安装与管理 Gitea 自托管 Git 服务。
# 从 GitHub 下载二进制，创建系统用户与目录，
# 配置 systemd（Linux）或 launchd（macOS）服务。
#
# 子命令：
#   install           安装/更新 Gitea
#   uninstall         卸载 Gitea
#   status            查看状态
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

GITEA_BIN="/usr/local/bin/gitea"
GITEA_USER="git"
GITEA_CONFIG="/etc/gitea/app.ini"
GITEA_DATA="/var/lib/gitea"
GITEA_SYSTEMD="/etc/systemd/system/gitea.service"
GITEA_PLIST="/Library/LaunchDaemons/io.gitea.web.plist"
GITEA_PLIST_LABEL="io.gitea.web"
GITEA_PORT="3000"
GITEA_SSH_PORT="2222"

# --- 获取最新版本 ---
get_latest_version() {
    local ver
    ver=$(http_github_latest_tag "go-gitea/gitea")
    if [[ -z "$ver" ]]; then
        error "$(_t 'Cannot fetch the latest version info, check the network connection')"
        return 1
    fi
    echo "$ver"
}

# --- 检测架构后缀 ---
detect_arch_suffix() {
    local arch
    arch=$(uname -m)
    case "$OS_TYPE" in
        linux)
            case "$arch" in
                x86_64)         echo "linux-amd64" ;;
                aarch64|arm64)  echo "linux-arm64" ;;
                armv7l)         echo "linux-arm-7" ;;
                *) error "$(_tf 'Unsupported Linux architecture: %s' "$arch")"; return 1 ;;
            esac
            ;;
        darwin)
            case "$arch" in
                x86_64) echo "darwin-amd64" ;;
                arm64)  echo "darwin-arm64" ;;
                *) error "$(_tf 'Unsupported macOS architecture: %s' "$arch")"; return 1 ;;
            esac
            ;;
    esac
}

# --- 检查已有安装 ---
handle_existing_installation() {
    if ! os_has_cmd gitea && [[ ! -f "$GITEA_BIN" ]]; then
        return 0
    fi
    local current_version
    current_version=$(gitea --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
    warn "$(_tf 'Gitea detected (%s)' "${current_version}")"
    if ! yes_no "$(_t 'Continue and overwrite it with the newest version?')"; then
        info "$(_t 'The installation was cancelled')"
        exit 0
    fi
    info "$(_t 'Stopping the existing service...')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop gitea 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$GITEA_PLIST" 2>/dev/null || true
    fi
}

# --- 创建系统用户（Linux） ---
create_gitea_user() {
    if id -u "$GITEA_USER" &>/dev/null; then
        info "$(_tf 'The user %s already exists' "$GITEA_USER")"
        return 0
    fi
    info "$(_tf 'Creating the system user %s...' "$GITEA_USER")"
    sudo adduser --system --shell /bin/bash --group --disabled-password --home "/home/$GITEA_USER" "$GITEA_USER" 2>/dev/null \
        || sudo useradd --system --shell /bin/bash --create-home "$GITEA_USER" 2>/dev/null \
        || { error "$(_t 'Failed to create the user')"; return 1; }
    success "$(_tf 'The user %s was created' "$GITEA_USER")"
}

# --- 创建目录结构 ---
create_directories() {
    require_sudo
    info "$(_t 'Creating the directory structure...')"
    sudo mkdir -p "$GITEA_DATA"/{data,indexers,log,custom}
    sudo mkdir -p /etc/gitea

    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo chown -R "$GITEA_USER":"$GITEA_USER" "$GITEA_DATA"
        sudo chown root:"$GITEA_USER" /etc/gitea
        sudo chmod 750 /etc/gitea
    fi
    success "$(_t 'The directory structure is ready')"
}

# --- 创建 systemd 服务（Linux） ---
setup_systemd_service() {
    info "$(_t 'Creating the systemd service...')"
    install_systemd_unit gitea.service <<EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target
Wants=network.target

[Service]
Type=simple
User=$GITEA_USER
Group=$GITEA_USER
WorkingDirectory=$GITEA_DATA
ExecStart=$GITEA_BIN web --config $GITEA_CONFIG
Restart=always
RestartSec=10
Environment=USER=$GITEA_USER HOME=/home/$GITEA_USER GITEA_WORK_DIR=$GITEA_DATA

[Install]
WantedBy=multi-user.target
EOF
    success "systemd $(_t 'The service file was created')"

    if uxs_svc enable-now gitea; then
        success "Gitea $(_t 'The service is running and enabled on boot')"
    else
        error "$(_t 'Failed to start the service')"
        return 1
    fi
}

# --- 创建 launchd 服务（macOS） ---
setup_launchd_service() {
    info "$(_t 'Creating the macOS service...')"
    sudo tee "$GITEA_PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$GITEA_PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$GITEA_BIN</string>
        <string>web</string>
        <string>--config</string>
        <string>$GITEA_CONFIG</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>$GITEA_DATA</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>GITEA_WORK_DIR</key>
        <string>$GITEA_DATA</string>
    </dict>
    <key>StandardErrorPath</key>
    <string>/var/log/gitea.err</string>
    <key>StandardOutPath</key>
    <string>/var/log/gitea.log</string>
</dict>
</plist>
EOF
    success "LaunchDaemon $(_t 'The service file was created')"

    if sudo launchctl list | grep -q "$GITEA_PLIST_LABEL"; then
        info "$(_t 'The service is already running')"
    else
        if sudo launchctl bootstrap system "$GITEA_PLIST"; then
            success "Gitea $(_t 'The service is running')"
        else
            warn "bootstrap $(_t 'failed, trying load')"
            if sudo launchctl load "$GITEA_PLIST" 2>/dev/null; then
                success "Gitea $(_t 'The service is running (load)')"
            else
                warn "$(_t 'The auto-start failed, the service file is installed')"
                info "$(_tf 'Start it manually: sudo launchctl bootstrap system %s' "$GITEA_PLIST")"
            fi
        fi
    fi
}

# --- 安装 Gitea ---
install_gitea() {
    detect_os
    check_commands curl
    handle_existing_installation

    info "$(_t '🚀 Gitea self-hosted Git service install script')"
    echo "=========================================="

    # macOS 优先 brew
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        info "$(_t 'Installing Gitea via Homebrew...')"
        brew install gitea
        brew services start gitea 2>/dev/null || true
        local ip_addr; ip_addr=$(get_local_ip)
        success "$(_t '🎉 Gitea installation complete! (managed by brew)')"
        info "$(_tf 'Access URL: http://%s:%s' "${ip_addr}" "${GITEA_PORT}")"
        info "$(_t 'Common commands: brew services info gitea')"
        return 0
    fi

    require_sudo

    # 获取最新版本
    info "$(_t 'Fetching the latest version info...')"
    local latest
    latest=$(get_latest_version) || return 1
    success "$(_tf 'Latest version: v%s' "$latest")"

    # 确定架构
    local arch_suffix
    arch_suffix=$(detect_arch_suffix) || return 1
    info "$(_t 'Detected architecture:')$(uname -m) -> $arch_suffix"

    # 确认安装
    echo
    info "$(_tf 'About to install Gitea v%s' "$latest")"
    info "$(_tf 'Install location: %s' "$GITEA_BIN")"
    info "Web $(_tf 'Port: %s | SSH port: %s' "$GITEA_PORT" "$GITEA_SSH_PORT")"
    info "$(_tf 'Configuration file: %s' "$GITEA_CONFIG")"
    info "$(_tf 'Data directory: %s' "$GITEA_DATA")"
    echo
    if ! yes_no "$(_t 'Continue with the installation?')"; then
        info "$(_t 'The installation was cancelled')"
        return 0
    fi

    # 下载二进制
    local url="https://github.com/go-gitea/gitea/releases/download/v${latest}/gitea-${latest}-${arch_suffix}"
    info "$(_tf 'Download URL: %s' "$url")"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    if ! curl -SL "$url" -o "$tmpdir/gitea"; then
        error "$(_t 'Download failed')"
        exit 1
    fi
    success "$(_t 'Download complete')"

    # 安装二进制
    sudo mv "$tmpdir/gitea" "$GITEA_BIN"
    sudo chmod 755 "$GITEA_BIN"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel "$GITEA_BIN"
    else
        sudo chown root:root "$GITEA_BIN"
    fi
    success "$(_t 'The binary files are installed')"

    # Linux：创建用户与目录，配置服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        create_gitea_user
        create_directories
        setup_systemd_service
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        create_directories
        setup_launchd_service
    fi

    rm -rf "$tmpdir"
    trap - EXIT

    # 验证
    info "$(_t 'Verifying the installation...')"
    sleep 3
    local ip_addr
    ip_addr=$(get_local_ip)

    if service_is_active gitea "$GITEA_PLIST_LABEL"; then
        success "$(_t 'The service is running normally')"
    else
        warn "$(_t 'The service may still be starting...')"
    fi

    echo
    echo "=========================================="
    success "$(_tf '🎉 Gitea v%s installation complete!' "$latest")"
    echo
    info "$(_t 'Service info:')"
    echo "  - Web $(_tf 'Access: http://%s:%s' "${ip_addr}" "${GITEA_PORT}")"
    echo "  - SSH $(_tf 'Address: ssh://%s:%s' "${ip_addr}" "${GITEA_SSH_PORT}")"
    echo "  - $(_tf 'Configuration file: %s' "$GITEA_CONFIG")"
    echo "  - $(_tf 'Data directory: %s' "$GITEA_DATA")"
    echo
    info "$(_t 'On the first visit, finish the initial setup wizard (set the admin account, the database, ...).')"
    echo
    info "$(_t 'Common commands:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - $(_t 'Service status: sudo systemctl status gitea')"
        echo "  - $(_t 'View the logs: sudo journalctl -u gitea -f')"
        echo "  - $(_t 'Restart the service: sudo systemctl restart gitea')"
        echo "  - $(_tf 'Edit the configuration: sudo nano %s' "$GITEA_CONFIG")"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - $(_t 'Service status: sudo launchctl list | grep gitea')"
        echo "  - $(_t 'View the logs: tail -f /var/log/gitea.log')"
        echo "  - $(_tf 'Restart the service: sudo launchctl kickstart -k system/%s' "$GITEA_PLIST_LABEL")"
        echo "  - $(_tf 'Edit the configuration: sudo nano %s' "$GITEA_CONFIG")"
    fi
}

# --- 卸载 Gitea ---
uninstall_gitea() {
    detect_os
    warn "$(_t 'About to uninstall Gitea.')"
    echo
    local delete_data=false
    if yes_no "$(_tf 'Delete the data directory (%s) too?' "${GITEA_DATA}")"; then
        delete_data=true
        info "$(_t 'The data directory will be deleted')"
    else
        info "$(_t 'The data directory will be kept')"
    fi

    if ! yes_no "$(_t 'Confirm uninstall of Gitea?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        require_sudo
        uxs_svc stop gitea 2>/dev/null || true
        uxs_svc disable gitea 2>/dev/null || true
        sudo rm -f "$GITEA_SYSTEMD"
        uxs_svc daemon-reload 2>/dev/null || true
        sudo rm -f "$GITEA_BIN"
        # 删除配置目录
        sudo rm -rf /etc/gitea
        # 按用户选择删除数据
        if $delete_data; then
            sudo rm -rf "$GITEA_DATA"
            info "$(_t 'Data directory deleted')"
        else
            info "$(_tf 'Data directory kept: %s' "$GITEA_DATA")"
        fi
        if id -u "$GITEA_USER" &>/dev/null; then
            sudo userdel "$GITEA_USER" 2>/dev/null || true
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if os_has_cmd brew; then
            brew services stop gitea 2>/dev/null || true
            brew uninstall gitea 2>/dev/null || true
        else
            sudo launchctl bootout system "$GITEA_PLIST" 2>/dev/null || true
            sudo rm -f "$GITEA_PLIST"
            sudo rm -f "$GITEA_BIN"
        fi
        sudo rm -rf /etc/gitea
        if $delete_data; then
            sudo rm -rf "$GITEA_DATA"
            info "$(_t 'Data directory deleted')"
        else
            info "$(_tf 'Data directory kept: %s' "$GITEA_DATA")"
        fi
    fi

    success "Gitea $(_t 'Uninstalled.')"
}

# --- 状态检查 ---
status_gitea() {
    detect_os
    local is_installed=false is_running=false version=""
    if os_has_cmd gitea || [[ -f "$GITEA_BIN" ]]; then
        is_installed=true
        if os_has_cmd gitea; then
            version=$(gitea --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
        fi
    fi
    if service_is_active gitea "$GITEA_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            uxs_emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC} ($version)"
        else
            uxs_emit_status "installed:stopped" "${YELLOW}$(_t '⚠️ Installed but the service is not running')${NC} ($version)"
        fi
        uxs_emit_version "$version"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

# --- 用法 ---
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install or update Gitea (default action)')
  uninstall   $(_t 'Uninstall Gitea')
  status      $(_t 'View the install and run status')
  help        $(_t 'Show this help')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_gitea ;;
        uninstall) uninstall_gitea ;;
        status)    status_gitea ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
