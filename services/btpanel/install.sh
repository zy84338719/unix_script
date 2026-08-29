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
        error "宝塔面板仅支持 Linux。当前：${OS_TYPE}"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "需要 systemctl（systemd）。"
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
        error "需要 curl 或 wget 之一，请先安装。"
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
        warn "检测到既有 Web/数据库环境在运行：${hit}"
        warn "宝塔官方要求在纯净系统上安装（会自建 Nginx/Apache/MySQL/PHP，易端口冲突）。"
        if ! yes_no "仍要继续安装宝塔面板？"; then
            info "已取消"; return 1
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

    info "下载官方安装脚本（${script_url}）..."
    fetch_to "$script_url" "$tmp"
    chmod +x "$tmp"

    info "执行官方安装脚本（耗时约 2 分钟）..."
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
        warn "检测到宝塔面板已安装"
        if ! yes_no "是否继续并重装/更新？"; then
            info "已取消"; return 0
        fi
    fi
    check_purity || return 0

    run_bt_installer "${BT_SCRIPT_URL}" "${BT_CHANNEL_CODE}"

    echo
    if is_installed; then
        success "🎉 宝塔面板安装完成！"
        info "查看面板地址/安全入口/默认密码：sudo bt default"
        warn "请务必放行面板端口（默认 8888，实际以 bt default 输出为准）后访问。"
    else
        warn "安装脚本已执行，但未检测到 bt——请检查上方输出确认安装结果。"
    fi
}

# 安装国际版 aaPanel（英文界面，与国内版同为 /www/server/panel）
install_aapanel() {
    preflight
    require_sudo

    if is_installed; then
        warn "检测到宝塔/aaPanel 已安装，两者不能共存。"
        if ! yes_no "是否继续并重装？"; then
            info "已取消"; return 0
        fi
    fi
    check_purity || return 0

    run_bt_installer "${AAPANEL_SCRIPT_URL}" "aapanel"

    echo
    if is_installed; then
        success "🎉 aaPanel 安装完成！"
        info "查看面板地址/入口/默认密码：sudo bt default"
    else
        warn "安装脚本已执行，但未检测到 bt——请检查上方输出确认安装结果。"
    fi
}

info_btpanel() {
    preflight
    if ! is_installed; then
        error "宝塔面板未安装。"
        exit 1
    fi
    sudo bt default
}

uninstall_btpanel() {
    preflight
    require_sudo
    if ! is_installed; then
        warn "宝塔面板未安装，无需卸载。"
        return 0
    fi
    warn "将停止面板并删除：/etc/init.d/bt、bt 命令、/www/server/panel（面板与软件环境）。"
    warn "站点数据 /www/wwwroot、日志 /www/wwwlogs 与数据库目录默认保留。"
    if ! yes_no "确认卸载宝塔面板？"; then
        info "已取消"; return 0
    fi
    sudo /etc/init.d/bt stop 2>/dev/null || true
    sudo rm -f /etc/init.d/bt /usr/bin/bt
    sudo rm -rf /www/server/panel
    if yes_no "是否连站点/数据库数据一并删除（rm -rf /www，不可恢复）？"; then
        sudo rm -rf /www
        warn "已删除 /www 全部数据。"
    fi
    success "宝塔面板已卸载。"
}

status_btpanel() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    if ! is_installed; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"; return
    fi
    # 面板主进程 BT-Panel；无特权即可探测，init 脚本作兜底（需 sudo -n 免密）
    if pgrep -f "BT-Panel" >/dev/null 2>&1 || sudo -n /etc/init.d/bt status >/dev/null 2>&1; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装（服务未运行）${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|en|info|uninstall|status|help}

  install     安装宝塔面板（国内版，download.bt.cn 官方脚本，仅 Linux）
  en          安装国际版 aaPanel（英文界面）
  info        查看面板地址/安全入口/默认密码（bt default）
  uninstall   卸载面板（站点数据默认保留，二次确认后可选删除 /www）
  status      查看状态
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
        *) error "未知操作: ${action}"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
