#!/usr/bin/env bash
#
# deno/install.sh
#
# 安装 Deno —— 安全的 JavaScript/TypeScript/WebAssembly 运行时与工具链。
# Linux + macOS。包装官方安装脚本。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://deno.land/install.sh"
DENO_DIR="$HOME/.deno"
DENO_BIN="$DENO_DIR/bin/deno"

preflight() {
    detect_os
    check_commands curl
}

install_deno() {
    preflight
    info "$(_t '🦕 Installing Deno (the JavaScript/TypeScript runtime)')"

    if os_has_cmd deno; then
        local cur
        cur=$(deno --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'Detected that Deno is already installed (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reinstall/update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        info "$(_t 'Installing deno via Homebrew...')"
        brew install deno
    else
        info "$(_tf 'Installing via the official script (%s)...' "${OFFICIAL_INSTALLER}")"
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
            error "$(_t 'The official installation script failed, see https://deno.land')"
            exit 1
        fi
    fi

    if ! os_has_cmd deno && [[ -x "$DENO_BIN" ]]; then
        warn "deno $(_tf 'Installed to %s, but it is not in the current PATH' "${DENO_BIN}")"
        # shellcheck disable=SC2016  # 译文里的 $PATH 是要原样打印的字面量，不能展开
        info "$(_tf 'Add it to your shell configuration: export PATH="%s/bin:$PATH"' "$DENO_DIR")"
    fi
    success "$(_t '🎉 Deno installation complete!')"
    info "$(_t 'Quick start:')"
    echo "  deno run https://deno.land/std/examples/welcome.ts"
    echo "  deno serve main.ts          # $(_t 'start the server')"
    echo "  deno test                   # $(_t 'run the tests')"
    echo "  deno compile app.ts         # $(_t 'compile to a single executable file')"
}

uninstall_deno() {
    preflight
    local removed=false
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        brew uninstall deno 2>/dev/null && removed=true
    fi
    if [[ -x "$DENO_BIN" ]]; then
        rm -f "$DENO_BIN"
        removed=true
    fi
    if [[ -d "$DENO_DIR" ]] && yes_no "$(_tf 'Delete %s (including the cache)?' "${DENO_DIR}")"; then
        rm -rf "$DENO_DIR"
    fi
    if $removed; then
        success "Deno $(_t 'Uninstalled')"
    else
        warn "$(_t 'No Deno installation found')"
    fi
}

status_deno() {
    detect_os
    if os_has_cmd deno || [[ -x "$DENO_BIN" ]]; then
        local ver
        ver=$(deno --version 2>/dev/null | head -1 || "$DENO_BIN" --version 2>/dev/null | head -1 || echo "")
        uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+($ver)}"
        uxs_emit_version "$ver"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Deno (default action)')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_deno ;;
        uninstall) uninstall_deno ;;
        status)    status_deno ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
