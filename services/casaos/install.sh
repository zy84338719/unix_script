#!/usr/bin/env bash
#
# casaos/install.sh
#
# 安装与管理 CasaOS —— 开源家庭云/NAS 轻量面板（Docker 应用商店、文件管理）。
# 仅 Linux（依赖 systemd）。官方脚本安装（get.casaos.io）。
#
# 用法: $0 {install|uninstall|status|help}
#
# 注意：CasaOS Web UI 默认占用 80 端口，与 nginx/caddy 等冲突；本模块安装前
# 会探测 80 端口并在占用时要求二次确认。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

readonly CASAOS_INSTALL_URL="https://get.casaos.io"
readonly CASAOS_UNINSTALL_URL="https://get.casaos.io/uninstall"
CASAOS_PORT=80

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_t 'CasaOS is Linux-only. Current: ')${OS_TYPE}"
        exit 1
    fi
    if ! os_has_cmd systemctl; then
        error "$(_t 'systemctl (systemd) is required.')"
        exit 1
    fi
}

is_installed() {
    os_has_cmd casaos 2>/dev/null || [[ -d /var/lib/casaos ]]
}

# bash 内建 /dev/tcp 探测端口占用，无外部依赖（子 shell 内开 fd，退出即关）
port_in_use() {
    (exec 3<>"/dev/tcp/127.0.0.1/${1}") 2>/dev/null || return 1
    return 0
}

fetch_to() {
    local url="$1" out="$2"
    if os_has_cmd curl; then
        curl -fsSL "$url" -o "$out"
    elif os_has_cmd wget; then
        wget -qO "$out" "$url"
    else
        error "$(_t 'Either curl or wget is required, please install one first.')"
        return 1
    fi
}

install_casaos() {
    preflight
    require_sudo

    if is_installed; then
        warn "$(_t 'Detected CasaOS installed')"
        if ! yes_no "$(_t 'Continue and reinstall/update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    if port_in_use "${CASAOS_PORT}"; then
        warn "$(_t 'Port 80 is already in use (nginx/caddy/other Web services), CasaOS uses port 80 by default, which may conflict.')"
        if ! yes_no "$(_t 'Still continue installing?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    local tmp
    tmp=$(mktemp /tmp/casaos_install.XXXXXX.sh)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN

    info "$(_t 'Downloading official installer (')${CASAOS_INSTALL_URL}$(_t ')...')"
    fetch_to "${CASAOS_INSTALL_URL}" "$tmp"
    info "$(_t 'Running official installer (installs Docker dependencies, takes several minutes)...')"
    sudo bash "$tmp"

    echo
    if is_installed; then
        success "$(_t 'CasaOS installation complete!')"
        local ip_addr
        ip_addr=$(get_local_ip)
        info "$(_tf 'Access URL: http://%s:%s (create local admin account on first visit)' "${ip_addr}" "${CASAOS_PORT}")"
        warn "$(_t 'If port 80 is occupied by another Web service, change it in CasaOS settings.')"
    else
        warn "$(_t 'Installer ran but casaos was not detected — check the output above to confirm the result.')"
    fi
}

uninstall_casaos() {
    preflight
    require_sudo
    if ! is_installed; then
        warn "$(_t 'CasaOS is not installed, nothing to uninstall.')"
        return 0
    fi
    warn "$(_t 'The official uninstall script will stop and remove all casaos services; created apps (Docker containers) and data are kept by default.')"
    if ! yes_no "$(_t 'Confirm uninstall of CasaOS?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    local tmp
    tmp=$(mktemp /tmp/casaos_uninstall.XXXXXX.sh)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN
    fetch_to "${CASAOS_UNINSTALL_URL}" "$tmp"
    sudo bash "$tmp"
    success "$(_t 'CasaOS uninstalled.')"
}

status_casaos() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        uxs_emit_status "n/a" "${YELLOW}⚠️  $(_t 'Not applicable (Linux only)')${NC}"; return
    fi
    if ! is_installed; then
        uxs_emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"; return
    fi
    if uxs_svc is-active casaos 2>/dev/null; then
        uxs_emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC}"
        uxs_emit_extra "port=${CASAOS_PORT}"
    else
        uxs_emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed (service not running)')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install CasaOS (home cloud/NAS panel, default port 80, Linux only)')
  uninstall   $(_t 'Uninstall CasaOS (Docker apps and data kept)')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_casaos ;;
        uninstall) uninstall_casaos ;;
        status)    status_casaos ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "${action}")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
