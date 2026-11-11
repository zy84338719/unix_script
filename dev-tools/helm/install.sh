#!/usr/bin/env bash
#
# helm/install.sh
#
# 安装 helm —— Kubernetes 包管理器。
# 支持 macOS (brew) + Linux (get.helm.sh 官方 tarball)。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="helm/helm"
BIN="/usr/local/bin/helm"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
}

# get.helm.sh tarball 用 amd64/arm64 命名
arch_for_helm() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "$(_tf 'unsupported architecture: %s (only x86_64/arm64 are supported)' "${ARCH_TYPE}")"; return 1 ;;
    esac
}

do_install() {
    preflight
    if os_has_cmd helm; then
        yes_no "$(_t 'helm detected, overwrite it with the latest version?')" || { info "$(_t 'Cancelled')"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing helm via Homebrew...')"
        pkg_install helm || { error "brew $(_t 'Installation failed')"; exit 1; }
    else
        info "$(_t 'Fetching the latest helm version (GitHub API)...')"
        local ver
        ver=$(http_github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "$(_t 'Cannot fetch the version number (GitHub is unreachable or rate limited), you can set GH_TOKEN and retry')"; exit 1; }
        local arch
        arch=$(arch_for_helm)
        local url="https://get.helm.sh/helm-v${ver}-linux-${arch}.tar.gz"
        info "$(_tf 'Downloading %s ...' "$url")"
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        curl -fSL "$url" -o "$tmpdir/helm.tar.gz" || { error "$(_t 'Download failed (is get.helm.sh unreachable?)')"; exit 1; }
        tar -xzf "$tmpdir/helm.tar.gz" -C "$tmpdir" || { error "$(_t 'Extraction failed')"; exit 1; }
        sudo install -m 0755 "$tmpdir/linux-${arch}/helm" "$BIN"
        success "helm v$ver $(_tf 'Installed to %s' "$BIN")"
    fi
    info "$(_t 'Next step: for a local cluster use minikube —— ./install.sh minikube')"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "helm"; then
            brew uninstall helm && success "$(_t 'helm has been uninstalled')"
        else
            warn "$(_t 'helm was not detected via brew')"
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
    if ! os_has_cmd helm; then
        uxs_emit_status "not_installed" "$(_t '❌ helm is not installed')"
        return 0
    fi
    local ver
    ver=$(helm version --short 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    uxs_emit_status "installed" "$(_t '✅ helm is installed') ${ver:-$(_t '(unknown version)')}"
    uxs_emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
helm $(_t '— Kubernetes package manager')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install the latest version (Linux: the official get.helm.sh tarball; macOS: brew)')
  uninstall  $(_t 'Uninstall the binary')
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
