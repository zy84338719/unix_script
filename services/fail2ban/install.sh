#!/usr/bin/env bash
#
# fail2ban/install.sh
#
# 安装与配置 Fail2ban（仅 Linux）。macOS 不适用（依赖 iptables/systemd）。
#
# 功能：
#   - 通过 apt/yum/dnf 安装 fail2ban
#   - 写入一份保护 sshd 的默认 /etc/fail2ban/jail.local
#   - 启用并启动 systemd 服务
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

JAIL_LOCAL="/etc/fail2ban/jail.local"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "Fail2ban 仅支持 Linux（依赖 iptables/systemd）。当前系统：$OS_TYPE"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "需要 systemctl（systemd）。当前系统可能不支持。"
        exit 1
    fi
}

# 生成默认 jail.local 内容
gen_jail_local() {
    cat <<EOF
# 由 unix_script fail2ban 模块生成
# 参考：https://github.com/fail2ban/fail2ban

[DEFAULT]
# 封禁时长（秒）。1h = 3600，1d = 86400
bantime  = 3600
# 统计窗口（秒）
findtime = 600
# 窗口内失败次数达到即封禁
maxretry = 5
# 不封禁本机与内网（按需调整）
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

[sshd]
enabled = true
backend = systemd
EOF
}

install_fail2ban() {
    preflight
    require_sudo
    detect_pkg_manager
    info "🚀 开始安装 Fail2ban（包管理器：$PKG_MANAGER）"

    if command_exists fail2ban-client; then
        local cur
        cur=$(fail2ban-client --version 2>/dev/null | head -1 || echo "未知版本")
        warn "检测到已安装 Fail2ban（$cur）"
        if ! yes_no "是否继续并重新写入默认 jail.local？"; then
            info "已取消"
            return 0
        fi
    fi

    info "安装 fail2ban..."
    ensure_epel
    if ! pkg_install fail2ban; then
        error "fail2ban 安装失败（包管理器：$PKG_MANAGER）"
        exit 1
    fi

    if ! command_exists fail2ban-client; then
        error "安装失败：找不到 fail2ban-client"
        exit 1
    fi

    # 写入默认 jail.local（如已存在则备份）
    if [[ -f "$JAIL_LOCAL" ]]; then
        sudo cp -a "$JAIL_LOCAL" "$JAIL_LOCAL.bak.$(date +%s)"
        warn "已备份现有 $JAIL_LOCAL 为 .bak.*"
    fi
    info "写入默认 $JAIL_LOCAL（保护 sshd）..."
    gen_jail_local | sudo tee "$JAIL_LOCAL" >/dev/null

    info "启用并启动 fail2ban..."
    sudo systemctl enable --now fail2ban
    sudo systemctl restart fail2ban

    # 验证
    info "验证..."
    sleep 2
    if systemctl is-active --quiet fail2ban; then
        success "fail2ban 服务运行正常"
    else
        error "fail2ban 服务未正常运行，请检查日志："
        echo "  sudo systemctl status fail2ban"
        echo "  sudo journalctl -u fail2ban -f"
        return 1
    fi

    echo
    success "🎉 Fail2ban 安装完成！"
    info "查看封禁状态："
    echo "  sudo fail2ban-client status"
    echo "  sudo fail2ban-client status sshd"
    echo "  sudo tail -f /var/log/fail2ban.log"
    echo
    info "调整策略请编辑：$JAIL_LOCAL，然后："
    echo "  sudo systemctl restart fail2ban"
}

uninstall_fail2ban() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! yes_no "确认卸载 Fail2ban？"; then
        info "已取消"
        return 0
    fi

    sudo systemctl disable --now fail2ban 2>/dev/null || true
    pkg_remove fail2ban 2>/dev/null || warn "fail2ban 包移除失败，请手动卸载"

    if [[ -f "$JAIL_LOCAL" ]]; then
        if yes_no "是否删除 $JAIL_LOCAL（保留 .bak.* 备份）？"; then
            sudo rm -f "$JAIL_LOCAL"
            success "$JAIL_LOCAL 已删除。"
        fi
    fi
    success "Fail2ban 已卸载。"
}

status_fail2ban() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        echo -e "${YELLOW}⚠️  不适用（仅 Linux）${NC}"
        return
    fi
    if ! command_exists fail2ban-client; then
        echo -e "${RED}❌ 未安装${NC}"
        return
    fi
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        echo -e "${GREEN}✅ 已安装并运行${NC}"
    else
        echo -e "${YELLOW}⚠️  已安装但服务未运行${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Fail2ban 并写入保护 sshd 的默认配置
  uninstall   卸载 Fail2ban
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_fail2ban ;;
        uninstall) uninstall_fail2ban ;;
        status)    status_fail2ban ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
