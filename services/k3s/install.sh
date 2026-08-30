#!/usr/bin/env bash
#
# k3s/install.sh
#
# 安装 k3s —— 轻量级 Kubernetes（边缘/服务器，Rancher 出品）。
# 仅 Linux（macOS 无服务端，全出口隐藏）；get.k3s.io 官方脚本安装。
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
    check_commands curl
}

do_install() {
    preflight
    if command_exists k3s; then
        local cur
        cur=$(k3s --version 2>/dev/null | head -1 | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 k3s ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi
    info "通过官方脚本安装 k3s（get.k3s.io）..."
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 \
        || { error "k3s 安装失败，可查看 /var/log 或手动执行官方脚本排查"; exit 1; }
    info "等待服务就绪..."
    sleep 5
    if sudo k3s kubectl get node 2>/dev/null; then
        success "k3s 安装完成，节点已就绪"
    else
        info "节点尚未就绪，稍后验证：sudo k3s kubectl get node"
    fi
    info "kubeconfig：/etc/rancher/k3s/k3s.yaml（已设 644 可读）"
    info "终端面板：./install.sh k9s；包管理：./install.sh helm"
}

do_uninstall() {
    preflight
    if ! command_exists k3s; then
        warn "k3s 未安装"
        exit 0
    fi
    if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
        yes_no "确认卸载 k3s（官方卸载脚本会连带清理集群数据）？" || { info "已取消"; exit 0; }
        sudo /usr/local/bin/k3s-uninstall.sh && success "k3s 已卸载"
    else
        error "未找到官方卸载脚本 /usr/local/bin/k3s-uninstall.sh，请手动处理"
        exit 1
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists k3s; then
        emit_status "not_installed" "❌ k3s 未安装"
        return 0
    fi
    local ver
    ver=$(k3s --version 2>/dev/null | head -1 | grep -m1 -oE 'v[0-9]+(\.[0-9]+)+' || true)
    if uxs_svc is-active k3s 2>/dev/null; then
        emit_status "installed:running" "✅ k3s 已安装且服务运行中 ${ver:-(版本未知)}"
    else
        emit_status "installed:stopped" "⚠️ k3s 已安装但服务未运行 ${ver:-(版本未知)}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
k3s —— 轻量级 Kubernetes（边缘/服务器，仅 Linux）

用法: install.sh {install|uninstall|status|help}

  install    get.k3s.io 官方脚本安装（--write-kubeconfig-mode 644）
  uninstall  官方卸载脚本（连带清理集群数据）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：kubeconfig 在 /etc/rancher/k3s/k3s.yaml；终端管理配 k9s，
包管理配 helm——./install.sh k9s / ./install.sh helm
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
