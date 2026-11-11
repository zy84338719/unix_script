#!/usr/bin/env bash
#
# kubectl/install.sh
#
# 安装 kubectl —— Kubernetes 命令行客户端。
# 支持 macOS (brew) + Linux (dl.k8s.io 官方二进制)。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

BIN="/usr/local/bin/kubectl"

preflight() {
    detect_os
    detect_arch
    check_commands curl
}

# dl.k8s.io 用 amd64/arm64 命名（ARCH_TYPE_LOWER 是 x86_64/arm64）
arch_for_k8s() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "$(_tf 'unsupported architecture: %s (only x86_64/arm64 are supported)' "${ARCH_TYPE}")"; return 1 ;;
    esac
}

# 从 kubectl 输出提取 vX.Y.Z 版本号（离线 --client 探测，不连集群）
kubectl_client_version() {
    kubectl version --client 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true
}

do_install() {
    preflight
    if command_exists kubectl; then
        local cur
        cur=$(kubectl_client_version)
        yes_no "$(_tf 'kubectl %s detected, overwrite it with the latest stable version?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing kubectl via Homebrew...')"
        pkg_install kubectl || { error "brew $(_t 'Installation failed')"; exit 1; }
    else
        info "$(_t 'Fetching the latest stable kubectl version (dl.k8s.io)...')"
        local ver
        ver=$(curl -fsSL --connect-timeout 10 https://dl.k8s.io/release/stable.txt || true)
        if [[ -z "$ver" ]]; then
            error "$(_t 'Cannot fetch the version number (dl.k8s.io is unreachable). Download it manually: https://kubernetes.io/zh-cn/docs/tasks/tools/')"
            exit 1
        fi
        local arch
        arch=$(arch_for_k8s)
        local url="https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl"
        info "$(_tf 'Downloading %s ...' "$url")"
        local tmp
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        curl -fSL "$url" -o "$tmp" || { error "$(_t 'Download failed')"; exit 1; }
        sudo install -m 0755 "$tmp" "$BIN"
        success "kubectl $(_tf 'Installed to %s' "$BIN")"
    fi
    info "$(_t 'Next step: for a local cluster use minikube —— ./install.sh minikube')"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "kubectl"; then
            brew uninstall kubectl && success "$(_t 'kubectl has been uninstalled')"
        else
            warn "$(_t 'kubectl was not detected via brew')"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "$(_tf 'Deleted %s' "$BIN")"
        else
            warn "$(_tf '%s was not detected' "$BIN")"
        fi
    fi
    if [[ -d "$HOME/.kube" ]]; then
        if yes_no "$(_t 'Also delete the cluster config ~/.kube (it contains the cluster credentials, kept by default)?')"; then
            rm -rf "$HOME/.kube" && success "$(_t 'Deleted ~/.kube')"
        else
            info "$(_t 'Kept ~/.kube')"
        fi
    fi
}

do_status() {
    if ! command_exists kubectl; then
        emit_status "not_installed" "$(_t '❌ kubectl is not installed')"
        return 0
    fi
    local ver
    ver=$(kubectl_client_version)
    emit_status "installed" "$(_t '✅ kubectl is installed') ${ver:-$(_t '(unknown version)')}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
kubectl $(_t '— Kubernetes command line client')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install the latest stable version (Linux: the official dl.k8s.io binary; macOS: brew)')
  uninstall  $(_t 'Uninstall (the ~/.kube cluster config is kept by default)')
  status     $(_t 'View the installation status (UXS_STATUS_MODE=machine is supported)')
  help       $(_t 'this help')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
