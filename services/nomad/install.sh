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
        *)      error "不支持的架构：$ARCH_TYPE（仅支持 x86_64/arm64）"; return 1 ;;
    esac
}

do_install() {
    preflight
    if command_exists nomad; then
        yes_no "已检测到 nomad，是否覆盖安装最新版？" || { info "已取消"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 nomad..."
        pkg_install nomad || { error "brew 安装失败"; exit 1; }
        info "体验 dev 模式：nomad agent -dev"
    else
        info "获取 nomad 最新版本（GitHub API）..."
        local ver
        ver=$(github_latest_tag "$REPO")
        [[ -n "$ver" ]] || { error "无法获取版本号（GitHub 不可达或限流），可设 GH_TOKEN 重试"; exit 1; }
        local arch
        arch=$(arch_for_nomad)
        local url
        url=$(github_release_asset_url "$REPO" "nomad_${ver}_linux_${arch}\.zip")
        [[ -n "$url" ]] || { error "未找到资产 nomad_${ver}_linux_${arch}.zip"; exit 1; }
        info "下载 $url ..."
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
        curl -fSL "$url" -o "$tmpdir/nomad.zip" || { error "下载失败"; exit 1; }
        unzip -o -q "$tmpdir/nomad.zip" -d "$tmpdir"
        sudo install -m 0755 "$tmpdir/nomad" "$BIN"
        success "nomad v$ver 已安装到 $BIN"
        info "体验 dev 模式：nomad agent -dev；生产部署需配 server/client 集群"
    fi
}

do_uninstall() {
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx "nomad"; then
            brew uninstall nomad && success "已卸载 nomad"
        else
            warn "未通过 brew 检测到 nomad"
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
    if ! command_exists nomad; then
        emit_status "not_installed" "❌ nomad 未安装"
        return 0
    fi
    local ver
    ver=$(nomad version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    emit_status "installed" "✅ nomad 已安装 ${ver:-(版本未知)}（单二进制，dev 模式: nomad agent -dev）"
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
Nomad —— HashiCorp 工作负载编排

用法: install.sh {install|uninstall|status|help}

  install    安装最新版（Linux: GitHub release zip；macOS: brew）
  uninstall  卸载二进制
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：单二进制、无内置服务概念；nomad agent -dev 一键体验；
容器任务运行时依赖 docker/podman——./install.sh docker
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
