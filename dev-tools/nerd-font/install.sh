#!/usr/bin/env bash
set -euo pipefail
#
# dev-tools/nerd-font/install.sh
#
# Nerd Font 图标字体安装器。字体由终端模拟器（客户端）渲染：
#   macOS → brew cask 装本机（本机终端立即可用）
#   Linux → ~/.local/share/fonts（仅本机桌面会话有意义）
#   SSH 远程/无头机 → install 直接提示并退出 0
#
# 子命令：install | list | uninstall | status | help
# 配置：UXS_CONFIG_FONTS 逗号分隔（默认 JetBrainsMono）
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 字体名 → macOS cask 名 映射表（新增字体在此登记；cask 名经 brew search 核实）
FONT_CASKS=(
    JetBrainsMono:font-jetbrains-mono-nerd-font
    FiraCode:font-fira-code-nerd-font
    Hack:font-hack-nerd-font
    CascadiaCode:font-cascadia-code-nf
)

cask_for() {
    local f
    for f in "${FONT_CASKS[@]}"; do
        [[ "${f%%:*}" == "$1" ]] && { echo "${f#*:}"; return 0; }
    done
    return 1
}

list_names() {
    local f out=""
    for f in "${FONT_CASKS[@]}"; do out+="${f%%:*} "; done
    echo "${out% }"
}

normalize_fonts() {
    local raw="${UXS_CONFIG_FONTS:-JetBrainsMono}"
    echo "$raw" | tr ',' '\n' | sed 's/ //g' | grep -v '^$'
}

install_nerd_font() {
    local fonts missing=() f
    fonts=$(normalize_fonts)
    for f in $fonts; do
        cask_for "$f" >/dev/null || missing+=("$f")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        # 命令替换不能进译文（译文是静态字符串，$(list_names) 会被原样打印）⇒ 先取值再翻译
        local avail; avail=$(list_names)
        error "$(_tf 'Unregistered font: %s (available: %s)' "${missing[*]}" "$avail")"
        return 1
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        os_has_cmd brew || { error "macOS $(_t 'Homebrew is required')"; return 1; }
        for f in $fonts; do
            local cask
            cask=$(cask_for "$f")
            if brew list --cask "$cask" >/dev/null 2>&1; then
                info "$(_tf 'Installed: %s' "$f")"
            elif brew install --cask "$cask"; then
                success "✅ $f"
            else
                warn "$(_tf '⚠️ %s installation failed' "$f")"
            fi
        done
    else
        # Linux：仅本机桌面会话有意义
        if ! os_has_cmd fc-cache || [[ "${IS_DESKTOP:-0}" != "1" ]]; then
            detect_desktop
        fi
        if [[ "${IS_DESKTOP:-0}" != "1" ]] || ! os_has_cmd fc-cache; then
            info "$(_t 'This machine is a remote/headless environment — the font is rendered by your local terminal machine, there is no need to install it here')"
            info "$(_t 'Run it on your local terminal machine: ./install.sh nerd-font')"
            return 0
        fi
        local ver
        ver=$(http_github_latest_tag "ryanoasis/nerd-fonts" 2>/dev/null) || { error "$(_t 'Cannot get the nerd-fonts version')"; return 1; }
        for f in $fonts; do
            local dest="$HOME/.local/share/fonts/NerdFonts/$f"
            if [[ -d "$dest" ]] && ls "$dest"/*.ttf >/dev/null 2>&1; then
                info "$(_tf 'Installed: %s' "$f")"
                continue
            fi
            # v3.x 资产名：<FontName>.tar.xz（JetBrainsMono.tar.xz，tag v3.5.1 实测）
            local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${ver}/${f}.tar.xz"
            mkdir -p "$dest"
            if curl -fsSL "$url" | tar -xJ -C "$dest" 2>/dev/null; then
                success "✅ $f ($ver)"
            else
                warn "$(_tf '⚠️ %s download failed' "$f")"
                rm -rf "$dest"
            fi
        done
        fc-cache -f >/dev/null 2>&1 || true
    fi
    success "$(_t '🎉 Nerd Font installation complete (remember to select a Nerd Font in your terminal emulator settings)')"
}

uninstall_nerd_font() {
    local f
    for f in $(normalize_fonts); do
        if [[ "$OS_TYPE" == "darwin" ]]; then
            local cask
            if cask=$(cask_for "$f"); then
                brew uninstall --cask "$cask" || true
            fi
        else
            rm -rf "$HOME/.local/share/fonts/NerdFonts/$f"
        fi
        info "$(_tf 'Uninstalled: %s' "$f")"
    done
    if os_has_cmd fc-cache; then
        fc-cache -f >/dev/null 2>&1 || true
    fi
}

status_nerd_font() {
    local f found=() total=0
    for f in $(normalize_fonts); do
        total=$((total + 1))
        if [[ "$OS_TYPE" == "darwin" ]]; then
            ls "$HOME/Library/Fonts/${f}Nerd"* >/dev/null 2>&1 && found+=("$f")
        else
            [[ -d "$HOME/.local/share/fonts/NerdFonts/$f" ]] && found+=("$f")
        fi
    done
    local csv
    csv=$(IFS=,; echo "${found[*]:-}")
    if [[ ${#found[@]} -eq $total ]]; then
        uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed:') ${csv:-$(_t 'none')}${NC}"
    elif [[ ${#found[@]} -gt 0 ]]; then
        uxs_emit_status "installed" "${YELLOW}$(_tf '⚠️ Partially installed: %s' "$csv")${NC}"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
    [[ -n "$csv" ]] && uxs_emit_extra "fonts=$csv"
    return 0
}

usage() {
    cat <<EOF
用法: $0 {install|list|uninstall|status|help}

  install     $(_t 'Install Nerd Font (default JetBrainsMono; UXS_CONFIG_FONTS="JetBrainsMono,FiraCode" can be specified)')
  list        $(_t 'List the installable fonts')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_nerd_font ;;
        list)      list_names ;;
        uninstall) uninstall_nerd_font ;;
        status)    status_nerd_font ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
