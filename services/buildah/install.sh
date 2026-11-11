#!/usr/bin/env bash
#
# buildah/install.sh
#
# 安装 buildah —— OCI 镜像构建工具（podman 亲兄弟，与 Dockerfile 兼容）。
# 仅 Linux：macOS 上无本地容器存储，buildah 无法工作，本模块在 macOS 全出口隐藏。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    detect_arch
}

do_install() {
    preflight
    if command_exists buildah; then
        local cur
        cur=$(buildah --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "$(printf "$(_t 'buildah %s is already installed, reinstall?')" "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    info "$(_t 'Installing buildah via system repositories...')"
    pkg_update || true
    pkg_install buildah || { error "$(_t 'buildah install failed (package not in system repos?)')"; exit 1; }
    success "$(_t 'buildah installed. Try: buildah from alpine:latest')"
    info "$(_t 'Companion image tool: ./install.sh skopeo')"
}

do_uninstall() {
    preflight
    if ! command_exists buildah; then
        warn "$(_t 'buildah not installed')"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of buildah?')" || { info "$(_t 'Cancelled')"; exit 0; }
    pkg_remove buildah || { error "$(_t 'Uninstall failed')"; exit 1; }
    success "$(_t 'buildah uninstalled')"
    if [[ -d "$HOME/.local/share/containers" ]]; then
        if yes_no "$(printf "$(_t 'Delete user container storage %s (images/layers, irreversible)?')" "$HOME/.local/share/containers")"; then
            rm -rf "$HOME/.local/share/containers" && success "$(_t 'Storage deleted')"
        else
            info "$(_t 'Storage kept')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists buildah; then
        emit_status "not_installed" "❌ $(_t 'buildah not installed')"
        return 0
    fi
    local ver
    ver=$(buildah --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ $(_t 'buildah installed') ${ver:-$(_t '(unknown version)')}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
$(_t 'buildah - OCI image build tool (Linux only)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install buildah via system repositories')
  uninstall  $(_t 'Uninstall (user container storage kept by default, deletion needs second confirmation)')
  status     $(_t 'View install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: no local container storage on macOS, buildah is unavailable, this module is hidden on macOS.')
$(_t 'You can also build images with podman build (Dockerfile compatible).')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(printf "$(_t 'Unknown subcommand: %s')" "$1")"; do_help; exit 1 ;;
esac
