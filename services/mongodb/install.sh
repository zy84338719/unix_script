#!/usr/bin/env bash
#
# mongodb/install.sh
#
# 安装 MongoDB —— 文档型数据库（mongodb-org 8.0）。
# 仅 Linux：官方 GPG key + TUNA 镜像仓库（apt/yum，国内可达）。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

MONGO_SERIES="8.0"
KEY_URL="https://www.mongodb.org/static/pgp/server-${MONGO_SERIES}.asc"
TUNA_BASE="https://mirrors.tuna.tsinghua.edu.cn/mongodb"

preflight() {
    detect_os
    detect_distro
    detect_arch
    check_commands curl gpg
}

setup_apt_repo() {
    local codename
    codename=$(uxs_os_release VERSION_CODENAME)
    case "$codename" in
        # TUNA mongodb apt 仓库支持的 Ubuntu/Debian 代号
        jammy|noble|bookworm|trixie) ;;
        *)
            error "发行版代号 ${codename:-未知} 不在 MongoDB ${MONGO_SERIES} 支持列表（jammy/noble/bookworm/trixie）"
            return 1
            ;;
    esac
    curl -fsSL "$KEY_URL" | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-${MONGO_SERIES}.gpg
    echo "deb [ arch=${ARCH_TYPE_LOWER} signed-by=/usr/share/keyrings/mongodb-server-${MONGO_SERIES}.gpg ] ${TUNA_BASE}/apt/ubuntu ${codename}/mongodb-org/${MONGO_SERIES} multiverse" \
        | sudo tee /etc/apt/sources.list.d/mongodb-org-${MONGO_SERIES}.list >/dev/null
}

setup_yum_repo() {
    local elver
    elver=$(uxs_os_release VERSION_ID | cut -d. -f1)
    cat <<EOF | sudo tee /etc/yum.repos.d/mongodb-org-${MONGO_SERIES}.repo >/dev/null
[mongodb-org-${MONGO_SERIES}]
name=MongoDB Repository
baseurl=${TUNA_BASE}/yum/el\$releasever/mongodb-org/${MONGO_SERIES}/\$basearch/
gpgcheck=1
enabled=1
gpgkey=${KEY_URL}
EOF
    [[ -n "$elver" ]] || true
}

do_install() {
    preflight
    if command_exists mongod; then
        local cur
        cur=$(mongod --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 MongoDB ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        info "配置 MongoDB ${MONGO_SERIES} APT 仓库（TUNA 镜像）..."
        setup_apt_repo || exit 1
    elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
        info "配置 MongoDB ${MONGO_SERIES} YUM 仓库（TUNA 镜像）..."
        setup_yum_repo
    else
        error "仅支持 Deb 系 / RHEL 系（当前：${DISTRO_FAMILY:-unknown}）"
        exit 1
    fi
    pkg_update || true
    pkg_install mongodb-org || { error "mongodb-org 安装失败"; exit 1; }
    uxs_svc enable-now mongod || warn "服务启动失败，可手动：sudo systemctl enable --now mongod"
    success "MongoDB ${MONGO_SERIES} 安装完成。连一下：mongosh"
}

do_uninstall() {
    preflight
    if ! command_exists mongod; then
        warn "MongoDB 未安装"
        exit 0
    fi
    yes_no "确认卸载 MongoDB？" || { info "已取消"; exit 0; }
    uxs_svc stop mongod 2>/dev/null || true
    pkg_remove mongodb-org || warn "包管理器卸载失败，请手动确认"
    sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list /etc/yum.repos.d/mongodb-org-*.repo
    success "MongoDB 已卸载"
    if [[ -d /var/lib/mongodb ]]; then
        if yes_no "是否删除数据库数据 /var/lib/mongodb（不可恢复）？"; then
            sudo rm -rf /var/lib/mongodb && success "数据已删除"
        else
            info "保留数据"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists mongod; then
        emit_status "not_installed" "❌ MongoDB 未安装"
        return 0
    fi
    local ver
    ver=$(mongod --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)
    if uxs_svc is-active mongod 2>/dev/null; then
        emit_status "installed:running" "✅ MongoDB 已安装且服务运行中 ${ver:-(版本未知)}"
    else
        emit_status "installed:stopped" "⚠️ MongoDB 已安装但服务未运行 ${ver:-(版本未知)}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
MongoDB 文档型数据库（mongodb-org 8.0，仅 Linux）

用法: install.sh {install|uninstall|status|help}

  install    官方 GPG key + TUNA 镜像仓库安装 mongodb-org，服务 enable-now
  uninstall  卸载（/var/lib/mongodb 数据默认保留，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：Deb 系支持 jammy/noble/bookworm/trixie 代号；RHEL 系走 el\$releasever。
客户端 shell：mongosh（随 mongodb-org 安装）。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
