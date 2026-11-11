#!/usr/bin/env bash
#
# incus/install.sh
#
# 安装 Incus —— 系统容器与虚拟化管理（LXD 社区分支，Linux Containers 项目）。
# 仅 Linux：Deb 系走 Zabbly 稳定仓（官方维护打包）；RHEL 系走发行版/EPEL 包。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    detect_distro
    detect_arch
    check_commands curl
}

setup_zabbly_repo() {
    curl -fsSL "https://pkgs.zabbly.com/key.asc" | sudo gpg --dearmor -o /usr/share/keyrings/zabbly.asc
    echo "deb [signed-by=/usr/share/keyrings/zabbly.asc] https://pkgs.zabbly.com/incus/stable $(. /etc/os-release && echo "${VERSION_CODENAME:-}") main" \
        | sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.list >/dev/null
}

do_install() {
    preflight
    if command_exists incus; then
        local cur
        cur=$(incus --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "$(_tf 'Incus %s detected, reinstall?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        info "$(_t 'Configuring the Zabbly stable repository and installing Incus...')"
        pkg_install gnupg 2>/dev/null || true
        setup_zabbly_repo
        pkg_update || true
        pkg_install incus || { error "incus $(_t 'Installation failed (is that codename missing from the Zabbly repository?)')"; exit 1; }
    elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
        info "$(_t 'Installing Incus from the system repositories...')"
        pkg_update || true
        pkg_install incus || { error "incus $(_t 'Installation failed (the EPEL or openEuler repository is required)')"; exit 1; }
    else
        error "$(_tf 'Only the Deb and RHEL families are supported (current: %s)' "${DISTRO_FAMILY:-unknown}")"
        exit 1
    fi
    uxs_svc enable-now incus || warn "$(_t 'Failed to start the service, start it manually: sudo systemctl enable --now incus')"
    success "Incus $(_t 'Installation complete')"
    info "$(_t 'Initialize it (interactive): sudo incus admin init')"
    info "$(_tf 'Add the user to the incus-admin group to run without sudo: sudo usermod -aG incus-admin %s' "$USER")"
}

do_uninstall() {
    preflight
    if ! command_exists incus; then
        warn "Incus $(_t 'Not installed')"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of Incus?')" || { info "$(_t 'Cancelled')"; exit 0; }
    uxs_svc stop incus 2>/dev/null || true
    pkg_remove incus || warn "$(_t 'Package manager uninstall failed, please check it manually')"
    sudo rm -f /etc/apt/sources.list.d/zabbly-incus-stable.list
    success "Incus $(_t 'Uninstalled')"
    if [[ -d /var/lib/incus ]]; then
        if yes_no "$(_t 'Delete the Incus data /var/lib/incus (containers/VMs/images, irreversible)?')"; then
            sudo rm -rf /var/lib/incus && success "$(_t 'Data deleted')"
        else
            info "$(_t 'Keeping the data')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists incus; then
        emit_status "not_installed" "$(_t '❌ Incus not installed')"
        return 0
    fi
    local ver
    ver=$(incus --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if uxs_svc is-active incus 2>/dev/null; then
        emit_status "installed:running" "$(_t '✅ Incus installed and the service is running') ${ver:-$(_t '(unknown version)')}"
    else
        emit_status "installed:stopped" "$(_t '⚠️ Incus installed but the service is not running') ${ver:-$(_t '(unknown version)')}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
Incus $(_t '— System container and virtual machine management (the LXD community branch, Linux only)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install and start the service (Deb family: Zabbly stable repo; RHEL family: distro/EPEL packages)')
  uninstall  $(_t 'Uninstall (the /var/lib/incus data is kept by default, deletion needs a second confirmation)')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: run sudo incus admin init after the install to set up storage/network;')
lxd $(_t 'it is the equivalent of the command; the images: remote mirror is available.')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
