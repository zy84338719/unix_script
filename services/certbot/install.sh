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

set -e

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
        cur=$(certbot --version 2>&1 || echo "未知版本")
        warn "检测到已安装 Certbot（$cur）"
        if ! yes_no "是否继续并尝试更新？"; then
            info "已取消"
            return 0
        fi
    fi

    info "安装 Certbot（包管理器：$PKG_MANAGER）..."
    if ! pkg_install certbot; then
        error "Certbot 安装失败（包管理器：$PKG_MANAGER）"
        exit 1
    fi

    if ! command_exists certbot; then
        error "安装失败：找不到 certbot 命令"
        exit 1
    fi

    # apt 系统建议安装 nginx 插件
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        if command_exists nginx && ! dpkg -s python3-certbot-nginx >/dev/null 2>&1; then
            info "检测到已安装 Nginx，建议安装 certbot nginx 插件以自动配置 SSL。"
            if yes_no "是否安装 python3-certbot-nginx？"; then
                pkg_install python3-certbot-nginx || warn "python3-certbot-nginx 安装失败，可手动安装"
            fi
        fi
    fi

    # Linux: 检查续期定时器
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "检查证书自动续期..."
        if systemctl is-active --quiet certbot.timer 2>/dev/null; then
            success "certbot.timer 已激活，证书将自动续期"
        elif systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
            info "certbot.timer 存在但未启用，正在启用..."
            sudo systemctl enable --now certbot.timer 2>/dev/null || warn "启用 certbot.timer 失败"
        elif systemctl is-active --quiet certbot-renew.timer 2>/dev/null; then
            success "certbot-renew.timer 已激活，证书将自动续期"
        else
            warn "未检测到 certbot 续期定时器。"
            info "可手动测试续期：certbot renew --dry-run"
            info "推荐设置 cron 或 systemd timer 进行自动续期。"
        fi
    fi

    # macOS: 建议配置 cron 续期
    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "macOS 上建议配置 cron 定时任务进行证书自动续期。"
        info "示例（每天凌晨 2 点尝试续期）："
        echo "  0 2 * * * certbot renew --quiet"
        echo
        if yes_no "是否查看当前 crontab 中是否已有 certbot 续期任务？"; then
            if crontab -l 2>/dev/null | grep -q certbot; then
                success "crontab 中已存在 certbot 续期任务"
                crontab -l 2>/dev/null | grep certbot
            else
                warn "crontab 中未找到 certbot 续期任务"
                if yes_no "是否添加 certbot renew cron 任务（每天凌晨 2 点）？"; then
                    (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet") | crontab -
                    success "cron 续期任务已添加"
                fi
            fi
        fi
    fi

    echo
    success "Certbot 安装完成！"
    info "版本：$(certbot --version 2>&1)"
    echo
    info "常用命令："
    echo "  # Nginx 插件模式（自动修改 nginx 配置）"
    echo "  sudo certbot --nginx -d example.com -d www.example.com"
    echo
    echo "  # Standalone 模式（临时监听 80 端口，需先停止 nginx）"
    echo "  sudo certbot certonly --standalone -d example.com"
    echo
    echo "  # Webroot 模式（配合现有 web 服务器）"
    echo "  sudo certbot certonly --webroot -w /var/www/html -d example.com"
    echo
    echo "  # 手动续期测试"
    echo "  sudo certbot renew --dry-run"
    echo
    echo "  # 查看已申请的证书"
    echo "  sudo certbot certificates"
    echo
    echo "  # 撤销证书"
    echo "  sudo certbot revoke --cert-name example.com"
    echo
    info "证书存放位置："
    echo "  /etc/letsencrypt/live/<domain>/  # 证书文件"
    echo "    fullchain.pem  # 完整证书链"
    echo "    privkey.pem    # 私钥"
    echo "    cert.pem       # 服务器证书"
    echo "    chain.pem      # 中间证书"
}

do_uninstall() {
    preflight
    require_sudo
    detect_pkg_manager

    if ! yes_no "确认卸载 Certbot？"; then
        info "已取消"
        return 0
    fi

    # 移除软件包
    pkg_remove certbot 2>/dev/null || warn "certbot 包移除失败，请手动卸载"
    # 同时移除可能安装的 nginx 插件
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        pkg_remove python3-certbot-nginx 2>/dev/null || true
    fi

    # 移除 cron 任务
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if crontab -l 2>/dev/null | grep -q certbot; then
            if yes_no "是否移除 crontab 中的 certbot 续期任务？"; then
                crontab -l 2>/dev/null | grep -v certbot | crontab -
                success "certbot cron 任务已移除"
            fi
        fi
    fi

    # 询问是否删除证书
    if [[ -d /etc/letsencrypt ]]; then
        warn "已有证书存放在 /etc/letsencrypt/"
        if yes_no "是否删除所有证书和配置（/etc/letsencrypt）？此操作不可逆！"; then
            sudo rm -rf /etc/letsencrypt
            success "证书目录已删除。"
        else
            info "证书目录已保留：/etc/letsencrypt"
            info "如需手动删除：sudo rm -rf /etc/letsencrypt"
        fi
    fi

    success "Certbot 已卸载。"
}

do_status() {
    detect_os
    if ! command_exists certbot; then
        echo -e "${RED}❌ 未安装${NC}"
        return
    fi

    local ver
    ver=$(certbot --version 2>&1 || echo "")

    # 检查续期定时器
    local renewal_status=""
    if [[ "$OS_TYPE" == "linux" ]]; then
        if systemctl is-active --quiet certbot.timer 2>/dev/null; then
            renewal_status="续期定时器运行中"
        elif systemctl is-active --quiet certbot-renew.timer 2>/dev/null; then
            renewal_status="续期定时器运行中"
        else
            renewal_status="未检测到续期定时器"
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if crontab -l 2>/dev/null | grep -q "certbot renew"; then
            renewal_status="cron 续期任务已配置"
        else
            renewal_status="未配置自动续期"
        fi
    fi

    echo -e "${GREEN}✅ 已安装${NC} ($ver)"
    if [[ -n "$renewal_status" ]]; then
        echo "  自动续期: $renewal_status"
    fi

    # 显示已有证书数量
    if [[ -d /etc/letsencrypt/live ]]; then
        local cert_count
        cert_count=$(find /etc/letsencrypt/live -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$cert_count" -gt 0 ]]; then
            echo "  已申请证书: ${cert_count} 个"
        fi
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Certbot 并配置自动续期
  uninstall   卸载 Certbot（可选删除证书）
  status      查看安装与续期状态
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
