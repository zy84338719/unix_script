#!/usr/bin/env bash
#
# frp/install.sh
#
# 安装 frp —— 内网穿透（fatedier/frp，frps 服务端 + frpc 客户端）。
# GitHub release 二进制；Linux 附 systemd unit（默认不启用）与配置样例。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="fatedier/frp"
CONF_DIR="/etc/frp"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
}

# GitHub release 资产用 amd64/arm64 命名
arch_for_frp() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

write_unit() {
    local name="$1" desc="$2"
    sudo tee "/etc/systemd/system/${name}.service" >/dev/null <<EOF
[Unit]
Description=${desc}
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/${name} -c ${CONF_DIR}/${name}.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

do_install() {
    preflight
    if command_exists frpc || command_exists frps; then
        yes_no "已检测到 frp，是否覆盖安装最新版？" || { info "已取消"; exit 0; }
    fi
    info "获取 frp 最新版本（GitHub API）..."
    local ver
    ver=$(github_latest_tag "$REPO")
    [[ -n "$ver" ]] || { error "无法获取版本号（GitHub 不可达或限流），可设 GH_TOKEN 重试"; exit 1; }
    local arch
    arch=$(arch_for_frp)
    local url
    url=$(github_release_asset_url "$REPO" "frp_${ver}_${OS_TYPE}_${arch}\.tar\.gz")
    [[ -n "$url" ]] || { error "未找到资产 frp_${ver}_${OS_TYPE}_${arch}.tar.gz"; exit 1; }
    info "下载 $url ..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    curl -fSL "$url" -o "$tmpdir/frp.tar.gz" || { error "下载失败"; exit 1; }
    tar -xzf "$tmpdir/frp.tar.gz" -C "$tmpdir"
    sudo install -m 0755 "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/frpc" /usr/local/bin/frpc
    sudo install -m 0755 "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/frps" /usr/local/bin/frps
    success "frpc / frps v$ver 已安装到 /usr/local/bin"

    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo mkdir -p "$CONF_DIR"
        # 配置样例：已存在不覆盖（含用户 token）
        [[ -f "$CONF_DIR/frpc.toml" ]] || sudo install -m 0600 \
            "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/conf/frpc_full_example.toml" "$CONF_DIR/frpc.toml"
        [[ -f "$CONF_DIR/frps.toml" ]] || sudo install -m 0600 \
            "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/conf/frps_full_example.toml" "$CONF_DIR/frps.toml"
        write_unit frpc "frp client"
        write_unit frps "frp server"
        sudo systemctl daemon-reload
        success "配置样例已放 $CONF_DIR（完整示例，编辑后使用）；systemd unit 已装（默认不启用）"
        info "服务端启用：sudo systemctl enable --now frps"
        info "客户端启用：sudo systemctl enable --now frpc"
    else
        info "macOS 不装 systemd 服务，直接手跑：frps -c <配置> / frpc -c <配置>"
    fi
    info "编辑 $CONF_DIR/frps.toml 设 bindPort 与 token；frpc.toml 配 serverAddr/serverName 及穿透规则"
}

do_uninstall() {
    preflight
    if ! command_exists frpc && ! command_exists frps; then
        warn "frp 未安装"
        exit 0
    fi
    yes_no "确认卸载 frp（frpc/frps 二进制与 systemd unit）？" || { info "已取消"; exit 0; }
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop frpc 2>/dev/null || true
        uxs_svc stop frps 2>/dev/null || true
        sudo systemctl disable frpc frps 2>/dev/null || true
        sudo rm -f /etc/systemd/system/frpc.service /etc/systemd/system/frps.service
        sudo systemctl daemon-reload
    fi
    sudo rm -f /usr/local/bin/frpc /usr/local/bin/frps
    success "frp 已卸载"
    if [[ -d "$CONF_DIR" ]]; then
        if yes_no "是否删除配置目录 $CONF_DIR（含你的 token 与穿透规则）？"; then
            sudo rm -rf "$CONF_DIR" && success "配置已删除"
        else
            info "保留配置"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists frpc && ! command_exists frps; then
        emit_status "not_installed" "❌ frp 未安装"
        return 0
    fi
    local ver
    ver=$(frps --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc is-active frps 2>/dev/null; then
            emit_status "installed:running" "✅ frp 已安装且 frps 服务运行中 ${ver:-(版本未知)}"
        else
            emit_status "installed:stopped" "⚠️ frp 已安装但 frps 服务未运行 ${ver:-(版本未知)}"
        fi
        if uxs_svc is-active frpc 2>/dev/null; then
            emit_extra "frpc_active=yes"
        else
            emit_extra "frpc_active=no"
        fi
    else
        emit_status "installed" "✅ frp 已安装 ${ver:-(版本未知)}（macOS 手动运行）"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
frp —— 内网穿透（frps 服务端 + frpc 客户端）

用法: install.sh {install|uninstall|status|help}

  install    安装 frpc/frps 二进制 + 配置样例（Linux 另附 systemd unit，默认不启用）
  uninstall  卸载（/etc/frp 配置含 token，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：服务端设 bindPort/token，客户端配 serverAddr 与穿透规则；
与 ddns-go（域名解析）、tailscale（组网）互补——./install.sh ddns-go
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
