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
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

# Linux 上经 GitHub release 安装 nerdctl（多数发行版仓库无此包）；失败不阻断
install_nerdctl_linux() {
    local ver
    ver=$(github_latest_tag "$NERDCTL_REPO")
    if [[ -z "$ver" ]]; then
        warn "无法获取 nerdctl 版本（GitHub 不可达或限流），跳过 nerdctl"
        return 0
    fi
    local arch
    arch=$(arch_generic)
    local url
    url=$(github_release_asset_url "$NERDCTL_REPO" "nerdctl-${ver}-linux-${arch}.tar.gz")
    if [[ -z "$url" ]]; then
        warn "未找到 nerdctl-${ver}-linux-${arch}.tar.gz 资产，跳过 nerdctl"
        return 0
    fi
    info "下载 nerdctl v$ver ..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    if ! curl -fSL "$url" -o "$tmpdir/nerdctl.tar.gz"; then
        warn "nerdctl 下载失败，跳过"
        return 0
    fi
    tar -xzf "$tmpdir/nerdctl.tar.gz" -C "$tmpdir"
    sudo install -m 0755 "$tmpdir/nerdctl" /usr/local/bin/nerdctl
    success "nerdctl v$ver 已安装到 /usr/local/bin/nerdctl（Docker 兼容 CLI）"
}

do_install() {
    preflight
    if command_exists ctr || command_exists containerd; then
        yes_no "已检测到 containerd/ctr，是否重新安装？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 containerd（含 ctr）与 nerdctl CLI..."
        pkg_install containerd nerdctl || { error "brew 安装失败"; exit 1; }
        warn "macOS 宿主无法运行 Linux 容器：ctr/nerdctl 仅作为客户端使用，"
        warn "需指向 Linux 环境（VM/远程主机）的 containerd socket，例如："
        warn "  export CONTAINERD_ADDRESS=/run/containerd/containerd.sock（经 lima/colima/SSH）"
        info "本机跑容器请用 docker / podman 模块"
    else
        info "通过系统仓库安装 containerd（ctr 随附）..."
        pkg_update || true
        # Debian/Ubuntu 等仓库包名 containerd；部分 RHEL 系仅 docker 仓库的 containerd.io
        pkg_install containerd 2>/dev/null || pkg_install containerd.io \
            || { error "containerd 安装失败（RHEL 系需先配 docker 仓库或 EPEL）"; exit 1; }
        uxs_svc enable-now containerd || warn "containerd 服务启用失败，可手动：sudo systemctl enable --now containerd"
        install_nerdctl_linux
        success "containerd 安装完成。试一下：sudo ctr images pull docker.io/library/alpine:latest"
    fi
}

do_uninstall() {
    preflight
    if ! command_exists ctr && ! command_exists containerd; then
        warn "containerd 未安装"
        exit 0
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew uninstall containerd 2>/dev/null || true
        brew uninstall nerdctl 2>/dev/null || true
        success "containerd/nerdctl CLI 已卸载"
    else
        yes_no "确认卸载 containerd？（若本机 docker 以其为依赖，可能受影响）" || { info "已取消"; exit 0; }
        pkg_remove nerdctl 2>/dev/null || true
        pkg_remove containerd 2>/dev/null || pkg_remove containerd.io 2>/dev/null \
            || warn "包管理器卸载失败，请手动确认包名"
        sudo rm -f /usr/local/bin/nerdctl
        success "containerd 已卸载"
        if [[ -d /var/lib/containerd ]]; then
            if yes_no "是否删除容器数据 /var/lib/containerd（镜像/快照，不可恢复）？"; then
                sudo rm -rf /var/lib/containerd && success "数据已删除"
            else
                info "保留数据"
            fi
        fi
        info "若 docker 因本卸载受损，重装：./install.sh docker"
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists ctr && ! command_exists containerd; then
        emit_status "not_installed" "❌ containerd 未安装"
        return 0
    fi
    local ver
    ver=$(containerd --version 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "darwin" ]]; then
        emit_status "installed" "✅ containerd 已安装 ${ver:-(版本未知)}（macOS 仅 CLI，无法本机跑容器）"
        emit_version "${ver#v}"
        emit_extra "mode=cli-only"
    else
        if uxs_svc is-active containerd 2>/dev/null; then
            emit_status "installed:running" "✅ containerd 已安装且服务运行中 ${ver:-(版本未知)}"
        else
            emit_status "installed:stopped" "⚠️ containerd 已安装但服务未运行 ${ver:-(版本未知)}"
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
    cat <<'EOF'
containerd —— 容器运行时（ctr 随附，含 nerdctl）

用法: install.sh {install|uninstall|status|help}

  install    安装 containerd（ctr 随附）+ nerdctl（Docker 兼容 CLI）
             Linux: 系统仓库（缺包时回退 containerd.io）；macOS: brew
  uninstall  卸载（默认保留 /var/lib/containerd 数据，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：
  - ctr 是 containerd 自带的底层 CLI，随 containerd 一并提供，无法单独安装
  - macOS 宿主无法运行 Linux 容器，ctr/nerdctl 仅作客户端连远程/VM 的 containerd
  - 本机跑容器请用 docker / podman 模块
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
