#!/usr/bin/env bash
#
# deskflow/install.sh
#
# 一键安装 Deskflow（键盘鼠标共享）。
# - Linux：via Flatpak（Ubuntu/Debian 系，需 Flatpak）
# - macOS：via Homebrew（deskflow/tap cask，装到 /Applications/Deskflow.app）
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" && "$OS_TYPE" != "darwin" ]]; then
        error "Deskflow 仅支持 Linux / macOS。当前：$OS_TYPE"
        exit 1
    fi
}

# ---------------- Linux 安装（Flatpak）----------------
install_deskflow_linux() {
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

# ---------------- macOS 安装（Homebrew cask）----------------
install_deskflow_macos() {
    # 确保 brew 可用（brew 不需要 sudo）
    if ! command_exists brew; then
        error "未检测到 Homebrew。请先安装：./install.sh brew  或参考 https://brew.sh"
        exit 1
    fi
    info "🚀 开始安装 Deskflow（Homebrew）"

    # 1. 添加官方 tap（已存在则跳过）
    info "==== 1. 添加 deskflow/tap（如已存在则跳过） ===="
    if brew tap | grep -q '^deskflow/tap$'; then
        info "deskflow/tap 已存在，跳过"
    else
        brew tap deskflow/tap
        success "deskflow/tap 添加成功"
    fi

    # 2. 安装 cask
    info "==== 2. 安装 Deskflow cask ===="
    brew install --cask deskflow

    # 3. 解除 quarantine（macOS 新版可能阻止未签名/非 App Store 应用启动）
    if [[ -d "/Applications/Deskflow.app" ]]; then
        info "==== 3. 解除 quarantine 属性（如有） ===="
        # xattr 失败不影响安装成功，仅是启动兼容性
        if xattr -c "/Applications/Deskflow.app" 2>/dev/null; then
            success "已清除 quarantine 属性"
        else
            info "无 quarantine 属性或已清除"
        fi
    fi

    echo
    success "🎉 Deskflow 安装完成！"
    info "在「应用程序」中找到 Deskflow，或通过："
    echo "  open -a Deskflow"
    echo "启动 Deskflow。"
    warn "若启动被 macOS 阻止（未签名提示），到「系统设置 → 隐私与安全性」点击「仍要打开」。"
}

install_deskflow() {
    preflight
    if [[ "$OS_TYPE" == "linux" ]]; then
        install_deskflow_linux
    else
        install_deskflow_macos
    fi
}

status_deskflow() {
    detect_os
    if [[ "$OS_TYPE" == "linux" ]]; then
        if command -v flatpak >/dev/null 2>&1 && flatpak list 2>/dev/null | grep -q org.deskflow.deskflow; then
            emit_status "installed" "${GREEN}✅ 已安装（Flatpak）${NC}"
        else
            emit_status "not_installed" "${RED}❌ 未安装${NC}"
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        # 主检测：/Applications/Deskflow.app（最可靠）；辅助：brew list
        if [[ -d "/Applications/Deskflow.app" ]]; then
            emit_status "installed" "${GREEN}✅ 已安装（Homebrew）${NC}"
        elif command_exists brew && brew list --cask deskflow >/dev/null 2>&1; then
            emit_status "installed" "${GREEN}✅ 已安装（Homebrew）${NC}"
        else
            emit_status "not_installed" "${RED}❌ 未安装${NC}"
        fi
    else
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux / macOS）${NC}"
    fi
}

# 卸载
uninstall_deskflow_linux() {
    require_sudo
    sudo flatpak uninstall -y org.deskflow.deskflow 2>/dev/null || warn "Deskflow 可能未安装"
    success "Deskflow 已卸载。"
}

uninstall_deskflow_macos() {
    if ! command_exists brew; then
        error "未检测到 Homebrew，无法卸载。请手动删除 /Applications/Deskflow.app"
        exit 1
    fi
    brew uninstall --cask deskflow 2>/dev/null || warn "Deskflow cask 可能未安装"
    # 残留 .app 也清理一下
    [[ -d "/Applications/Deskflow.app" ]] && rm -rf "/Applications/Deskflow.app" 2>/dev/null || true
    success "Deskflow 已卸载。"
}

uninstall_deskflow() {
    preflight
    if ! yes_no "确认卸载 Deskflow？"; then
        info "已取消"
        return 0
    fi
    if [[ "$OS_TYPE" == "linux" ]]; then
        uninstall_deskflow_linux
    else
        uninstall_deskflow_macos
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Deskflow（Linux: Flatpak / macOS: Homebrew）
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
