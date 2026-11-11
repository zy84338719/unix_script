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
    if os_has_cmd mariadb; then
        local cur
        cur=$(mariadb --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "$(_tf 'MariaDB %s detected, reinstall?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    if os_has_cmd mysql && ! os_has_cmd mariadb; then
        warn "$(_t 'MySQL detected: MariaDB listens on the same port 3306, running both on one machine conflicts')"
        yes_no "$(_t 'Continue installing MariaDB anyway?')" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing MariaDB via Homebrew...')"
        pkg_install mariadb || { error "brew $(_t 'Installation failed')"; exit 1; }
        info "$(_t 'Start it: brew services start mariadb (the first root login has no password)')"
    else
        info "$(_t 'Installing MariaDB from the system repositories...')"
        pkg_update || true
        pkg_install mariadb-server || { error "MariaDB $(_t 'Installation failed (is the package missing from the system repositories?)')"; exit 1; }
        uxs_svc enable-now mariadb 2>/dev/null || uxs_svc enable-now mysql 2>/dev/null \
            || warn "$(_t 'Failed to start the service, start it manually: sudo systemctl enable --now mariadb')"
        success "MariaDB $(_t 'Installation complete')"
        info "$(_t 'Run this soon: mariadb-secure-installation')"
    fi
    info "$(_t 'Check the status: ./install.sh mariadb status')"
}

do_uninstall() {
    preflight
    if ! os_has_cmd mariadb; then
        warn "MariaDB $(_t 'Not installed')"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of MariaDB?')" || { info "$(_t 'Cancelled')"; exit 0; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop mariadb 2>/dev/null || true
        brew uninstall mariadb 2>/dev/null || true
        success "MariaDB $(_t 'Uninstalled')"
    else
        uxs_svc stop mariadb 2>/dev/null || true
        pkg_remove mariadb-server || { error "$(_t 'Uninstall failed')"; exit 1; }
        success "MariaDB $(_t 'Uninstalled')"
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
    if ! os_has_cmd mariadb; then
        uxs_emit_status "not_installed" "$(_t '❌ MariaDB not installed')"
        return 0
    fi
    local ver
    ver=$(mariadb --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc is-active mariadb 2>/dev/null || uxs_svc is-active mysql 2>/dev/null; then
            uxs_emit_status "installed:running" "$(_t '✅ MariaDB installed and the service is running') ${ver:-$(_t '(unknown version)')}"
        else
            uxs_emit_status "installed:stopped" "$(_t '⚠️ MariaDB installed but the service is not running') ${ver:-$(_t '(unknown version)')}"
        fi
    else
        uxs_emit_status "installed" "$(_t '✅ MariaDB installed') ${ver:-$(_t '(unknown version)')}"
    fi
    uxs_emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
MariaDB $(_t 'Database (the MySQL compatible branch)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install and start (Linux: system repositories; macOS: brew)')
  uninstall  $(_t 'Uninstall (the /var/lib/mysql data is kept by default, deletion needs a second confirmation)')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: it shares port 3306 with MySQL, change the port to run both on one machine; run this after the install')
mariadb-secure-installation$(_t '. For MySQL 8 use ./install.sh mysql.')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
