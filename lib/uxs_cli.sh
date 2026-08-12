#!/usr/bin/env bash
#
# lib/uxs_cli.sh
#
# 全局命令 uxs 的安装与卸载。
# 将仓库的 install.sh 包装成 ~/.tools/bin/uxs，配置 PATH。
#

# 幂等保护
if [[ -n "${_UXS_CLI_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_UXS_CLI_LOADED=1

UXS_CMD_NAME="uxs"
UXS_TOOLS_BIN="$HOME/.tools/bin"

# 检测当前用户的 shell 及对应 rc 文件，设置 UXS_SHELL_RC / UXS_USER_SHELL。
detect_shell_rc() {
    UXS_USER_SHELL="$(basename "${SHELL:-/bin/sh}")"
    case "$UXS_USER_SHELL" in
        bash)
            if [[ "$OS_TYPE" == "darwin" ]]; then
                UXS_SHELL_RC="$HOME/.bash_profile"
            else
                UXS_SHELL_RC="$HOME/.bashrc"
            fi
            ;;
        zsh)  UXS_SHELL_RC="$HOME/.zshrc" ;;
        fish) UXS_SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)    UXS_SHELL_RC="$HOME/.profile" ;;
    esac
}

# 安装 uxs 命令：创建 wrapper + 配置 PATH
install_cli() {
    detect_os
    detect_shell_rc

    header "🔧 安装全局命令：uxs"
    echo "───────────────────────────────"

    # 1) 创建 ~/.tools/bin 目录
    if [[ ! -d "$UXS_TOOLS_BIN" ]]; then
        info "创建目录：$UXS_TOOLS_BIN"
        mkdir -p "$UXS_TOOLS_BIN" || { error "无法创建 $UXS_TOOLS_BIN"; return 1; }
    fi

    # 2) 创建 wrapper 脚本（指向本仓库 install.sh，透传所有参数）
    local repo_install="$SCRIPT_DIR/install.sh"
    if [[ ! -f "$repo_install" ]]; then
        error "未找到 install.sh：$repo_install"
        return 1
    fi
    local wrapper="$UXS_TOOLS_BIN/$UXS_CMD_NAME"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
# 由 unix_script install.sh cli 生成 —— 全局命令 uxs
# 透传所有参数给仓库的 install.sh
exec bash "$repo_install" "\$@"
EOF
    chmod +x "$wrapper"
    success "已创建命令：$wrapper → $repo_install"

    # 3) 配置 PATH（若已包含则跳过）
    if echo "$PATH" | grep -q "$UXS_TOOLS_BIN"; then
        info "PATH 中已包含 $UXS_TOOLS_BIN"
    else
        info "配置 PATH（写入 $UXS_USER_SHELL 的 ${UXS_SHELL_RC}）..."
        if ! grep -q "/.tools/bin" "$UXS_SHELL_RC" 2>/dev/null; then
            if [[ -f "$UXS_SHELL_RC" ]]; then
                cp "$UXS_SHELL_RC" "${UXS_SHELL_RC}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            fi
            if [[ "$UXS_USER_SHELL" == "fish" ]]; then
                {
                    echo ""
                    echo "# 添加 ~/.tools/bin 到 PATH（由 unix_script cli 添加）"
                    echo "set -gx PATH \$HOME/.tools/bin \$PATH"
                } >> "$UXS_SHELL_RC"
            else
                {
                    echo ""
                    echo "# 添加 ~/.tools/bin 到 PATH（由 unix_script cli 添加）"
                    # shellcheck disable=SC2016
                    echo 'export PATH="$HOME/.tools/bin:$PATH"'
                } >> "$UXS_SHELL_RC"
            fi
            success "已更新 $UXS_SHELL_RC"
        else
            info "$UXS_SHELL_RC 已含 ~/.tools/bin 配置（跳过）"
        fi
    fi

    echo
    header "✅ 安装完成"
    echo "  命令：uxs"
    echo "  位置：$wrapper"
    echo
    if echo "$PATH" | grep -q "$UXS_TOOLS_BIN"; then
        info "当前 shell 已可直接使用，试运行：uxs --version"
    else
        warn "PATH 尚未在当前 shell 生效，请执行以下任一操作："
        echo "    source $UXS_SHELL_RC      # 当前终端立即生效"
        echo "    # 或重新打开终端"
    fi
    echo
    info "用法示例：uxs docker-image  |  uxs --status  |  uxs check-update  |  uxs update"
}

# 卸载 uxs 命令：删除 wrapper，并清理 PATH 配置（可选）
uninstall_cli() {
    detect_os
    detect_shell_rc

    header "🗑️  卸载全局命令：uxs"
    echo "───────────────────────────────"

    local wrapper="$UXS_TOOLS_BIN/$UXS_CMD_NAME"
    local removed=false

    # 1) 删除 wrapper
    if [[ -f "$wrapper" ]]; then
        rm -f "$wrapper" && success "已删除：$wrapper" && removed=true
    else
        info "未找到 ${wrapper}（可能未安装）"
    fi

    # 2) 询问是否清理 PATH 配置
    if [[ -f "$UXS_SHELL_RC" ]] && grep -q "/.tools/bin" "$UXS_SHELL_RC" 2>/dev/null; then
        echo
        warn "$UXS_SHELL_RC 中含 ~/.tools/bin 的 PATH 配置。"
        warn "（注意：process_manager 等其它工具可能也在用该目录，清理需谨慎）"
        if yes_no "是否从 $UXS_SHELL_RC 移除 ~/.tools/bin 的 PATH 配置？"; then
            cp "$UXS_SHELL_RC" "${UXS_SHELL_RC}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            sed -i.tmp '/# 添加 .*\.tools\/bin 到 PATH（由 unix_script cli 添加）/,/^$/d' "$UXS_SHELL_RC" 2>/dev/null || true
            rm -f "${UXS_SHELL_RC}.tmp" 2>/dev/null || true
            success "已从 $UXS_SHELL_RC 移除本工具添加的 PATH 配置"
        else
            info "保留 PATH 配置（~/.tools/bin 仍可用）"
        fi
    fi

    echo
    if $removed; then
        success "uxs 命令已卸载"
    else
        warn "无需清理的内容"
    fi
}

# ---------------- Tab 补全安装 ----------------
install_completions() {
    detect_os
    detect_shell_rc

    header "🔧 安装 Tab 补全"
    echo "───────────────────────────────"

    local comp_dir="$SCRIPT_DIR/completions"
    local installed=false

    # Bash 补全
    if [[ "$UXS_USER_SHELL" == "bash" ]]; then
        local bash_comp="$comp_dir/uxs.bash"
        if [[ ! -f "$bash_comp" ]]; then
            error "未找到 $bash_comp"
            return 1
        fi
        local source_line="source \"$bash_comp\""
        if grep -qF "$bash_comp" "$UXS_SHELL_RC" 2>/dev/null; then
            info "Bash 补全已在 $UXS_SHELL_RC 中配置"
        else
            {
                echo ""
                echo "# unix_script Tab 补全（由 install.sh completions 添加）"
                echo "$source_line"
            } >> "$UXS_SHELL_RC"
            success "已添加 Bash 补全到 $UXS_SHELL_RC"
            installed=true
        fi
    # Zsh 补全
    elif [[ "$UXS_USER_SHELL" == "zsh" ]]; then
        local zsh_comp="$comp_dir/uxs.zsh"
        if [[ ! -f "$zsh_comp" ]]; then
            error "未找到 $zsh_comp"
            return 1
        fi
        local source_line="source \"$zsh_comp\""
        if grep -qF "$zsh_comp" "$UXS_SHELL_RC" 2>/dev/null; then
            info "Zsh 补全已在 $UXS_SHELL_RC 中配置"
        else
            {
                echo ""
                echo "# unix_script Tab 补全（由 install.sh completions 添加）"
                echo "$source_line"
            } >> "$UXS_SHELL_RC"
            success "已添加 Zsh 补全到 $UXS_SHELL_RC"
            installed=true
        fi
    else
        warn "当前 shell ($UXS_USER_SHELL) 暂不支持自动安装补全"
        info "请手动 source 对应补全文件："
        echo "  bash: source $comp_dir/uxs.bash"
        echo "  zsh:  source $comp_dir/uxs.zsh"
        return 0
    fi

    echo
    if $installed; then
        header "✅ 补全安装完成"
        info "请执行以下操作使补全生效："
        echo "    source $UXS_SHELL_RC      # 当前终端立即生效"
        echo "    # 或重新打开终端"
    else
        success "补全已安装，无需重复配置"
    fi
    echo
    info "补全范围：模块名 + 子命令（如 uxs doc<Tab> → uxs docker）"
}
