#!/usr/bin/env bash
#
# harbor/install.sh
#
# 安装 Harbor —— 自托管 Docker 镜像仓库（CNCF 毕业项目，offline installer）。
# 仅 Linux（PLATFORMS=linux）；运行依赖 docker + compose 插件（框架自动先装 docker）。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="goharbor/harbor"
HARBOR_DIR="/opt/harbor"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
    if ! command_exists docker; then
        error "Harbor 运行依赖 docker，请先：./install.sh docker"
        exit 1
    fi
}

# 本机主 IP（配置 hostname 用）
primary_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

gen_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

do_install() {
    preflight
    if [[ -d "$HARBOR_DIR" ]]; then
        yes_no "已检测到 $HARBOR_DIR（Harbor 可能已安装），是否重新安装？" || { info "已取消"; exit 0; }
    fi
    info "获取 Harbor 最新版本（GitHub API）..."
    local ver
    ver=$(github_latest_tag "$REPO")
    [[ -n "$ver" ]] || { error "无法获取版本号（GitHub 不可达或限流），可设 GH_TOKEN 重试"; exit 1; }
    local url="https://github.com/${REPO}/releases/download/v${ver}/harbor-offline-installer-v${ver}.tgz"
    warn "Harbor 离线安装包约 600MB+，下载耗时取决于网络"
    info "下载 $url ..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    curl -fSL "$url" -o "$tmpdir/harbor.tgz" || { error "下载失败（GitHub 大文件较慢，可重试）"; exit 1; }
    info "解压到 $HARBOR_DIR ..."
    sudo mkdir -p "$HARBOR_DIR"
    sudo tar -xzf "$tmpdir/harbor.tgz" -C "$(dirname "$HARBOR_DIR")"

    # 生成 harbor.yml：hostname 取本机主 IP，http 80；密码交互输入、非 TTY 随机生成
    local admin_pwd
    if [[ -t 0 ]]; then
        read -r -p "设置 Harbor admin 密码（直接回车则随机生成）: " admin_pwd || true
    fi
    [[ -n "${admin_pwd:-}" ]] || admin_pwd=$(gen_password)
    local ip
    ip=$(primary_ip)
    [[ -n "$ip" ]] || ip="reg.example.com"
    sudo cp "$HARBOR_DIR/harbor.yml.tmpl" "$HARBOR_DIR/harbor.yml"
    sudo sed -i "s/^hostname: .*/hostname: $ip/" "$HARBOR_DIR/harbor.yml"
    sudo sed -i "s/^harbor_admin_password: .*/harbor_admin_password: $admin_pwd/" "$HARBOR_DIR/harbor.yml"
    # 默认注释 https 段会校验失败？模板 http/https 均含——关掉 https 以便纯内网 http 可用
    sudo sed -i 's/^https:/#https:/; s/^  port: 443/#  port: 443/; s/^  certificate: .#/#  certificate:/; s/^  private_key: .#/#  private_key:/' "$HARBOR_DIR/harbor.yml" || true

    info "执行官方安装编排（含 prepare 与 compose up，需数分钟）..."
    (cd "$HARBOR_DIR" && sudo ./install.sh) || { error "Harbor 编排安装失败，可查看 $HARBOR_DIR 排查"; exit 1; }
    echo
    success "Harbor v$ver 安装完成：http://$ip"
    warn "admin 密码：$admin_pwd（请妥善保存，仅此一次回显）"
    info "Docker 客户端使用该仓库需配 insecure-registries（纯 http 时），见 README"
}

do_uninstall() {
    preflight
    if [[ ! -d "$HARBOR_DIR" ]]; then
        warn "Harbor 未安装（未找到 $HARBOR_DIR）"
        exit 0
    fi
    yes_no "确认卸载 Harbor（停止并移除全部容器）？" || { info "已取消"; exit 0; }
    (cd "$HARBOR_DIR" && sudo docker compose down 2>/dev/null) \
        || (cd "$HARBOR_DIR" && sudo docker-compose down 2>/dev/null) \
        || warn "compose down 失败，可手动在 $HARBOR_DIR 执行"
    sudo rm -rf "$HARBOR_DIR"
    success "Harbor 已卸载"
    if [[ -d /data ]]; then
        if yes_no "是否删除 Harbor 数据目录 /data（镜像/数据库/证书，不可恢复）？"; then
            sudo rm -rf /data/harbor 2>/dev/null || sudo rm -rf /data && success "数据已删除"
        else
            info "保留数据"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if [[ ! -d "$HARBOR_DIR" ]]; then
        emit_status "not_installed" "❌ Harbor 未安装"
        return 0
    fi
    if sudo docker ps --format '{{.Image}}' 2>/dev/null | grep -q "^goharbor/harbor-core"; then
        emit_status "installed:running" "✅ Harbor 容器运行中"
    else
        emit_status "installed:stopped" "⚠️ Harbor 已安装但容器未运行"
    fi
}

do_help() {
    cat <<'EOF'
Harbor —— 自托管 Docker 镜像仓库（仅 Linux，依赖 docker）

用法: install.sh {install|uninstall|status|help}

  install    下载 offline installer 到 /opt/harbor 并官方编排安装（http 模式）
  uninstall  停容器并卸载（/data 数据默认保留，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：admin 密码安装时设置（非交互随机生成、一次性回显）；默认 http，
Docker 客户端需在 daemon.json 的 insecure-registries 加仓库地址。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
