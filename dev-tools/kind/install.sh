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
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

do_install() {
    preflight
    if command_exists kind; then
        yes_no "已检测到 kind，是否覆盖安装最新版？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 kind..."
        pkg_install kind || { error "brew 安装失败"; exit 1; }
    else
        info "获取 kind 最新版本（GitHub API）..."
        local ver
        ver=$(github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "无法获取版本号（GitHub 不可达或限流），可设 GH_TOKEN 重试"; exit 1; }
        local arch
        arch=$(arch_for_kind)
        local url
        url=$(github_release_asset_url "$REPO" "kind-linux-${arch}\$")
        [[ -n "$url" ]] || { error "未找到资产 kind-linux-${arch}"; exit 1; }
        info "下载 $url ..."
        local tmp
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        curl -fSL "$url" -o "$tmp" || { error "下载失败"; exit 1; }
        sudo install -m 0755 "$tmp" "$BIN"
        success "kind v$ver 已安装到 $BIN"
    fi
    if ! command_exists docker; then
        warn "未检测到 docker——kind 创建集群需要它：./install.sh docker"
    fi
    info "试一下：kind create cluster --name demo"
}

do_uninstall() {
    if command_exists kind; then
        info "注意：kind 卸载不影响已创建的集群，删除集群用：kind delete clusters --all"
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "kind"; then
            brew uninstall kind && success "已卸载 kind"
        else
            warn "未通过 brew 检测到 kind"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "已删除 $BIN"
        else
            warn "未检测到 $BIN"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists kind; then
        emit_status "not_installed" "❌ kind 未安装"
        return 0
    fi
    local ver
    ver=$(kind version 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ kind 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
kind —— 用 Docker 起本地 Kubernetes 集群

用法: install.sh {install|uninstall|status|help}

  install    安装最新版（Linux: GitHub release 二进制；macOS: brew）
  uninstall  卸载二进制（不动已创建的集群）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：运行依赖 docker（安装本模块时框架自动先装）。本地开发集群也可选
minikube（功能更全）——./install.sh minikube
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
