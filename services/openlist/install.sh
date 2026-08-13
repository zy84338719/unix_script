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
        *) error "不支持的架构：$OS_TYPE/$arch"; exit 1 ;;
    esac
}

install_openlist() {
    preflight
    require_sudo
    info "🚀 开始安装 OpenList"

    if [[ -x "$OPENLIST_BIN" ]]; then
        local cur
        cur=$("$OPENLIST_BIN" version 2>/dev/null | head -1 || echo "已安装")
        warn "检测到已安装 OpenList（${cur}）"
        if ! yes_no "是否继续并覆盖安装最新版？"; then
            info "已取消"; return 0
        fi
        # 停止现有服务
        service_stop "$SERVICE_NAME" "$PLIST_FILE"
    fi

    info "获取最新版本..."
    local version suffix url tmpdir
    version=$(github_latest_tag "OpenListTeam/OpenList")
    if [[ -z "$version" ]]; then
        error "无法获取最新版本（请检查网络或设置 GH_TOKEN 规避 API 限速）"
        exit 1
    fi
    success "最新版本：v$version"

    suffix=$(arch_suffix)
    url="https://github.com/OpenListTeam/OpenList/releases/download/v${version}/openlist-${suffix}.tar.gz"
    info "下载：$url"

    tmpdir=$(mktemp -d)
    if ! curl -fSL "$url" -o "$tmpdir/openlist.tar.gz"; then
        error "下载失败"; rm -rf "$tmpdir"; exit 1
    fi
    if ! tar -xzf "$tmpdir/openlist.tar.gz" -C "$tmpdir"; then
        error "解压失败"; rm -rf "$tmpdir"; exit 1
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
    success "二进制安装完成"

    # 配置服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "创建 systemd 服务..."
        sudo tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF
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
        sudo systemctl daemon-reload
        sudo systemctl enable --now "$SERVICE_NAME"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "创建 launchd 服务..."
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

    info "验证..."
    sleep 3
    if service_is_active "$SERVICE_NAME" "$PLIST_LABEL"; then
        success "OpenList 服务运行正常"
    else
        warn "服务可能仍在启动中，稍后访问 Web 界面确认"
    fi

    # 首次安装需获取随机管理员密码
    info "首次安装的管理员密码（随机生成）："
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo journalctl -u "$SERVICE_NAME" --no-pager 2>/dev/null | grep -i "password" | tail -3 || \
            echo "  可执行：sudo ${OPENLIST_BIN} admin random   # 重新生成随机密码"
    else
        echo "  可执行：sudo ${OPENLIST_BIN} admin random"
    fi

    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "🎉 OpenList v$version 安装完成！"
    info "访问地址：http://${ip_addr}:${OPENLIST_PORT}"
    info "默认管理员账号：admin"
    echo
    info "常用命令："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status openlist"
        echo "  sudo journalctl -u openlist -f"
    else
        echo "  sudo launchctl list | grep openlist"
        echo "  tail -f /var/log/openlist.log"
    fi
    echo "  sudo ${OPENLIST_BIN} admin set NEW_PASSWORD   # 设置管理员密码"
}

uninstall_openlist() {
    preflight
    require_sudo
    if ! yes_no "确认卸载 OpenList？"; then
        info "已取消"; return 0
    fi
    service_stop "$SERVICE_NAME" "$PLIST_FILE"
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo rm -f /etc/systemd/system/${SERVICE_NAME}.service
        sudo systemctl daemon-reload 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo rm -f "$PLIST_FILE"
    fi
    if yes_no "是否删除数据目录 ${INSTALL_DIR}（含配置与数据库）？"; then
        sudo rm -rf "$INSTALL_DIR"
        success "数据目录已删除"
    fi
    success "OpenList 已卸载。"
}

status_openlist() {
    detect_os
    if [[ ! -x "$OPENLIST_BIN" ]]; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"; return
    fi
    if service_is_active "$SERVICE_NAME" "$PLIST_LABEL"; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装但未运行${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Alist（文件列表/网盘聚合，默认端口 5244）
  uninstall   卸载 Alist
  status      查看状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
