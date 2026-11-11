#!/usr/bin/env bash
#
# podman-desktop/install.sh
#
# 安装 Podman Desktop —— 容器/K8s 桌面管理台（GUI）。
# macOS: brew cask；Linux: Flatpak（flathub）。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

FLATPAK_ID="io.podman_desktop.PodmanDesktop"

preflight() {
    detect_os
    detect_arch
}

do_install() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -d "/Applications/Podman Desktop.app" ]]; then
            yes_no "$(_t 'Detected Podman Desktop, reinstall?')" || { info "$(_t 'Cancelled')"; exit 0; }
        fi
        info "$(_t 'Installing Podman Desktop via Homebrew cask...')"
        pkg_install --cask podman-desktop 2>/dev/null || brew install --cask podman-desktop \
            || { error "$(_t 'cask install failed')"; exit 1; }
        success "$(_t 'Podman Desktop installed to /Applications')"
        info "$(_t 'Container runtime setup: podman machine — ./install.sh podman')"
    else
        if ! os_has_cmd flatpak; then
            error "$(_t 'On Linux, Podman Desktop is distributed via Flatpak; please install flatpak (apt/dnf install flatpak) and add the flathub remote first')"
            exit 1
        fi
        if flatpak list --app 2>/dev/null | grep -q "$FLATPAK_ID"; then
            yes_no "$(_t 'Detected Podman Desktop (Flatpak), reinstall?')" || { info "$(_t 'Cancelled')"; exit 0; }
        fi
        info "$(_t 'Installing Podman Desktop via Flatpak (flathub)...')"
        flatpak install -y flathub "$FLATPAK_ID" || { error "$(_t 'Flatpak install failed (has the flathub remote been added?)')"; exit 1; }
        success "$(_t 'Podman Desktop installed; launch it from the applications menu')"
        info "$(_t 'Container runtime setup: podman — ./install.sh podman')"
    fi
}

do_uninstall() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --cask 2>/dev/null | grep -qx "podman-desktop"; then
            brew uninstall --cask podman-desktop && success "$(_t 'Podman Desktop uninstalled')"
        else
            warn "$(_t 'podman-desktop not detected via brew')"
        fi
    else
        if os_has_cmd flatpak && flatpak list --app 2>/dev/null | grep -q "$FLATPAK_ID"; then
            flatpak uninstall -y "$FLATPAK_ID" && success "$(_t 'Podman Desktop uninstalled')"
        else
            warn "$(_t 'Podman Desktop (Flatpak) not detected')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -d "/Applications/Podman Desktop.app" ]]; then
            uxs_emit_status "installed" "✅ $(_t 'Podman Desktop installed (/Applications)')"
        else
            uxs_emit_status "not_installed" "❌ $(_t 'Podman Desktop not installed')"
        fi
    else
        if os_has_cmd flatpak && flatpak list --app 2>/dev/null | grep -q "$FLATPAK_ID"; then
            uxs_emit_status "installed" "✅ $(_t 'Podman Desktop installed (Flatpak)')"
        else
            uxs_emit_status "not_installed" "❌ $(_t 'Podman Desktop not installed')"
        fi
    fi
}

do_help() {
    # <<EOF（不加引号）：_t 要在这里求值。
    # 首行保留中文「用法:」—— module_subcommands 靠它解析子命令。
    cat <<EOF
$(_t 'Podman Desktop - container/K8s desktop manager (GUI)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install (macOS: brew cask; Linux: Flatpak/flathub)')
  uninstall  $(_t 'Uninstall')
  status     $(_t 'View install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Notes: the GUI manages containers and K8s contexts; on Linux install flatpak and add flathub first;
container runtime setup uses podman — ./install.sh podman')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
