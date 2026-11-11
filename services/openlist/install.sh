#!/usr/bin/env bash
#
# openlist/install.sh
#
# 安装与管理 OpenList（原 Alist，已更名）—— 文件列表程序 / 网盘聚合（支持多存储后端，提供 WebDAV）。
# Linux（systemd）+ macOS（launchd）。默认端口 5244。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

INSTALL_DIR="/opt/openlist"
OPENLIST_BIN="$INSTALL_DIR/openlist"
SERVICE_NAME="openlist"
PLIST_LABEL="org.openlist.server"
PLIST_FILE="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
OPENLIST_PORT=5244

preflight() {
    detect_os
    check_commands curl tar
}

# 解析架构到 openlist 的发布后缀
arch_suffix() {
    local arch
    arch="$(uname -m)"
    case "$OS_TYPE/$arch" in
        linux/x86_64)        echo "linux-amd64" ;;
        linux/aarch64|linux/arm64) echo "linux-arm64" ;;
        linux/armv7l)        echo "linux-arm-7" ;;
        darwin/x86_64)       echo "darwin-amd64" ;;
        darwin/arm64|darwin/aarch64) echo "darwin-arm64" ;;
        *) error "$(_tf 'Unsupported architecture: %s/%s' "$OS_TYPE" "$arch")"; exit 1 ;;
    esac
}

install_openlist() {
    preflight
    require_sudo
    info "$(_t '🚀 Starting the OpenList installation')"

    if [[ -x "$OPENLIST_BIN" ]]; then
        local cur
        cur=$("$OPENLIST_BIN" version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'OpenList detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and overwrite it with the latest version?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
        # 停止现有服务
        service_stop "$SERVICE_NAME" "$PLIST_FILE"
    fi

    info "$(_t 'Fetching the latest version...')"
    local version suffix url tmpdir
    version=$(http_github_latest_tag "OpenListTeam/OpenList")
    if [[ -z "$version" ]]; then
        error "$(_t 'Cannot fetch the latest version (check the network or set GH_TOKEN to avoid the API rate limit)')"
        exit 1
    fi
    success "$(_tf 'Latest version: v%s' "$version")"

    suffix=$(arch_suffix)
    url="https://github.com/OpenListTeam/OpenList/releases/download/v${version}/openlist-${suffix}.tar.gz"
    info "$(_tf 'Downloading: %s' "$url")"

    tmpdir=$(mktemp -d)
    if ! curl -fSL "$url" -o "$tmpdir/openlist.tar.gz"; then
        error "$(_t 'Download failed')"; rm -rf "$tmpdir"; exit 1
    fi
    if ! tar -xzf "$tmpdir/openlist.tar.gz" -C "$tmpdir"; then
        error "$(_t 'Extract failed')"; rm -rf "$tmpdir"; exit 1
    fi

    sudo mkdir -p "$INSTALL_DIR"
    sudo mv "$tmpdir/openlist" "$OPENLIST_BIN"
    sudo chmod +x "$OPENLIST_BIN"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel "$OPENLIST_BIN"
    else
        sudo chown root:root "$OPENLIST_BIN"
    fi
    rm -rf "$tmpdir"
    success "$(_t 'The binary installation is complete')"

    # 配置服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "$(_t 'Creating the systemd service...')"
        install_systemd_unit "${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Alist File List Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${OPENLIST_BIN} server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        uxs_svc enable-now "$SERVICE_NAME"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Creating the launchd service...')"
        sudo tee "$PLIST_FILE" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${OPENLIST_BIN}</string>
        <string>server</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/openlist.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/openlist.err</string>
</dict>
</plist>
EOF
        service_start "" "$PLIST_FILE"
    fi

    info "$(_t 'Verifying...')"
    sleep 3
    if service_is_active "$SERVICE_NAME" "$PLIST_LABEL"; then
        success "OpenList $(_t 'The service is running normally')"
    else
        warn "$(_t 'The service may still be starting, check the web interface later')"
    fi

    # 首次安装需获取随机管理员密码
    info "$(_t 'The admin password of the first install (randomly generated):')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo journalctl -u "$SERVICE_NAME" --no-pager 2>/dev/null | grep -i "password" | tail -3 || \
            echo "  $(_tf 'Run: sudo %s admin random   # regenerate a random password' "${OPENLIST_BIN}")"
    else
        echo "  $(_tf 'Run: sudo %s admin random' "${OPENLIST_BIN}")"
    fi

    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "$(_tf '🎉 OpenList v%s installation complete!' "$version")"
    info "$(_tf 'Access URL: http://%s:%s' "${ip_addr}" "${OPENLIST_PORT}")"
    info "$(_t 'The default admin account is: admin')"
    echo
    info "$(_t 'Common commands:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status openlist"
        echo "  sudo journalctl -u openlist -f"
    else
        echo "  sudo launchctl list | grep openlist"
        echo "  tail -f /var/log/openlist.log"
    fi
    echo "  sudo ${OPENLIST_BIN} admin set NEW_PASSWORD   # $(_t 'Set the admin password')"
}

uninstall_openlist() {
    preflight
    require_sudo
    if ! yes_no "$(_t 'Confirm uninstall of OpenList?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    service_stop "$SERVICE_NAME" "$PLIST_FILE"
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo rm -f /etc/systemd/system/${SERVICE_NAME}.service
        uxs_svc daemon-reload 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo rm -f "$PLIST_FILE"
    fi
    if yes_no "$(_tf 'Delete the data directory %s (it holds the configuration and the database)?' "${INSTALL_DIR}")"; then
        sudo rm -rf "$INSTALL_DIR"
        success "$(_t 'Data directory deleted')"
    fi
    success "OpenList $(_t 'Uninstalled.')"
}

status_openlist() {
    detect_os
    if [[ ! -x "$OPENLIST_BIN" ]]; then
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"; return
    fi
    local ver
    # 不用 `| head -1`：head 命中即退会给上游 SIGPIPE(141)；grep 无匹配时退出 1。
    # 两者在 pipefail 下都会让整条管道非 0，set -e 会让 status 子命令整体中止
    # （违反「状态子命令恒 0」契约）。改用 sed 取首行（sed 读完整个输入才退出），
    # 取不到版本号就回落成空值。
    ver=$("$OPENLIST_BIN" version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | sed -n '1p') || ver=""
    if service_is_active "$SERVICE_NAME" "$PLIST_LABEL"; then
        uxs_emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC}"
    else
        uxs_emit_status "installed:stopped" "${YELLOW}$(_t '⚠️  Installed but not running')${NC}"
    fi
    # 收尾用 if 而不是 `[[ -n "$ver" ]] && ...`：后者在版本号为空时返回 1，
    # 会让 status 子命令整体退出 1（同样是「status 恒 0」契约）。
    if [[ -n "$ver" ]]; then
        uxs_emit_version "$ver"
    fi
    return 0
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Alist (file listing / drive aggregation, default port 5244)')
  uninstall   $(_t 'Uninstall Alist')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_openlist ;;
        uninstall) uninstall_openlist ;;
        status)    status_openlist ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
