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
# 信任模型：GitHub 官方 release（HTTPS），http_github_latest_tag 解析版本以增强可审计性；
# 资产名以 release 页实际清单为准：tealdeer-linux-<arch>-musl.tar.gz
install_tealdeer_from_release() {
    local ver arch url tmp
    ver=$(http_github_latest_tag "tealdeer-rs/tealdeer" 2>/dev/null) || return 1
    arch=$(uname -m)
    case "$arch" in
        x86_64)        arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) warn "tealdeer: $(_tf 'Architecture %s has no prebuilt package' "$arch")"; return 1 ;;
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
    info "$(_t '⚡ Install the modern CLI toolset (bat/eza/rg/fd/fzf/zoxide/starship/tldr/direnv)')"

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if ! os_has_cmd brew; then
            error "macOS $(_t 'Homebrew is required')"
            exit 1
        fi
        info "$(_t 'Installing via Homebrew...')"
        # macOS 的包名：fd-find → fd
        brew install bat eza ripgrep fd fzf zoxide starship tealdeer direnv
    else
        detect_pkg_manager
        info "$(_tf 'Installing via %s...' "$PKG_MANAGER")"
        for tool in "${TOOLS[@]}"; do
            local pkg
            pkg=$(pkg_name_for "$tool")
            if pkg_install "$pkg" >/dev/null 2>&1; then
                success "  ✅ $pkg"
            else
                # eza/starship 较新，可能需额外方式
                if [[ "$tool" == "starship" ]] && ! os_has_cmd starship; then
                    # 信任模型：starship.rs/install.sh 是官方安装器（HTTPS 传输），
                    # 它从 GitHub release 拉取二进制。此处解析并展示目标版本以增强可审计性；
                    # 若需端到端校验，可用 common.sh 的 http_github_release_asset + net_verify
                    # 直接下载带 .sha256 的 release 资产并校验（资产命名随版本变化，需按需适配）。
                    local starship_ver
                    starship_ver=$(http_github_latest_tag "starship/starship" 2>/dev/null || echo "latest")
                    info "  starship $(_tf 'Installing via the official script (target version: %s)...' "${starship_ver}")"
                    if curl -fsSL https://starship.rs/install.sh | bash -s -- -y >/dev/null 2>&1; then
                        success "  $(_tf '✅ starship (script, %s)' "${starship_ver}")"
                    else
                        warn "  $(_t '⚠️ starship installation failed')"
                    fi
                elif [[ "$tool" == "eza" ]] && ! os_has_cmd eza; then
                    warn "  $(_tf '⚠️ %s is not available in the repository (install it manually from https://github.com/eza-community/eza)' "$pkg")"
                elif [[ "$tool" == "tealdeer" ]] && ! os_has_cmd tldr; then
                    if install_tealdeer_from_release; then
                        success "  $(_t '✅ tealdeer (official binary)')"
                    else
                        warn "  $(_t '⚠️ tealdeer installation failed (try cargo install tealdeer)')"
                    fi                else
                    warn "  $(_tf '⚠️ %s installation failed' "$pkg")"
                fi
            fi
        done
        # Debian 的 fd-find 命令是 fdfind，建别名
        if os_has_cmd fdfind && ! os_has_cmd fd; then
            local sudo_prefix=""
            [[ $EUID -ne 0 ]] && sudo_prefix="sudo"
            $sudo_prefix ln -sf "$(command -v fdfind)" /usr/local/bin/fd 2>/dev/null || true
        fi
    fi

    # 配置 shell 集成（fzf + zoxide + starship + 别名）
    configure_shell_integration

    # tealdeer 缓存（首次使用前必须更新）
    if os_has_cmd tldr; then
        if tldr --update >/dev/null 2>&1; then
            info "tealdeer $(_t 'Cache updated')"
        else
            warn "tealdeer $(_t 'Cache update failed (run tldr --update later)')"
        fi
    fi

    echo
    success "$(_t '🎉 Modern CLI toolset installation complete!')"
    info "$(_t 'Reload your shell to apply: source ~/.bashrc (or ~/.zshrc)')"
    echo
    info "$(_t 'Common commands:')"
    echo "  bat file.py          # $(_t 'replaces cat (syntax highlighting)')"
    echo "  eza -la --icons      # $(_t 'replaces ls (colors + icons + git)')"
    echo "  rg 'pattern'         # $(_t 'replaces grep (much faster)')"
    echo "  fd '\.py$'           # $(_t 'replaces find')"
    echo "  Ctrl+R               # fzf $(_t 'search command history')"
    echo "  z project            # zoxide $(_t 'jump to a directory')"
}

configure_shell_integration() {
    info "$(_t 'Configuring shell integration (aliases + fzf + zoxide + starship)...')"
    local rc rcbase mark="# >>> unix_script modern-cli >>>"
    local endmark="# <<< unix_script modern-cli <<<"

    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if grep -q "$mark" "$rc" 2>/dev/null; then
            # 已配置
            continue
        fi
        {
            echo ""
            echo "$mark"
            echo "# $(_t 'modern CLI tool aliases')"
            echo "alias cat='bat --paging=never 2>/dev/null || cat'"
            echo "alias ls='eza --group-directories-first 2>/dev/null || ls'"
            echo "alias ll='eza -la --group-directories-first --icons 2>/dev/null || ls -la'"
            echo "alias la='eza -a --group-directories-first --icons 2>/dev/null || ls -a'"
            echo "# fzf $(_t 'fzf integration')"
            echo "[ -f /usr/share/fzf/key-bindings.bash ] && source /usr/share/fzf/key-bindings.bash 2>/dev/null"
            echo "[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash 2>/dev/null"
            echo "[ -f /opt/homebrew/opt/fzf/shell/key-bindings.zsh ] && source /opt/homebrew/opt/fzf/shell/key-bindings.zsh 2>/dev/null"
            echo "[ -f \$HOME/.fzf.zsh ] && source \$HOME/.fzf.zsh 2>/dev/null"
            echo "# zoxide"
            echo "command -v zoxide >/dev/null 2>&1 && eval \"\$(zoxide init \$(basename \$SHELL))\""
            echo "# starship $(_t 'starship prompt')"
            echo "command -v starship >/dev/null 2>&1 && eval \"\$(starship init \$(basename \$SHELL))\""
            echo "$endmark"
        } >> "$rc"
        rcbase=$(basename "$rc")
        info "$(_tf 'Added the modern CLI integration for %s' "$rcbase")"
    done

    # extras 块：tldr/direnv（新增于 v1.15.0，独立标记块保证老 rc 也能补上）
    local emark="# >>> unix_script modern-cli extras >>>"
    local eendmark="# <<< unix_script modern-cli extras <<<"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if grep -q "$emark" "$rc" 2>/dev/null; then
            # 已配置
            continue
        fi
        {
            echo ""
            echo "$emark"
            echo "# direnv$(_t '(loads .envrc automatically when entering a directory)')"
            echo "command -v direnv >/dev/null 2>&1 && eval \"\$(direnv hook \$(basename \$SHELL))\""
            echo "$eendmark"
        } >> "$rc"
        rcbase=$(basename "$rc")
        info "$(_tf 'Added the direnv integration for %s' "$rcbase")"
    done

    # starship 默认配置（若不存在）
    if os_has_cmd starship && [[ ! -f "$HOME/.config/starship.toml" ]]; then
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
        info "$(_t 'Generated the default starship config ~/.config/starship.toml')"
    fi
}

uninstall_modern_cli() {
    detect_os
    warn "modern-cli $(_t 'Uninstall instructions:')"
    echo "  $(_t 'Tools:    brew uninstall bat eza ripgrep fd fzf zoxide starship tealdeer direnv')"
    echo "           $(_t 'or sudo <pkgmgr> remove bat eza ripgrep fd fzf zoxide starship tealdeer direnv')"
    echo "  shell:   $(_t 'delete from the rc file the lines between the # >>> unix_script modern-cli >>> marker block and')"
    echo "           '# >>> unix_script modern-cli extras >>>' $(_t 'the # >>> unix_script modern-cli extras >>> marker block')"
    echo "  $(_t 'Cache:    rm -rf ~/.cache/tealdeer')"
    echo "  $(_t 'Config:    rm ~/.config/starship.toml')"
    info "$(_t '(clean up manually as needed)')"
}

status_modern_cli() {
    detect_os
    local found=0 total=${#TOOLS[@]}
    local missing=() t
    for t in bat eza rg fd fzf zoxide starship tldr direnv; do
        if os_has_cmd "$t"; then
            found=$((found + 1))
        else
            missing+=("$t")
        fi
    done
    if [[ $found -ge $total ]]; then
        uxs_emit_status "installed" "${GREEN}$(_tf '✅ All installed (%s/%s)' "$found" "${total}")${NC}"
    elif [[ $found -gt 0 ]]; then
        uxs_emit_status "installed" "${YELLOW}$(_tf '⚠️ Partially installed (%s/%s)' "$found" "${total}")${NC}"
        uxs_emit_extra "installed=$found/$total"
        local missing_csv
        missing_csv=$(IFS=,; echo "${missing[*]}")
        uxs_emit_extra "missing=$missing_csv"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install the modern CLI toolset (bat/eza/rg/fd/fzf/zoxide/starship/tldr/direnv)')
  uninstall   $(_t 'Show the uninstall instructions')
  status      $(_t 'Show the status')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
