#!/usr/bin/env bash
#
# redis/install.sh
#
# 安装与管理 Redis 内存数据库。
#   - Linux (apt): 安装 redis-server，启用 systemd 服务
#   - Linux (dnf/yum): 安装 redis，启用 systemd 服务
#   - macOS: 通过 Homebrew 安装 redis，brew services 启动
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REDIS_PORT=6379

preflight() {
    detect_os
}

# 根据包管理器返回包名和 systemd 服务名
redis_pkg_name() {
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "redis-server" ;;
        *)       echo "redis" ;;
    esac
}

redis_service_name() {
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "redis-server" ;;
        *)       echo "redis" ;;
    esac
}

redis_config_path() {
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "/usr/local/etc/redis.conf"
    else
        case "$PKG_MANAGER" in
            apt-get) echo "/etc/redis/redis.conf" ;;
            *)       echo "/etc/redis.conf" ;;
        esac
    fi
}

install_redis() {
    preflight
    info "安装 Redis（内存数据库，默认端口 $REDIS_PORT）"

    if command_exists redis-cli; then
        local cur
        cur=$(redis-cli --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 Redis（$cur）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    local pkg
    pkg=$(redis_pkg_name)

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 redis..."
        pkg_install redis
        info "启动 Redis 服务..."
        brew services start redis
    else
        require_sudo
        info "通过 $PKG_MANAGER 安装 $pkg..."
        pkg_update
        pkg_install "$pkg"

        local svc
        svc=$(redis_service_name)
        info "启用并启动 $svc 服务..."
        sudo systemctl enable --now "$svc"
    fi

    # 验证安装
    if ! command_exists redis-cli; then
        error "安装后仍找不到 redis-cli，请检查 PATH"
        exit 1
    fi

    # 验证服务是否运行
    sleep 1
    local pong
    pong=$(redis-cli ping 2>/dev/null || echo "")
    if [[ "$pong" == "PONG" ]]; then
        success "Redis 安装完成，服务运行正常"
    else
        warn "Redis 已安装，但 redis-cli ping 未返回 PONG，服务可能还在启动中"
    fi

    echo
    local cfg
    cfg=$(redis_config_path)
    info "安装摘要："
    echo "  端口：$REDIS_PORT"
    echo "  配置文件：$cfg"
    echo "  连接测试：redis-cli ping"
    echo
    info "常用命令："
    echo "  redis-cli                    # 进入交互式命令行"
    echo "  redis-cli ping               # 测试连接"
    echo "  redis-cli info               # 查看服务器信息"
    echo "  redis-cli shutdown           # 停止服务（需密码时用 -a <password>）"
}

uninstall_redis() {
    preflight
    if ! command_exists redis-cli && ! pkg_installed "$(redis_pkg_name)" 2>/dev/null; then
        warn "Redis 未安装"; return 0
    fi

    if ! yes_no "确认卸载 Redis？"; then
        info "已取消"; return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop redis 2>/dev/null || true
        brew uninstall redis 2>/dev/null || true
        success "Redis 已卸载（macOS）"
    else
        require_sudo
        local svc
        svc=$(redis_service_name)
        sudo systemctl stop "$svc" 2>/dev/null || true
        sudo systemctl disable "$svc" 2>/dev/null || true
        local pkg
        pkg=$(redis_pkg_name)
        pkg_remove "$pkg"
        success "Redis 已卸载"
    fi
}

status_redis() {
    if ! command_exists redis-cli; then
        echo -e "${RED}❌ 未安装${NC}"; return
    fi

    local ver
    ver=$(redis-cli --version 2>/dev/null || echo "未知版本")
    local running=false

    if [[ "$OS_TYPE" == "linux" ]]; then
        local svc
        svc=$(redis_service_name)
        systemctl is-active --quiet "$svc" 2>/dev/null && running=true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        pgrep -x redis-server >/dev/null 2>&1 && running=true
    fi

    if $running; then
        echo -e "${GREEN}✅ 已安装并运行${NC} ($ver, 端口 $REDIS_PORT)"
    else
        echo -e "${YELLOW}⚠️  已安装但服务未运行${NC} ($ver)"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install      安装 Redis（内存数据库，默认端口 $REDIS_PORT）
  uninstall    卸载 Redis
  status       查看安装与运行状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)    install_redis ;;
        uninstall)  uninstall_redis ;;
        status)     status_redis ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
