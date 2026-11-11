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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" && "$OS_TYPE" != "darwin" ]]; then
        error "Deskflow $(_tf 'Only supports Linux / macOS. Current: %s' "$OS_TYPE")"
        exit 1
    fi
}

# ---------------- Linux 安装（Flatpak）----------------
install_deskflow_linux() {
    require_sudo
    detect_pkg_manager
    info "$(_t '🚀 Starting Deskflow installation (Flatpak)')"

    # 1. 安装 flatpak 与 curl
    info "==== 1. $(_t 'Install flatpak and curl ====')"
    if ! pkg_install flatpak curl; then
        error "flatpak/curl $(_tf 'Installation failed (package manager: %s)' "${PKG_MANAGER}")"
        exit 1
    fi

    # 2. 添加 Flathub 仓库
    info "==== 2. $(_t 'Add Flathub repository (skip if already present) ====')"
    if flatpak remotes 2>/dev/null | grep -q '^flathub'; then
        info "Flathub $(_t 'Already exists, skipping')"
    else
        if sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
            success "Flathub $(_t 'Added successfully')"
        else
            warn "$(_t 'Online add failed, trying offline add...')"
            curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/flathub.flatpakrepo
            sudo flatpak remote-add --if-not-exists flathub /tmp/flathub.flatpakrepo
        fi
    fi

    # 3. 安装 Deskflow
    info "==== 3. $(_t 'Install Deskflow ====')"
    sudo flatpak install -y flathub org.deskflow.deskflow

    # 4. 配置桌面集成（XDG_DATA_DIRS）
    info "==== 4. $(_t 'Configure desktop integration (XDG_DATA_DIRS) ====')"
    local profile="$HOME/.profile"
    # 该行需以字面量写入 .profile（$HOME/$XDG_DATA_DIRS 在用户登录时展开），故用单引号（SC2016 误报）
    # shellcheck disable=SC2016
    local line='export XDG_DATA_DIRS=/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:$XDG_DATA_DIRS'
    if grep -Fxq "$line" "$profile" 2>/dev/null; then
        info "$profile $(_t 'already contains XDG_DATA_DIRS configuration, skipping')"
    else
        echo "$line" >> "$profile"
        info "$(_tf 'Appended XDG_DATA_DIRS to %s' "$profile")"
    fi

    echo
    success "$(_t '🎉 Deskflow installation complete!')"
    info "$(_t 'Please run:')"
    echo "  source \$HOME/.profile"
    printf '%s\n' "$(_t 'Or after logging out or restarting the session, you can find Deskflow in the application menu, or run:')"
    echo "  flatpak run org.deskflow.deskflow"
    printf '%s\n' "$(_t 'Start Deskflow.')"
}

# ---------------- macOS 安装（Homebrew cask）----------------
install_deskflow_macos() {
    # 确保 brew 可用（brew 不需要 sudo）
    if ! os_has_cmd brew; then
        error "$(_t 'Homebrew not detected. Please install it first: ./install.sh brew  or see https://brew.sh')"
        exit 1
    fi
    info "$(_t '🚀 Starting Deskflow installation (Homebrew)')"

    # 1. 添加官方 tap（已存在则跳过）
    info "==== 1. $(_t 'Add deskflow/tap (skip if already present) ====')"
    if brew tap | grep -q '^deskflow/tap$'; then
        info "deskflow/tap $(_t 'Already exists, skipping')"
    else
        brew tap deskflow/tap
        success "deskflow/tap $(_t 'Added successfully')"
    fi

    # 2. 安装 cask
    info "==== 2. $(_t 'Install Deskflow cask ====')"
    brew install --cask deskflow

    # 3. 解除 quarantine（macOS 新版可能阻止未签名/非 App Store 应用启动）
    if [[ -d "/Applications/Deskflow.app" ]]; then
        info "==== 3. $(_t 'Remove the quarantine attribute (if any) ====')"
        # xattr 失败不影响安装成功，仅是启动兼容性
        if xattr -c "/Applications/Deskflow.app" 2>/dev/null; then
            success "$(_t 'quarantine attribute cleared')"
        else
            info "$(_t 'No quarantine attribute or already cleared')"
        fi
    fi

    echo
    success "$(_t '🎉 Deskflow installation complete!')"
    info "$(_t 'Find Deskflow in Applications, or run:')"
    echo "  open -a Deskflow"
    printf '%s\n' "$(_t 'Start Deskflow.')"
    warn "$(_t 'If macOS blocks the launch (unsigned app warning), go to System Settings → Privacy & Security and click Open Anyway.')"
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
            uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed (Flatpak)')${NC}"
        else
            uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        # 主检测：/Applications/Deskflow.app（最可靠）；辅助：brew list
        if [[ -d "/Applications/Deskflow.app" ]]; then
            uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed (Homebrew)')${NC}"
        elif os_has_cmd brew && brew list --cask deskflow >/dev/null 2>&1; then
            uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed (Homebrew)')${NC}"
        else
            uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
        fi
    else
        uxs_emit_status "n/a" "${YELLOW}$(_t '⚠️  Not applicable (Linux / macOS only)')${NC}"
    fi
}

# 卸载
uninstall_deskflow_linux() {
    require_sudo
    sudo flatpak uninstall -y org.deskflow.deskflow 2>/dev/null || warn "Deskflow $(_t 'may not be installed')"
    success "Deskflow $(_t 'Uninstalled.')"
}

uninstall_deskflow_macos() {
    if ! os_has_cmd brew; then
        error "$(_t 'Homebrew not detected, cannot uninstall. Please remove /Applications/Deskflow.app manually')"
        exit 1
    fi
    brew uninstall --cask deskflow 2>/dev/null || warn "Deskflow cask $(_t 'may not be installed')"
    # 残留 .app 也清理一下
    if [[ -d "/Applications/Deskflow.app" ]]; then
        rm -rf "/Applications/Deskflow.app" 2>/dev/null || true
    fi
    success "Deskflow $(_t 'Uninstalled.')"
}

uninstall_deskflow() {
    preflight
    if ! yes_no "$(_t 'Uninstall Deskflow?')"; then
        info "$(_t 'Cancelled')"
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

  install     $(_t 'Install Deskflow (Linux: Flatpak / macOS: Homebrew)')
  uninstall   $(_t 'Uninstall Deskflow')
  status      $(_t 'View installation status')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
