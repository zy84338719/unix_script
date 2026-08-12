#!/usr/bin/env bash
#
# uptime-kuma/install.sh
#
# 安装与管理 Uptime Kuma —— 自托管的服务/网站可用性监控面板。
# 通过 Docker 容器部署。需要先安装 Docker。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

CONTAINER_NAME="uptime-kuma"
IMAGE="louislam/uptime-kuma:1"
DATA_VOLUME="uptime-kuma-data"
WEB_PORT=3001

preflight() {
    detect_os
    if ! command_exists docker; then
        error "未检测到 Docker。请先安装 Docker（可使用本项目的 docker 模块）。"
        exit 1
    fi
}

install_uptime_kuma() {
    preflight
    require_sudo
    info "🚀 开始安装 Uptime Kuma（Docker 部署）"

    # 检查是否已存在同名容器
    if sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        warn "检测到已存在容器 $CONTAINER_NAME"
        if ! yes_no "是否停止并删除旧容器后重新部署？"; then
            info "已取消"; return 0
        fi
        sudo docker rm -f "$CONTAINER_NAME" >/dev/null
    fi

    info "拉取镜像 $IMAGE ..."
    if ! sudo docker pull "$IMAGE"; then
        error "镜像拉取失败，请检查 Docker 与网络"
        exit 1
    fi

    info "创建并启动容器..."
    sudo docker run -d \
        --restart=always \
        --name "$CONTAINER_NAME" \
        -p "${WEB_PORT}:3001" \
        -v "${DATA_VOLUME}":/app/data \
        "$IMAGE" >/dev/null

    info "验证..."
    sleep 4
    if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        success "Uptime Kuma 容器运行正常"
    else
        error "容器未正常运行，查看日志：sudo docker logs $CONTAINER_NAME"
        exit 1
    fi

    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "🎉 Uptime Kuma 安装完成！"
    info "访问地址：http://${ip_addr}:${WEB_PORT}"
    info "首次访问需创建管理员账号。"
    echo
    info "常用命令："
    echo "  sudo docker ps | grep $CONTAINER_NAME"
    echo "  sudo docker logs -f $CONTAINER_NAME"
    echo "  sudo docker restart $CONTAINER_NAME"
}

uninstall_uptime_kuma() {
    preflight
    require_sudo
    if ! yes_no "确认卸载 Uptime Kuma？"; then
        info "已取消"; return 0
    fi
    sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    sudo docker rmi "$IMAGE" 2>/dev/null || true
    if yes_no "是否同时删除数据卷 ${DATA_VOLUME}（监控历史数据将丢失）？"; then
        sudo docker volume rm "$DATA_VOLUME" 2>/dev/null || true
        success "数据卷已删除"
    fi
    success "Uptime Kuma 已卸载。"
}

status_uptime_kuma() {
    detect_os
    if ! command_exists docker; then
        emit_status "not_installed" "${RED}❌ 未安装（需 Docker）${NC}"; return
    fi
    if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"
    elif sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        emit_status "installed:stopped" "${YELLOW}⚠️  容器已创建但未运行${NC}"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     通过 Docker 部署 Uptime Kuma（监控面板，默认端口 ${WEB_PORT}）
  uninstall   卸载 Uptime Kuma（容器与镜像）
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_uptime_kuma ;;
        uninstall) uninstall_uptime_kuma ;;
        status)    status_uptime_kuma ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
