#!/usr/bin/env bash
#
# nginx/install.sh
#
# 安装与管理 Nginx Web 服务器。
#   - Linux: 通过 apt/dnf/yum 安装，启用 systemd 服务
#   - macOS: 通过 Homebrew 安装，使用 brew services 或 launchd 管理
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 配置路径（macOS brew 与 Linux 不同）
nginx_conf_dir() {
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        echo "$(brew --prefix)/etc/nginx"
    else
        echo "/etc/nginx"
    fi
}

# macOS launchd plist 路径
NGINX_PLIST="/Library/LaunchDaemons/homebrew.mxcl.nginx.plist"

preflight() {
    detect_os
    check_commands curl
}

do_install() {
    preflight
    require_sudo

    if command_exists nginx; then
        local cur
        cur=$(nginx -v 2>&1 || echo "未知版本")
        warn "检测到已安装 Nginx（$cur）"
        if ! yes_no "是否继续并尝试更新？"; then
            info "已取消"
            return 0
        fi
    fi

    detect_pkg_manager
    info "安装 Nginx（包管理器：$PKG_MANAGER）..."
    if ! pkg_install nginx; then
        error "Nginx 安装失败（包管理器：$PKG_MANAGER）"
        exit 1
    fi

    if ! command_exists nginx; then
        error "安装失败：找不到 nginx 命令"
        exit 1
    fi

    # 启动服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "启用并启动 Nginx 服务..."
        sudo systemctl enable --now nginx
        if systemctl is-active --quiet nginx; then
            success "Nginx 服务已启动"
        else
            warn "Nginx 服务未正常启动，请检查日志："
            echo "  sudo systemctl status nginx"
            echo "  sudo journalctl -u nginx -f"
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            info "通过 brew services 启动 Nginx..."
            sudo brew services start nginx 2>/dev/null || brew services start nginx
            success "Nginx 已通过 brew services 启动"
        else
            warn "未检测到 brew，请手动启动 Nginx 或配置 launchd。"
        fi
    fi

    local conf_dir
    conf_dir=$(nginx_conf_dir)

    echo
    success "Nginx 安装完成！"
    info "版本：$(nginx -v 2>&1)"
    echo
    info "配置文件目录："
    echo "  $conf_dir/"
    echo "  $conf_dir/nginx.conf        # 主配置"
    echo "  $conf_dir/conf.d/           # 虚拟主机配置"
    echo
    info "默认站点："
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  http://$(get_local_ip)       # 默认欢迎页"
        echo "  /var/www/html/               # 默认网站根目录"
    else
        echo "  http://localhost:8080        # macOS brew 默认端口"
    fi
    echo
    info "常用命令："
    echo "  sudo nginx -t                     # 测试配置语法"
    echo "  sudo nginx -s reload              # 重载配置（不中断连接）"
    echo "  sudo nginx -s stop                # 停止服务"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status nginx       # 查看服务状态"
        echo "  sudo systemctl restart nginx      # 重启服务"
        echo "  sudo tail -f /var/log/nginx/error.log  # 查看错误日志"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  sudo brew services restart nginx  # 重启服务"
        echo "  sudo brew services stop nginx     # 停止服务"
    fi
}

do_uninstall() {
    preflight
    require_sudo
    detect_pkg_manager

    if ! yes_no "确认卸载 Nginx？"; then
        info "已取消"
        return 0
    fi

    # 停止服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl disable --now nginx 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            sudo brew services stop nginx 2>/dev/null || brew services stop nginx 2>/dev/null || true
        fi
        service_stop "nginx" "$NGINX_PLIST" 2>/dev/null || true
    fi

    # 移除软件包
    pkg_remove nginx 2>/dev/null || warn "nginx 包移除失败，请手动卸载"

    # 询问是否删除配置文件
    local conf_dir
    conf_dir=$(nginx_conf_dir)
    if [[ -d "$conf_dir" ]]; then
        if yes_no "是否删除配置文件目录 $conf_dir？（站点配置和证书链接也会被删除）"; then
            sudo rm -rf "$conf_dir"
            success "配置目录 $conf_dir 已删除。"
        else
            info "配置目录已保留：$conf_dir"
        fi
    fi

    # 询问是否删除默认网站目录
    if [[ "$OS_TYPE" == "linux" && -d /var/www/html ]]; then
        if yes_no "是否删除默认网站目录 /var/www/html？"; then
            sudo rm -rf /var/www/html
            success "/var/www/html 已删除。"
        fi
    fi

    success "Nginx 已卸载。"
}

do_status() {
    detect_os
    if ! command_exists nginx; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
        return
    fi

    local ver
    ver=$(nginx -v 2>&1 || echo "")
    local active=false

    if [[ "$OS_TYPE" == "linux" ]]; then
        if systemctl is-active --quiet nginx 2>/dev/null; then
            active=true
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if service_is_active "nginx" "nginx" 2>/dev/null; then
            active=true
        fi
    fi

    if $active; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC} ($ver)"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装但服务未运行${NC} ($ver)"
    fi
    emit_version "$ver"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Nginx 并启动服务
  uninstall   卸载 Nginx（可选删除配置文件）
  status      查看安装与运行状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)    do_install ;;
        uninstall)  do_uninstall ;;
        status)     do_status ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
