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
        error "CasaOS 仅支持 Linux。当前：${OS_TYPE}"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "需要 systemctl（systemd）。"
        exit 1
    fi
}

is_installed() {
    command_exists casaos 2>/dev/null || [[ -d /var/lib/casaos ]]
}

# bash 内建 /dev/tcp 探测端口占用，无外部依赖（子 shell 内开 fd，退出即关）
port_in_use() {
    (exec 3<>"/dev/tcp/127.0.0.1/${1}") 2>/dev/null || return 1
    return 0
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

install_casaos() {
    preflight
    require_sudo

    if is_installed; then
        warn "检测到 CasaOS 已安装"
        if ! yes_no "是否继续并重装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    if port_in_use "${CASAOS_PORT}"; then
        warn "80 端口已被占用（nginx/caddy/其他 Web 服务），CasaOS 默认使用 80 端口，可能冲突。"
        if ! yes_no "仍要继续安装？"; then
            info "已取消"; return 0
        fi
    fi

    local tmp
    tmp=$(mktemp /tmp/casaos_install.XXXXXX.sh)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN

    info "下载官方安装脚本（${CASAOS_INSTALL_URL}）..."
    fetch_to "${CASAOS_INSTALL_URL}" "$tmp"
    info "执行官方安装脚本（会安装 Docker 相关依赖，耗时数分钟）..."
    sudo bash "$tmp"

    echo
    if is_installed; then
        success "🎉 CasaOS 安装完成！"
        local ip_addr
        ip_addr=$(get_local_ip)
        info "访问地址：http://${ip_addr}:${CASAOS_PORT}（首次访问创建本地管理员账号）"
        warn "若 80 端口被其他 Web 服务占用，请在 CasaOS 设置中修改端口。"
    else
        warn "安装脚本已执行，但未检测到 casaos——请检查上方输出确认安装结果。"
    fi
}

uninstall_casaos() {
    preflight
    require_sudo
    if ! is_installed; then
        warn "CasaOS 未安装，无需卸载。"
        return 0
    fi
    warn "官方卸载脚本会停止并移除 casaos 全家桶服务；已创建的应用（Docker 容器）与数据默认保留。"
    if ! yes_no "确认卸载 CasaOS？"; then
        info "已取消"; return 0
    fi
    local tmp
    tmp=$(mktemp /tmp/casaos_uninstall.XXXXXX.sh)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN
    fetch_to "${CASAOS_UNINSTALL_URL}" "$tmp"
    sudo bash "$tmp"
    success "CasaOS 已卸载。"
}

status_casaos() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    if ! is_installed; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"; return
    fi
    if systemctl is-active --quiet casaos 2>/dev/null; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"
        emit_extra "port=${CASAOS_PORT}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装（服务未运行）${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 CasaOS（家庭云/NAS 面板，默认 80 端口，仅 Linux）
  uninstall   卸载 CasaOS（Docker 应用与数据保留）
  status      查看状态
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
        *) error "未知操作: ${action}"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
