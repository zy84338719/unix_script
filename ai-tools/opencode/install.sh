#!/usr/bin/env bash
#
# opencode/install.sh
#
# 安装 OpenCode（sst/opencode）—— 开源终端 AI 编程助手。
# Linux + macOS。包装官方安装脚本 / Homebrew。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://opencode.ai/install"

preflight() {
    detect_os
    check_commands curl
}

install_opencode() {
    preflight
    info "$(_t '🤖 Installing OpenCode (the terminal AI coding assistant)')"

    if command_exists opencode; then
        local cur
        cur=$(opencode --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'OpenCode detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reinstall/update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "$(_t 'Installing opencode via Homebrew...')"
        brew install opencode
    else
        info "$(_tf 'Installing with the official script (%s)...' "${OFFICIAL_INSTALLER}")"
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
            error "$(_t 'The official installation script failed, check the network or see https://opencode.ai/docs/')"
            exit 1
        fi
    fi

    if ! command_exists opencode; then
        # 官方脚本可能装到 ~/.local/bin，可能不在当前 PATH
        if [[ -x "$HOME/.local/bin/opencode" ]]; then
            warn "opencode $(_t 'It has been installed to ~/.local/bin/opencode, but it is not in the current PATH')"
            # shellcheck disable=SC2016  # 单引号有意为之：$PATH 是让用户照抄的原文，不该在这里展开
            info "$(_tf 'Please add it to your shell configuration: export PATH="%s/.local/bin:$PATH"' "$HOME")"
        else
            error "$(_t 'opencode was not found after the installation, reopen the terminal or check PATH')"
            exit 1
        fi
    fi

    success "$(_t '🎉 OpenCode installation complete!')"
    info "$(_t 'Quick start:')"
    echo "  opencode          # $(_t 'Start an AI coding session in the project directory')"
    echo "  opencode --help   # $(_t 'View the help')"
    echo
    info "$(_t 'Configure the model / API key: see https://opencode.ai/docs/')"
}

uninstall_opencode() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall opencode 2>/dev/null && success "$(_t 'opencode has been uninstalled via brew')" && return 0
    fi
    # 官方脚本安装的通常在 ~/.local/bin
    local removed=false
    for p in "$HOME/.local/bin/opencode" "/usr/local/bin/opencode"; do
        if [[ -x "$p" ]]; then
            rm -f "$p"
            removed=true
        fi
    done
    if $removed; then
        success "$(_t 'The opencode binary has been deleted')"
    else
        warn "$(_t 'The opencode binary was not found (it may have been installed in another way, uninstall it manually)')"
    fi
    info "$(_t 'The configuration directory is kept: ~/.config/opencode (you can delete it manually)')"
}

status_opencode() {
    detect_os
    if command_exists opencode || [[ -x "$HOME/.local/bin/opencode" ]]; then
        local ver
        ver=$(opencode --version 2>/dev/null || "$HOME/.local/bin/opencode" --version 2>/dev/null || echo "")
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+($ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install OpenCode (the terminal AI coding assistant, default action)')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_opencode ;;
        uninstall) uninstall_opencode ;;
        status)    status_opencode ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
