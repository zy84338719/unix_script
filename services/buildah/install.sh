#!/usr/bin/env bash
#
# buildah/install.sh
#
# 安装 buildah —— OCI 镜像构建工具（podman 亲兄弟，与 Dockerfile 兼容）。
# 仅 Linux：macOS 上无本地容器存储，buildah 无法工作，本模块在 macOS 全出口隐藏。
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
    if command_exists buildah; then
        local cur
        cur=$(buildah --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 buildah ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi
    info "通过系统仓库安装 buildah..."
    pkg_update || true
    pkg_install buildah || { error "buildah 安装失败（系统仓库无该包？）"; exit 1; }
    success "buildah 安装完成。试一下：buildah from alpine:latest"
    info "配套镜像搬运工具：./install.sh skopeo"
}

do_uninstall() {
    preflight
    if ! command_exists buildah; then
        warn "buildah 未安装"
        exit 0
    fi
    yes_no "确认卸载 buildah？" || { info "已取消"; exit 0; }
    pkg_remove buildah || { error "卸载失败"; exit 1; }
    success "buildah 已卸载"
    if [[ -d "$HOME/.local/share/containers" ]]; then
        if yes_no "是否删除用户容器存储 $HOME/.local/share/containers（镜像/层，不可恢复）？"; then
            rm -rf "$HOME/.local/share/containers" && success "存储已删除"
        else
            info "保留存储"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists buildah; then
        emit_status "not_installed" "❌ buildah 未安装"
        return 0
    fi
    local ver
    ver=$(buildah --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ buildah 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
buildah —— OCI 镜像构建工具（仅 Linux）

用法: install.sh {install|uninstall|status|help}

  install    通过系统仓库安装 buildah
  uninstall  卸载（用户容器存储默认保留，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：macOS 上无本地容器存储，buildah 不可用，本模块在 macOS 隐藏。
构建镜像也可用 podman build（Dockerfile 兼容）。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
