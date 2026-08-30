#!/usr/bin/env bash
#
# mysql/install.sh
#
# 安装 MySQL 数据库——库内数据库补齐（此前只有 postgres/redis）。
# Linux: 发行版仓库（RHEL 系 AppStream 的 mysql-server / Deb 系 mysql-server）；
# macOS: brew。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 各发行版服务名不同：Deb 系 mysql，RHEL 系 mysqld
svc_name() {
    if systemctl list-unit-files mysql.service >/dev/null 2>&1 \
        && systemctl list-unit-files mysql.service 2>/dev/null | grep -q "^mysql"; then
        echo "mysql"
    else
        echo "mysqld"
    fi
}

do_install() {
    preflight
    if command_exists mysql; then
        local cur
        cur=$(mysql --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 MySQL ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 MySQL..."
        pkg_install mysql || { error "brew 安装失败"; exit 1; }
        info "启动：brew services start mysql（首次 root 无密码）"
    else
        info "通过系统仓库安装 MySQL..."
        pkg_update || true
        # RHEL 系 AppStream 为 mysql-server；Deb 系 Ubuntu 为 mysql-server、
        # Debian 为 default-mysql-server，逐个回退
        pkg_install mysql-server 2>/dev/null \
            || pkg_install default-mysql-server 2>/dev/null \
            || { error "MySQL 安装失败（系统仓库无该包，RHEL 系需启用 AppStream）"; exit 1; }
        local svc
        svc=$(svc_name)
        uxs_svc enable-now "$svc" || warn "服务启动失败，可手动：sudo systemctl enable --now $svc"
        success "MySQL 安装完成"
        if [[ -f /var/log/mysqld.log ]]; then
            local tp
            tp=$(grep -m1 'temporary password' /var/log/mysqld.log 2>/dev/null | awk '{print $NF}' || true)
            [[ -n "$tp" ]] && warn "RHEL 系 root 临时密码：$tp（登录后请立即改密）"
        fi
        info "Deb 系 root 默认走 auth_socket（sudo mysql 直登）；建议尽快跑 mysql_secure_installation"
    fi
    info "状态查询：./install.sh mysql status"
}

do_uninstall() {
    preflight
    if ! command_exists mysql; then
        warn "MySQL 未安装"
        exit 0
    fi
    yes_no "确认卸载 MySQL？" || { info "已取消"; exit 0; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop mysql 2>/dev/null || true
        brew uninstall mysql 2>/dev/null || true
        success "MySQL 已卸载"
    else
        local svc
        svc=$(svc_name)
        uxs_svc stop "$svc" 2>/dev/null || true
        pkg_remove mysql-server 2>/dev/null || pkg_remove default-mysql-server 2>/dev/null \
            || warn "包管理器卸载失败，请手动确认包名"
        success "MySQL 已卸载"
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
    if ! command_exists mysql; then
        emit_status "not_installed" "❌ MySQL 未安装"
        return 0
    fi
    local ver
    ver=$(mysql --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "linux" ]]; then
        local svc
        svc=$(svc_name)
        if uxs_svc is-active "$svc" 2>/dev/null; then
            emit_status "installed:running" "✅ MySQL 已安装且服务运行中 ${ver:-(版本未知)}"
        else
            emit_status "installed:stopped" "⚠️ MySQL 已安装但服务未运行 ${ver:-(版本未知)}"
        fi
    else
        emit_status "installed" "✅ MySQL 已安装 ${ver:-(版本未知)}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
MySQL 数据库

用法: install.sh {install|uninstall|status|help}

  install    安装并启动（Linux: 发行版仓库；macOS: brew）
  uninstall  卸载（/var/lib/mysql 数据默认保留，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：Deb 系 root 走 auth_socket（sudo mysql 直登）；RHEL 系首次 root
临时密码在 /var/log/mysqld.log；装完建议跑 mysql_secure_installation。
需要 MariaDB 的用户可直接用系统仓库 mariadb-server，本模块不做封装。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
