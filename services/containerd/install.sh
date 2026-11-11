#!/usr/bin/env bash
#
# containerd/install.sh
#
# 安装 containerd —— 容器运行时（ctr 随附，含 nerdctl Docker 兼容 CLI）。
# Linux: 发行版仓库 + GitHub release nerdctl；macOS: brew（仅 CLI，宿主无法运行 Linux 容器）。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

NERDCTL_REPO="containerd/nerdctl"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
}

# GitHub release 资产用 amd64/arm64 命名
arch_generic() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "$(_tf 'Unsupported architecture: %s (only x86_64/arm64 supported)' "${ARCH_TYPE}")"; return 1 ;;
    esac
}

# Linux 上经 GitHub release 安装 nerdctl（多数发行版仓库无此包）；失败不阻断
install_nerdctl_linux() {
    local ver
    ver=$(github_latest_tag "$NERDCTL_REPO")
    if [[ -z "$ver" ]]; then
        warn "$(_t 'Unable to get nerdctl version (GitHub unreachable or rate-limited), skipping nerdctl')"
        return 0
    fi
    local arch
    arch=$(arch_generic)
    local url
    url=$(github_release_asset_url "$NERDCTL_REPO" "nerdctl-${ver}-linux-${arch}.tar.gz")
    if [[ -z "$url" ]]; then
        warn "$(_tf 'Asset nerdctl-%s-linux-%s.tar.gz not found, skipping nerdctl' "$ver" "$arch")"
        return 0
    fi
    info "$(_tf 'Downloading nerdctl v%s ...' "$ver")"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    if ! curl -fSL "$url" -o "$tmpdir/nerdctl.tar.gz"; then
        warn "$(_t 'nerdctl download failed, skipping')"
        return 0
    fi
    tar -xzf "$tmpdir/nerdctl.tar.gz" -C "$tmpdir"
    sudo install -m 0755 "$tmpdir/nerdctl" /usr/local/bin/nerdctl
    success "$(_tf 'nerdctl v%s installed to /usr/local/bin/nerdctl (Docker-compatible CLI)' "$ver")"
}

do_install() {
    preflight
    if command_exists ctr || command_exists containerd; then
        yes_no "$(_t 'Detected containerd/ctr, reinstall?')" || { info "$(_t 'Cancelled')"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing containerd (with ctr) and nerdctl CLI via Homebrew...')"
        pkg_install containerd nerdctl || { error "$(_t 'brew install failed')"; exit 1; }
        warn "$(_t 'macOS host cannot run Linux containers: ctr/nerdctl are client-only,')"
        warn "$(_t 'point them to a containerd socket in a Linux environment (VM/remote host), e.g.:')"
        warn "  export CONTAINERD_ADDRESS=/run/containerd/containerd.sock $(_t '(via lima/colima/SSH)')"
        info "$(_t 'For local containers use the docker / podman modules')"
    else
        info "$(_t 'Installing containerd (with ctr) via system repositories...')"
        pkg_update || true
        # Debian/Ubuntu 等仓库包名 containerd；部分 RHEL 系仅 docker 仓库的 containerd.io
        pkg_install containerd 2>/dev/null || pkg_install containerd.io \
            || { error "$(_t 'containerd install failed (RHEL needs docker repo or EPEL configured first)')"; exit 1; }
        uxs_svc enable-now containerd || warn "$(_t 'Failed to enable containerd service, manually: sudo systemctl enable --now containerd')"
        install_nerdctl_linux
        success "$(_t 'containerd installed. Try: sudo ctr images pull docker.io/library/alpine:latest')"
    fi
}

do_uninstall() {
    preflight
    if ! command_exists ctr && ! command_exists containerd; then
        warn "$(_t 'containerd not installed')"
        exit 0
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew uninstall containerd 2>/dev/null || true
        brew uninstall nerdctl 2>/dev/null || true
        success "$(_t 'containerd/nerdctl CLI uninstalled')"
    else
        yes_no "$(_t 'Confirm uninstall of containerd? (local docker may be affected if it depends on it)')" || { info "$(_t 'Cancelled')"; exit 0; }
        pkg_remove nerdctl 2>/dev/null || true
        pkg_remove containerd 2>/dev/null || pkg_remove containerd.io 2>/dev/null \
            || warn "$(_t 'Package manager uninstall failed, please confirm the package name manually')"
        sudo rm -f /usr/local/bin/nerdctl
        success "$(_t 'containerd uninstalled')"
        if [[ -d /var/lib/containerd ]]; then
            if yes_no "$(_t 'Delete container data /var/lib/containerd (images/snapshots, irreversible)?')"; then
                sudo rm -rf /var/lib/containerd && success "$(_t 'Data deleted')"
            else
                info "$(_t 'Data kept')"
            fi
        fi
        info "$(_t 'If docker is affected by this uninstall, reinstall: ./install.sh docker')"
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists ctr && ! command_exists containerd; then
        emit_status "not_installed" "❌ $(_t 'containerd not installed')"
        return 0
    fi
    local ver
    ver=$(containerd --version 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "darwin" ]]; then
        emit_status "installed" "✅ $(_t 'containerd installed') ${ver:-$(_t '(unknown version)')} $(_t '(macOS CLI only, cannot run local containers)')"
        emit_version "${ver#v}"
        emit_extra "mode=cli-only"
    else
        if uxs_svc is-active containerd 2>/dev/null; then
            emit_status "installed:running" "✅ $(_t 'containerd installed and service running') ${ver:-$(_t '(unknown version)')}"
        else
            emit_status "installed:stopped" "⚠️ $(_t 'containerd installed but service not running') ${ver:-$(_t '(unknown version)')}"
        fi
        emit_version "${ver#v}"
        if command_exists nerdctl; then
            emit_extra "nerdctl=yes"
        else
            emit_extra "nerdctl=no"
        fi
    fi
}

do_help() {
    cat <<EOF
$(_t 'containerd - container runtime (ctr included, with nerdctl)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install containerd (ctr included) + nerdctl (Docker-compatible CLI)')
             $(_t 'Linux: system repos (falls back to containerd.io); macOS: brew')
  uninstall  $(_t 'Uninstall (keeps /var/lib/containerd data by default, deletion needs second confirmation)')
  status     $(_t 'View install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Notes:')
$(_t '  - ctr is the built-in low-level CLI of containerd, shipped with containerd, cannot be installed separately')
$(_t '  - macOS host cannot run Linux containers; ctr/nerdctl only connect to a remote/VM containerd as clients')
$(_t '  - For local containers use the docker / podman modules')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
