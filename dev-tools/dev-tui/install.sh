#!/usr/bin/env bash
#
# dev-tui/install.sh
#
# 安装终端 TUI 开发工具：lazydocker（Docker TUI）与 lazygit（Git TUI）。
# 下载 Go 二进制到 ~/.local/bin（纯用户态，无需 sudo），Linux + macOS 均可。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

INSTALL_DIR="$HOME/.local/bin"
TOOLS=(lazydocker lazygit)

preflight() {
    detect_os
    check_commands curl tar
}

# 解析架构 -> lazydocker/lazygit 发布后缀格式（Go_X86_64 / Go_arm64）
arch_go_suffix() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)         echo "x86_64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l)         echo "armv7" ;;
        *) error "$(_tf 'unsupported architecture: %s' "$arch")"; exit 1 ;;
    esac
}

# 安装单个工具：参数 <repo> <工具名>
install_one() {
    local repo="$1" tool="$2"
    local arch version url tmpdir suffix capos
    version=$(github_latest_tag "$repo")
    if [[ -z "$version" ]]; then
        error "$(_tf 'Cannot get the latest version of %s (check the network or set GH_TOKEN)' "$tool")"
        return 1
    fi
    suffix=$(arch_go_suffix)
    # 大写的 OS（Linux/Darwin）+ 大写架构是 lazydocker/lazygit 的命名约定
    case "$OS_TYPE" in
        linux)  capos="Linux" ;;
        darwin) capos="Darwin" ;;
    esac
    url="https://github.com/${repo}/releases/download/v${version}/${tool}_${version}_${capos}_${suffix}.tar.gz"
    info "$(_tf 'Downloading %s v%s ...' "$tool" "$version")"
    tmpdir=$(mktemp -d)
    if ! curl -fSL "$url" -o "$tmpdir/pkg.tar.gz"; then
        error "$tool $(_tf 'Download failed: %s' "$url")"
        rm -rf "$tmpdir"; return 1
    fi
    if ! tar -xzf "$tmpdir/pkg.tar.gz" -C "$tmpdir" 2>/dev/null; then
        # 部分版本可能是 .tar.xz 或裸二进制，兜底尝试
        if ! tar -xJf "$tmpdir/pkg.tar.gz" -C "$tmpdir" 2>/dev/null; then
            error "$tool $(_t 'Extraction failed')"
            rm -rf "$tmpdir"; return 1
        fi
    fi
    mkdir -p "$INSTALL_DIR"
    if [ -f "$tmpdir/$tool" ]; then
        mv "$tmpdir/$tool" "$INSTALL_DIR/$tool"
    else
        # 某些 lazydocker 包把二进制放在子目录
        local found
        found=$(find "$tmpdir" -name "$tool" -type f | head -1)
        if [[ -n "$found" ]]; then
            mv "$found" "$INSTALL_DIR/$tool"
        else
            error "$tool $(_t 'The binary was not found in the archive')"
            rm -rf "$tmpdir"; return 1
        fi
    fi
    chmod +x "$INSTALL_DIR/$tool"
    rm -rf "$tmpdir"
    success "$tool v$version $(_tf 'Installed to %s/%s' "$INSTALL_DIR" "$tool")"
}

install_dev_tui() {
    preflight
    info "$(_t '🚀 Starting the installation of the terminal TUI tools (lazydocker + lazygit)')"

    # macOS 优先 brew
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "$(_t 'Installing via Homebrew...')"
        brew install lazydocker lazygit
        success "lazydocker + lazygit $(_t 'Installation complete (managed by brew)')"
        info "$(_t 'Usage: lazydocker / lazygit')"
        return 0
    fi

    mkdir -p "$INSTALL_DIR"
    install_one "jesseduffield/lazydocker" "lazydocker" || warn "lazydocker $(_t 'Installation failed')"
    install_one "jesseduffield/lazygit" "lazygit" || warn "lazygit $(_t 'Installation failed')"

    # PATH 配置提示
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        warn "$INSTALL_DIR $(_t 'is not in PATH. Please add it to your shell configuration:')"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi

    echo
    info "$(_t 'How to use:')"
    echo "  lazydocker    # Docker $(_t 'terminal UI')"
    echo "  lazygit       # Git $(_t 'terminal UI')"
}

uninstall_dev_tui() {
    preflight
    if ! yes_no "$(_t 'Confirm uninstalling lazydocker and lazygit?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    local t
    for t in "${TOOLS[@]}"; do
        if [[ -f "$INSTALL_DIR/$t" ]]; then
            rm -f "$INSTALL_DIR/$t"
            success "$(_tf 'Deleted %s/%s' "$INSTALL_DIR" "$t")"
        fi
    done
    success "TUI $(_t 'The tools have been uninstalled.')"
}

status_dev_tui() {
    detect_os
    local installed=0
    local t
    for t in "${TOOLS[@]}"; do
        if [[ -x "$INSTALL_DIR/$t" ]]; then
            installed=$((installed + 1))
        fi
    done
    if [[ $installed -eq ${#TOOLS[@]} ]]; then
        emit_status "installed" "${GREEN}$(_t '✅ lazydocker + lazygit are installed')${NC}"
    elif [[ $installed -gt 0 ]]; then
        emit_status "installed" "${YELLOW}$(_tf '⚠️  partially installed (%s/%s)' "$installed" "${#TOOLS[@]}")${NC}"
        emit_extra "installed=$installed/${#TOOLS[@]}"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_tf 'Install lazydocker + lazygit to %s' "$INSTALL_DIR")
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_dev_tui ;;
        uninstall) uninstall_dev_tui ;;
        status)    status_dev_tui ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
