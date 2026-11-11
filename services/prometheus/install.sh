#!/usr/bin/env bash
set -euo pipefail

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 全局变量
PROM_BIN="/usr/local/bin/prometheus"
PROMTOOL_BIN="/usr/local/bin/promtool"
PROM_PLIST="/Library/LaunchDaemons/io.prometheus.prometheus.plist"
PROM_PLIST_LABEL="io.prometheus.prometheus"
PROM_CONFIG="/etc/prometheus/prometheus.yml"
PROM_DATA_DIR="/var/lib/prometheus"
PROM_USER="prometheus"
PROM_PORT=9090

# --- 获取最新版本 ---
get_latest_version() {
    local ver
    ver=$(http_github_latest_tag "prometheus/prometheus")
    if [[ -z "$ver" ]]; then
        error "$(_t 'Cannot fetch the latest version info, check the network connection')"
        return 1
    fi
    echo "$ver"
}

# --- 检测架构后缀 ---
detect_arch_suffix() {
    case "$OS_TYPE" in
        linux)
            case "$(uname -m)" in
                x86_64)         echo "linux-amd64" ;;
                aarch64|arm64)  echo "linux-arm64" ;;
                armv7l)         echo "linux-armv7" ;;
                *) error "$(_t 'Unsupported Linux architecture:')$(uname -m)"; return 1 ;;
            esac
            ;;
        darwin)
            case "$(uname -m)" in
                x86_64) echo "darwin-amd64" ;;
                arm64)  echo "darwin-arm64" ;;
                *) error "$(_t 'Unsupported macOS architecture:')$(uname -m)"; return 1 ;;
            esac
            ;;
    esac
}

# --- 检查已有安装并处理 ---
handle_existing_installation() {
    if ! command -v prometheus &>/dev/null; then
        return 0
    fi
    local current_version
    current_version=$(prometheus --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || printf '%s\n' "$(_t 'Unknown version')")
    warn "$(_tf 'Prometheus v%s detected' "$current_version")"
    if ! yes_no "$(_t 'Continue and overwrite it with the newest version?')"; then
        info "$(_t 'The installation was cancelled')"
        exit 0
    fi

    info "$(_t 'Stopping the existing service...')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop prometheus &>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$PROM_PLIST" &>/dev/null || true
    fi
}

# --- 下载并解压 ---
download_and_extract() {
    local latest="$1" arch_suffix="$2" tmpdir="$3"
    local url="https://github.com/prometheus/prometheus/releases/download/v${latest}/prometheus-${latest}.${arch_suffix}.tar.gz"
    info "$(_tf 'Download URL: %s' "$url")"

    if ! curl -fSL "$url" -o "$tmpdir/prometheus.tar.gz"; then
        error "$(_t 'Download failed')"
        return 1
    fi
    if ! tar -xzf "$tmpdir/prometheus.tar.gz" -C "$tmpdir"; then
        error "$(_t 'Extract failed')"
        return 1
    fi
    success "$(_t 'Download and extract complete')"
}

# --- 安装二进制文件 ---
install_binaries() {
    local latest="$1" arch_suffix="$2" tmpdir="$3"
    local src_dir="$tmpdir/prometheus-${latest}.${arch_suffix}"

    info "$(_t 'Installing the binary files...')"
    sudo cp "$src_dir/prometheus" "$PROM_BIN"
    sudo cp "$src_dir/promtool" "$PROMTOOL_BIN"
    sudo chmod 755 "$PROM_BIN" "$PROMTOOL_BIN"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel "$PROM_BIN" "$PROMTOOL_BIN"
    else
        sudo chown root:root "$PROM_BIN" "$PROMTOOL_BIN"
    fi
    success "$(_t 'The binary files are installed (prometheus, promtool)')"
}

# --- 创建目录和配置（Linux） ---
setup_linux_dirs_and_config() {
    # 创建用户
    info "$(_t 'Creating the system user...')"
    if ! id -u "$PROM_USER" &>/dev/null; then
        sudo useradd --no-create-home --shell /bin/false "$PROM_USER"
        success "$(_tf 'The user %s was created' "$PROM_USER")"
    else
        info "$(_tf 'The user %s already exists' "$PROM_USER")"
    fi

    # 创建目录
    sudo mkdir -p /etc/prometheus "$PROM_DATA_DIR"
    sudo chown "$PROM_USER:$PROM_USER" "$PROM_DATA_DIR"

    # 写入默认配置（如果不存在）
    if [[ ! -f "$PROM_CONFIG" ]]; then
        info "$(_tf 'Creating the default configuration %s ...' "$PROM_CONFIG")"
        sudo tee "$PROM_CONFIG" >/dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF
        sudo chown "$PROM_USER:$PROM_USER" "$PROM_CONFIG"
        success "$(_t 'The default configuration is ready')"
    else
        info "$(_tf 'The configuration file %s already exists, skipping the creation' "$PROM_CONFIG")"
    fi
}

# --- 创建 systemd 服务（Linux） ---
setup_systemd_service() {
    info "$(_t 'Creating the systemd service file...')"
    install_systemd_unit prometheus.service <<EOF
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=$PROM_USER
Group=$PROM_USER
Type=simple
ExecStart=$PROM_BIN \\
    --config.file=$PROM_CONFIG \\
    --storage.tsdb.path=$PROM_DATA_DIR \\
    --web.listen-address=0.0.0.0:$PROM_PORT \\
    --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    success "systemd $(_t 'The service file was created')"

    info "$(_t 'Starting the service...')"
    uxs_svc enable-now prometheus
    success "Prometheus $(_t 'The service is running and enabled on boot')"
}

# --- 创建 launchd 服务（macOS） ---
setup_launchd_service() {
    # 创建目录
    sudo mkdir -p /etc/prometheus "$PROM_DATA_DIR"

    # 写入默认配置（如果不存在）
    if [[ ! -f "$PROM_CONFIG" ]]; then
        info "$(_tf 'Creating the default configuration %s ...' "$PROM_CONFIG")"
        sudo tee "$PROM_CONFIG" >/dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
EOF
        success "$(_t 'The default configuration is ready')"
    else
        info "$(_tf 'The configuration file %s already exists, skipping the creation' "$PROM_CONFIG")"
    fi

    info "$(_t 'Creating the macOS service file...')"
    sudo tee "$PROM_PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PROM_PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PROM_BIN}</string>
        <string>--config.file=${PROM_CONFIG}</string>
        <string>--storage.tsdb.path=${PROM_DATA_DIR}</string>
        <string>--web.listen-address=0.0.0.0:${PROM_PORT}</string>
        <string>--web.enable-lifecycle</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/prometheus.err</string>
    <key>StandardOutPath</key>
    <string>/var/log/prometheus.log</string>
</dict>
</plist>
EOF
    success "LaunchDaemon $(_t 'The service file was created')"

    info "$(_t 'Starting the service...')"
    if sudo launchctl list 2>/dev/null | grep -q "$PROM_PLIST_LABEL"; then
        info "$(_t 'The service is already running')"
    else
        if sudo launchctl bootstrap system "$PROM_PLIST" 2>/dev/null; then
            success "Prometheus $(_t 'The service is running')"
        else
            warn "bootstrap $(_t 'failed, trying the load command')"
            sudo launchctl load "$PROM_PLIST" 2>/dev/null || true
        fi
    fi
}

# --- 验证安装 ---
verify_install() {
    info "$(_t 'Verifying the installation...')"
    sleep 3

    if service_is_active prometheus "$PROM_PLIST_LABEL"; then
        success "$(_t 'The service is running normally')"
        sleep 2
        if curl -s "http://localhost:${PROM_PORT}/-/healthy" >/dev/null; then
            success "$(_tf 'Port %s responds normally' "${PROM_PORT}")"
        else
            warn "$(_tf 'Port %s does not respond yet, it may take a few seconds' "${PROM_PORT}")"
        fi
    else
        error "$(_t 'The service is not running normally')"
        info "$(_t 'You can use these commands to check the status and the logs:')"
        if [[ "$OS_TYPE" == "linux" ]]; then
            echo "  sudo systemctl status prometheus"
            echo "  sudo journalctl -u prometheus -f"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            echo "  sudo launchctl list | grep prometheus"
            echo "  tail -f /var/log/prometheus.log"
        fi
    fi
}

# --- 打印安装结果 ---
print_install_summary() {
    local ip_addr
    ip_addr=$(get_local_ip)

    echo
    echo "========================================"
    success "Prometheus $(_t 'Installation complete!')"
    echo
    info "$(_t 'Service info:')"
    echo "  - $(_tf 'Listen address: http://0.0.0.0:%s' "${PROM_PORT}")"
    echo "  - Web UI$(_tf ': http://%s:%s' "${ip_addr}" "${PROM_PORT}")"
    echo "  - $(_tf 'Configuration file: %s' "$PROM_CONFIG")"
    echo "  - $(_tf 'Data directory: %s' "$PROM_DATA_DIR")"
    echo
    info "$(_t 'Default scrape jobs:')"
    echo "  - prometheus: localhost:9090$(_t '(its own metrics)')"
    echo "  - node_exporter: localhost:9100$(_t '(system metrics)')"
    echo
    info "$(_t 'Common commands:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - $(_t 'Service status: sudo systemctl status prometheus')"
        echo "  - $(_t 'View the logs: sudo journalctl -u prometheus -f')"
        echo "  - $(_t 'Restart the service: sudo systemctl restart prometheus')"
        echo "  - $(_tf 'Check the configuration: promtool check config %s' "$PROM_CONFIG")"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - $(_t 'Service status: sudo launchctl list | grep prometheus')"
        echo "  - $(_t 'View the logs: tail -f /var/log/prometheus.log')"
        echo "  - $(_tf 'Restart the service: sudo launchctl kickstart -k system/%s' "$PROM_PLIST_LABEL")"
        echo "  - $(_tf 'Check the configuration: promtool check config %s' "$PROM_CONFIG")"
    fi
}

# --- 安装主逻辑 ---
install_prometheus() {
    detect_os
    check_commands curl tar

    info "Prometheus $(_t 'Cross-platform install script')"
    echo "=========================================="

    handle_existing_installation
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
    info "$(_tf 'About to install Prometheus v%s' "$latest")"
    info "$(_tf 'Install locations: %s, %s' "$PROM_BIN" "$PROMTOOL_BIN")"
    info "$(_tf 'Service port: %s' "$PROM_PORT")"
    echo
    if ! yes_no "$(_t 'Continue with the installation?')"; then
        info "$(_t 'The installation was cancelled')"
        return 0
    fi

    # 下载并解压
    info "$(_t 'Downloading and extracting...')"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    download_and_extract "$latest" "$arch_suffix" "$tmpdir" || return 1

    # 安装二进制
    install_binaries "$latest" "$arch_suffix" "$tmpdir" || return 1

    # 创建服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        setup_linux_dirs_and_config || return 1
        setup_systemd_service || return 1
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        setup_launchd_service || return 1
    fi

    # 验证与清理
    verify_install
    rm -rf "$tmpdir"
    trap - EXIT

    print_install_summary
}

# 卸载
uninstall_prometheus() {
    detect_os
    require_sudo
    info "$(_t 'Uninstalling Prometheus...')"

    # 停止服务
    service_stop prometheus "$PROM_PLIST"

    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo rm -f /etc/systemd/system/prometheus.service
        uxs_svc daemon-reload &>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo rm -f "$PROM_PLIST"
        sudo rm -f /var/log/prometheus.log /var/log/prometheus.err
    fi

    # 删除二进制
    sudo rm -f "$PROM_BIN" "$PROMTOOL_BIN"

    # 删除用户（Linux）
    if [[ "$OS_TYPE" == "linux" ]] && id -u "$PROM_USER" &>/dev/null; then
        sudo userdel "$PROM_USER" 2>/dev/null || true
    fi

    # 询问是否删除配置和数据
    if yes_no "$(_t 'Delete the configuration directory /etc/prometheus?')"; then
        sudo rm -rf /etc/prometheus
        success "$(_t 'Configuration directory deleted')"
    else
        info "$(_t 'Keeping the configuration directory /etc/prometheus')"
    fi

    if yes_no "$(_tf 'Delete the data directory %s (the historical monitoring data is lost)?' "${PROM_DATA_DIR}")"; then
        sudo rm -rf "$PROM_DATA_DIR"
        success "$(_t 'Data directory deleted')"
    else
        info "$(_tf 'Keeping the data directory %s' "$PROM_DATA_DIR")"
    fi

    success "Prometheus $(_t 'Uninstalled successfully!')"
}

# 状态
status_prometheus() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v prometheus &>/dev/null || [[ -f "$PROM_BIN" ]]; then
        is_installed=true
        version=$(prometheus --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || printf '%s\n' "$(_t 'Unknown version')")
    fi
    if service_is_active prometheus "$PROM_PLIST_LABEL"; then
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

  install     $(_t 'Install or update Prometheus (default action)')
  uninstall   $(_t 'Uninstall Prometheus')
  status      $(_t 'View the install and run status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_prometheus ;;
        uninstall) uninstall_prometheus ;;
        status)    status_prometheus ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
