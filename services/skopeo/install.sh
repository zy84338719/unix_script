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
        yes_no "已检测到 skopeo ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 skopeo..."
        pkg_install skopeo || { error "brew 安装失败"; exit 1; }
    else
        info "通过系统仓库安装 skopeo..."
        pkg_update || true
        pkg_install skopeo || { error "skopeo 安装失败"; exit 1; }
    fi
    success "skopeo 安装完成。试一下：skopeo inspect docker://docker.io/library/alpine:latest"
}

do_uninstall() {
    preflight
    if ! command_exists skopeo; then
        warn "skopeo 未安装"
        exit 0
    fi
    yes_no "确认卸载 skopeo？" || { info "已取消"; exit 0; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew uninstall skopeo 2>/dev/null || true
    else
        pkg_remove skopeo || { error "卸载失败"; exit 1; }
    fi
    success "skopeo 已卸载"
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists skopeo; then
        emit_status "not_installed" "❌ skopeo 未安装"
        return 0
    fi
    local ver
    ver=$(skopeo --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ skopeo 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
skopeo —— 镜像搬运/检查工具（无需本地容器运行时）

用法: install.sh {install|uninstall|status|help}

  install    安装（Linux: 系统仓库；macOS: brew）
  uninstall  卸载
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

常用：skopeo inspect/copy docker://<镜像>（跨仓库镜像搬运、离线同步）
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
