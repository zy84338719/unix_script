#!/usr/bin/env bash
#
# mariadb/install.sh
#
# 安装 MariaDB 数据库（MySQL 兼容分支，各大发行版仓库默认数据库）。
# Linux: 发行版仓库；macOS: brew。
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
    if command_exists mariadb; then
        local cur
        cur=$(mariadb --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 MariaDB ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi
    if command_exists mysql && ! command_exists mariadb; then
        warn "检测到已装 MySQL：MariaDB 同样监听 3306，同机共存会端口冲突"
        yes_no "仍要继续安装 MariaDB？" || { info "已取消"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 MariaDB..."
        pkg_install mariadb || { error "brew 安装失败"; exit 1; }
        info "启动：brew services start mariadb（首次 root 无密码）"
    else
        info "通过系统仓库安装 MariaDB..."
        pkg_update || true
        pkg_install mariadb-server || { error "MariaDB 安装失败（系统仓库无该包？）"; exit 1; }
        uxs_svc enable-now mariadb 2>/dev/null || uxs_svc enable-now mysql 2>/dev/null \
            || warn "服务启动失败，可手动：sudo systemctl enable --now mariadb"
        success "MariaDB 安装完成"
        info "建议尽快跑：mariadb-secure-installation"
    fi
    info "状态查询：./install.sh mariadb status"
}

do_uninstall() {
    preflight
    if ! command_exists mariadb; then
        warn "MariaDB 未安装"
        exit 0
    fi
    yes_no "确认卸载 MariaDB？" || { info "已取消"; exit 0; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop mariadb 2>/dev/null || true
        brew uninstall mariadb 2>/dev/null || true
        success "MariaDB 已卸载"
    else
        uxs_svc stop mariadb 2>/dev/null || true
        pkg_remove mariadb-server || { error "卸载失败"; exit 1; }
        success "MariaDB 已卸载"
    fi
    if [[ -d /var/lib/mysql ]]; then
        if yes_no "是否删除数据库数据 /var/lib/mysql（所有库表，不可恢复）？"; then
            sudo rm -rf /var/lib/mysql && success "数据已删除"
        else
            info "保留数据"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists mariadb; then
        emit_status "not_installed" "❌ MariaDB 未安装"
        return 0
    fi
    local ver
    ver=$(mariadb --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc is-active mariadb 2>/dev/null || uxs_svc is-active mysql 2>/dev/null; then
            emit_status "installed:running" "✅ MariaDB 已安装且服务运行中 ${ver:-(版本未知)}"
        else
            emit_status "installed:stopped" "⚠️ MariaDB 已安装但服务未运行 ${ver:-(版本未知)}"
        fi
    else
        emit_status "installed" "✅ MariaDB 已安装 ${ver:-(版本未知)}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
MariaDB 数据库（MySQL 兼容分支）

用法: install.sh {install|uninstall|status|help}

  install    安装并启动（Linux: 系统仓库；macOS: brew）
  uninstall  卸载（/var/lib/mysql 数据默认保留，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：与 MySQL 同端口 3306，同机共存需改端口；装完建议跑
mariadb-secure-installation。要 MySQL 8 用 ./install.sh mysql。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
