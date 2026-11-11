#!/usr/bin/env bash
#
# pnpm/install.sh
#
# 安装 pnpm —— 快速、节省磁盘的 Node.js 包管理器。
# Linux + macOS。包装官方独立安装脚本（不依赖 Node）。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://get.pnpm.io/install.sh"
PNPM_DIR="$HOME/.local/share/pnpm"

preflight() {
    detect_os
    check_commands curl
}

install_pnpm() {
    preflight
    info "$(_t '📦 Installing pnpm (the Node.js package manager)')"

    if os_has_cmd pnpm; then
        local cur
        cur=$(pnpm --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'Detected that pnpm is already installed (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reinstall/update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        info "$(_t 'Installing pnpm via Homebrew...')"
        brew install pnpm
    else
        info "$(_tf 'Installing via the official standalone script (%s)...' "${OFFICIAL_INSTALLER}")"
        # get.pnpm.io 的脚本需要 sh - 接收管道
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")" -; then
            error "$(_t 'The official installation script failed, see https://pnpm.io/installation')"
            exit 1
        fi
    fi

    if ! os_has_cmd pnpm && [[ -x "$PNPM_DIR/pnpm" ]]; then
        warn "pnpm $(_tf 'Installed to %s/pnpm, but it is not in the current PATH' "$PNPM_DIR")"
        # shellcheck disable=SC2016  # 译文里的 $PATH 是要原样打印的字面量，不能展开
        info "$(_tf 'Add it to your shell configuration: export PATH="%s:$PATH"' "$PNPM_DIR")"
    fi
    success "$(_t '🎉 pnpm installation complete!')"
    info "$(_t 'Quick start:')"
    echo "  pnpm install         # $(_t 'Install dependencies')"
    echo "  pnpm run dev         # $(_t 'Run a script')"
    echo "  pnpm add <$(_t 'package name>       # Add a dependency')"
}

uninstall_pnpm() {
    preflight
    local removed=false
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
        brew uninstall pnpm 2>/dev/null && removed=true
    fi
    if [[ -x "$PNPM_DIR/pnpm" ]]; then
        rm -rf "$PNPM_DIR"
        removed=true
    fi
    if $removed; then
        success "pnpm $(_t 'Uninstalled')"
    else
        warn "$(_t 'No pnpm installation found')"
    fi
}

status_pnpm() {
    detect_os
    if os_has_cmd pnpm || [[ -x "$PNPM_DIR/pnpm" ]]; then
        local ver
        ver=$(pnpm --version 2>/dev/null || "$PNPM_DIR/pnpm" --version 2>/dev/null || echo "")
        uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+(v$ver)}"
        uxs_emit_version "$ver"
    else
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install pnpm (default action)')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_pnpm ;;
        uninstall) uninstall_pnpm ;;
        status)    status_pnpm ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
