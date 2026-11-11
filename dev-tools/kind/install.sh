#!/usr/bin/env bash
#
# kind/install.sh
#
# 安装 kind —— 用 Docker 起本地 Kubernetes 集群（CI 常用，minikube 的轻量替代）。
# Linux: GitHub release 单文件二进制；macOS: brew。运行依赖 docker（框架自动先装）。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="kubernetes-sigs/kind"
BIN="/usr/local/bin/kind"

preflight() {
    detect_os
    detect_arch
    check_commands curl
}

# GitHub release 资产用 amd64/arm64 命名
arch_for_kind() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "$(_tf 'unsupported architecture: %s (only x86_64/arm64 are supported)' "${ARCH_TYPE}")"; return 1 ;;
    esac
}

do_install() {
    preflight
    if os_has_cmd kind; then
        yes_no "$(_t 'kind detected, overwrite it with the latest version?')" || { info "$(_t 'Cancelled')"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing kind via Homebrew...')"
        pkg_install kind || { error "brew $(_t 'Installation failed')"; exit 1; }
    else
        info "$(_t 'Fetching the latest kind version (GitHub API)...')"
        local ver
        ver=$(http_github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "$(_t 'Cannot fetch the version number (GitHub is unreachable or rate limited), you can set GH_TOKEN and retry')"; exit 1; }
        local arch
        arch=$(arch_for_kind)
        local url
        url=$(http_github_release_asset "$REPO" "kind-linux-${arch}\$")
        [[ -n "$url" ]] || { error "$(_tf 'asset kind-linux-%s not found' "${arch}")"; exit 1; }
        info "$(_tf 'Downloading %s ...' "$url")"
        local tmp
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        curl -fSL "$url" -o "$tmp" || { error "$(_t 'Download failed')"; exit 1; }
        sudo install -m 0755 "$tmp" "$BIN"
        success "kind v$ver $(_tf 'Installed to %s' "$BIN")"
    fi
    if ! os_has_cmd docker; then
        warn "$(_t 'docker was not detected — kind needs it to create a cluster: ./install.sh docker')"
    fi
    info "$(_t 'Try it: kind create cluster --name demo')"
}

do_uninstall() {
    if os_has_cmd kind; then
        info "$(_t 'Note: uninstalling kind does not affect the clusters already created, delete them with: kind delete clusters --all')"
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "kind"; then
            brew uninstall kind && success "$(_t 'kind has been uninstalled')"
        else
            warn "$(_t 'kind was not detected via brew')"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "$(_tf 'Deleted %s' "$BIN")"
        else
            warn "$(_tf '%s was not detected' "$BIN")"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! os_has_cmd kind; then
        uxs_emit_status "not_installed" "$(_t '❌ kind is not installed')"
        return 0
    fi
    local ver
    ver=$(kind version 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    uxs_emit_status "installed" "$(_t '✅ kind is installed') ${ver:-$(_t '(unknown version)')}"
    uxs_emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
kind $(_t '— spin up a local Kubernetes cluster with Docker')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install the latest version (Linux: the GitHub release binary; macOS: brew)')
  uninstall  $(_t 'Uninstall the binary (the clusters already created are left untouched)')
  status     $(_t 'View the installation status (UXS_STATUS_MODE=machine is supported)')
  help       $(_t 'this help')

$(_t 'Note: it depends on docker (the framework installs it first when this module is installed). For a local dev cluster you can also choose')
minikube$(_t ' (more features) —— ./install.sh minikube')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
