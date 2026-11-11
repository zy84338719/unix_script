#!/usr/bin/env bash
#
# btpanel/install.sh
#
# 安装与管理 宝塔面板（BT Panel）——国内主流 Linux 运维面板。
# install 装国内版（download.bt.cn）；en 装 国际版 aaPanel（aapanel.com）。
# 仅 Linux。默认端口 8888（官方会随机化端口与安全入口，用 `bt default` 查询）。
#
# 用法: $0 {install|en|info|uninstall|status|help}
#
# 注意：宝塔官方要求在「纯净系统」上安装（无既有 Apache/Nginx/MySQL/PHP 环境），
# 本模块安装前会自动检测并在命中时要求二次确认。
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

readonly BT_SCRIPT_URL="https://download.bt.cn/install/install_lts.sh"
readonly BT_CHANNEL_CODE="ed8484bec"
readonly AAPANEL_SCRIPT_URL="https://www.aapanel.com/script/install_7.0_en.sh"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_t 'BT Panel is Linux-only. Current: ')${OS_TYPE}"
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
    [[ -f /etc/init.d/bt ]] || command_exists bt 2>/dev/null
}

# 宝塔官方建议纯净系统：命中常见 Web/DB 环境则提示并要求确认
check_purity() {
    local hit=""
    local proc
    for proc in nginx httpd apache2 mysqld mariadbd php-fpm; do
        if pgrep -x "${proc}" >/dev/null 2>&1; then
            hit="${hit}${proc} "
        fi
    done
    if [[ -n "${hit}" ]]; then
        warn "$(_t 'Detected existing Web/database environment running: ')${hit}"
        warn "$(_t 'BT Panel officially requires a clean system (it installs its own Nginx/Apache/MySQL/PHP, which may conflict with existing services).')"
        if ! yes_no "$(_t 'Still continue installing BT Panel?')"; then
            info "$(_t 'Cancelled')"; return 1
        fi
    fi
    return 0
}

run_bt_installer() {
    local script_url="$1" script_arg="$2"
    local tmp
    tmp=$(mktemp /tmp/bt_install.XXXXXX.sh)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN

    info "$(_t 'Downloading official installer (')${script_url}$(_t ')...')"
    fetch_to "$script_url" "$tmp"
    chmod +x "$tmp"

    info "$(_t 'Running official installer (takes about 2 minutes)...')"
    if [[ -t 0 ]]; then
        sudo bash "$tmp" "${script_arg}"
    else
        echo y | sudo bash "$tmp" "${script_arg}"
    fi
}

install_btpanel() {
    preflight
    require_sudo

    if is_installed; then
        warn "$(_t 'Detected BT Panel installed')"
        if ! yes_no "$(_t 'Continue and reinstall/update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi
    check_purity || return 0

    run_bt_installer "${BT_SCRIPT_URL}" "${BT_CHANNEL_CODE}"

    echo
    if is_installed; then
        success "$(_t 'Party popper BT Panel installation complete!')"
        info "$(_t 'View panel address/security entry/default password: sudo bt default')"
        warn "$(_t 'Make sure to open the panel port (default 8888, check bt default output) before accessing.')"
    else
        warn "$(_t 'Installer ran but bt was not detected — check the output above to confirm the result.')"
    fi
}

# 安装国际版 aaPanel（英文界面，与国内版同为 /www/server/panel）
install_aapanel() {
    preflight
    require_sudo

    if is_installed; then
        warn "$(_t 'Detected BT Panel/aaPanel installed, they cannot coexist.')"
        if ! yes_no "$(_t 'Continue and reinstall?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi
    check_purity || return 0

    run_bt_installer "${AAPANEL_SCRIPT_URL}" "aapanel"

    echo
    if is_installed; then
        success "$(_t 'Party popper aaPanel installation complete!')"
        info "$(_t 'View panel address/entry/default password: sudo bt default')"
    else
        warn "$(_t 'Installer ran but bt was not detected — check the output above to confirm the result.')"
    fi
}

info_btpanel() {
    preflight
    if ! is_installed; then
        error "$(_t 'BT Panel is not installed.')"
        exit 1
    fi
    sudo bt default
}

uninstall_btpanel() {
    preflight
    require_sudo
    if ! is_installed; then
        warn "$(_t 'BT Panel is not installed, nothing to uninstall.')"
        return 0
    fi
    warn "$(_t 'Will stop the panel and delete: /etc/init.d/bt, bt command, /www/server/panel (panel and software environment).')"
    warn "$(_t 'Site data /www/wwwroot, logs /www/wwwlogs and database directories are kept by default.')"
    if ! yes_no "$(_t 'Confirm uninstall of BT Panel?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    sudo /etc/init.d/bt stop 2>/dev/null || true
    sudo rm -f /etc/init.d/bt /usr/bin/bt
    sudo rm -rf /www/server/panel
    if yes_no "$(_t 'Also delete site/database data (rm -rf /www, irreversible)?')"; then
        sudo rm -rf /www
        warn "$(_t 'All data in /www has been deleted.')"
    fi
    success "$(_t 'BT Panel uninstalled.')"
}

status_btpanel() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  $(_t 'Not applicable (Linux only)')${NC}"; return
    fi
    if ! is_installed; then
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"; return
    fi
    # 面板主进程 BT-Panel；无特权即可探测，init 脚本作兜底（需 sudo -n 免密）
    if pgrep -f "BT-Panel" >/dev/null 2>&1 || sudo -n /etc/init.d/bt status >/dev/null 2>&1; then
        emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed (service not running)')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|en|info|uninstall|status|help}

  install     $(_t 'Install BT Panel (domestic version, download.bt.cn official script, Linux only)')
  en          $(_t 'Install international version aaPanel (English UI)')
  info        $(_t 'View panel address/security entry/default password (bt default)')
  uninstall   $(_t 'Uninstall panel (site data kept by default, /www can be deleted after second confirmation)')
  status      $(_t 'View status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_btpanel ;;
        en)        install_aapanel ;;
        info)      info_btpanel ;;
        uninstall) uninstall_btpanel ;;
        status)    status_btpanel ;;
        help|--help|-h) usage ;;
        *) error "$(_t 'Unknown action: ')${action}"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
