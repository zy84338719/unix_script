#!/usr/bin/env bash
#
# k9s/install.sh
#
# 安装 k9s —— Kubernetes 终端管理面板（TUI）。
# 支持 macOS (brew) + Linux (GitHub release 二进制)。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="derailed/k9s"
BIN="/usr/local/bin/k9s"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
}

# GitHub release 资产用 amd64/arm64 命名
arch_for_k9s() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "$(_tf 'unsupported architecture: %s (only x86_64/arm64 are supported)' "${ARCH_TYPE}")"; return 1 ;;
    esac
}

do_install() {
    preflight
    if os_has_cmd k9s; then
        yes_no "$(_t 'k9s detected, overwrite it with the latest version?')" || { info "$(_t 'Cancelled')"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing k9s via Homebrew...')"
        pkg_install k9s || { error "brew $(_t 'Installation failed')"; exit 1; }
    else
        info "$(_t 'Fetching the latest k9s version (GitHub API)...')"
        local ver
        ver=$(http_github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "$(_t 'Cannot fetch the version number (GitHub is unreachable or rate limited), you can set GH_TOKEN and retry')"; exit 1; }
        local arch
        arch=$(arch_for_k9s)
        local url
        url=$(http_github_release_asset "$REPO" "k9s_Linux_${arch}.tar.gz")
        [[ -n "$url" ]] || { error "$(_tf 'asset k9s_Linux_%s.tar.gz not found' "${arch}")"; exit 1; }
        info "$(_tf 'Downloading %s ...' "$url")"
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        curl -fSL "$url" -o "$tmpdir/k9s.tar.gz" || { error "$(_t 'Download failed')"; exit 1; }
        tar -xzf "$tmpdir/k9s.tar.gz" -C "$tmpdir" || { error "$(_t 'Extraction failed')"; exit 1; }
        sudo install -m 0755 "$tmpdir/k9s" "$BIN"
        success "k9s v$ver $(_tf 'Installed to %s' "$BIN")"
    fi
    info "$(_t 'Next step: for a local cluster use minikube —— ./install.sh minikube')"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "k9s"; then
            brew uninstall k9s && success "$(_t 'k9s has been uninstalled')"
        else
            warn "$(_t 'k9s was not detected via brew')"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "$(_tf 'Deleted %s' "$BIN")"
        else
            warn "$(_tf '%s was not detected' "$BIN")"
        fi
    fi
    info "k9s $(_t 'kubeconfig is left untouched, there is no cluster config to clean up')"
}

do_status() {
    if ! os_has_cmd k9s; then
        uxs_emit_status "not_installed" "$(_t '❌ k9s is not installed')"
        return 0
    fi
    local ver
    ver=$(k9s version 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    uxs_emit_status "installed" "$(_t '✅ k9s is installed') ${ver:-$(_t '(unknown version)')}"
    uxs_emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
k9s $(_t '— Kubernetes terminal dashboard (TUI)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install the latest version (Linux: the GitHub release binary; macOS: brew)')
  uninstall  $(_t 'Uninstall the binary (kubeconfig is left untouched)')
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
