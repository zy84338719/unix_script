#!/usr/bin/env bash
#
# skopeo/install.sh
#
# 安装 skopeo —— 镜像搬运/检查工具（纯 registry 客户端，无需本地容器运行时）。
# Linux: 发行版仓库；macOS: brew（registry 操作全平台可用）。
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
    if command_exists skopeo; then
        local cur
        cur=$(skopeo --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "$(_tf 'Detected skopeo %s installed, reinstall?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing skopeo via Homebrew...')"
        pkg_install skopeo || { error "$(_t 'brew install failed')"; exit 1; }
    else
        info "$(_t 'Installing skopeo via system repositories...')"
        pkg_update || true
        pkg_install skopeo || { error "$(_t 'skopeo install failed')"; exit 1; }
    fi
    success "$(_t 'skopeo installed. Try: skopeo inspect docker://docker.io/library/alpine:latest')"
}

do_uninstall() {
    preflight
    if ! command_exists skopeo; then
        warn "$(_t 'skopeo not installed')"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of skopeo?')" || { info "$(_t 'Cancelled')"; exit 0; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew uninstall skopeo 2>/dev/null || true
    else
        pkg_remove skopeo || { error "$(_t 'Uninstall failed')"; exit 1; }
    fi
    success "$(_t 'skopeo uninstalled')"
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists skopeo; then
        emit_status "not_installed" "❌ $(_t 'skopeo not installed')"
        return 0
    fi
    local ver
    ver=$(skopeo --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ $(_t 'skopeo installed') ${ver:-$(_t '(unknown version)')}"
    emit_version "${ver#v}"
}

do_help() {
    # <<EOF（不加引号）：_t 要在这里求值。
    # 首行保持中文「用法:」—— module_subcommands 靠它解析子命令。
    cat <<EOF
$(_t 'skopeo - image copy/inspection tool (no local container runtime needed)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install (Linux: system repositories; macOS: brew)')
  uninstall  $(_t 'Uninstall')
  status     $(_t 'View install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Common: skopeo inspect/copy docker://<image> (cross-registry image copy, offline sync)')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
