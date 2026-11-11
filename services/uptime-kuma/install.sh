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
        error "$(_t 'Docker not detected. Install Docker first (you can use the docker module of this project).')"
        exit 1
    fi
}

install_uptime_kuma() {
    preflight
    require_sudo
    info "$(_t '🚀 Starting the Uptime Kuma installation (Docker deployment)')"

    # 检查是否已存在同名容器
    if sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        warn "$(_tf 'Existing container %s detected' "$CONTAINER_NAME")"
        if ! yes_no "$(_t 'Stop and delete the old container, then deploy again?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
        sudo docker rm -f "$CONTAINER_NAME" >/dev/null
    fi

    info "$(_tf 'Pulling the image %s ...' "$IMAGE")"
    if ! sudo docker pull "$IMAGE"; then
        error "$(_t 'Image pull failed, check Docker and the network')"
        exit 1
    fi

    info "$(_t 'Creating and starting the container...')"
    sudo docker run -d \
        --restart=always \
        --name "$CONTAINER_NAME" \
        -p "${WEB_PORT}:3001" \
        -v "${DATA_VOLUME}":/app/data \
        "$IMAGE" >/dev/null

    info "$(_t 'Verifying...')"
    sleep 4
    if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        success "Uptime Kuma $(_t 'The container is running normally')"
    else
        error "$(_tf 'The container is not running normally, check the logs: sudo docker logs %s' "$CONTAINER_NAME")"
        exit 1
    fi

    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "$(_t '🎉 Uptime Kuma installation complete!')"
    info "$(_tf 'Access URL: http://%s:%s' "${ip_addr}" "${WEB_PORT}")"
    info "$(_t 'The first visit needs an administrator account.')"
    echo
    info "$(_t 'Common commands:')"
    echo "  sudo docker ps | grep $CONTAINER_NAME"
    echo "  sudo docker logs -f $CONTAINER_NAME"
    echo "  sudo docker restart $CONTAINER_NAME"
}

uninstall_uptime_kuma() {
    preflight
    require_sudo
    if ! yes_no "$(_t 'Confirm uninstall of Uptime Kuma?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    sudo docker rmi "$IMAGE" 2>/dev/null || true
    if yes_no "$(_tf 'Delete the data volume %s too (the monitoring history will be lost)?' "${DATA_VOLUME}")"; then
        sudo docker volume rm "$DATA_VOLUME" 2>/dev/null || true
        success "$(_t 'Data volume deleted')"
    fi
    success "Uptime Kuma $(_t 'Uninstalled.')"
}

status_uptime_kuma() {
    detect_os
    if ! command_exists docker; then
        emit_status "not_installed" "${RED}$(_t '❌ Not installed (Docker required)')${NC}"; return
    fi
    # docker CLI 走 socket 无需 sudo；status 查询绝不弹密码
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC}"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"; then
        emit_status "installed:stopped" "${YELLOW}$(_t '⚠️  The container was created but is not running')${NC}"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_tf 'Deploy Uptime Kuma via Docker (monitoring dashboard, default port %s)' "${WEB_PORT}")
  uninstall   $(_t 'Uninstall Uptime Kuma (container and image)')
  status      $(_t 'View status')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
