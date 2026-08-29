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
#   tealdeer  → tldr（命令例子速查，替代啃 man）
#   direnv    → 目录级环境变量（进目录自动加载 .envrc）
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 工具列表（包名，部分发行版名字不同）
TOOLS=(bat eza ripgrep fd-find fzf zoxide starship tealdeer direnv)

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

# tealdeer 官方预编译二进制回退（musl 静态链接，glibc/musl 通用）。
# 信任模型：GitHub 官方 release（HTTPS），github_latest_tag 解析版本以增强可审计性；
# 资产名以 release 页实际清单为准：tealdeer-linux-<arch>-musl.tar.gz
install_tealdeer_from_release() {
    local ver arch url tmp
    ver=$(github_latest_tag "tealdeer-rs/tealdeer" 2>/dev/null) || return 1
    case "$(uname -m)" in
        x86_64)        arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) warn "tealdeer: 架构 $(uname -m) 无预编译包"; return 1 ;;
    esac
    url="https://github.com/tealdeer-rs/tealdeer/releases/download/${ver}/tealdeer-linux-${arch}-musl.tar.gz"
    tmp=$(mktemp -d)
    if curl -fsSL "$url" | tar -xz -C "$tmp" 2>/dev/null && [[ -f "$tmp/tealdeer" ]]; then
        local sudo_prefix=""
        [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
        $sudo_prefix install -m 755 "$tmp/tealdeer" /usr/local/bin/tldr
    else
        return 1
    fi
}

preflight() {
    detect_os
    check_commands curl
}

install_modern_cli() {
    preflight
    info "⚡ 安装现代 CLI 工具集（bat/eza/rg/fd/fzf/zoxide/starship/tldr/direnv）"

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! command_exists brew; then
            error "macOS 需要 Homebrew"
            exit 1
        fi
        info "通过 Homebrew 安装..."
        # macOS 的包名：fd-find → fd
        brew install bat eza ripgrep fd fzf zoxide starship tealdeer direnv
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
                    # 信任模型：starship.rs/install.sh 是官方安装器（HTTPS 传输），
                    # 它从 GitHub release 拉取二进制。此处解析并展示目标版本以增强可审计性；
                    # 若需端到端校验，可用 common.sh 的 github_release_asset_url + verify_sha256
                    # 直接下载带 .sha256 的 release 资产并校验（资产命名随版本变化，需按需适配）。
                    local starship_ver
                    starship_ver=$(github_latest_tag "starship/starship" 2>/dev/null || echo "latest")
                    info "  starship 通过官方脚本安装（目标版本：${starship_ver}）..."
                    if curl -fsSL https://starship.rs/install.sh | bash -s -- -y >/dev/null 2>&1; then
                        success "  ✅ starship (脚本, ${starship_ver})"
                    else
                        warn "  ⚠️ starship 安装失败"
                    fi
                elif [[ "$tool" == "eza" ]] && ! command_exists eza; then
                    warn "  ⚠️ $pkg 不在仓库（可从 https://github.com/eza-community/eza 手动装）"
                elif [[ "$tool" == "tealdeer" ]] && ! command_exists tldr; then
                    if install_tealdeer_from_release; then
                        success "  ✅ tealdeer (官方二进制)"
                    else
                        warn "  ⚠️ tealdeer 安装失败（可 cargo install tealdeer）"
                    fi                else
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

    # tealdeer 缓存（首次使用前必须更新）
    if command_exists tldr; then
        if tldr --update >/dev/null 2>&1; then
            info "tealdeer 缓存已更新"
        else
            warn "tealdeer 缓存更新失败（可稍后 tldr --update）"
        fi
    fi

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

    # extras 块：tldr/direnv（新增于 v1.15.0，独立标记块保证老 rc 也能补上）
    local emark="# >>> unix_script modern-cli extras >>>"
    local eendmark="# <<< unix_script modern-cli extras <<<"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if grep -q "$emark" "$rc" 2>/dev/null; then
            continue  # 已配置
        fi
        {
            echo ""
            echo "$emark"
            echo "# direnv（进目录自动加载 .envrc）"
            echo "command -v direnv >/dev/null 2>&1 && eval \"\$(direnv hook \$(basename \$SHELL))\""
            echo "$eendmark"
        } >> "$rc"
        info "已为 $(basename "$rc") 添加 direnv 集成"
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
    echo "  工具:    brew uninstall bat eza ripgrep fd fzf zoxide starship tealdeer direnv"
    echo "           或 sudo <pkgmgr> remove bat eza ripgrep fd fzf zoxide tealdeer direnv"
    echo "  shell:   删除 rc 文件中 '# >>> unix_script modern-cli >>>' 与"
    echo "           '# >>> unix_script modern-cli extras >>>' 标记块之间的行"
    echo "  缓存:    rm -rf ~/.cache/tealdeer"
    echo "  配置:    rm ~/.config/starship.toml"
    info "（按需手动清理）"
}

status_modern_cli() {
    detect_os
    local found=0 total=${#TOOLS[@]}
    local missing=() t
    for t in bat eza rg fd fzf zoxide starship tldr direnv; do
        if command_exists "$t"; then
            found=$((found + 1))
        else
            missing+=("$t")
        fi
    done
    if [[ $found -ge $total ]]; then
        emit_status "installed" "${GREEN}✅ 全部已安装（$found/${total}）${NC}"
    elif [[ $found -gt 0 ]]; then
        emit_status "installed" "${YELLOW}⚠️  部分已安装（$found/${total}）${NC}"
        emit_extra "installed=$found/$total"
        local missing_csv
        missing_csv=$(IFS=,; echo "${missing[*]}")
        emit_extra "missing=$missing_csv"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装现代 CLI 工具集（bat/eza/rg/fd/fzf/zoxide/starship/tldr/direnv）
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
