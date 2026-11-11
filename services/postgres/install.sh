#!/usr/bin/env bash
#
# postgres/install.sh
#
# 安装与管理 PostgreSQL 数据库。
#   - Linux (apt): 安装 postgresql postgresql-contrib，服务自动创建
#   - Linux (dnf/yum): 安装 postgresql-server postgresql-contrib，需手动 initdb
#   - macOS: 通过 Homebrew 安装 postgresql@16，brew services 启动
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

PG_PORT=5432
PG_BREW_VERSION="postgresql@16"

preflight() {
    detect_os
}

# 根据包管理器返回要安装的包名
pg_pkg_names() {
    detect_pkg_manager || { error "$(_t 'Unable to detect the package manager')"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "postgresql postgresql-contrib" ;;
        brew)    echo "$PG_BREW_VERSION" ;;
        *)       echo "postgresql-server postgresql-contrib" ;;
    esac
}

pg_service_name() {
    detect_pkg_manager || { error "$(_t 'Unable to detect the package manager')"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "postgresql" ;;
        brew)    echo "$PG_BREW_VERSION" ;;
        *)       echo "postgresql" ;;
    esac
}

pg_config_dir() {
    detect_pkg_manager || { error "$(_t 'Unable to detect the package manager')"; return 1; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "$(brew --prefix)/var/postgres"
    else
        case "$PKG_MANAGER" in
            apt-get)
                # 尝试获取主版本号
                local ver
                ver=$(pg_config --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
                if [[ -n "$ver" ]]; then
                    echo "/etc/postgresql/${ver}/main"
                else
                    echo "/etc/postgresql/*/main"
                fi
                ;;
            *) echo "/var/lib/pgsql/data" ;;
        esac
    fi
}

install_postgres() {
    preflight
    info "$(_tf 'Install PostgreSQL (relational database, default port %s)' "${PG_PORT}")"

    if command_exists psql; then
        local cur
        cur=$(psql --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'PostgreSQL detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reinstall or update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    local pkgs_str
    pkgs_str=$(pg_pkg_names)
    local -a pkgs
    read -ra pkgs <<< "$pkgs_str"

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_tf 'Installing %s via Homebrew...' "$PG_BREW_VERSION")"
        # 若已有旧版本 postgresql，先 unlink 避免冲突
        brew unlink postgresql 2>/dev/null || true
        pkg_install "${pkgs[@]}"
        brew link --force "$PG_BREW_VERSION" 2>/dev/null || true
        info "$(_t 'Starting the PostgreSQL service...')"
        brew services start "$PG_BREW_VERSION"
    else
        require_sudo
        info "$(_tf 'Installing %s via %s...' "$PKG_MANAGER" "${pkgs[*]}")"
        pkg_update
        pkg_install "${pkgs[@]}"

        detect_pkg_manager
        case "$PKG_MANAGER" in
            dnf|yum)
                # RHEL 系需要手动初始化数据库
                if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
                    info "$(_t 'Initializing the database (postgresql-setup --initdb)...')"
                    sudo postgresql-setup --initdb
                fi
                ;;
        esac

        info "$(_t 'Enabling and starting the postgresql service...')"
        uxs_svc enable-now postgresql
    fi

    # 验证安装
    if ! command_exists psql; then
        error "$(_t 'psql is still not found after the install, check PATH')"
        exit 1
    fi

    # 验证服务是否运行
    sleep 1
    if pg_isready -q 2>/dev/null; then
        success "PostgreSQL $(_t 'Installation complete, the service is running normally')"
    else
        warn "PostgreSQL $(_t 'Installed, but pg_isready is not ready yet, the service may still be starting')"
    fi

    echo
    local cfg
    cfg=$(pg_config_dir)
    info "$(_t 'Installation summary:')"
    echo "  $(_tf 'Port: %s' "$PG_PORT")"
    echo "  $(_tf 'Configuration directory: %s' "$cfg")"
    echo "  $(_t 'Connection test: pg_isready')"
    echo
    info "$(_t 'Quick start:')"
    echo "  # Linux: $(_t 'Log in with the postgres system user')"
    echo "  sudo -u postgres psql"
    echo
    echo "  # $(_t 'Create a user and a database')"
    echo "  sudo -u postgres createuser --interactive"
    echo "  sudo -u postgres createdb <$(_t 'Database name>')"
    echo
    echo "  # macOS: $(_t 'Connect directly with the current user (brew creates it at install time)')"
    echo "  psql postgres"
    echo
    echo "  # $(_t 'A remote connection needs pg_hba.conf edited to allow the matching IP/user')"
}

uninstall_postgres() {
    preflight
    if ! command_exists psql && ! pkg_installed "$(pg_pkg_names | awk '{print $1}')" 2>/dev/null; then
        warn "PostgreSQL $(_t 'Not installed')"; return 0
    fi

    warn "$(_t 'Uninstalling PostgreSQL removes the package.')"
    warn "$(_t 'The database data directory may be kept, clean it up manually.')"
    if ! yes_no "$(_t 'Confirm uninstall of PostgreSQL?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop "$PG_BREW_VERSION" 2>/dev/null || true
        brew services stop postgresql 2>/dev/null || true
        brew uninstall "$PG_BREW_VERSION" 2>/dev/null || true
        brew uninstall postgresql 2>/dev/null || true
        success "PostgreSQL $(_t 'Uninstalled (macOS)')"
    else
        require_sudo
        uxs_svc stop postgresql 2>/dev/null || true
        uxs_svc disable postgresql 2>/dev/null || true
        local pkgs_str
        pkgs_str=$(pg_pkg_names)
        local -a pkgs
        read -ra pkgs <<< "$pkgs_str"
        pkg_remove "${pkgs[@]}"
        success "PostgreSQL $(_t 'Uninstalled')"
    fi

    warn "$(_t 'To delete the database data, clean it up manually:')"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  rm -rf /usr/local/var/postgres"
    else
        echo "  sudo rm -rf /var/lib/pgsql/data        # dnf/yum"
        echo "  sudo rm -rf /var/lib/postgresql          # apt"
    fi
}

status_postgres() {
    if ! command_exists psql; then
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"; return
    fi

    local ver
    ver=$(psql --version 2>/dev/null || printf '%s\n' "$(_t 'Unknown version')")
    local running=false

    if pg_isready -q 2>/dev/null; then
        running=true
    fi

    if $running; then
        emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC} ($ver, $(_tf 'port %s)' "$PG_PORT")"
        emit_extra "port=$PG_PORT"
    else
        emit_status "installed:stopped" "${YELLOW}$(_t '⚠️  Installed but the service is not running')${NC} ($ver)"
    fi
    emit_version "$ver"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install      $(_tf 'Install PostgreSQL (relational database, default port %s)' "${PG_PORT}")
  uninstall    $(_t 'Uninstall PostgreSQL (it asks whether to keep the data directory)')
  status       $(_t 'View the install and run status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)    install_postgres ;;
        uninstall)  uninstall_postgres ;;
        status)     status_postgres ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
