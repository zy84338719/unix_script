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
            yes_no "已检测到 Podman Desktop，是否重新安装？" || { info "已取消"; exit 0; }
        fi
        info "通过 Homebrew cask 安装 Podman Desktop..."
        pkg_install --cask podman-desktop 2>/dev/null || brew install --cask podman-desktop \
            || { error "cask 安装失败"; exit 1; }
        success "Podman Desktop 已安装到 /Applications"
        info "容器运行时配 podman machine：./install.sh podman"
    else
        if ! command_exists flatpak; then
            error "Linux 上 Podman Desktop 经 Flatpak 分发，请先安装 flatpak（apt/dnf install flatpak）并添加 flathub 远程"
            exit 1
        fi
        if flatpak list --app 2>/dev/null | grep -q "$FLATPAK_ID"; then
            yes_no "已检测到 Podman Desktop（Flatpak），是否重新安装？" || { info "已取消"; exit 0; }
        fi
        info "通过 Flatpak 安装 Podman Desktop（flathub）..."
        flatpak install -y flathub "$FLATPAK_ID" || { error "Flatpak 安装失败（flathub 远程已添加？）"; exit 1; }
        success "Podman Desktop 已安装，应用菜单启动"
        info "容器运行时配 podman：./install.sh podman"
    fi
}

do_uninstall() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --cask 2>/dev/null | grep -qx "podman-desktop"; then
            brew uninstall --cask podman-desktop && success "已卸载 Podman Desktop"
        else
            warn "未通过 brew 检测到 podman-desktop"
        fi
    else
        if command_exists flatpak && flatpak list --app 2>/dev/null | grep -q "$FLATPAK_ID"; then
            flatpak uninstall -y "$FLATPAK_ID" && success "已卸载 Podman Desktop"
        else
            warn "未检测到 Podman Desktop（Flatpak）"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -d "/Applications/Podman Desktop.app" ]]; then
            emit_status "installed" "✅ Podman Desktop 已安装（/Applications）"
        else
            emit_status "not_installed" "❌ Podman Desktop 未安装"
        fi
    else
        if command_exists flatpak && flatpak list --app 2>/dev/null | grep -q "$FLATPAK_ID"; then
            emit_status "installed" "✅ Podman Desktop 已安装（Flatpak）"
        else
            emit_status "not_installed" "❌ Podman Desktop 未安装"
        fi
    fi
}

do_help() {
    cat <<'EOF'
Podman Desktop —— 容器/K8s 桌面管理台（GUI）

用法: install.sh {install|uninstall|status|help}

  install    安装（macOS: brew cask；Linux: Flatpak/flathub）
  uninstall  卸载
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：GUI 管理容器与 K8s 上下文；Linux 需先装 flatpak 并添加 flathub；
容器运行时配 podman——./install.sh podman
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
