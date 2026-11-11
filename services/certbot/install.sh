#!/usr/bin/env bash
#
# certbot/install.sh
#
# 安装与管理 Certbot（Let's Encrypt 证书自动化工具）。
#   - Linux: 通过 apt/dnf/yum 安装，可选安装 nginx 插件，检查续期定时器
#   - macOS: 通过 Homebrew 安装，可选配置 cron 续期
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
}

do_install() {
    preflight
    require_sudo
    detect_pkg_manager

    if command_exists certbot; then
        local cur
        cur=$(certbot --version 2>&1 || printf '%s' "$(_t 'Unknown version')")
        warn "$(_t 'Detected Certbot installed (')${cur}$(_t ')')"
        if ! yes_no "$(_t 'Continue and try to update?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi

    info "$(_t 'Installing Certbot (package manager: ')${PKG_MANAGER}$(_t ')...')"
    if ! pkg_install certbot; then
        error "$(_t 'Certbot install failed (package manager: ')${PKG_MANAGER}$(_t ')')"
        exit 1
    fi

    if ! command_exists certbot; then
        error "$(_t 'Install failed: certbot command not found')"
        exit 1
    fi

    # apt 系统建议安装 nginx 插件
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        if command_exists nginx && ! dpkg -s python3-certbot-nginx >/dev/null 2>&1; then
            info "$(_t 'Nginx detected, installing the certbot nginx plugin for automatic SSL is recommended.')"
            if yes_no "$(_t 'Install python3-certbot-nginx?')"; then
                pkg_install python3-certbot-nginx || warn "$(_t 'python3-certbot-nginx install failed, install it manually')"
            fi
        fi
    fi

    # Linux: 检查续期定时器
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "$(_t 'Checking certificate auto-renewal...')"
        if uxs_svc is-active certbot.timer 2>/dev/null; then
            success "$(_t 'certbot.timer is active, certificates will auto-renew')"
        elif uxs_svc list-unit-files certbot.timer >/dev/null 2>&1; then
            info "$(_t 'certbot.timer exists but is not enabled, enabling...')"
            uxs_svc enable-now certbot.timer 2>/dev/null || warn "$(_t 'Failed to enable certbot.timer')"
        elif uxs_svc is-active certbot-renew.timer 2>/dev/null; then
            success "$(_t 'certbot-renew.timer is active, certificates will auto-renew')"
        else
            warn "$(_t 'No certbot renewal timer detected.')"
            info "$(_t 'Manually test renewal: certbot renew --dry-run')"
            info "$(_t 'Setting up cron or a systemd timer for auto-renewal is recommended.')"
        fi
    fi

    # macOS: 建议配置 cron 续期
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'On macOS, setting up a cron job for certificate auto-renewal is recommended.')"
        info "$(_t 'Example (attempt renewal daily at 2 AM):')"
        echo "  0 2 * * * certbot renew --quiet"
        echo
        if yes_no "$(_t 'Check if a certbot renewal task already exists in the current crontab?')"; then
            if crontab -l 2>/dev/null | grep -q certbot; then
                success "$(_t 'A certbot renewal task already exists in crontab')"
                crontab -l 2>/dev/null | grep certbot
            else
                warn "$(_t 'No certbot renewal task found in crontab')"
                if yes_no "$(_t 'Add a certbot renew cron job (daily at 2 AM)?')"; then
                    (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet") | crontab -
                    success "$(_t 'cron renewal task added')"
                fi
            fi
        fi
    fi

    echo
    success "$(_t 'Certbot installation complete!')"
    info "$(_t 'Version: ')$(certbot --version 2>&1)"
    echo
    info "$(_t 'Common commands:')"
    echo "  # $(_t 'Nginx plugin mode (auto-modifies nginx config)')"
    echo "  sudo certbot --nginx -d example.com -d www.example.com"
    echo
    echo "  # $(_t 'Standalone mode (temporarily listens on port 80, stop nginx first)')"
    echo "  sudo certbot certonly --standalone -d example.com"
    echo
    echo "  # $(_t 'Webroot mode (works with existing web server)')"
    echo "  sudo certbot certonly --webroot -w /var/www/html -d example.com"
    echo
    echo "  # $(_t 'Manual renewal test')"
    echo "  sudo certbot renew --dry-run"
    echo
    echo "  # $(_t 'View issued certificates')"
    echo "  sudo certbot certificates"
    echo
    echo "  # $(_t 'Revoke certificate')"
    echo "  sudo certbot revoke --cert-name example.com"
    echo
    info "$(_t 'Certificate storage location:')"
    echo "  /etc/letsencrypt/live/<domain>/  # $(_t 'certificate files')"
    echo "    fullchain.pem  # $(_t 'full certificate chain')"
    echo "    privkey.pem    # $(_t 'private key')"
    echo "    cert.pem       # $(_t 'server certificate')"
    echo "    chain.pem      # $(_t 'intermediate certificate')"
}

do_uninstall() {
    preflight
    require_sudo
    detect_pkg_manager

    if ! yes_no "$(_t 'Confirm uninstall of Certbot?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    # 移除软件包
    pkg_remove certbot 2>/dev/null || warn "$(_t 'Failed to remove certbot package, uninstall it manually')"
    # 同时移除可能安装的 nginx 插件
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        pkg_remove python3-certbot-nginx 2>/dev/null || true
    fi

    # 移除 cron 任务
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if crontab -l 2>/dev/null | grep -q certbot; then
            if yes_no "$(_t 'Remove the certbot renewal task from crontab?')"; then
                crontab -l 2>/dev/null | grep -v certbot | crontab -
                success "$(_t 'certbot cron task removed')"
            fi
        fi
    fi

    # 询问是否删除证书
    if [[ -d /etc/letsencrypt ]]; then
        warn "$(_t 'Existing certificates are stored in /etc/letsencrypt/')"
        if yes_no "$(_t 'Delete all certificates and configuration (/etc/letsencrypt)? This is irreversible!')"; then
            sudo rm -rf /etc/letsencrypt
            success "$(_t 'Certificate directory deleted.')"
        else
            info "$(_t 'Certificate directory kept: /etc/letsencrypt')"
            info "$(_t 'To delete manually: sudo rm -rf /etc/letsencrypt')"
        fi
    fi

    success "$(_t 'Certbot uninstalled.')"
}

do_status() {
    detect_os
    if ! command_exists certbot; then
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"
        return
    fi

    local ver
    ver=$(certbot --version 2>&1 || echo "")

    # 检查续期定时器
    local renewal_status="" autorenew=""
    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc is-active certbot.timer 2>/dev/null; then
            renewal_status="$(_t 'Renewal timer running')"
            autorenew="enabled"
        elif uxs_svc is-active certbot-renew.timer 2>/dev/null; then
            renewal_status="$(_t 'Renewal timer running')"
            autorenew="enabled"
        else
            renewal_status="$(_t 'No renewal timer detected')"
            autorenew="disabled"
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if crontab -l 2>/dev/null | grep -q "certbot renew"; then
            renewal_status="$(_t 'cron renewal task configured')"
            autorenew="enabled"
        else
            renewal_status="$(_t 'Auto-renewal not configured')"
            autorenew="disabled"
        fi
    fi

    emit_status "installed" "${GREEN}✅ $(_t 'Installed')${NC} ($ver)"
    emit_version "$ver"
    if [[ -n "$renewal_status" ]]; then
        emit_extra "autorenew=$autorenew"
        if ! uxs_is_machine_mode; then
            echo "  $(_t 'Auto-renewal: ')$renewal_status"
        fi
    fi

    # 显示已有证书数量
    if [[ -d /etc/letsencrypt/live ]]; then
        local cert_count
        cert_count=$(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$cert_count" -gt 0 ]]; then
            emit_extra "certs=$cert_count"
            if ! uxs_is_machine_mode; then
                echo "  $(_tf 'Certificates issued: %s' "${cert_count}")"
            fi
        fi
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Certbot and configure auto-renewal')
  uninstall   $(_t 'Uninstall Certbot (optionally delete certificates)')
  status      $(_t 'View install and renewal status')
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
