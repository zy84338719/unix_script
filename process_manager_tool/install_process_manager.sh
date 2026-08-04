#!/usr/bin/env bash
#
# install_process_manager.sh
#
# 安装进程管理工具到用户的 ~/.tools 目录，并配置环境变量
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

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
            warn "未识别的 Shell: $user_shell，使用默认配置"
            if [[ "$OS_TYPE" == "darwin" ]]; then
                SHELL_RC="$HOME/.bash_profile"
            else
                SHELL_RC="$HOME/.bashrc"
            fi
            user_shell="unknown"
            ;;
    esac
    USER_SHELL="$user_shell"
    info "检测到 Shell: $USER_SHELL，配置文件: $SHELL_RC"
}

# --- 创建工具目录 ---
create_tools_directory() {
    info "检查 ~/.tools 目录..."
    if [[ ! -d "$TOOLS_DIR" ]]; then
        mkdir -p "$TOOLS_DIR"
        success "已创建 $TOOLS_DIR"
    fi
    if [[ ! -d "$BIN_DIR" ]]; then
        mkdir -p "$BIN_DIR"
        success "已创建 $BIN_DIR"
    fi
}

# --- 复制脚本文件 ---
install_scripts() {
    info "安装进程管理工具脚本..."

    if [[ ! -f "$SCRIPT_DIR/process_manager.sh" ]]; then
        error "未找到 process_manager.sh 文件"
        return 1
    fi

    cp "$SCRIPT_DIR/process_manager.sh" "$BIN_DIR/$SCRIPT_NAME"
    chmod +x "$BIN_DIR/$SCRIPT_NAME"
    success "已安装 $SCRIPT_NAME 到 $BIN_DIR"

    if [[ -f "$SCRIPT_DIR/pm_wrapper.sh" ]]; then
        cp "$SCRIPT_DIR/pm_wrapper.sh" "$BIN_DIR/pm"
        chmod +x "$BIN_DIR/pm"
        success "已安装 pm 包装脚本到 $BIN_DIR"
    fi

    if [[ -f "$SCRIPT_DIR/process_manager_config.sh" ]]; then
        cp "$SCRIPT_DIR/process_manager_config.sh" "$BIN_DIR/$CONFIG_NAME.sh"
        success "已安装配置文件到 $BIN_DIR"
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
    info "配置环境变量..."

    if echo "$PATH" | grep -q "$BIN_DIR"; then
        info "PATH 中已包含 ~/.tools/bin"
        return 0
    fi

    local path_export='export PATH="$HOME/.tools/bin:$PATH"'
    local alias_pmc="alias pmc='source \$HOME/.tools/bin/$CONFIG_NAME.sh && quick_search'"

    case "$USER_SHELL" in
        fish)
            local fish_config_dir="$HOME/.config/fish"
            mkdir -p "$fish_config_dir"
            if ! grep -q "/.tools/bin" "$SHELL_RC" 2>/dev/null; then
                {
                    echo ""
                    echo "# 添加 ~/.tools/bin 到 PATH（由 unix_script process_manager 添加）"
                    echo "set -gx PATH \$HOME/.tools/bin \$PATH"
                } >> "$SHELL_RC"
                success "已更新 Fish 配置文件"
            fi
            ;;
        *)
            if ! grep -q "/.tools/bin" "$SHELL_RC" 2>/dev/null; then
                {
                    echo ""
                    echo "# 添加 ~/.tools/bin 到 PATH（由 unix_script process_manager 添加）"
                    # shellcheck disable=SC2016
                    echo 'export PATH="$HOME/.tools/bin:$PATH"'
                } >> "$SHELL_RC"
                success "已更新 $USER_SHELL 配置文件"
            fi
            ;;
    esac
}

# --- 验证安装 ---
verify_installation() {
    info "验证安装..."
    if [[ -f "$BIN_DIR/$SCRIPT_NAME" && -x "$BIN_DIR/$SCRIPT_NAME" ]]; then
        success "主脚本文件安装成功"
    else
        error "主脚本文件安装失败"
        return 1
    fi

    if [[ -f "$BIN_DIR/pm" && -x "$BIN_DIR/pm" ]]; then
        success "包装脚本安装成功"
    else
        info "包装脚本未安装（可选）"
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
        header "🎉 安装完成！"
        echo "================================================"
        success "进程管理工具已安装到: $BIN_DIR/$SCRIPT_NAME"
        echo
        info "使用方法："
        echo "  source $SHELL_RC          # 重新加载 Shell 配置"
        echo "  pm <搜索词>               # 搜索进程"
        echo "  pm                        # 交互式模式"
        echo "  process_manager <搜索词>  # 直接使用主脚本"
        echo "================================================"
        warn "请重新加载 Shell 配置或重启终端以使环境变量生效"
    else
        error "安装验证失败"
        return 1
    fi
}

# --- 卸载功能 ---
uninstall_pm() {
    detect_os
    detect_user_shell

    header "🗑️  卸载进程管理工具"
    echo

    warn "将删除以下内容:"
    echo "  • $BIN_DIR/$SCRIPT_NAME"
    echo "  • $BIN_DIR/pm"
    [[ -f "$BIN_DIR/$CONFIG_NAME.sh" ]] && echo "  • $BIN_DIR/$CONFIG_NAME.sh"
    [[ -f "$TOOLS_DIR/docs/process_manager_README.md" ]] && echo "  • 文档文件"
    echo "  • Shell 配置文件中的相关配置"
    echo

    if ! yes_no "确认卸载？"; then
        info "已取消卸载"
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
        sed -i.tmp '/# 添加.*\.tools\/bin.*unix_script process_manager/,/^$/d' "$SHELL_RC" 2>/dev/null || true
        rm -f "$SHELL_RC.tmp" 2>/dev/null || true
    fi

    success "卸载完成"
    info "Shell 配置文件已备份为: $SHELL_RC.backup.*"
    warn "请重启终端或重新加载 Shell 配置以使更改生效"
}

# --- 状态检查 ---
status_pm() {
    detect_os
    local installed=false
    if [[ -f "$BIN_DIR/$SCRIPT_NAME" && -x "$BIN_DIR/$SCRIPT_NAME" ]]; then
        installed=true
    fi

    if $installed; then
        if echo "$PATH" | grep -q "$BIN_DIR"; then
            echo -e "${GREEN}✅ 已安装并配置${NC}"
        else
            echo -e "${YELLOW}⚠️  已安装但 PATH 未配置${NC}"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装进程管理工具到 ~/.tools（默认动作）
  uninstall   卸载进程管理工具
  status      查看安装状态
  help        显示此帮助信息
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
