#!/usr/bin/env bash
#
# ufw/install.sh
#
# 安装与配置 UFW 防火墙（仅 Linux）。macOS 自带防火墙，跳过并提示。
#
# 功能：
#   - 通过 apt/yum/dnf 安装 ufw
#   - 配置默认策略：deny incoming / allow outgoing
#   - 放行 SSH（22 端口，防止锁定）
#   - 可选放行 HTTP（80）/ HTTPS（443）
#   - 启用防火墙
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "macOS 自带应用程序防火墙，UFW 不适用。"
        info "如需配置 macOS 防火墙：系统设置 > 网络 > 防火墙"
        exit 0
    fi
}

install_ufw() {
    preflight
    require_sudo
    detect_pkg_manager
    info "开始安装 UFW 防火墙（包管理器：${PKG_MANAGER}）"

    if command_exists ufw; then
        local cur
        cur=$(ufw version 2>/dev/null | head -1 || echo "未知版本")
        warn "检测到已安装 UFW（${cur}）"
        if ! yes_no "是否继续并重新配置默认规则？"; then
            info "已取消"
            return 0
        fi
    fi

    info "安装 ufw..."
    if ! pkg_install ufw; then
        error "ufw 安装失败（包管理器：${PKG_MANAGER}）"
        exit 1
    fi

    if ! command_exists ufw; then
        error "安装失败：找不到 ufw 命令"
        exit 1
    fi

    # 配置默认策略
    info "配置默认策略..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # 放行 SSH —— 关键步骤，防止锁定
    warn "【关键】放行 SSH（22 端口），防止启用防火墙后无法远程连接"
    sudo ufw allow ssh

    # 可选：放行 HTTP / HTTPS
    echo
    info "可选：放行常用 Web 端口"
    if yes_no "是否放行 HTTP（80）和 HTTPS（443）？"; then
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        info "已放行 80/tcp 和 443/tcp"
    else
        info "跳过 Web 端口放行（后续可手动添加：sudo ufw allow 80/tcp）"
    fi

    # 启用防火墙
    echo
    info "启用 UFW 防火墙..."
    sudo ufw --force enable

    success "UFW 防火墙已启用"
    echo
    info "当前规则："
    sudo ufw status verbose
    echo
    info "常用管理命令："
    echo "  sudo ufw status              # 查看状态"
    echo "  sudo ufw status verbose      # 详细状态（含规则）"
    echo "  sudo ufw allow <port>/tcp    # 放行端口"
    echo "  sudo ufw deny <port>/tcp     # 拒绝端口"
    echo "  sudo ufw delete allow <port> # 删除规则"
    echo "  sudo ufw reload              # 重新加载规则"
}

uninstall_ufw() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! yes_no "确认卸载 UFW 防火墙？卸载后防火墙规则将全部失效。"; then
        info "已取消"
        return 0
    fi

    info "禁用 UFW..."
    sudo ufw disable 2>/dev/null || true

    info "卸载 ufw 包..."
    pkg_remove ufw 2>/dev/null || warn "ufw 包移除失败，请手动卸载"

    success "UFW 防火墙已卸载并禁用。"
    warn "注意：卸载后系统将不再有防火墙保护，请确保有其他安全措施。"
}

status_ufw() {
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then
        emit_status "n/a" "${YELLOW}不适用（macOS 自带应用程序防火墙）${NC}"
        if ! uxs_is_machine_mode; then
            echo "配置路径：系统设置 > 网络 > 防火墙"
        fi
        return
    fi
    if ! command_exists ufw; then
        emit_status "not_installed" "${RED}未安装${NC}"
        return
    fi
    # 三级降级：sudo -n ufw status → systemctl is-active ufw → 兜底 installed。
    # 防 set -e/pipefail 中止：所有命令替换带 || true，任何路径必须落到一个 emit_status。
    local ufw_status sysd
    ufw_status=""
    if ufw_status=$(sudo -n ufw status 2>/dev/null | head -1 || true) && [[ -n "$ufw_status" ]]; then
        # 精确匹配 active（排除 inactive 子串误匹配——"Status: inactive" 含 "active"）
        if [[ "$ufw_status" == *"active"* && "$ufw_status" != *"inactive"* ]]; then
            emit_status "configured" "${GREEN}已安装并启用${NC}"
            if ! uxs_is_machine_mode; then
                echo
                sudo -n ufw status verbose 2>/dev/null || sudo ufw status verbose
            fi
        else
            emit_status "not_configured" "${YELLOW}已安装但未启用${NC}"
        fi
        return
    fi
    # sudo 不可用（无凭据/无 TTY）：降级 systemd 单元状态
    if command_exists systemctl && sysd=$(systemctl is-active ufw 2>/dev/null || true); then
        if [[ "$sysd" == "active" ]]; then
            emit_status "installed:running" "${GREEN}已安装且服务运行中（降级检测）${NC}"
        else
            emit_status "installed" "${YELLOW}已安装（sudo 不可用，降级检测）${NC}"
        fi
        return
    fi
    # systemctl 也没有：命令存在即视为已装
    emit_status "installed" "${YELLOW}已安装（无法读取详细状态）${NC}"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装并启用 UFW 防火墙（配置默认策略 + 放行 SSH）
  uninstall   禁用并卸载 UFW
  status      查看防火墙状态和规则
  help        显示帮助

⚠️  安全提示：启用防火墙前会自动放行 SSH（22 端口），防止远程连接被锁定。
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_ufw ;;
        uninstall) uninstall_ufw ;;
        status)    status_ufw ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
