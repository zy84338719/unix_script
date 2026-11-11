#!/usr/bin/env bash
#
# k3s/install.sh
#
# 安装 k3s —— 轻量级 Kubernetes（边缘/服务器，Rancher 出品）。
# 仅 Linux（macOS 无服务端，全出口隐藏）；get.k3s.io 官方脚本安装。
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
    check_commands curl
}

do_install() {
    preflight
    if os_has_cmd k3s; then
        local cur
        cur=$(k3s --version 2>/dev/null | head -1 | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
        yes_no "$(_tf 'Detected k3s %s installed, reinstall?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    info "$(_t 'Installing k3s via the official script (get.k3s.io)...')"
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 \
        || { error "$(_t 'k3s install failed; check /var/log or run the official script manually to troubleshoot')"; exit 1; }
    info "$(_t 'Waiting for the service to be ready...')"
    sleep 5
    if sudo k3s kubectl get node 2>/dev/null; then
        success "$(_t 'k3s installation complete, node is ready')"
    else
        info "$(_t 'Node not ready yet; verify later: sudo k3s kubectl get node')"
    fi
    info "$(_t 'kubeconfig: /etc/rancher/k3s/k3s.yaml (mode 644, readable)')"
    info "$(_t 'Terminal UI: ./install.sh k9s; package manager: ./install.sh helm')"
}

do_uninstall() {
    preflight
    if ! os_has_cmd k3s; then
        warn "$(_t 'k3s not installed')"
        exit 0
    fi
    if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
        yes_no "$(_t 'Confirm uninstall of k3s (the official uninstall script also cleans up cluster data)?')" || { info "$(_t 'Cancelled')"; exit 0; }
        sudo /usr/local/bin/k3s-uninstall.sh && success "$(_t 'k3s uninstalled')"
    else
        error "$(_t 'Official uninstall script /usr/local/bin/k3s-uninstall.sh not found; please handle it manually')"
        exit 1
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! os_has_cmd k3s; then
        uxs_emit_status "not_installed" "❌ $(_t 'k3s not installed')"
        return 0
    fi
    local ver
    ver=$(k3s --version 2>/dev/null | head -1 | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    if uxs_svc is-active k3s 2>/dev/null; then
        uxs_emit_status "installed:running" "✅ $(_t 'k3s installed and service running') ${ver:-$(_t '(unknown version)')}"
    else
        uxs_emit_status "installed:stopped" "⚠️ $(_t 'k3s installed but service not running') ${ver:-$(_t '(unknown version)')}"
    fi
    uxs_emit_version "${ver#v}"
}

do_help() {
    # <<EOF（不加引号）：_t 要在这里求值。
    # 首行保持「用法:」开头的用法行（行首 + 含 {…}）—— module_subcommands 靠它解析子命令。
    cat <<EOF
$(_t 'k3s - lightweight Kubernetes (edge/server, Linux only)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install via the official get.k3s.io script (--write-kubeconfig-mode 644)')
  uninstall  $(_t 'Official uninstall script (also cleans up cluster data)')
  status     $(_t 'View install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Notes: kubeconfig is at /etc/rancher/k3s/k3s.yaml; terminal management uses k9s,
package management uses helm — ./install.sh k9s / ./install.sh helm')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
