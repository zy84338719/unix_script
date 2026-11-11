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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 配置路径（macOS brew 与 Linux 不同）
nginx_conf_dir() {
    if [[ "$OS_TYPE" == "darwin" ]] && os_has_cmd brew; then
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

    if os_has_cmd nginx; then
        local cur
        cur=$(nginx -v 2>&1 || printf '%s\n' "$(_t 'Unknown version')")
        warn "$(_tf 'Nginx detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and try to update?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi

    detect_pkg_manager
    info "$(_tf 'Installing Nginx (package manager: %s)...' "${PKG_MANAGER}")"
    if ! pkg_install nginx; then
        error "Nginx $(_tf 'Installation failed (package manager: %s)' "${PKG_MANAGER}")"
        exit 1
    fi

    if ! os_has_cmd nginx; then
        error "$(_t 'Installation failed: the nginx command was not found')"
        exit 1
    fi

    # 启动服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "$(_t 'Enabling and starting the Nginx service...')"
        uxs_svc enable-now nginx
        if uxs_svc is-active nginx; then
            success "Nginx $(_t 'The service is running')"
        else
            warn "Nginx $(_t 'The service did not start properly, check the logs:')"
            echo "  sudo systemctl status nginx"
            echo "  sudo journalctl -u nginx -f"
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if os_has_cmd brew; then
            info "$(_t 'Starting Nginx through brew services...')"
            sudo brew services start nginx 2>/dev/null || brew services start nginx
            success "Nginx $(_t 'Started through brew services')"
        else
            warn "$(_t 'brew not detected, start Nginx manually or configure launchd.')"
        fi
    fi

    local conf_dir
    conf_dir=$(nginx_conf_dir)

    echo
    success "Nginx $(_t 'Installation complete!')"
    info "$(_t 'Version:')$(nginx -v 2>&1)"
    echo
    info "$(_t 'Configuration directory:')"
    echo "  $conf_dir/"
    echo "  $conf_dir/nginx.conf        # $(_t 'Main configuration')"
    echo "  $conf_dir/conf.d/           # $(_t 'Virtual host configurations')"
    echo
    info "$(_t 'Default site:')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  http://$(get_local_ip)       # $(_t 'Default welcome page')"
        echo "  /var/www/html/               # $(_t 'Default document root')"
    else
        echo "  http://localhost:8080        # macOS brew $(_t 'Default port')"
    fi
    echo
    info "$(_t 'Common commands:')"
    echo "  sudo nginx -t                     # $(_t 'Test the configuration syntax')"
    echo "  sudo nginx -s reload              # $(_t 'Reload the configuration (without dropping the connections)')"
    echo "  sudo nginx -s stop                # $(_t 'Stop the service')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status nginx       # $(_t 'View the service status')"
        echo "  sudo systemctl restart nginx      # $(_t 'Restart the service')"
        echo "  sudo tail -f /var/log/nginx/error.log  # $(_t 'View the error log')"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        echo "  sudo brew services restart nginx  # $(_t 'Restart the service')"
        echo "  sudo brew services stop nginx     # $(_t 'Stop the service')"
    fi
}

do_uninstall() {
    preflight
    require_sudo
    detect_pkg_manager

    if ! yes_no "$(_t 'Confirm uninstall of Nginx?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    # 停止服务
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc disable-now nginx 2>/dev/null || true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if os_has_cmd brew; then
            sudo brew services stop nginx 2>/dev/null || brew services stop nginx 2>/dev/null || true
        fi
        service_stop "nginx" "$NGINX_PLIST" 2>/dev/null || true
    fi

    # 移除软件包
    pkg_remove nginx 2>/dev/null || warn "nginx $(_t 'Package removal failed, uninstall it manually')"

    # 询问是否删除配置文件
    local conf_dir
    conf_dir=$(nginx_conf_dir)
    if [[ -d "$conf_dir" ]]; then
        if yes_no "$(_tf 'Delete the configuration directory %s? (the site configurations and the certificate links are deleted too)' "${conf_dir}")"; then
            sudo rm -rf "$conf_dir"
            success "$(_tf 'Configuration directory %s deleted.' "$conf_dir")"
        else
            info "$(_tf 'Configuration directory kept: %s' "$conf_dir")"
        fi
    fi

    # 询问是否删除默认网站目录
    if [[ "$OS_TYPE" == "linux" && -d /var/www/html ]]; then
        if yes_no "$(_t 'Delete the default website directory /var/www/html?')"; then
            sudo rm -rf /var/www/html
            success "/var/www/html $(_t 'Deleted.')"
        fi
    fi

    success "Nginx $(_t 'Uninstalled.')"
}

do_status() {
    detect_os
    if ! os_has_cmd nginx; then
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
        return
    fi

    local ver
    ver=$(nginx -v 2>&1 || echo "")
    local active=false

    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc is-active nginx 2>/dev/null; then
            active=true
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if service_is_active "nginx" "nginx" 2>/dev/null; then
            active=true
        fi
    fi

    if $active; then
        uxs_emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC} ($ver)"
    else
        uxs_emit_status "installed:stopped" "${YELLOW}$(_t '⚠️ Installed but the service is not running')${NC} ($ver)"
    fi
    uxs_emit_version "$ver"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Nginx and start the service')
  uninstall   $(_t 'Uninstall Nginx (deleting the configuration files is optional)')
  status      $(_t 'View the install and run status')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
