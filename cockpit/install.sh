#!/usr/bin/env bash
#
# cockpit/install.sh
#
# 安装与管理 Cockpit —— Linux 的 Web 服务器管理图形面板。
# 仅 Linux（依赖 systemd）。提供 Web UI（默认 9090 端口）管理系统。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

COCKPIT_PORT=9090

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "Cockpit 仅支持 Linux（依赖 systemd）。当前：$OS_TYPE"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "需要 systemctl（systemd）。"
        exit 1
    fi
}

install_cockpit() {
    preflight
    require_sudo
    detect_pkg_manager
    info "🚀 开始安装 Cockpit（包管理器：$PKG_MANAGER）"

    if command_exists cockpit-bridge 2>/dev/null || rpm -q cockpit >/dev/null 2>&1 || dpkg -s cockpit >/dev/null 2>&1; then
        warn "检测到 Cockpit 已安装"
        if ! yes_no "是否继续并重装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    info "安装 cockpit..."
    case "$PKG_MANAGER" in
        apt-get)
            sudo apt-get update -y
            sudo apt-get install -y cockpit
            ;;
        dnf)
            sudo dnf install -y cockpit
            ;;
        yum)
            sudo yum install -y cockpit
            ;;
        *)
            error "不支持的包管理器，请手动安装 cockpit"; exit 1
            ;;
    esac

    if ! command_exists cockpit-bridge 2>/dev/null; then
        error "安装失败：找不到 cockpit-bridge"
        exit 1
    fi

    info "启用并启动 cockpit.socket（按需激活的 socket，更安全）..."
    sudo systemctl enable --now cockpit.socket 2>/dev/null || sudo systemctl enable --now cockpit 2>/dev/null || true

    # 放行防火墙（若存在）
    if command_exists firewall-cmd; then
        sudo firewall-cmd --add-service=cockpit --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        success "已放行防火墙 cockpit 服务"
    fi
    if command_exists ufw; then
        sudo ufw allow "$COCKPIT_PORT"/tcp 2>/dev/null || true
        success "已放行 ufw $COCKPIT_PORT/tcp"
    fi

    info "验证..."
    sleep 2
    if systemctl is-active --quiet cockpit.socket 2>/dev/null || systemctl is-active --quiet cockpit 2>/dev/null; then
        success "Cockpit socket/service 运行正常"
    else
        warn "Cockpit 服务未运行（socket 模式下首次访问才激活，属正常）"
    fi

    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "🎉 Cockpit 安装完成！"
    info "访问地址：https://${ip_addr}:${COCKPIT_PORT}"
    warn "使用系统用户账号登录（需要该用户有 sudo 权限以进行管理操作）。"
    info "常用命令："
    echo "  sudo systemctl status cockpit.socket"
    echo "  sudo journalctl -u cockpit -f"
}

uninstall_cockpit() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! yes_no "确认卸载 Cockpit？"; then
        info "已取消"; return 0
    fi
    sudo systemctl disable --now cockpit.socket 2>/dev/null || true
    sudo systemctl disable --now cockpit 2>/dev/null || true
    case "$PKG_MANAGER" in
        apt-get) sudo apt-get remove --purge -y cockpit ;;
        dnf)     sudo dnf remove -y cockpit ;;
        yum)     sudo yum remove -y cockpit ;;
    esac
    if command_exists firewall-cmd; then
        sudo firewall-cmd --remove-service=cockpit --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
    fi
    success "Cockpit 已卸载。"
}

status_cockpit() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        echo -e "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    if ! command_exists cockpit-bridge 2>/dev/null && ! rpm -q cockpit >/dev/null 2>&1 && ! dpkg -s cockpit >/dev/null 2>&1; then
        echo -e "${RED}❌ 未安装${NC}"; return
    fi
    if systemctl is-active --quiet cockpit.socket 2>/dev/null || systemctl is-active --quiet cockpit 2>/dev/null; then
        echo -e "${GREEN}✅ 已安装并运行${NC}"
    else
        echo -e "${YELLOW}⚠️  已安装（socket 模式，访问时激活）${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Cockpit（Web 管理面板，仅 Linux，默认端口 9090）
  uninstall   卸载 Cockpit
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_cockpit ;;
        uninstall) uninstall_cockpit ;;
        status)    status_cockpit ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
