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
    if uxs_svc list-unit-files mysql.service 2>/dev/null | grep -q "^mysql"; then
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
        yes_no "$(_tf 'MySQL %s detected, reinstall?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing MySQL via Homebrew...')"
        pkg_install mysql || { error "brew $(_t 'Installation failed')"; exit 1; }
        info "$(_t 'Start it: brew services start mysql (the first root login has no password)')"
    else
        info "$(_t 'Installing MySQL from the system repositories...')"
        pkg_update || true
        # RHEL 系 AppStream 为 mysql-server；Deb 系 Ubuntu 为 mysql-server、
        # Debian 为 default-mysql-server，逐个回退
        pkg_install mysql-server 2>/dev/null \
            || pkg_install default-mysql-server 2>/dev/null \
            || { error "MySQL $(_t 'Installation failed (the package is missing from the system repositories, the RHEL family needs AppStream)')"; exit 1; }
        local svc
        svc=$(svc_name)
        uxs_svc enable-now "$svc" || warn "$(_tf 'Failed to start the service, start it manually: sudo systemctl enable --now %s' "$svc")"
        success "MySQL $(_t 'Installation complete')"
        if [[ -f /var/log/mysqld.log ]]; then
            local tp
            tp=$(grep -m1 'temporary password' /var/log/mysqld.log 2>/dev/null | awk '{print $NF}' || true)
            [[ -n "$tp" ]] && warn "RHEL $(_tf 'The temporary root password is: %s (change it right after you log in)' "${tp}")"
        fi
        info "Deb $(_t 'On the Deb family the root account uses auth_socket (log in directly with sudo mysql); run mysql_secure_installation soon')"
    fi
    info "$(_t 'Check the status: ./install.sh mysql status')"
}

do_uninstall() {
    preflight
    if ! command_exists mysql; then
        warn "MySQL $(_t 'Not installed')"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of MySQL?')" || { info "$(_t 'Cancelled')"; exit 0; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop mysql 2>/dev/null || true
        brew uninstall mysql 2>/dev/null || true
        success "MySQL $(_t 'Uninstalled')"
    else
        local svc
        svc=$(svc_name)
        uxs_svc stop "$svc" 2>/dev/null || true
        pkg_remove mysql-server 2>/dev/null || pkg_remove default-mysql-server 2>/dev/null \
            || warn "$(_t 'Package manager uninstall failed, check the package name manually')"
        success "MySQL $(_t 'Uninstalled')"
    fi
    if [[ -d /var/lib/mysql ]]; then
        if yes_no "$(_t 'Delete the database data /var/lib/mysql (all databases and tables, irreversible)?')"; then
            sudo rm -rf /var/lib/mysql && success "$(_t 'Data deleted')"
        else
            info "$(_t 'Keeping the data')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists mysql; then
        emit_status "not_installed" "$(_t '❌ MySQL not installed')"
        return 0
    fi
    local ver
    ver=$(mysql --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "linux" ]]; then
        local svc
        svc=$(svc_name)
        if uxs_svc is-active "$svc" 2>/dev/null; then
            emit_status "installed:running" "$(_t '✅ MySQL installed and the service is running') ${ver:-$(_t '(unknown version)')}"
        else
            emit_status "installed:stopped" "$(_t '⚠️ MySQL installed but the service is not running') ${ver:-$(_t '(unknown version)')}"
        fi
    else
        emit_status "installed" "$(_t '✅ MySQL installed') ${ver:-$(_t '(unknown version)')}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
MySQL $(_t 'Database')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install and start (Linux: distro repositories; macOS: brew)')
  uninstall  $(_t 'Uninstall (the /var/lib/mysql data is kept by default, deletion needs a second confirmation)')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: on the Deb family the root account uses auth_socket (log in directly with sudo mysql); on the RHEL family the first root')
$(_t 'temporary password is in /var/log/mysqld.log; run mysql_secure_installation after the install.')
$(_t 'Users who need MariaDB can install mariadb-server from the system repositories, this module does not wrap it.')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
