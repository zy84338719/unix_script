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

set -e

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
        error "clash(mihomo) 服务模式仅支持 Linux。当前：$OS_TYPE"
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
        *) error "不支持的架构：$arch"; exit 1 ;;
    esac
}

# 安装 mihomo 二进制 + systemd 服务
install_clash() {
    preflight
    require_sudo
    info "🚀 安装 mihomo (clash.meta)"

    local version suffix url tmpdir
    version=$(github_latest_tag "$REPO")
    if [[ -z "$version" ]]; then
        error "无法获取 mihomo 最新版本（请检查网络或设置 GH_TOKEN）"
        exit 1
    fi
    success "最新版本：$version"
    suffix=$(arch_suffix)

    # 优先用 -compatible 变体（兼容老 CPU），失败回退标准版
    url="https://github.com/${REPO}/releases/download/${version}/mihomo-linux-${suffix}-compatible-${version}.gz"
    info "下载：$url"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    if ! curl -fSL "$url" -o "$tmpdir/mihomo.gz" 2>/dev/null; then
        url="https://github.com/${REPO}/releases/download/${version}/mihomo-linux-${suffix}-${version}.gz"
        info "compatible 版下载失败，尝试标准版：$url"
        if ! curl -fSL "$url" -o "$tmpdir/mihomo.gz"; then
            error "下载失败"; rm -rf "$tmpdir"; exit 1
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
    success "mihomo 二进制安装完成：$BIN"

    # systemd 服务（前台运行，日志走 journalctl）
    info "创建 systemd 服务..."
    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
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
# 允许 TUN 模式（如启用）
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload

    # 若无配置，生成示例
    if [[ ! -f "$CONFIG_FILE" ]]; then
        do_example
    fi

    echo
    success "🎉 mihomo 安装完成！"
    info "下一步："
    echo "  1. 放入配置: $0 config <订阅URL或本地文件>"
    echo "     或先用示例: $0 example"
    echo "  2. 启动: $0 start"
    echo "  3. 代理地址: HTTP/SOCKS 混合端口 $MIXED_PORT"
    echo "  4. 管理 API: http://127.0.0.1:$API_PORT"
}

# config <url|file>: 下载订阅或复制本地文件为配置
do_config() {
    preflight
    require_sudo
    local src="${1:-}"
    if [[ -z "$src" ]]; then
        error "用法: $0 config <订阅URL | 本地文件>"
        exit 1
    fi
    sudo mkdir -p "$CONFIG_DIR"
    # 备份现有
    if [[ -f "$CONFIG_FILE" ]]; then
        sudo cp -a "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"
        info "已备份现有配置"
    fi
    if [[ "$src" == http* ]]; then
        info "从订阅 URL 下载配置..."
        if ! curl -fsSL "$src" -o "$CONFIG_FILE"; then
            error "下载失败：$src"
            exit 1
        fi
    else
        if [[ ! -f "$src" ]]; then
            error "文件不存在：$src"
            exit 1
        fi
        sudo cp "$src" "$CONFIG_FILE"
    fi
    sudo chmod 644 "$CONFIG_FILE"
    success "配置已写入 $CONFIG_FILE"
    info "重启生效: $0 restart"
}

# example: 生成最小示例配置
do_example() {
    preflight
    require_sudo
    sudo mkdir -p "$CONFIG_DIR"
    sudo tee "$CONFIG_FILE" >/dev/null <<'EOF'
# mihomo 最小示例配置（由 clash/install.sh example 生成）
# 请替换为你的真实订阅/节点配置
mixed-port: 7890          # HTTP 与 SOCKS5 混合代理端口
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF
    success "已生成示例配置 $CONFIG_FILE（请替换为真实订阅）"
}

# TUN 透明代理开关
do_tun_on() {
    preflight
    require_sudo
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "无配置文件，请先 config/example"; exit 1
    fi
    info "在配置中启用 TUN 透明代理..."
    # 追加 tun 段（若已存在则跳过）
    if grep -q "^tun:" "$CONFIG_FILE" 2>/dev/null; then
        warn "配置中已有 tun 段，跳过"
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
        success "已启用 TUN（需重启 mihomo 生效）"
    fi
    # 确保 IP 转发开启
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    info "已开启 net.ipv4.ip_forward"
    warn "TUN 需要 NET_ADMIN 权限（systemd 服务已配置 AmbientCapabilities）"
}

do_tun_off() {
    preflight
    require_sudo
    if grep -q "^tun:" "$CONFIG_FILE" 2>/dev/null; then
        # 把 tun.enable 改为 false
        sudo sed -i '/^tun:/,/^[^ ]/ s/enable: true/enable: false/' "$CONFIG_FILE" 2>/dev/null || true
        success "已关闭 TUN（重启 mihomo 生效）"
    else
        info "配置中无 tun 段，无需关闭"
    fi
}

# 服务管理
do_start()   { preflight; require_sudo; sudo systemctl enable --now "$SERVICE_NAME"; success "mihomo 已启动"; }
do_stop()    { preflight; require_sudo; sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true; success "mihomo 已停止"; }
do_restart() { preflight; require_sudo; sudo systemctl restart "$SERVICE_NAME"; success "mihomo 已重启"; }

status_clash() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    if [[ ! -x "$BIN" ]]; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"; return
    fi
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装但未运行${NC}"
    fi
}

uninstall_clash() {
    preflight
    require_sudo
    if ! yes_no "确认卸载 mihomo（clash）？"; then
        info "已取消"; return 0
    fi
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo rm -f "$BIN"
    if yes_no "是否删除配置目录 $CONFIG_DIR（含订阅/节点）？"; then
        sudo rm -rf "$CONFIG_DIR"
        success "配置目录已删除"
    fi
    success "mihomo 已卸载"
}

usage() {
    cat <<EOF
用法: $0 {install|config|example|tun-on|tun-off|start|stop|restart|status|uninstall|help}  (仅 Linux)

mihomo (clash.meta) 安装与配置:
  install              安装二进制 + systemd 服务（默认）
  config <url|file>    下载订阅/复制本地文件为配置
  example              生成最小示例配置
  tun-on / tun-off     开启/关闭 TUN 透明代理
  start|stop|restart   服务管理
  status               查看状态
  uninstall            卸载

代理端口: HTTP/SOCKS 混合 $MIXED_PORT ｜ 管理 API $API_PORT
示例:
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
