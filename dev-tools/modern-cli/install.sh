#!/usr/bin/env bash
#
# modern-cli/install.sh
#
# 安装现代 CLI 工具集，替代传统命令，大幅提升终端体验。
# Linux + macOS。
#
# 工具映射:
#   bat       → cat（带语法高亮 + 行号）
#   eza       → ls（彩色 + 图标 + git 集成）
#   ripgrep   → grep（超快递归搜索，rg 命令）
#   fd        → find（更友好的文件查找，fd 命令）
#   fzf       → 模糊查找（Ctrl+R 搜历史、Ctrl+T 搜文件）
#   zoxide    → cd（智能跳转，z 命令，记录常用目录）
#   starship  → 跨 shell 提示符（显示 git/语言/时间）
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 工具列表（包名，部分发行版名字不同）
TOOLS=(bat eza ripgrep fd-find fzf zoxide starship)

# 包名映射（某些发行版名字不同）
pkg_name_for() {
    local tool="$1"
    case "$tool" in
        fd-find)
            # Debian/Ubuntu 叫 fd-find（命令 fd），其他叫 fd
            case "$PKG_MANAGER" in
                apt-get) echo "fd-find" ;;
                *)       echo "fd" ;;
            esac
            ;;
        eza)
            # eza 较新，某些发行版可能不在仓库
            echo "eza"
            ;;
        *) echo "$tool" ;;
    esac
}

preflight() {
    detect_os
    check_commands curl
}

install_modern_cli() {
    preflight
    info "⚡ 安装现代 CLI 工具集（bat/eza/rg/fd/fzf/zoxide/starship）"

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! command_exists brew; then
            error "macOS 需要 Homebrew"
            exit 1
        fi
        info "通过 Homebrew 安装..."
        # macOS 的包名：fd-find → fd
        brew install bat eza ripgrep fd fzf zoxide starship
    else
        detect_pkg_manager
        info "通过 $PKG_MANAGER 安装..."
        for tool in "${TOOLS[@]}"; do
            local pkg
            pkg=$(pkg_name_for "$tool")
            if pkg_install "$pkg" >/dev/null 2>&1; then
                success "  ✅ $pkg"
            else
                # eza/starship 较新，可能需额外方式
                if [[ "$tool" == "starship" ]] && ! command_exists starship; then
                    info "  starship 通过官方脚本安装..."
                    if curl -fsSL https://starship.rs/install.sh | bash -s -- -y >/dev/null 2>&1; then
                        success "  ✅ starship (脚本)"
                    else
                        warn "  ⚠️ starship 安装失败"
                    fi
                elif [[ "$tool" == "eza" ]] && ! command_exists eza; then
                    warn "  ⚠️ $pkg 不在仓库（可从 https://github.com/eza-community/eza 手动装）"
                else
                    warn "  ⚠️ $pkg 安装失败"
                fi
            fi
        done
        # Debian 的 fd-find 命令是 fdfind，建别名
        if command_exists fdfind && ! command_exists fd; then
            local sudo_prefix=""
            [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
            $sudo_prefix ln -sf "$(command -v fdfind)" /usr/local/bin/fd 2>/dev/null || true
        fi
    fi

    # 配置 shell 集成（fzf + zoxide + starship + 别名）
    configure_shell_integration

    echo
    success "🎉 现代 CLI 工具集安装完成！"
    info "重新加载 shell 后生效：source ~/.bashrc（或 ~/.zshrc）"
    echo
    info "常用命令："
    echo "  bat file.py          # 替代 cat（语法高亮）"
    echo "  eza -la --icons      # 替代 ls（彩色+图标+git）"
    echo "  rg 'pattern'         # 替代 grep（超快）"
    echo "  fd '\.py$'           # 替代 find"
    echo "  Ctrl+R               # fzf 搜历史命令"
    echo "  z project            # zoxide 跳转目录"
}

configure_shell_integration() {
    info "配置 shell 集成（别名 + fzf + zoxide + starship）..."
    local rc mark="# >>> unix_script modern-cli >>>"
    local endmark="# <<< unix_script modern-cli <<<"

    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if grep -q "$mark" "$rc" 2>/dev/null; then
            continue  # 已配置
        fi
        {
            echo ""
            echo "$mark"
            echo "# 现代 CLI 工具别名"
            echo "alias cat='bat --paging=never 2>/dev/null || cat'"
            echo "alias ls='eza --group-directories-first 2>/dev/null || ls'"
            echo "alias ll='eza -la --group-directories-first --icons 2>/dev/null || ls -la'"
            echo "alias la='eza -a --group-directories-first --icons 2>/dev/null || ls -a'"
            echo "# fzf 集成"
            echo "[ -f /usr/share/fzf/key-bindings.bash ] && source /usr/share/fzf/key-bindings.bash 2>/dev/null"
            echo "[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash 2>/dev/null"
            echo "[ -f /opt/homebrew/opt/fzf/shell/key-bindings.zsh ] && source /opt/homebrew/opt/fzf/shell/key-bindings.zsh 2>/dev/null"
            echo "[ -f \$HOME/.fzf.zsh ] && source \$HOME/.fzf.zsh 2>/dev/null"
            echo "# zoxide"
            echo "command -v zoxide >/dev/null 2>&1 && eval \"\$(zoxide init \$(basename \$SHELL))\""
            echo "# starship 提示符"
            echo "command -v starship >/dev/null 2>&1 && eval \"\$(starship init \$(basename \$SHELL))\""
            echo "$endmark"
        } >> "$rc"
        info "已为 $(basename "$rc") 添加现代 CLI 集成"
    done

    # starship 默认配置（若不存在）
    if command_exists starship && [[ ! -f "$HOME/.config/starship.toml" ]]; then
        mkdir -p "$HOME/.config"
        cat > "$HOME/.config/starship.toml" <<'STARSHIPEOF'
# unix_script starship 默认配置
add_newline = true
format = "$directory$git_branch$git_status$python$nodejs$rust$golang$cmd_duration\n$character"

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"

[cmd_duration]
min_time = 2000
format = " ⏱ $duration"

[directory]
truncation_length = 3
truncate_to_repo = true
STARSHIPEOF
        info "已生成 starship 默认配置 ~/.config/starship.toml"
    fi
}

uninstall_modern_cli() {
    detect_os
    warn "modern-cli 卸载说明："
    echo "  工具:    brew uninstall bat eza ripgrep fd fzf zoxide starship"
    echo "           或 sudo <pkgmgr> remove bat eza ripgrep fd fzf zoxide"
    echo "  shell:   删除 rc 文件中 '# >>> unix_script modern-cli >>>' 之间的行"
    echo "  配置:    rm ~/.config/starship.toml"
    info "（按需手动清理）"
}

status_modern_cli() {
    detect_os
    local found=0 total=${#TOOLS[@]}
    for t in bat eza rg fd fzf zoxide starship; do
        command_exists "$t" && found=$((found + 1))
    done
    if [[ $found -ge $total ]]; then
        echo -e "${GREEN}✅ 全部已安装（$found/$total）${NC}"
    elif [[ $found -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  部分已安装（$found/$total）${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装现代 CLI 工具集（bat/eza/rg/fd/fzf/zoxide/starship）
  uninstall   显示卸载说明
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_modern_cli ;;
        uninstall) uninstall_modern_cli ;;
        status)    status_modern_cli ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
