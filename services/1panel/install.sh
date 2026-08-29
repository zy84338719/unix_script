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
        error "1Panel 仅支持 Linux。当前：${OS_TYPE}"
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
    command_exists 1pctl 2>/dev/null
}

install_1panel() {
    preflight
    require_sudo

    if is_installed; then
        warn "检测到 1Panel 已安装（$(1pctl version 2>/dev/null || echo 未知版本)）"
        if ! yes_no "是否继续并重装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    local tmp
    tmp=$(mktemp /tmp/1panel_quick_start.XXXXXX.sh)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN

    info "下载官方安装脚本（${ONEPANEL_SCRIPT_URL}）..."
    fetch_to "$ONEPANEL_SCRIPT_URL" "$tmp"

    info "执行官方安装脚本（如已设置 PANEL_* 环境变量则按其非交互安装）..."
    sudo bash "$tmp"

    echo
    if is_installed; then
        success "🎉 1Panel 安装完成！"
        info "查看面板地址/安全入口/账号：sudo 1pctl user-info"
        info "常用命令：1pctl status | 1pctl restart | 1pctl update"
    else
        warn "安装脚本已执行，但未检测到 1pctl——请检查上方输出确认安装结果。"
    fi
}

info_1panel() {
    preflight
    if ! is_installed; then
        error "1Panel 未安装。"
        exit 1
    fi
    sudo 1pctl user-info
}

update_1panel() {
    preflight
    if ! is_installed; then
        error "1Panel 未安装。"
        exit 1
    fi
    sudo 1pctl update
}

uninstall_1panel() {
    preflight
    require_sudo
    if ! is_installed; then
        warn "1Panel 未安装，无需卸载。"
        return 0
    fi
    warn "卸载不会删除面板数据目录（默认 /opt/1panel），站点与镜像数据将保留。"
    if ! yes_no "确认卸载 1Panel？"; then
        info "已取消"; return 0
    fi
    sudo 1pctl uninstall || warn "1pctl uninstall 失败，请手动检查。"
    success "1Panel 已卸载。"
}

status_1panel() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    if ! is_installed; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"; return
    fi
    local ver
    ver=$(1pctl version 2>/dev/null | head -n1 || true)
    if [[ -n "${ver}" ]]; then
        emit_version "${ver}"
    fi
    if systemctl is-active --quiet 1panel 2>/dev/null; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装（服务未运行）${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|info|update|uninstall|status|help}

  install     安装 1Panel（官方 v2 脚本，交互/透传 PANEL_* 非交互，仅 Linux）
  info        查看面板地址、安全入口与账号（1pctl user-info）
  update      升级 1Panel（1pctl update）
  uninstall   卸载 1Panel（保留数据目录）
  status      查看状态
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
        *) error "未知操作: ${action}"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
