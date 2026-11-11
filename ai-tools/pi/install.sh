#!/usr/bin/env bash
#
# pi/install.sh
#
# 安装 Pi（pi.dev）—— 极简可定制的 AI 编程代理框架（Earendil Inc.）。
# 支持多模型、树状历史、扩展/技能/提示模板自定义。Linux + macOS。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://pi.dev/install.sh"

preflight() {
    detect_os
    check_commands curl
}

install_pi() {
    preflight
    info "$(_t '🤖 Installing Pi (the AI coding agent framework, pi.dev)')"

    if command_exists pi; then
        local cur
        cur=$(pi --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'Pi detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reinstall/update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    info "$(_tf 'Installing with the official script (%s)...' "${OFFICIAL_INSTALLER}")"
    if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
        error "$(_t 'The official installation script failed, check the network or see https://pi.dev')"
        exit 1
    fi

    # Pi 可能装到 ~/.pi 或 npm 全局，检测一下
    if ! command_exists pi; then
        # 尝试常见路径
        local found=""
        for p in "$HOME/.pi/bin/pi" "$HOME/.local/bin/pi" "/usr/local/bin/pi"; do
            [[ -x "$p" ]] && found="$p" && break
        done
        if [[ -n "$found" ]]; then
            warn "pi $(_tf 'It has been installed to %s, but it is not in the current PATH' "${found}")"
            info "$(_t 'Please add it to your shell configuration:')export PATH=\"$(dirname "$found"):\$PATH\""
        else
            warn "$(_t 'The pi command was not found right after the installation, reopen the terminal or check PATH')"
            info "Pi $(_t 'It can also be installed via npm/pnpm/bun: npm install -g @earendil-works/pi-coding-agent')"
        fi
    fi

    success "$(_t '🎉 Pi installation complete!')"
    info "$(_t 'Quick start:')"
    echo "  pi                         # $(_t 'Start an interactive TUI session')"
    echo "  pi '$(_t 'fix this bug           # give the prompt directly')"
    echo "  pi --help                  # $(_t 'View the help')"
    echo
    info "$(_t 'Configure the model / API key and the extensions: see https://pi.dev')"
}

uninstall_pi() {
    preflight
    local removed=false
    # 尝试 pi 自带卸载
    if command_exists pi; then
        pi uninstall >/dev/null 2>&1 && removed=true
    fi
    # 清理常见路径
    for p in "$HOME/.pi/bin/pi" "$HOME/.local/bin/pi" "/usr/local/bin/pi"; do
        if [[ -x "$p" ]]; then
            rm -f "$p"
            removed=true
        fi
    done
    if [[ -d "$HOME/.pi" ]] && yes_no "$(_tf 'Delete %s/.pi (with the configuration and the extensions)?' "$HOME")"; then
        rm -rf "$HOME/.pi"
        success "$(_tf 'Deleted %s/.pi' "$HOME")"
    fi
    if $removed; then
        success "Pi $(_t 'Uninstalled')"
    else
        warn "$(_t 'The Pi binary was not found (it may have been installed globally with npm, uninstall it with npm uninstall -g @earendil-works/pi-coding-agent)')"
    fi
}

status_pi() {
    detect_os
    if command_exists pi || [[ -x "$HOME/.pi/bin/pi" ]]; then
        local ver
        ver=$(pi --version 2>/dev/null || "$HOME/.pi/bin/pi" --version 2>/dev/null || echo "")
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+($ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Pi (the AI coding agent framework, default action)')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_pi ;;
        uninstall) uninstall_pi ;;
        status)    status_pi ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
