#!/usr/bin/env bash
#
# clash/install.sh
#
# 安装与配置 mihomo（clash.meta）—— 活跃维护的 clash 核心分叉。
# 仅 Linux（服务器命令行场景）。提供二进制安装 + systemd 服务 + 配置管理。
#
# 子命令:
#   install              下载安装 mihomo 二进制 + systemd 服务（默认）
#   config <url|file>    下载/复制配置到 /etc/mihomo/config.yaml
#   example              生成一份本地示例配置（SOCKS 1080 / HTTP 7890）
#   tun-on / tun-off     开启/关闭 TUN 透明代理（需内核 tun 模块）
#   start|stop|restart   服务管理
#   status               查看状态
#   uninstall            卸载
#   help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="MetaCubeX/mihomo"
INSTALL_DIR="/opt/mihomo"
BIN="$INSTALL_DIR/mihomo"
CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SERVICE_NAME="mihomo"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
# 混合端口（mihomo 默认）
MIXED_PORT=7890
API_PORT=9090

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "clash(mihomo) $(_tf 'Service mode is Linux only. Current: %s' "$OS_TYPE")"
        exit 1
    fi
    check_commands curl
}

arch_suffix() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)         echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l)         echo "armv7" ;;
        *) error "$(_tf 'Unsupported architecture: %s' "$arch")"; exit 1 ;;
    esac
}

# 安装 mihomo 二进制 + systemd 服务
install_clash() {
    preflight
    require_sudo
    info "$(_t '🚀 Installing mihomo (clash.meta)')"

    local version suffix url tmpdir
    version=$(github_latest_tag "$REPO")
    if [[ -z "$version" ]]; then
        error "$(_t 'Cannot fetch the latest mihomo version (check the network or set GH_TOKEN)')"
        exit 1
    fi
    success "$(_tf 'Latest version: %s' "$version")"
    suffix=$(arch_suffix)

    # 优先用 -compatible 变体（兼容老 CPU），失败回退标准版
    url="https://github.com/${REPO}/releases/download/${version}/mihomo-linux-${suffix}-compatible-${version}.gz"
    info "$(_tf 'Downloading: %s' "$url")"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    if ! curl -fSL "$url" -o "$tmpdir/mihomo.gz" 2>/dev/null; then
        url="https://github.com/${REPO}/releases/download/${version}/mihomo-linux-${suffix}-${version}.gz"
        info "compatible $(_tf 'build download failed, trying the standard build: %s' "$url")"
        if ! curl -fSL "$url" -o "$tmpdir/mihomo.gz"; then
            error "$(_t 'Download failed')"; rm -rf "$tmpdir"; exit 1
        fi
    fi
    if ! gzip -d -f "$tmpdir/mihomo.gz" 2>/dev/null; then
        # 某些情况下文件已是二进制（非 gzip）
        mv "$tmpdir/mihomo.gz" "$tmpdir/mihomo" 2>/dev/null || true
    fi

    sudo mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
    sudo mv "$tmpdir/mihomo" "$BIN"
    sudo chmod +x "$BIN"
    sudo chown root:root "$BIN"
    rm -rf "$tmpdir"
    success "mihomo $(_tf 'The binary installation is complete: %s' "$BIN")"

    # systemd 服务（前台运行，日志走 journalctl）
    info "$(_t 'Creating the systemd service...')"
    install_systemd_unit "${SERVICE_NAME}.service" <<EOF
[Unit]
Description=mihomo (Clash.Meta) Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN -d $CONFIG_DIR -f $CONFIG_FILE
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
# $(_t 'Allow TUN mode (if enabled)')
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    # 若无配置，生成示例
    if [[ ! -f "$CONFIG_FILE" ]]; then
        do_example
    fi

    echo
    success "$(_t '🎉 mihomo installation complete!')"
    info "$(_t 'Next steps:')"
    echo "  1. $(_tf 'Put the configuration in place: %s config <subscription URL or local file>' "$0")"
    echo "     $(_tf 'Or start with the example: %s example' "$0")"
    echo "  2. $(_tf 'Start it: %s start' "$0")"
    echo "  3. $(_tf 'Proxy address: HTTP/SOCKS mixed port %s' "$MIXED_PORT")"
    echo "  4. $(_tf 'Management API: http://127.0.0.1:%s' "$API_PORT")"
}

# config <url|file>: 下载订阅或复制本地文件为配置
do_config() {
    preflight
    require_sudo
    local src="${1:-}"
    if [[ -z "$src" ]]; then
        error "$(_tf 'Usage: %s config <subscription URL | local file>' "$0")"
        exit 1
    fi
    sudo mkdir -p "$CONFIG_DIR"
    # 备份现有
    if [[ -f "$CONFIG_FILE" ]]; then
        sudo cp -a "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"
        info "$(_t 'The existing configuration has been backed up')"
    fi
    if [[ "$src" == http* ]]; then
        info "$(_t 'Downloading the configuration from the subscription URL...')"
        if ! curl -fsSL "$src" -o "$CONFIG_FILE"; then
            error "$(_tf 'Download failed: %s' "$src")"
            exit 1
        fi
    else
        if [[ ! -f "$src" ]]; then
            error "$(_tf 'The file does not exist: %s' "$src")"
            exit 1
        fi
        sudo cp "$src" "$CONFIG_FILE"
    fi
    sudo chmod 644 "$CONFIG_FILE"
    success "$(_tf 'The configuration has been written to %s' "$CONFIG_FILE")"
    info "$(_tf 'It takes effect after a restart: %s restart' "$0")"
}

# example: 生成最小示例配置
do_example() {
    preflight
    require_sudo
    sudo mkdir -p "$CONFIG_DIR"
    sudo tee "$CONFIG_FILE" >/dev/null <<'EOF'
# Minimal sample configuration for mihomo (generated by clash/install.sh example)
# Replace it with your real subscription / node configuration
mixed-port: 7890          # HTTP and SOCKS5 mixed proxy port
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
    success "$(_tf 'The sample configuration %s has been generated (replace it with a real subscription)' "${CONFIG_FILE}")"
}

# TUN 透明代理开关
do_tun_on() {
    preflight
    require_sudo
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "$(_t 'No configuration file, run config/example first')"; exit 1
    fi
    info "$(_t 'Enabling the TUN transparent proxy in the configuration...')"
    # 追加 tun 段（若已存在则跳过）
    if grep -q "^tun:" "$CONFIG_FILE" 2>/dev/null; then
        warn "$(_t 'The configuration already has a tun section, skipping')"
    else
        sudo tee -a "$CONFIG_FILE" >/dev/null <<'EOF'

tun:
  enable: true
  stack: system
  dns-hijack:
    - any:53
  auto-route: true
  auto-detect-interface: true
EOF
        success "$(_t 'TUN has been enabled (restart mihomo to apply it)')"
    fi
    # 确保 IP 转发开启
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    info "$(_t 'net.ipv4.ip_forward has been enabled')"
    warn "TUN $(_t 'The NET_ADMIN capability is required (the systemd service already sets AmbientCapabilities)')"
}

do_tun_off() {
    preflight
    require_sudo
    if grep -q "^tun:" "$CONFIG_FILE" 2>/dev/null; then
        # 把 tun.enable 改为 false
        sudo sed -i '/^tun:/,/^[^ ]/ s/enable: true/enable: false/' "$CONFIG_FILE" 2>/dev/null || true
        success "$(_t 'TUN has been disabled (restart mihomo to apply it)')"
    else
        info "$(_t 'The configuration has no tun section, nothing to disable')"
    fi
}

# 服务管理
do_start()   { preflight; require_sudo; uxs_svc enable-now "$SERVICE_NAME"; success "mihomo $(_t 'Started')"; }
do_stop()    { preflight; require_sudo; uxs_svc stop "$SERVICE_NAME" 2>/dev/null || true; success "mihomo $(_t 'Stopped')"; }
do_restart() { preflight; require_sudo; uxs_svc restart "$SERVICE_NAME"; success "mihomo $(_t 'Restarted')"; }

status_clash() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}$(_t '⚠️  Not applicable (Linux only)')${NC}"; return
    fi
    if [[ ! -x "$BIN" ]]; then
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"; return
    fi
    if uxs_svc is-active "$SERVICE_NAME" 2>/dev/null; then
        emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}$(_t '⚠️  Installed but not running')${NC}"
    fi
}

uninstall_clash() {
    preflight
    require_sudo
    if ! yes_no "$(_t 'Uninstall mihomo (clash)?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    uxs_svc stop "$SERVICE_NAME" 2>/dev/null || true
    uxs_svc disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"
    uxs_svc daemon-reload 2>/dev/null || true
    sudo rm -f "$BIN"
    if yes_no "$(_tf 'Delete the configuration directory %s (with the subscriptions and nodes)?' "${CONFIG_DIR}")"; then
        sudo rm -rf "$CONFIG_DIR"
        success "$(_t 'The configuration directory has been deleted')"
    fi
    success "mihomo $(_t 'Uninstalled')"
}

usage() {
    cat <<EOF
用法: $0 {install|config|example|tun-on|tun-off|start|stop|restart|status|uninstall|help}  (仅 Linux)

mihomo (clash.meta) $(_t 'Install and configure:')
  install              $(_t 'Install the binary and the systemd service (default)')
  config <url|file>    $(_t 'Download a subscription or copy a local file as the configuration')
  example              $(_t 'Generate a minimal sample configuration')
  tun-on / tun-off     $(_t 'Enable or disable the TUN transparent proxy')
  start|stop|restart   $(_t 'Service management')
  status               $(_t 'View the status')
  uninstall            $(_t 'Uninstall')

$(_tf 'Proxy port: HTTP/SOCKS mixed %s ｜ Management API %s' "$MIXED_PORT" "$API_PORT")
$(_t 'Examples:')
  $0 install
  $0 config https://example.com/sub.yaml
  $0 start
  curl -x http://127.0.0.1:$MIXED_PORT https://ifconfig.me
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_clash ;;
        config)    shift; do_config "$@" ;;
        example)   do_example ;;
        tun-on)    do_tun_on ;;
        tun-off)   do_tun_off ;;
        start)     do_start ;;
        stop)      do_stop ;;
        restart)   do_restart ;;
        status)    status_clash ;;
        uninstall) uninstall_clash ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
