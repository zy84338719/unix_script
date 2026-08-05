#!/usr/bin/env bash
#
# deskflow/install.sh
#
# 一键安装 Deskflow（键盘鼠标共享） via Flatpak。
# 仅适用于 Linux 图形环境（Ubuntu/Debian 系，需 Flatpak）。
#
# 子命令：install | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "Deskflow (Flatpak) 仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
}

install_deskflow() {
    preflight
    require_sudo
    detect_pkg_manager
    info "🚀 开始安装 Deskflow（Flatpak）"

    # 1. 安装 flatpak 与 curl
    info "==== 1. 安装 flatpak 与 curl ===="
    if ! pkg_install flatpak curl; then
        error "flatpak/curl 安装失败（包管理器：$PKG_MANAGER）"
        exit 1
    fi

    # 2. 添加 Flathub 仓库
    info "==== 2. 添加 Flathub 仓库（如已存在则跳过） ===="
    if flatpak remotes 2>/dev/null | grep -q '^flathub'; then
        info "Flathub 已存在，跳过"
    else
        if sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
            success "Flathub 添加成功"
        else
            warn "在线添加失败，尝试离线添加…"
            curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/flathub.flatpakrepo
            sudo flatpak remote-add --if-not-exists flathub /tmp/flathub.flatpakrepo
        fi
    fi

    # 3. 安装 Deskflow
    info "==== 3. 安装 Deskflow ===="
    sudo flatpak install -y flathub org.deskflow.deskflow

    # 4. 配置桌面集成（XDG_DATA_DIRS）
    info "==== 4. 配置桌面集成（XDG_DATA_DIRS） ===="
    local profile="$HOME/.profile"
    # 该行需以字面量写入 .profile（$HOME/$XDG_DATA_DIRS 在用户登录时展开），故用单引号（SC2016 误报）
    # shellcheck disable=SC2016
    local line='export XDG_DATA_DIRS=/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:$XDG_DATA_DIRS'
    if grep -Fxq "$line" "$profile" 2>/dev/null; then
        info "$profile 中已包含 XDG_DATA_DIRS 配置，跳过"
    else
        echo "$line" >> "$profile"
        info "已追加 XDG_DATA_DIRS 到 $profile"
    fi

    echo
    success "🎉 Deskflow 安装完成！"
    info "请执行："
    echo "  source \$HOME/.profile"
    echo "或注销/重启会话后，即可在应用菜单中找到 Deskflow，或通过："
    echo "  flatpak run org.deskflow.deskflow"
    echo "启动 Deskflow。"
}

status_deskflow() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        echo -e "${YELLOW}⚠️  不适用（仅 Linux）${NC}"
        return
    fi
    if command -v flatpak >/dev/null 2>&1 && flatpak list 2>/dev/null | grep -q org.deskflow.deskflow; then
        echo -e "${GREEN}✅ 已安装（Flatpak）${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 卸载
uninstall_deskflow() {
    preflight
    require_sudo
    if ! yes_no "确认卸载 Deskflow？"; then
        info "已取消"
        return 0
    fi
    sudo flatpak uninstall -y org.deskflow.deskflow 2>/dev/null || warn "Deskflow 可能未安装"
    success "Deskflow 已卸载。"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Deskflow（Flatpak，仅 Linux 图形环境）
  uninstall   卸载 Deskflow
  status      查看安装状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_deskflow ;;
        uninstall) uninstall_deskflow ;;
        status)    status_deskflow ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
