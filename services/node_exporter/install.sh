#!/usr/bin/env bash
set -euo pipefail

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 全局变量
NE_BIN="/usr/local/bin/node_exporter"
NE_PLIST="/Library/LaunchDaemons/com.prometheus.node_exporter.plist"
NE_PLIST_LABEL="com.prometheus.node_exporter"

# --- 获取最新版本 ---
get_latest_version() {
    local ver
    ver=$(github_latest_tag "prometheus/node_exporter")
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
                armv7l)         echo "linux-armv7" ;;
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

# --- 检查已有安装并处理 ---
# brew 装的 node_exporter 落在 /opt/homebrew/bin，PATH 里未必有（服务跑在别的账号、
# 或非交互 shell 下 brew 不在 PATH 时都会漏）。而它和我们要装的绑同一个 9100，
# 所以「停旧服务」不能挂在 command -v node_exporter 这个判断上，否则会漏停，
# 新起的进程直接抢不到端口。
handle_existing_installation() {
    local found_install=false brew_managed=false
    if command -v node_exporter &>/dev/null || [[ -f "$NE_BIN" ]]; then
        found_install=true
        local current_version ne_path="node_exporter"
        # /usr/local/bin 不在非交互 shell 的默认 PATH 里，只认 command -v 会读不到版本
        command_exists node_exporter || ne_path="$NE_BIN"
        current_version=$("$ne_path" --version 2>&1 | grep -o 'version [0-9.]*' | cut -d' ' -f2 2>/dev/null || true)
        warn "$(_t 'node_exporter v detected')${current_version:-$(_t 'Unknown version')}"
    fi
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        if brew services list 2>/dev/null | awk '$1=="node_exporter" && $2=="started" {f=1} END {exit !f}'; then
            brew_managed=true
        fi
    fi

    # 先问再停：用户取消的话不该已经把服务停了
    if $found_install || $brew_managed; then
        if ! yes_no "$(_t 'Continue and upgrade to the latest version?')"; then
            info "$(_t 'The installation was cancelled')"
            exit 0
        fi
    fi

    info "$(_t 'Stopping the existing service...')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop node_exporter &>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if sudo launchctl list 2>/dev/null | grep -q "$NE_PLIST_LABEL"; then
            sudo launchctl bootout system "$NE_PLIST" &>/dev/null || true
        fi
        if $brew_managed; then
            brew services stop node_exporter &>/dev/null || true
        fi
    fi
}

# --- 下载并解压 ---
download_and_extract() {
    local latest="$1" arch_suffix="$2" tmpdir="$3"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${latest}/node_exporter-${latest}.${arch_suffix}.tar.gz"
    info "$(_tf 'Download URL: %s' "$url")"

    if ! curl -SL "$url" -o "$tmpdir/node_exporter.tar.gz"; then
        error "$(_t 'Download failed')"
        return 1
    fi
    if ! tar -xzf "$tmpdir/node_exporter.tar.gz" -C "$tmpdir"; then
        error "$(_t 'Extract failed')"
        return 1
    fi
    success "$(_t 'Download and extract complete')"
}

# --- 安装二进制文件 ---
install_binary() {
    local latest="$1" arch_suffix="$2" tmpdir="$3"
    info "$(_t 'Installing the binary files...')"
    if sudo mv "$tmpdir/node_exporter-${latest}.${arch_suffix}/node_exporter" /usr/local/bin/; then
        sudo chmod 755 "$NE_BIN"
        if [[ "$OS_TYPE" == "darwin" ]]; then
            sudo chown root:wheel "$NE_BIN"
        elif [[ "$OS_TYPE" == "linux" ]]; then
            sudo chown root:root "$NE_BIN"
        fi
        success "$(_t 'The binary files are installed')"
    else
        error "$(_t 'The binary installation failed')"
        return 1
    fi
}

# --- 创建 systemd 服务（Linux） ---
setup_systemd_service() {
    info "$(_t 'Creating the system user...')"
    if ! id -u node_exporter &>/dev/null; then
        if sudo useradd --no-create-home --shell /bin/false node_exporter; then
            success "$(_t 'The user node_exporter was created')"
        else
            error "$(_t 'The user creation failed')"
            return 1
        fi
    else
        info "$(_t 'The user node_exporter already exists')"
    fi

    info "$(_t 'Creating the systemd service file...')"
    if ! install_systemd_unit node_exporter.service <<EOF; then
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=${NE_BIN} --web.listen-address=":9100"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        error "systemd $(_t 'Failed to create the service file')"
        return 1
    fi
    success "systemd $(_t 'The service file was created')"

    info "$(_t 'Starting the service...')"
    if uxs_svc enable-now node_exporter; then
        success "node_exporter $(_t 'The service is running and enabled on boot')"
    else
        error "$(_t 'Failed to start the service')"
        return 1
    fi
}

# --- 创建 launchd 服务（macOS） ---
setup_launchd_service() {
    info "$(_t 'Creating the macOS service file...')"
    if ! sudo tee "$NE_PLIST" >/dev/null <<EOF; then
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${NE_PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NE_BIN}</string>
        <string>--web.listen-address=:9100</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/node_exporter.err</string>
    <key>StandardOutPath</key>
    <string>/var/log/node_exporter.log</string>
</dict>
</plist>
EOF
        error "LaunchDaemon $(_t 'Failed to create the service file')"
        return 1
    fi
    success "LaunchDaemon $(_t 'The service file was created')"

    info "$(_t 'Starting the service...')"
    if sudo launchctl list | grep -q "$NE_PLIST_LABEL"; then
        info "$(_t 'The service is already running')"
        success "node_exporter $(_t 'The service is running and enabled on boot')"
    else
        if sudo launchctl bootstrap system "$NE_PLIST"; then
            success "node_exporter $(_t 'The service is running and enabled on boot')"
        else
            warn "bootstrap $(_t 'The command failed, trying the load command as a fallback')"
            if sudo launchctl load "$NE_PLIST" 2>/dev/null; then
                success "node_exporter $(_t 'The service is running (started with the load command)')"
            else
                warn "$(_t 'The auto-start failed, but the service file is installed')"
                info "$(_tf 'You can start the service manually: sudo launchctl bootstrap system %s' "$NE_PLIST")"
            fi
        fi
    fi
}

# --- 验证安装 ---
verify_install() {
    info "$(_t 'Verifying the installation...')"
    sleep 3

    if service_is_active node_exporter "$NE_PLIST_LABEL"; then
        success "$(_t 'The service is running normally')"
        sleep 2
        if curl -s http://localhost:9100/metrics >/dev/null; then
            success "$(_t 'Port 9100 responds normally')"
        else
            warn "$(_t 'Port 9100 does not respond yet, it may take a few seconds')"
        fi
    else
        error "$(_t 'The service is not running normally')"
        info "$(_t 'You can use these commands to check the status and the logs:')"
        if [[ "$OS_TYPE" == "linux" ]]; then
            echo "  sudo systemctl status node_exporter"
            echo "  sudo journalctl -u node_exporter -f"
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            echo "  sudo launchctl list | grep node_exporter"
            echo "  tail -f /var/log/node_exporter.log"
        fi
    fi
}

# --- 打印安装结果 ---
print_install_summary() {
    local ip_addr installed_ver ne_path="node_exporter"
    ip_addr=$(get_local_ip)
    # brew 兜底装的位置在 /opt/homebrew/bin，不一定在 PATH 里
    command_exists node_exporter || ne_path="$NE_BIN"
    installed_ver=$("$ne_path" --version 2>&1 | grep -o 'version [0-9.]*' | cut -d' ' -f2 || true)

    echo
    echo "========================================"
    success "$(_t '🎉 Node Exporter installation complete!')"
    echo
    if [[ -n "$installed_ver" ]]; then
        info "$(_tf 'Installed version: v%s' "$installed_ver")"
    fi
    info "$(_t 'Service info:')"
    echo "  - $(_t 'Listen address: http://0.0.0.0:9100')"
    echo "  - $(_tf 'Metrics URL: http://%s:9100/metrics' "${ip_addr}")"
    echo "  - $(_tf 'Status page: http://%s:9100' "${ip_addr}")"
    echo
    info "$(_t 'Common commands:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  - $(_t 'Service status: sudo systemctl status node_exporter')"
        echo "  - $(_t 'View the logs: sudo journalctl -u node_exporter -f')"
        echo "  - $(_t 'Restart the service: sudo systemctl restart node_exporter')"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  - $(_t 'Service status: sudo launchctl list | grep node_exporter')"
        echo "  - $(_t 'View the logs: tail -f /var/log/node_exporter.log')"
        echo "  - $(_tf 'Start the service: sudo launchctl bootstrap system %s' "$NE_PLIST")"
    fi
}

# --- macOS：Homebrew 安装 / 升级 ---
# Homebrew 是 macOS 的核心安装载体，本模块以 brew 为主路径。
# 但 brew 有两个必须显式绕开的 no-op，二者都不报错，直接串起来会让「重跑即升级」
# 变成空操作、还照常报成功（实机复现：10.10.10.99 卡在 v1.9.1，重跑多少次都不动）：
#   brew install <已装>          → 提示 already installed 后 exit 0，二进制不动
#   brew services start <已跑>  → 提示 already started 后 exit 0，旧进程继续占着 9100
# 所以：已装必须显式 upgrade，升级后必须 restart。
install_via_brew() {
    local installed_ver="" new_ver="" latest_ver="" ne_path="node_exporter"
    if brew list --versions node_exporter &>/dev/null; then
        installed_ver=$(brew list --versions node_exporter 2>/dev/null | awk '{print $2}')
        info "$(_tf 'Version v%s installed, running brew upgrade to pull the latest...' "${installed_ver}")"
        if ! brew upgrade node_exporter; then
            warn "brew upgrade $(_t 'It did not work, falling back to brew reinstall')"
            brew reinstall node_exporter || return 1
        fi
    else
        brew install node_exporter || return 1
    fi

    # 换了二进制但旧进程还在监听 9100，不 restart 的话跑的还是老版本
    if brew services list 2>/dev/null | awk '$1=="node_exporter" && $2=="started" {f=1} END {exit !f}'; then
        info "$(_t 'The service is running, running restart to make the new version effective...')"
        brew services restart node_exporter &>/dev/null || true
    else
        brew services start node_exporter &>/dev/null || true
    fi

    # brew 装的在 /opt/homebrew/bin，非交互 shell 下未必在 PATH 里
    command_exists node_exporter || ne_path="$NE_BIN"
    new_ver=$("$ne_path" --version 2>&1 | grep -o 'version [0-9.]*' | cut -d' ' -f2 || true)

    local ip_addr
    ip_addr=$(get_local_ip)
    success "$(_t '🎉 Node Exporter installation complete! (managed by Homebrew)')"
    if [[ -n "$new_ver" ]]; then
        info "$(_tf 'Current version: v%s' "${new_ver}")"
    fi

    # brew 装的是 Homebrew Core 的版本，同步上游有延迟，可能还不是官方最新 tag。
    # 这里如实报出差距——否则「已装到最新版」就是句空头承诺。
    latest_ver=$(get_latest_version 2>/dev/null || true)
    if [[ -n "$latest_ver" && -n "$new_ver" ]] && version_gt "$latest_ver" "$new_ver"; then
        warn "Homebrew Core $(_tf 'The upstream sync lags behind: the official latest is v%s, brew currently provides v%s' "${latest_ver}" "${new_ver}")"
        info "$(_t 'Wait for the Homebrew sync and run this script again, this repository needs no change')"
    fi
    info "$(_tf 'Metrics URL: http://%s:9100/metrics' "${ip_addr}")"
    info "$(_t 'Common commands: brew services info node_exporter')"
}

# --- 安装主逻辑 ---
install_node_exporter() {
    detect_os
    check_commands curl tar
    handle_existing_installation

    info "$(_t '🚀 Node Exporter cross-platform install script')"
    echo "=========================================="

    # macOS 走 Homebrew（macOS 核心安装载体，且自带服务管理）；
    # Linux 与「没装 brew 的 macOS」走 GitHub 官方二进制。
    # 两条路径的版本都是动态取的（brew upgrade / github_latest_tag），
    # 上游发新版重跑即可，本仓库不需要跟着改。
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        install_via_brew || return 1
        return 0
    fi

    require_sudo

    # 官方源取版本（不硬编码，上游发新版重跑即可）
    info "$(_t 'Fetching the official latest version info...')"
    local latest
    latest=$(get_latest_version) || return 1
    success "$(_tf 'Official latest version: v%s' "${latest}")"

    # 确定架构
    local arch_suffix
    arch_suffix=$(detect_arch_suffix) || return 1
    info "$(_t 'Detected architecture:')$(uname -m) -> $arch_suffix"

    # 确认安装
    echo
    info "$(_tf 'About to install Node Exporter v%s (official GitHub release)' "${latest}")"
    info "$(_tf 'Install location: %s' "$NE_BIN")"
    info "$(_t 'Service port: 9100')"
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

    if ! download_and_extract "$latest" "$arch_suffix" "$tmpdir"; then
        error "$(_t 'Download failed')"
        return 1
    fi

    # 安装二进制
    install_binary "$latest" "$arch_suffix" "$tmpdir" || return 1

    # 创建服务
    if [[ "$OS_TYPE" == "linux" ]]; then
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
uninstall_node_exporter() {
    detect_os
    require_sudo
    info "$(_t 'Uninstalling Node Exporter...')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop node_exporter &>/dev/null || true
        uxs_svc disable node_exporter &>/dev/null || true
        sudo rm -f /etc/systemd/system/node_exporter.service
        uxs_svc daemon-reload &>/dev/null || true
        sudo rm -f "$NE_BIN"
        if id node_exporter &>/dev/null; then
            sudo userdel node_exporter
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system "$NE_PLIST" &>/dev/null || true
        sudo rm -f "$NE_PLIST"
        sudo rm -f "$NE_BIN"
        sudo rm -f /var/log/node_exporter.log /var/log/node_exporter.err
    fi
    success "Node Exporter $(_t 'Uninstalled successfully!')"
}

# 状态
status_node_exporter() {
    detect_os
    local is_installed=false is_running=false version=""
    if command -v node_exporter &>/dev/null || [[ -f "$NE_BIN" ]]; then
        is_installed=true
        if command -v node_exporter &>/dev/null; then
            version=$(node_exporter --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Unknown version')")
        fi
    fi
    if service_is_active node_exporter "$NE_PLIST_LABEL"; then
        is_running=true
    fi
    if $is_installed; then
        if $is_running; then
            emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC} ($version)"
        else
            emit_status "installed:stopped" "${YELLOW}$(_t '⚠️  Installed but not running')${NC} ($version)"
        fi
        emit_version "$version"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install or update Node Exporter (default action)')
  uninstall   $(_t 'Uninstall Node Exporter')
  status      $(_t 'View the install and run status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_node_exporter ;;
        uninstall) uninstall_node_exporter ;;
        status)    status_node_exporter ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
