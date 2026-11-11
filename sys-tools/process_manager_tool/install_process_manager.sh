#!/usr/bin/env bash
# 安装器（非交互菜单），与其它模块入口一致启用 set -euo pipefail。
# 交互菜单在 process_manager.sh（运行时工具）与 lib/submenus.sh 的 manage_process_manager_tool。
set -euo pipefail
#
# install_process_manager.sh
#
# 安装进程管理工具到用户的 ~/.tools 目录，并配置环境变量
#
# 子命令：install | uninstall | status | help
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# --- 全局变量 ---
TOOLS_DIR="$HOME/.tools"
BIN_DIR="$TOOLS_DIR/bin"
SCRIPT_NAME="process_manager"
CONFIG_NAME="process_manager_config"

# --- 检测用户 Shell 及 rc 文件 ---
detect_user_shell() {
    local user_shell
    user_shell=$(basename "${SHELL:-/bin/sh}")
    case "$user_shell" in
        bash)
            if [[ "$OS_TYPE" == "darwin" ]]; then
                SHELL_RC="$HOME/.bash_profile"
            else
                SHELL_RC="$HOME/.bashrc"
            fi
            ;;
        zsh)  SHELL_RC="$HOME/.zshrc" ;;
        fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)
            warn "$(_tf 'Unrecognized shell: %s, using the default configuration' "${user_shell}")"
            if [[ "$OS_TYPE" == "darwin" ]]; then
                SHELL_RC="$HOME/.bash_profile"
            else
                SHELL_RC="$HOME/.bashrc"
            fi
            user_shell="unknown"
            ;;
    esac
    USER_SHELL="$user_shell"
    info "$(_tf 'Detected shell: %s, configuration file: %s' "${USER_SHELL}" "$SHELL_RC")"
}

# --- 创建工具目录 ---
create_tools_directory() {
    info "$(_t 'Checking the ~/.tools directory...')"
    if [[ ! -d "$TOOLS_DIR" ]]; then
        mkdir -p "$TOOLS_DIR"
        success "$(_tf 'Created %s' "$TOOLS_DIR")"
    fi
    if [[ ! -d "$BIN_DIR" ]]; then
        mkdir -p "$BIN_DIR"
        success "$(_tf 'Created %s' "$BIN_DIR")"
    fi
}

# --- 复制脚本文件 ---
install_scripts() {
    info "$(_t 'Installing the process manager scripts...')"

    if [[ ! -f "$SCRIPT_DIR/process_manager.sh" ]]; then
        error "$(_t 'The process_manager.sh file was not found')"
        return 1
    fi

    # 装到 ~/.tools/bin 的脚本由用户的 shell 直接运行，运行时没有 unix_script 的 _t
    # ⇒ 译文在安装时用 uxs_i18n_localize_file 烘进目标文件
    uxs_i18n_localize_file "$SCRIPT_DIR/process_manager.sh" "$BIN_DIR/$SCRIPT_NAME"
    chmod +x "$BIN_DIR/$SCRIPT_NAME"
    success "$(_tf 'Installed %s to %s' "$SCRIPT_NAME" "$BIN_DIR")"

    if [[ -f "$SCRIPT_DIR/pm_wrapper.sh" ]]; then
        uxs_i18n_localize_file "$SCRIPT_DIR/pm_wrapper.sh" "$BIN_DIR/pm"
        chmod +x "$BIN_DIR/pm"
        success "$(_tf 'Installed the pm wrapper script to %s' "$BIN_DIR")"
    fi

    if [[ -f "$SCRIPT_DIR/process_manager_config.sh" ]]; then
        uxs_i18n_localize_file "$SCRIPT_DIR/process_manager_config.sh" "$BIN_DIR/$CONFIG_NAME.sh"
        success "$(_tf 'Installed the configuration file to %s' "$BIN_DIR")"
    fi

    if [[ -f "$SCRIPT_DIR/README.md" ]]; then
        mkdir -p "$TOOLS_DIR/docs"
        cp "$SCRIPT_DIR/README.md" "$TOOLS_DIR/docs/process_manager_README.md"
    fi

    if [[ -f "$SCRIPT_DIR/PROCESS_MANAGER_QUICKSTART.md" ]]; then
        mkdir -p "$TOOLS_DIR/docs"
        cp "$SCRIPT_DIR/PROCESS_MANAGER_QUICKSTART.md" "$TOOLS_DIR/docs/process_manager_quickstart.md"
    fi
}

# --- 配置环境变量 ---
setup_environment() {
    info "$(_t 'Configuring the environment variables...')"

    if echo "$PATH" | grep -q "$BIN_DIR"; then
        info "PATH $(_t 'already contains ~/.tools/bin')"
        return 0
    fi

    # shellcheck disable=SC2016  # 单引号有意为之：$HOME 在 source 时才展开
    local path_export='export PATH="$HOME/.tools/bin:$PATH"'
    local alias_pmc="alias pmc='source \$HOME/.tools/bin/$CONFIG_NAME.sh && quick_search'"

    case "$USER_SHELL" in
        fish)
            local fish_config_dir="$HOME/.config/fish"
            mkdir -p "$fish_config_dir"
            if ! grep -q "/.tools/bin" "$SHELL_RC" 2>/dev/null; then
                {
                    echo ""
                    echo "# $(_t 'Adding ~/.tools/bin to PATH (added by unix_script process_manager)')"
                    echo "set -gx PATH \$HOME/.tools/bin \$PATH"
                } >> "$SHELL_RC"
                success "$(_t 'Updated the Fish configuration file')"
            fi
            ;;
        *)
            if ! grep -q "/.tools/bin" "$SHELL_RC" 2>/dev/null; then
                {
                    echo ""
                    echo "# $(_t 'Adding ~/.tools/bin to PATH (added by unix_script process_manager)')"
                    # shellcheck disable=SC2016
                    echo 'export PATH="$HOME/.tools/bin:$PATH"'
                } >> "$SHELL_RC"
                success "$(_tf 'Updated the %s configuration file' "$USER_SHELL")"
            fi
            ;;
    esac
}

# --- 验证安装 ---
verify_installation() {
    info "$(_t 'Verifying the process manager installation...')"
    if [[ -f "$BIN_DIR/$SCRIPT_NAME" && -x "$BIN_DIR/$SCRIPT_NAME" ]]; then
        success "$(_t 'The main script file was installed successfully')"
    else
        error "$(_t 'The main script file failed to install')"
        return 1
    fi

    if [[ -f "$BIN_DIR/pm" && -x "$BIN_DIR/pm" ]]; then
        success "$(_t 'The wrapper script was installed successfully')"
    else
        info "$(_t 'The wrapper script is not installed (optional)')"
    fi
    return 0
}

# --- 安装主逻辑 ---
install_pm() {
    detect_os
    detect_user_shell
    echo

    create_tools_directory
    echo

    install_scripts
    echo

    setup_environment
    echo

    if verify_installation; then
        echo
        header "$(_t '🎉 Installation complete!')"
        echo "================================================"
        success "$(_tf 'The process manager has been installed to: %s/%s' "$BIN_DIR" "$SCRIPT_NAME")"
        echo
        info "$(_t 'How to use:')"
        echo "  source $SHELL_RC          # $(_t 'Reload the shell configuration')"
        echo "  pm <$(_t 'search term>               # search the processes')"
        echo "  pm                        # $(_t 'Interactive mode')"
        echo "  process_manager <$(_t 'search term>  # use the main script directly')"
        echo "================================================"
        warn "$(_t 'Please reload the shell configuration or restart the terminal for the environment variables to take effect')"
    else
        error "$(_t 'The installation verification failed')"
        return 1
    fi
}

# --- 卸载功能 ---
uninstall_pm() {
    detect_os
    detect_user_shell

    header "$(_t '🗑️  Uninstalling the process manager')"
    echo

    warn "$(_t 'The following will be removed:')"
    echo "  • $BIN_DIR/$SCRIPT_NAME"
    echo "  • $BIN_DIR/pm"
    [[ -f "$BIN_DIR/$CONFIG_NAME.sh" ]] && echo "  • $BIN_DIR/$CONFIG_NAME.sh"
    [[ -f "$TOOLS_DIR/docs/process_manager_README.md" ]] && echo "  $(_t '• The documentation files')"
    echo "  $(_t '• The related configuration in the shell configuration files')"
    echo

    if ! yes_no "$(_t 'Confirm the uninstall?')"; then
        info "$(_t 'The uninstall has been cancelled')"
        return 0
    fi

    # 删除文件
    rm -f "$BIN_DIR/$SCRIPT_NAME"
    rm -f "$BIN_DIR/pm"
    rm -f "$BIN_DIR/$CONFIG_NAME.sh"
    rm -f "$TOOLS_DIR/docs/process_manager_README.md"
    rm -f "$TOOLS_DIR/docs/process_manager_quickstart.md"

    # 删除全局链接
    if [[ -L "/usr/local/bin/pm" ]]; then
        sudo rm -f "/usr/local/bin/pm" 2>/dev/null || true
    fi

    # 删除用户级链接
    if [[ -L "$HOME/.local/bin/pm" ]]; then
        rm -f "$HOME/.local/bin/pm" 2>/dev/null || true
    fi

    # 清理 Shell 配置
    if [[ -f "$SHELL_RC" ]]; then
        cp "$SHELL_RC" "$SHELL_RC.backup.$(date +%Y%m%d_%H%M%S)"
        # 标记行是安装时写进 rc 的注释，会随安装语言变化 ⇒ 匹配模式必须与语言无关：
        # 标记里恒定含 "unix_script process_manager"，中英文都命中。
        sed -i.tmp '/unix_script process_manager/,/^$/d' "$SHELL_RC" 2>/dev/null || true
        rm -f "$SHELL_RC.tmp" 2>/dev/null || true
    fi

    success "$(_t 'Uninstall complete')"
    info "Shell $(_tf 'The configuration file has been backed up to: %s.backup.*' "$SHELL_RC")"
    warn "$(_t 'Please restart the terminal or reload the shell configuration for the changes to take effect')"
}

# --- 状态检查（契约：emit_status 双轨，供 status --json 复用）---
status_pm() {
    detect_os
    local installed=false state human
    # 主程序 + pm 包装器都存在才算已安装（与原 lib/status.sh 判定一致）
    if [[ -f "$BIN_DIR/process_manager" && -f "$BIN_DIR/pm" ]]; then
        installed=true
    fi
    if $installed; then
        state="installed"
        if echo "$PATH" | grep -q "$BIN_DIR"; then
            human="${GREEN}$(_t '✅ Installed and configured')${NC}"
        else
            human="${YELLOW}$(_t '⚠️  Installed but PATH is not configured')${NC}"
            emit_extra "path=not_configured"
        fi
    else
        state="not_installed"
        human="${RED}$(_t '❌ Not installed')${NC}"
    fi
    emit_status "$state" "$human"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install the process manager into ~/.tools (default action)')
  uninstall   $(_t 'Uninstall the process manager')
  status      $(_t 'View the installation status')
  help        $(_t 'Show this help information')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_pm ;;
        uninstall) uninstall_pm ;;
        status)    status_pm ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
