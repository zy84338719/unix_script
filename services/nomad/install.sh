#!/usr/bin/env bash
#
# nomad/install.sh
#
# 安装 Nomad —— HashiCorp 工作负载编排（容器/非容器任务统一调度）。
# Linux: GitHub release zip 单二进制；macOS: brew（dev agent 可用）。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="hashicorp/nomad"
BIN="/usr/local/bin/nomad"

preflight() {
    detect_os
    detect_arch
    check_commands curl unzip
}

# GitHub release 资产用 amd64/arm64 命名
arch_for_nomad() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "$(_tf 'Unsupported architecture: %s (only x86_64/arm64 are supported)' "${ARCH_TYPE}")"; return 1 ;;
    esac
}

do_install() {
    preflight
    if os_has_cmd nomad; then
        yes_no "$(_t 'nomad detected, overwrite it with the latest version?')" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing nomad via Homebrew...')"
        pkg_install nomad || { error "brew $(_t 'Installation failed')"; exit 1; }
        info "$(_t 'Try the dev mode: nomad agent -dev')"
    else
        info "$(_t 'Fetching the latest nomad version (GitHub API)...')"
        local ver
        ver=$(http_github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "$(_t 'Cannot fetch the version (GitHub is unreachable or rate limited), set GH_TOKEN and retry')"; exit 1; }
        local arch
        arch=$(arch_for_nomad)
        local url
        url=$(http_github_release_asset "$REPO" "nomad_${ver}_linux_${arch}\.zip")
        [[ -n "$url" ]] || { error "$(_tf 'Asset nomad_%s_linux_%s.zip not found' "${ver}" "${arch}")"; exit 1; }
        info "$(_tf 'Downloading %s ...' "$url")"
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        curl -fSL "$url" -o "$tmpdir/nomad.zip" || { error "$(_t 'Download failed')"; exit 1; }
        unzip -o -q "$tmpdir/nomad.zip" -d "$tmpdir"
        sudo install -m 0755 "$tmpdir/nomad" "$BIN"
        success "nomad v$ver $(_tf 'Installed to %s' "$BIN")"
        info "$(_t 'Try the dev mode: nomad agent -dev; a production deployment needs a server/client cluster')"
    fi
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "nomad"; then
            brew uninstall nomad && success "$(_t 'nomad uninstalled')"
        else
            warn "$(_t 'nomad not detected through brew')"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "$(_tf 'Deleted %s' "$BIN")"
        else
            warn "$(_tf '%s not detected' "$BIN")"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! os_has_cmd nomad; then
        uxs_emit_status "not_installed" "$(_t '❌ nomad not installed')"
        return 0
    fi
    local ver
    ver=$(nomad version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    uxs_emit_status "installed" "$(_t '✅ nomad installed') ${ver:-$(_t '(unknown version)')}$(_t '(single binary, dev mode: nomad agent -dev)')"
    uxs_emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
Nomad $(_t '— HashiCorp workload orchestration')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install the latest version (Linux: GitHub release zip; macOS: brew)')
  uninstall  $(_t 'Uninstall the binary')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: a single binary with no built-in service concept; nomad agent -dev gives you a quick start;')
$(_t 'Container task runtimes depend on docker/podman — run ./install.sh docker')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
