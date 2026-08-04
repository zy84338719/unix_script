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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PG_PORT=5432
PG_BREW_VERSION="postgresql@16"

preflight() {
    detect_os
}

# 根据包管理器返回要安装的包名
pg_pkg_names() {
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "postgresql postgresql-contrib" ;;
        brew)    echo "$PG_BREW_VERSION" ;;
        *)       echo "postgresql-server postgresql-contrib" ;;
    esac
}

pg_service_name() {
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    case "$PKG_MANAGER" in
        apt-get) echo "postgresql" ;;
        brew)    echo "$PG_BREW_VERSION" ;;
        *)       echo "postgresql" ;;
    esac
}

pg_config_dir() {
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "$(brew --prefix)/var/postgres"
    else
        case "$PKG_MANAGER" in
            apt-get)
                # 尝试获取主版本号
                local ver
                ver=$(pg_config --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
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
    info "安装 PostgreSQL（关系型数据库，默认端口 $PG_PORT）"

    if command_exists psql; then
        local cur
        cur=$(psql --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 PostgreSQL（$cur）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    local pkgs_str
    pkgs_str=$(pg_pkg_names)
    local -a pkgs
    read -ra pkgs <<< "$pkgs_str"

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 $PG_BREW_VERSION..."
        # 若已有旧版本 postgresql，先 unlink 避免冲突
        brew unlink postgresql 2>/dev/null || true
        pkg_install "${pkgs[@]}"
        brew link --force "$PG_BREW_VERSION" 2>/dev/null || true
        info "启动 PostgreSQL 服务..."
        brew services start "$PG_BREW_VERSION"
    else
        require_sudo
        info "通过 $PKG_MANAGER 安装 ${pkgs[*]}..."
        pkg_update
        pkg_install "${pkgs[@]}"

        detect_pkg_manager
        case "$PKG_MANAGER" in
            dnf|yum)
                # RHEL 系需要手动初始化数据库
                if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
                    info "初始化数据库（postgresql-setup --initdb）..."
                    sudo postgresql-setup --initdb
                fi
                ;;
        esac

        info "启用并启动 postgresql 服务..."
        sudo systemctl enable --now postgresql
    fi

    # 验证安装
    if ! command_exists psql; then
        error "安装后仍找不到 psql，请检查 PATH"
        exit 1
    fi

    # 验证服务是否运行
    sleep 1
    if pg_isready -q 2>/dev/null; then
        success "PostgreSQL 安装完成，服务运行正常"
    else
        warn "PostgreSQL 已安装，但 pg_isready 未就绪，服务可能还在启动中"
    fi

    echo
    local cfg
    cfg=$(pg_config_dir)
    info "安装摘要："
    echo "  端口：$PG_PORT"
    echo "  配置目录：$cfg"
    echo "  连接测试：pg_isready"
    echo
    info "快速开始："
    echo "  # Linux: 使用 postgres 系统用户登录"
    echo "  sudo -u postgres psql"
    echo
    echo "  # 创建用户和数据库"
    echo "  sudo -u postgres createuser --interactive"
    echo "  sudo -u postgres createdb <数据库名>"
    echo
    echo "  # macOS: 直接用当前用户连接（brew 安装时已创建）"
    echo "  psql postgres"
    echo
    echo "  # 远程连接需编辑 pg_hba.conf 允许对应 IP/用户"
}

uninstall_postgres() {
    preflight
    if ! command_exists psql && ! pkg_installed "$(pg_pkg_names | awk '{print $1}')" 2>/dev/null; then
        warn "PostgreSQL 未安装"; return 0
    fi

    warn "卸载 PostgreSQL 将移除软件包。"
    warn "数据库数据目录可能保留，需手动清理。"
    if ! yes_no "确认卸载 PostgreSQL？"; then
        info "已取消"; return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        brew services stop "$PG_BREW_VERSION" 2>/dev/null || true
        brew services stop postgresql 2>/dev/null || true
        brew uninstall "$PG_BREW_VERSION" 2>/dev/null || true
        brew uninstall postgresql 2>/dev/null || true
        success "PostgreSQL 已卸载（macOS）"
    else
        require_sudo
        sudo systemctl stop postgresql 2>/dev/null || true
        sudo systemctl disable postgresql 2>/dev/null || true
        local pkgs_str
        pkgs_str=$(pg_pkg_names)
        local -a pkgs
        read -ra pkgs <<< "$pkgs_str"
        pkg_remove "${pkgs[@]}"
        success "PostgreSQL 已卸载"
    fi

    warn "如需删除数据库数据，请手动清理："
    if [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  rm -rf /usr/local/var/postgres"
    else
        echo "  sudo rm -rf /var/lib/pgsql/data        # dnf/yum"
        echo "  sudo rm -rf /var/lib/postgresql          # apt"
    fi
}

status_postgres() {
    if ! command_exists psql; then
        echo -e "${RED}❌ 未安装${NC}"; return
    fi

    local ver
    ver=$(psql --version 2>/dev/null || echo "未知版本")
    local running=false

    if pg_isready -q 2>/dev/null; then
        running=true
    fi

    if $running; then
        echo -e "${GREEN}✅ 已安装并运行${NC} ($ver, 端口 $PG_PORT)"
    else
        echo -e "${YELLOW}⚠️  已安装但服务未运行${NC} ($ver)"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install      安装 PostgreSQL（关系型数据库，默认端口 $PG_PORT）
  uninstall    卸载 PostgreSQL（提示是否保留数据目录）
  status       查看安装与运行状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
