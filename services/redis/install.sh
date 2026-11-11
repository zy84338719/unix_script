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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REDIS_PORT=6379

preflight() {
    detect_os
}

# 根据包管理器返回包名和 systemd 服务名
redis_pkg_name() {
    detect_pkg_manager || { error "$(_t 'Unable to detect the package manager')"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "redis-server" ;;
        *)       echo "redis" ;;
    esac
}

redis_service_name() {
    detect_pkg_manager || { error "$(_t 'Unable to detect the package manager')"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "redis-server" ;;
        *)       echo "redis" ;;
    esac
}

redis_config_path() {
    detect_pkg_manager || { error "$(_t 'Unable to detect the package manager')"; return 1; }
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
    info "$(_tf 'Installing Redis (in-memory database, default port %s)' "$REDIS_PORT")"

    if command_exists redis-cli; then
        local cur
        cur=$(redis-cli --version 2>/dev/null || printf '%s\n' "$(_t 'installed')")
        warn "$(_tf 'Detected Redis installed (%s)' "$cur")"
        if ! yes_no "$(_t 'Continue and reinstall or update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    local pkg
    pkg=$(redis_pkg_name)

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing redis via Homebrew...')"
        pkg_install redis
        info "$(_t 'Starting the Redis service...')"
        brew services start redis
    else
        require_sudo
        info "$(_tf 'Using %s to install %s ...' "$PKG_MANAGER" "$pkg")"
        pkg_update
        pkg_install "$pkg"

        local svc
        svc=$(redis_service_name)
        info "$(_tf 'Enabling and starting the %s service...' "$svc")"
        uxs_svc enable-now "$svc"
    fi

    # 验证安装
    if ! command_exists redis-cli; then
        error "$(_t 'redis-cli still not found after the install; check PATH')"
        exit 1
    fi

    # 验证服务是否运行
    sleep 1
    local pong
    pong=$(redis-cli ping 2>/dev/null || echo "")
    if [[ "$pong" == "PONG" ]]; then
        success "$(_t 'Redis installation complete, the service is running normally')"
    else
        warn "$(_t 'Redis is installed, but redis-cli ping did not return PONG; the service may still be starting')"
    fi

    echo
    local cfg
    cfg=$(redis_config_path)
    info "$(_t 'Installation summary:')"
    printf '%s\n' "$(_tf '  Port: %s' "$REDIS_PORT")"
    printf '%s\n' "$(_tf '  Config file: %s' "$cfg")"
    printf '%s\n' "$(_t '  Connection test: redis-cli ping')"
    echo
    info "$(_t 'Common commands:')"
    printf '%s\n' "$(_t '  redis-cli                    # Enter the interactive command line')"
    printf '%s\n' "$(_t '  redis-cli ping               # Test the connection')"
    printf '%s\n' "$(_t '  redis-cli info               # Show the server info')"
    printf '%s\n' "$(_t '  redis-cli shutdown           # Stop the service (use -a <password> when a password is set)')"
}

uninstall_redis() {
    preflight
    if ! command_exists redis-cli && ! pkg_installed "$(redis_pkg_name)" 2>/dev/null; then
        warn "$(_t 'Redis not installed')"; return 0
    fi

    if ! yes_no "$(_t 'Confirm uninstall of Redis?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop redis 2>/dev/null || true
        brew uninstall redis 2>/dev/null || true
        success "$(_t 'Redis uninstalled (macOS)')"
    else
        require_sudo
        local svc
        svc=$(redis_service_name)
        uxs_svc stop "$svc" 2>/dev/null || true
        uxs_svc disable "$svc" 2>/dev/null || true
        local pkg
        pkg=$(redis_pkg_name)
        pkg_remove "$pkg"
        success "$(_t 'Redis uninstalled')"
    fi
}

status_redis() {
    if ! command_exists redis-cli; then
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"; return
    fi

    local ver
    ver=$(redis-cli --version 2>/dev/null || printf '%s\n' "$(_t 'Unknown version')")
    local running=false

    if [[ "$OS_TYPE" == "linux" ]]; then
        local svc
        svc=$(redis_service_name)
        uxs_svc is-active "$svc" 2>/dev/null && running=true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        pgrep -x redis-server >/dev/null 2>&1 && running=true
    fi

    if $running; then
        emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC} $(_tf '(%s, port %s)' "$ver" "$REDIS_PORT")"
        emit_extra "port=$REDIS_PORT"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed but service not running')${NC} ($ver)"
    fi
    emit_version "$ver"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install      $(_tf 'Install Redis (in-memory database, default port %s)' "$REDIS_PORT")
  uninstall    $(_t 'Uninstall Redis')
  status       $(_t 'View install and run status')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
