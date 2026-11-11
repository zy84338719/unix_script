#!/usr/bin/env bash
#
# webmin/install.sh
#
# 安装与管理 Webmin —— 经典 Web 系统管理面板（用户/服务/文件/防火墙/计划任务等）。
# 仅 Linux（依赖 systemd）。通过官方 APT/YUM 仓库安装（download.webmin.com，国内可达）。
# Web UI：https://<IP>:10000，用系统 root 账号登录。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

readonly WEBMIN_KEY_URL="https://download.webmin.com/developers-key.asc"
readonly WEBMIN_APT_BASE="https://download.webmin.com/download/newkey/repository"
readonly WEBMIN_YUM_BASE="https://download.webmin.com/download/newkey/yum"
readonly WEBMIN_KEYRING="/usr/share/keyrings/webmin-developers.gpg"
readonly WEBMIN_RPM_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-webmin-developers"
readonly WEBMIN_PORT=10000

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_tf 'Webmin is Linux-only. Current: %s' "$OS_TYPE")"
        exit 1
    fi
    if ! os_has_cmd systemctl; then
        error "$(_t 'systemctl (systemd) is required.')"
        exit 1
    fi
}

fetch_to() {
    local url="$1" out="$2"
    if os_has_cmd curl; then
        curl -fsSL "$url" -o "$out"
    elif os_has_cmd wget; then
        wget -qO "$out" "$url"
    else
        error "$(_t 'Either curl or wget is required; please install one of them first.')"
        return 1
    fi
}

is_installed() {
    [[ -d /etc/webmin ]]
}

setup_repo_deb() {
    if ! os_has_cmd gpg; then
        info "$(_t 'Installing gnupg (needed to import the repository signing key)...')"
        pkg_install gnupg
    fi
    local tmp
    tmp=$(mktemp /tmp/webmin-key.XXXXXX.asc)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN
    info "$(_t 'Importing the Webmin official signing key...')"
    fetch_to "${WEBMIN_KEY_URL}" "$tmp"
    sudo gpg --dearmor --yes -o "${WEBMIN_KEYRING}" "$tmp"
    sudo chmod 644 "${WEBMIN_KEYRING}"
    echo "deb [signed-by=${WEBMIN_KEYRING}] ${WEBMIN_APT_BASE} stable contrib" \
        | sudo tee /etc/apt/sources.list.d/webmin-stable.list >/dev/null
    info "$(_t 'Refreshing the apt index...')"
    pkg_update
    info "$(_t 'Installing webmin (with the recommended dependencies)...')"
    sudo apt-get install -y --install-recommends webmin
}

setup_repo_rhel() {
    local repo_dir="/etc/yum.repos.d"
    if [[ "${DISTRO_FAMILY:-}" == "suse" ]]; then
        repo_dir="/etc/zypp/repos.d"
    fi
    info "$(_t 'Importing the Webmin official signing key...')"
    sudo mkdir -p /etc/pki/rpm-gpg
    fetch_to "${WEBMIN_KEY_URL}" "/tmp/webmin-dev-key.asc"
    sudo mv /tmp/webmin-dev-key.asc "${WEBMIN_RPM_KEY}"
    sudo chmod 644 "${WEBMIN_RPM_KEY}"
    sudo rpm --import "${WEBMIN_RPM_KEY}" 2>/dev/null || true
    info "$(_tf 'Writing the repository file %s/webmin-stable.repo ...' "$repo_dir")"
    printf '[webmin-stable]\nname=Webmin Stable\nbaseurl=%s\nenabled=1\ngpgkey=file://%s\ngpgcheck=1\n' \
        "${WEBMIN_YUM_BASE}" "${WEBMIN_RPM_KEY}" \
        | sudo tee "${repo_dir}/webmin-stable.repo" >/dev/null
    info "$(_t 'Installing webmin...')"
    pkg_install webmin
}

allow_firewall() {
    if os_has_cmd firewall-cmd; then
        sudo firewall-cmd --add-port="${WEBMIN_PORT}/tcp" --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        success "$(_tf 'Allowed firewalld %s/tcp' "$WEBMIN_PORT")"
    fi
    if os_has_cmd ufw; then
        sudo ufw allow "${WEBMIN_PORT}"/tcp 2>/dev/null || true
        success "$(_tf 'Allowed ufw %s/tcp' "$WEBMIN_PORT")"
    fi
}

install_webmin() {
    preflight
    require_sudo
    detect_pkg_manager
    detect_distro

    if is_installed; then
        warn "$(_t 'Detected Webmin installed')"
        if ! yes_no "$(_t 'Continue and reinstall/update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    info "🚀 $(_tf 'Configuring the Webmin official repository (package manager: %s)' "$PKG_MANAGER")"
    if [[ "${DISTRO_FAMILY:-}" == "debian" ]]; then
        setup_repo_deb
    else
        setup_repo_rhel
    fi

    if ! is_installed; then
        error "$(_t 'Install failed: /etc/webmin not found; check the output above.')"
        exit 1
    fi

    allow_firewall
    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "🎉 $(_t 'Webmin installation complete!')"
    info "$(_tf 'Access URL: https://%s:%s' "$ip_addr" "$WEBMIN_PORT")"
    warn "$(_t 'Log in with the system root account and the root password (the browser warning about the self-signed certificate can be ignored).')"
}

uninstall_webmin() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! is_installed; then
        warn "$(_t 'Webmin is not installed, nothing to uninstall.')"
        return 0
    fi
    if ! yes_no "$(_t 'Confirm uninstall of Webmin (including the /etc/webmin configuration)?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    uxs_svc stop webmin 2>/dev/null || true
    pkg_remove webmin 2>/dev/null || warn "$(_t 'Failed to remove the webmin package, uninstall it manually')"
    sudo rm -f /etc/apt/sources.list.d/webmin-stable.list \
        /etc/yum.repos.d/webmin-stable.repo /etc/zypp/repos.d/webmin-stable.repo \
        "${WEBMIN_KEYRING}" "${WEBMIN_RPM_KEY}"
    if yes_no "$(_t 'Delete the /etc/webmin configuration directory (it holds the panel accounts and certificates)?')"; then
        sudo rm -rf /etc/webmin
    fi
    success "$(_t 'Webmin uninstalled.')"
}

status_webmin() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        uxs_emit_status "n/a" "${YELLOW}⚠️  $(_t 'Not applicable (Linux only)')${NC}"; return
    fi
    if ! is_installed; then
        uxs_emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"; return
    fi
    local ver port
    ver=$(cat /etc/webmin/version 2>/dev/null || true)
    if [[ -n "${ver}" ]]; then
        uxs_emit_version "${ver}"
    fi
    if uxs_svc is-active webmin 2>/dev/null; then
        uxs_emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC}"
    else
        uxs_emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed (service not running)')${NC}"
    fi
    port=$(grep -E '^port=' /etc/webmin/miniserv.conf 2>/dev/null | cut -d= -f2 || true)
    if [[ -n "${port}" ]]; then
        uxs_emit_extra "port=${port}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Webmin from the official repository (web management panel, Linux only, default port 10000)')
  uninstall   $(_t 'Uninstall Webmin')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_webmin ;;
        uninstall) uninstall_webmin ;;
        status)    status_webmin ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
