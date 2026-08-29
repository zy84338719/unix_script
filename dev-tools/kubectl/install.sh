#!/usr/bin/env bash
#
# kubectl/install.sh
#
# 安装 kubectl —— Kubernetes 命令行客户端。
# 支持 macOS (brew) + Linux (dl.k8s.io 官方二进制)。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

BIN="/usr/local/bin/kubectl"

preflight() {
    detect_os
    detect_arch
    check_commands curl
}

# dl.k8s.io 用 amd64/arm64 命名（ARCH_TYPE_LOWER 是 x86_64/arm64）
arch_for_k8s() {
    case "$ARCH_TYPE_LOWER" in
        x86_64) echo "amd64" ;;
        arm64)  echo "arm64" ;;
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

# 从 kubectl 输出提取 vX.Y.Z 版本号（离线 --client 探测，不连集群）
kubectl_client_version() {
    kubectl version --client 2>/dev/null | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true
}

do_install() {
    preflight
    if command_exists kubectl; then
        local cur
        cur=$(kubectl_client_version)
        yes_no "已检测到 kubectl ${cur:-}，是否覆盖安装最新稳定版？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 kubectl..."
        pkg_install kubectl || { error "brew 安装失败"; exit 1; }
    else
        info "获取 kubectl 最新稳定版本号（dl.k8s.io）..."
        local ver
        ver=$(curl -fsSL --connect-timeout 10 https://dl.k8s.io/release/stable.txt || true)
        if [[ -z "$ver" ]]; then
            error "无法获取版本号（dl.k8s.io 不可达）。手动下载：https://kubernetes.io/zh-cn/docs/tasks/tools/"
            exit 1
        fi
        local arch
        arch=$(arch_for_k8s)
        local url="https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl"
        info "下载 $url ..."
        local tmp
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        curl -fSL "$url" -o "$tmp" || { error "下载失败"; exit 1; }
        sudo install -m 0755 "$tmp" "$BIN"
        success "kubectl 已安装到 $BIN"
    fi
    info "下一步：本地集群用 minikube —— ./install.sh minikube"
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "kubectl"; then
            brew uninstall kubectl && success "已卸载 kubectl"
        else
            warn "未通过 brew 检测到 kubectl"
        fi
    else
        if [[ -e "$BIN" ]]; then
            sudo rm -f "$BIN" && success "已删除 $BIN"
        else
            warn "未检测到 $BIN"
        fi
    fi
    if [[ -d "$HOME/.kube" ]]; then
        if yes_no "是否同时删除集群配置 ~/.kube（含集群凭据，默认保留）？"; then
            rm -rf "$HOME/.kube" && success "已删除 ~/.kube"
        else
            info "保留 ~/.kube"
        fi
    fi
}

do_status() {
    if ! command_exists kubectl; then
        emit_status "not_installed" "❌ kubectl 未安装"
        return 0
    fi
    local ver
    ver=$(kubectl_client_version)
    emit_status "installed" "✅ kubectl 已安装 ${ver:-(版本未知)}"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
kubectl —— Kubernetes 命令行客户端

用法: install.sh {install|uninstall|status|help}

  install    安装最新稳定版（Linux: dl.k8s.io 官方二进制；macOS: brew）
  uninstall  卸载（默认保留 ~/.kube 集群配置）
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
