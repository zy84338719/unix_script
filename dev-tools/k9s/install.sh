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
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

do_install() {
    preflight
    if command_exists k9s; then
        yes_no "已检测到 k9s，是否覆盖安装最新版？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 k9s..."
        pkg_install k9s || { error "brew 安装失败"; exit 1; }
    else
        info "获取 k9s 最新版本（GitHub API）..."
        local ver
        ver=$(github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "无法获取版本号（GitHub 不可达或限流），可设 GH_TOKEN 重试"; exit 1; }
        local arch
        arch=$(arch_for_k9s)
        local url
        url=$(github_release_asset_url "$REPO" "k9s_Linux_${arch}.tar.gz")
        [[ -n "$url" ]] || { error "未找到资产 k9s_Linux_${arch}.tar.gz"; exit 1; }
        info "下载 $url ..."
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        curl -fSL "$url" -o "$tmpdir/k9s.tar.gz" || { error "下载失败"; exit 1; }
        tar -xzf "$tmpdir/k9s.tar.gz" -C "$tmpdir" || { error "解压失败"; exit 1; }
        sudo install -m 0755 "$tmpdir/k9s" "$BIN"
        success "k9s v$ver 已安装到 $BIN"
    fi
    info "下一步：本地集群用 minikube —— ./install.sh minikube"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "k9s"; then
            brew uninstall k9s && success "已卸载 k9s"
        else
            warn "未通过 brew 检测到 k9s"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "已删除 $BIN"
        else
            warn "未检测到 $BIN"
        fi
    fi
    info "k9s 不改写 kubeconfig，集群配置无需清理"
}

do_status() {
    if ! command_exists k9s; then
        emit_status "not_installed" "❌ k9s 未安装"
        return 0
    fi
    local ver
    ver=$(k9s version 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ k9s 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
k9s —— Kubernetes 终端管理面板（TUI）

用法: install.sh {install|uninstall|status|help}

  install    安装最新版（Linux: GitHub release 二进制；macOS: brew）
  uninstall  卸载二进制（不动 kubeconfig）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
