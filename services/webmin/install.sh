#!/usr/bin/env bash
#
# webmin/install.sh
#
# 安装与管理 Webmin —— 经典 Web 系统管理面板（用户/服务/文件/防火墙/计划任务等）。
# 仅 Linux（依赖 systemd）。通过官方 APT/YUM 仓库安装（download.webmin.com，国内可达）。
# Web UI：https://<IP>:10000，用系统 root 账号登录。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

readonly WEBMIN_KEY_URL="https://download.webmin.com/developers-key.asc"
readonly WEBMIN_APT_BASE="https://download.webmin.com/download/newkey/repository"
readonly WEBMIN_YUM_BASE="https://download.webmin.com/download/newkey/yum"
readonly WEBMIN_KEYRING="/usr/share/keyrings/webmin-developers.gpg"
readonly WEBMIN_RPM_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-webmin-developers"
readonly WEBMIN_PORT=10000

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "Webmin 仅支持 Linux。当前：${OS_TYPE}"
        exit 1
    fi
    if ! command_exists systemctl; then
        error "需要 systemctl（systemd）。"
        exit 1
    fi
}

fetch_to() {
    local url="$1" out="$2"
    if command_exists curl; then
        curl -fsSL "$url" -o "$out"
    elif command_exists wget; then
        wget -qO "$out" "$url"
    else
        error "需要 curl 或 wget 之一，请先安装。"
        return 1
    fi
}

is_installed() {
    [[ -d /etc/webmin ]]
}

setup_repo_deb() {
    if ! command_exists gpg; then
        info "安装 gnupg（导入仓库签名密钥需要）..."
        pkg_install gnupg
    fi
    local tmp
    tmp=$(mktemp /tmp/webmin-key.XXXXXX.asc)
    # shellcheck disable=SC2064  # tmp 在本函数内不再变，展开一次即可
    trap "rm -f '$tmp'" RETURN
    info "导入 Webmin 官方签名密钥..."
    fetch_to "${WEBMIN_KEY_URL}" "$tmp"
    sudo gpg --dearmor --yes -o "${WEBMIN_KEYRING}" "$tmp"
    sudo chmod 644 "${WEBMIN_KEYRING}"
    echo "deb [signed-by=${WEBMIN_KEYRING}] ${WEBMIN_APT_BASE} stable contrib" \
        | sudo tee /etc/apt/sources.list.d/webmin-stable.list >/dev/null
    info "刷新 apt 索引..."
    pkg_update
    info "安装 webmin（含推荐依赖）..."
    sudo apt-get install -y --install-recommends webmin
}

setup_repo_rhel() {
    local repo_dir="/etc/yum.repos.d"
    if [[ "${DISTRO_FAMILY:-}" == "suse" ]]; then
        repo_dir="/etc/zypp/repos.d"
    fi
    info "导入 Webmin 官方签名密钥..."
    sudo mkdir -p /etc/pki/rpm-gpg
    fetch_to "${WEBMIN_KEY_URL}" "/tmp/webmin-dev-key.asc"
    sudo mv /tmp/webmin-dev-key.asc "${WEBMIN_RPM_KEY}"
    sudo chmod 644 "${WEBMIN_RPM_KEY}"
    sudo rpm --import "${WEBMIN_RPM_KEY}" 2>/dev/null || true
    info "写入仓库文件 ${repo_dir}/webmin-stable.repo ..."
    printf '[webmin-stable]\nname=Webmin Stable\nbaseurl=%s\nenabled=1\ngpgkey=file://%s\ngpgcheck=1\n' \
        "${WEBMIN_YUM_BASE}" "${WEBMIN_RPM_KEY}" \
        | sudo tee "${repo_dir}/webmin-stable.repo" >/dev/null
    info "安装 webmin..."
    pkg_install webmin
}

allow_firewall() {
    if command_exists firewall-cmd; then
        sudo firewall-cmd --add-port="${WEBMIN_PORT}/tcp" --permanent 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
        success "已放行 firewalld ${WEBMIN_PORT}/tcp"
    fi
    if command_exists ufw; then
        sudo ufw allow "${WEBMIN_PORT}"/tcp 2>/dev/null || true
        success "已放行 ufw ${WEBMIN_PORT}/tcp"
    fi
}

install_webmin() {
    preflight
    require_sudo
    detect_pkg_manager
    detect_distro

    if is_installed; then
        warn "检测到 Webmin 已安装"
        if ! yes_no "是否继续并重装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    info "🚀 配置 Webmin 官方仓库（包管理器：${PKG_MANAGER}）"
    if [[ "${DISTRO_FAMILY:-}" == "debian" ]]; then
        setup_repo_deb
    else
        setup_repo_rhel
    fi

    if ! is_installed; then
        error "安装失败：未找到 /etc/webmin，请检查上方输出。"
        exit 1
    fi

    allow_firewall
    local ip_addr
    ip_addr=$(get_local_ip)
    echo
    success "🎉 Webmin 安装完成！"
    info "访问地址：https://${ip_addr}:${WEBMIN_PORT}"
    warn "使用系统 root 账号与 root 密码登录（自签证书浏览器告警可忽略）。"
}

uninstall_webmin() {
    preflight
    require_sudo
    detect_pkg_manager
    if ! is_installed; then
        warn "Webmin 未安装，无需卸载。"
        return 0
    fi
    if ! yes_no "确认卸载 Webmin（含 /etc/webmin 配置）？"; then
        info "已取消"; return 0
    fi
    sudo systemctl stop webmin 2>/dev/null || true
    pkg_remove webmin 2>/dev/null || warn "webmin 包移除失败，请手动卸载"
    sudo rm -f /etc/apt/sources.list.d/webmin-stable.list \
        /etc/yum.repos.d/webmin-stable.repo /etc/zypp/repos.d/webmin-stable.repo \
        "${WEBMIN_KEYRING}" "${WEBMIN_RPM_KEY}"
    if yes_no "是否删除 /etc/webmin 配置目录（含面板账号/证书）？"; then
        sudo rm -rf /etc/webmin
    fi
    success "Webmin 已卸载。"
}

status_webmin() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"; return
    fi
    if ! is_installed; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"; return
    fi
    local ver port
    ver=$(cat /etc/webmin/version 2>/dev/null || true)
    if [[ -n "${ver}" ]]; then
        emit_version "${ver}"
    fi
    if systemctl is-active --quiet webmin 2>/dev/null; then
        emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"
    else
        emit_status "installed:stopped" "${YELLOW}⚠️  已安装（服务未运行）${NC}"
    fi
    port=$(grep -E '^port=' /etc/webmin/miniserv.conf 2>/dev/null | cut -d= -f2 || true)
    if [[ -n "${port}" ]]; then
        emit_extra "port=${port}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     通过官方仓库安装 Webmin（Web 管理面板，仅 Linux，默认端口 10000）
  uninstall   卸载 Webmin
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_webmin ;;
        uninstall) uninstall_webmin ;;
        status)    status_webmin ;;
        help|--help|-h) usage ;;
        *) error "未知操作: ${action}"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
