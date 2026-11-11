#!/usr/bin/env bash
#
# 1panel/install.sh
#
# 安装与管理 1Panel —— 新一代 Linux 服务器运维管理面板（FIT2CLOUD 开源，v2）。
# 仅 Linux（依赖 systemd）。Web UI 端口安装时自选/随机，用 `1pctl user-info` 查询。
#
# 用法: $0 {install|info|update|uninstall|status|help}
#
# 非交互安装：透传官方 PANEL_* 环境变量即可（文档
# https://1panel.cn/docs/v2/installation/online_installation/），例：
#   PANEL_NON_INTERACTIVE=true PANEL_LANG=zh PANEL_PORT=18080 \
#   PANEL_USERNAME=admin PANEL_PASSWORD='ChangeMe_123456' \
#   ./install.sh install
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

readonly ONEPANEL_SCRIPT_URL="https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_t '1Panel is Linux-only. Current: ')\${OS_TYPE}"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "$(_t 'systemctl (systemd) is required.')"
        exit 1
    fi
}

fetch_to() {
    local url="$1" out="$2"
    if command_exists curl; then
        curl -fsSL "$url" -o "$out"
    elif command_exists wget; then
        wget -qO "$out" "$url"
    else
        error "$(_t 'Either curl or wget is required, please install one first.')"
        return 1
    fi
}

is_installed() {
    command_exists 1pctl 2>/dev/null
}

install_1panel() {
    preflight
    require_sudo

    if is_installed; then
        warn "$(_t 'Detected 1Panel installed (')$(1pctl version 2>/dev/null || echo "$(_t 'Unknown version')")$(_t ')')"
        if ! yes_no "$(_t 'Continue and reinstall/update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    local tmp
    tmp=$(mktemp /tmp/1panel_quick_start.XXXXXX.sh)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN

    info "$(_t 'Downloading official installer (')\${ONEPANEL_SCRIPT_URL}$(_t ')...')"
    fetch_to "$ONEPANEL_SCRIPT_URL" "$tmp"

    info "$(_t 'Running official installer (non-interactive if PANEL_* env vars are set)...')"
    sudo bash "$tmp"

    echo
    if is_installed; then
        success "$(_t 'Party popper 1Panel installation complete!')"
        info "$(_t 'View panel address/security entry/account: sudo 1pctl user-info')"
        info "$(_t 'Common commands: 1pctl status | 1pctl restart | 1pctl update')"
    else
        warn "$(_t 'Installer ran but 1pctl was not detected — check the output above to confirm the result.')"
    fi
}

info_1panel() {
    preflight
    if ! is_installed; then
        error "$(_t '1Panel is not installed.')"
        exit 1
    fi
    sudo 1pctl user-info
}

update_1panel() {
    preflight
    if ! is_installed; then
        error "$(_t '1Panel is not installed.')"
        exit 1
    fi
    sudo 1pctl update
}

uninstall_1panel() {
    preflight
    require_sudo
    if ! is_installed; then
        warn "$(_t '1Panel is not installed, nothing to uninstall.')"
        return 0
    fi
    warn "$(_t 'Uninstalling does not delete the panel data directory (default /opt/1panel), site and image data will be kept.')"
    if ! yes_no "$(_t 'Confirm uninstall of 1Panel?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    sudo 1pctl uninstall || warn "$(_t '1pctl uninstall failed, please check manually.')"
    success "$(_t '1Panel uninstalled.')"
}

status_1panel() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "\${YELLOW}⚠️  $(_t 'Not applicable (Linux only)')\${NC}"; return
    fi
    if ! is_installed; then
        emit_status "not_installed" "\${RED}❌ $(_t 'Not installed')\${NC}"; return
    fi
    local ver
    ver=$(1pctl version 2>/dev/null | head -n1 || true)
    if [[ -n "${ver}" ]]; then
        emit_version "${ver}"
    fi
    if uxs_svc is-active 1panel 2>/dev/null; then
        emit_status "installed:running" "\${GREEN}✅ $(_t 'Installed and running')\${NC}"
    else
        emit_status "installed:stopped" "\${YELLOW}⚠️  $(_t 'Installed (service not running)')\${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|info|update|uninstall|status|help}

  install     $(_t 'Install 1Panel (official v2 script, interactive/pass PANEL_* for non-interactive, Linux only)')
  info        $(_t 'View panel address, security entry and account (1pctl user-info)')
  update      $(_t 'Upgrade 1Panel (1pctl update)')
  uninstall   $(_t 'Uninstall 1Panel (keep data directory)')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_1panel ;;
        info)      info_1panel ;;
        update)    update_1panel ;;
        uninstall) uninstall_1panel ;;
        status)    status_1panel ;;
        help|--help|-h) usage ;;
        *) error "$(_t 'Unknown action: ')\${action}"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
