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
            error "$(_t 'Distribution codename') ${codename:-$(_t 'Unknown')} $(_tf 'is not in the MongoDB %s supported list (jammy/noble/bookworm/trixie)' "${MONGO_SERIES}")"
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
        yes_no "$(_tf 'MongoDB %s detected, reinstall?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        info "$(_tf 'Configuring the MongoDB %s APT repository (TUNA mirror)...' "${MONGO_SERIES}")"
        setup_apt_repo || exit 1
    elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
        info "$(_tf 'Configuring the MongoDB %s YUM repository (TUNA mirror)...' "${MONGO_SERIES}")"
        setup_yum_repo
    else
        error "$(_tf 'Only the Deb and RHEL families are supported (current: %s)' "${DISTRO_FAMILY:-unknown}")"
        exit 1
    fi
    pkg_update || true
    pkg_install mongodb-org || { error "mongodb-org $(_t 'Installation failed')"; exit 1; }
    uxs_svc enable-now mongod || warn "$(_t 'Failed to start the service, start it manually: sudo systemctl enable --now mongod')"
    success "MongoDB ${MONGO_SERIES} $(_t 'Installation complete. Connect with: mongosh')"
}

do_uninstall() {
    preflight
    if ! command_exists mongod; then
        warn "MongoDB $(_t 'Not installed')"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of MongoDB?')" || { info "$(_t 'Cancelled')"; exit 0; }
    uxs_svc stop mongod 2>/dev/null || true
    pkg_remove mongodb-org || warn "$(_t 'Package manager uninstall failed, please check it manually')"
    sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list /etc/yum.repos.d/mongodb-org-*.repo
    success "MongoDB $(_t 'Uninstalled')"
    if [[ -d /var/lib/mongodb ]]; then
        if yes_no "$(_t 'Delete the database data /var/lib/mongodb (irreversible)?')"; then
            sudo rm -rf /var/lib/mongodb && success "$(_t 'Data deleted')"
        else
            info "$(_t 'Keeping the data')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists mongod; then
        emit_status "not_installed" "$(_t '❌ MongoDB not installed')"
        return 0
    fi
    local ver
    ver=$(mongod --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' | head -1 || true)
    if uxs_svc is-active mongod 2>/dev/null; then
        emit_status "installed:running" "$(_t '✅ MongoDB installed and the service is running') ${ver:-$(_t '(unknown version)')}"
    else
        emit_status "installed:stopped" "$(_t '⚠️ MongoDB installed but the service is not running') ${ver:-$(_t '(unknown version)')}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<EOF
MongoDB $(_t 'Document database (mongodb-org 8.0, Linux only)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Install mongodb-org with the official GPG key and the TUNA mirror repository, service enable-now')
  uninstall  $(_t 'Uninstall (the /var/lib/mongodb data is kept by default, deletion needs a second confirmation)')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t "Note: the Deb family supports the jammy/noble/bookworm/trixie codenames; the RHEL family uses el\$releasever.")
$(_t 'Client shell: mongosh (installed together with mongodb-org).')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
