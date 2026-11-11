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
        *)      error "$(_tf 'Unsupported architecture: %s (only x86_64/arm64 are supported)' "${ARCH_TYPE}")"; return 1 ;;
    esac
}

write_unit() {
    local name="$1" desc="$2"
    install_systemd_unit "${name}.service" <<EOF
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
        yes_no "$(_t 'frp detected, overwrite it with the latest version?')" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    info "$(_t 'Fetching the latest frp version (GitHub API)...')"
    local ver
    ver=$(github_latest_tag "$REPO")
    [[ -n "$ver" ]] || { error "$(_t 'Cannot fetch the version (GitHub is unreachable or rate limited), set GH_TOKEN and retry')"; exit 1; }
    local arch
    arch=$(arch_for_frp)
    local url
    url=$(github_release_asset_url "$REPO" "frp_${ver}_${OS_TYPE}_${arch}\.tar\.gz")
    [[ -n "$url" ]] || { error "$(_tf 'Asset frp_%s_%s_%s.tar.gz not found' "${ver}" "${OS_TYPE}" "${arch}")"; exit 1; }
    info "$(_tf 'Downloading %s ...' "$url")"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    curl -fSL "$url" -o "$tmpdir/frp.tar.gz" || { error "$(_t 'Download failed')"; exit 1; }
    tar -xzf "$tmpdir/frp.tar.gz" -C "$tmpdir"
    sudo install -m 0755 "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/frpc" /usr/local/bin/frpc
    sudo install -m 0755 "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/frps" /usr/local/bin/frps
    success "frpc / frps v$ver $(_t 'Installed to /usr/local/bin')"

    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo mkdir -p "$CONF_DIR"
        # 配置样例：已存在不覆盖（含用户 token）
        [[ -f "$CONF_DIR/frpc.toml" ]] || sudo install -m 0600 \
            "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/conf/frpc_full_example.toml" "$CONF_DIR/frpc.toml"
        [[ -f "$CONF_DIR/frps.toml" ]] || sudo install -m 0600 \
            "$tmpdir/frp_${ver}_${OS_TYPE}_${arch}/conf/frps_full_example.toml" "$CONF_DIR/frps.toml"
        write_unit frpc "frp client"
        write_unit frps "frp server"
        success "$(_tf 'The sample configuration is in %s (a full example, edit it before use); the systemd unit is installed (disabled by default)' "${CONF_DIR}")"
        info "$(_t 'Enable the server: sudo systemctl enable --now frps')"
        info "$(_t 'Enable the client: sudo systemctl enable --now frpc')"
    else
        info "macOS $(_t 'Without the systemd service, run it manually: frps -c <config> / frpc -c <config>')"
    fi
    info "$(_tf 'Edit %s/frps.toml to set bindPort and token; set serverAddr/serverName and the tunnel rules in frpc.toml' "$CONF_DIR")"
}

do_uninstall() {
    preflight
    if ! command_exists frpc && ! command_exists frps; then
        warn "frp $(_t 'Not installed')"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of frp (the frpc/frps binaries and the systemd unit)?')" || { info "$(_t 'Cancelled')"; exit 0; }
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc stop frpc 2>/dev/null || true
        uxs_svc stop frps 2>/dev/null || true
        uxs_svc disable frpc frps 2>/dev/null || true
        sudo rm -f /etc/systemd/system/frpc.service /etc/systemd/system/frps.service
        uxs_svc daemon-reload
    fi
    sudo rm -f /usr/local/bin/frpc /usr/local/bin/frps
    success "frp $(_t 'Uninstalled')"
    if [[ -d "$CONF_DIR" ]]; then
        if yes_no "$(_tf 'Delete the configuration directory %s (it holds your token and the tunnel rules)?' "${CONF_DIR}")"; then
            sudo rm -rf "$CONF_DIR" && success "$(_t 'Configuration deleted')"
        else
            info "$(_t 'Keeping the configuration')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists frpc && ! command_exists frps; then
        emit_status "not_installed" "$(_t '❌ frp not installed')"
        return 0
    fi
    local ver
    ver=$(frps --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc is-active frps 2>/dev/null; then
            emit_status "installed:running" "$(_t '✅ frp installed and the frps service is running') ${ver:-$(_t '(unknown version)')}"
        else
            emit_status "installed:stopped" "$(_t '⚠️ frp installed but the frps service is not running') ${ver:-$(_t '(unknown version)')}"
        fi
        if uxs_svc is-active frpc 2>/dev/null; then
            emit_extra "frpc_active=yes"
        else
            emit_extra "frpc_active=no"
        fi
    else
        emit_status "installed" "$(_t '✅ frp installed') ${ver:-$(_t '(unknown version)')}$(_t '(run it manually on macOS)')"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
frp $(_t '— Intranet penetration (the frps server + the frpc client)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install the frpc/frps binaries and a sample configuration (Linux also gets a systemd unit, disabled by default)')
  uninstall  $(_t 'Uninstall (the /etc/frp configuration holds the token, deletion needs a second confirmation)')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: the server sets bindPort/token, the client sets serverAddr and the tunnel rules;')
$(_t 'it complements ddns-go (DNS resolution) and tailscale (networking) — run ./install.sh ddns-go')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
