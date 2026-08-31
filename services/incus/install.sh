#!/usr/bin/env bash
#
# incus/install.sh
#
# 安装 Incus —— 系统容器与虚拟化管理（LXD 社区分支，Linux Containers 项目）。
# 仅 Linux：Deb 系走 Zabbly 稳定仓（官方维护打包）；RHEL 系走发行版/EPEL 包。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    detect_distro
    detect_arch
    check_commands curl
}

setup_zabbly_repo() {
    curl -fsSL "https://pkgs.zabbly.com/key.asc" | sudo gpg --dearmor -o /usr/share/keyrings/zabbly.asc
    echo "deb [signed-by=/usr/share/keyrings/zabbly.asc] https://pkgs.zabbly.com/incus/stable $(. /etc/os-release && echo "${VERSION_CODENAME:-}") main" \
        | sudo tee /etc/apt/sources.list.d/zabbly-incus-stable.list >/dev/null
}

do_install() {
    preflight
    if command_exists incus; then
        local cur
        cur=$(incus --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 Incus ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        info "配置 Zabbly 稳定仓库并安装 Incus..."
        pkg_install gnupg 2>/dev/null || true
        setup_zabbly_repo
        pkg_update || true
        pkg_install incus || { error "incus 安装失败（Zabbly 仓库不含该代号？）"; exit 1; }
    elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
        info "通过系统仓库安装 Incus..."
        pkg_update || true
        pkg_install incus || { error "incus 安装失败（需 EPEL 或 openEuler 仓库）"; exit 1; }
    else
        error "仅支持 Deb 系 / RHEL 系（当前：${DISTRO_FAMILY:-unknown}）"
        exit 1
    fi
    uxs_svc enable-now incus || warn "服务启动失败，可手动：sudo systemctl enable --now incus"
    success "Incus 安装完成"
    info "初始化（交互式）：sudo incus admin init"
    info "把用户加入 incus-admin 组可免 sudo：sudo usermod -aG incus-admin $USER"
}

do_uninstall() {
    preflight
    if ! command_exists incus; then
        warn "Incus 未安装"
        exit 0
    fi
    yes_no "确认卸载 Incus？" || { info "已取消"; exit 0; }
    uxs_svc stop incus 2>/dev/null || true
    pkg_remove incus || warn "包管理器卸载失败，请手动确认"
    sudo rm -f /etc/apt/sources.list.d/zabbly-incus-stable.list
    success "Incus 已卸载"
    if [[ -d /var/lib/incus ]]; then
        if yes_no "是否删除 Incus 数据 /var/lib/incus（容器/虚拟机/镜像，不可恢复）？"; then
            sudo rm -rf /var/lib/incus && success "数据已删除"
        else
            info "保留数据"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists incus; then
        emit_status "not_installed" "❌ Incus 未安装"
        return 0
    fi
    local ver
    ver=$(incus --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if uxs_svc is-active incus 2>/dev/null; then
        emit_status "installed:running" "✅ Incus 已安装且服务运行中 ${ver:-(版本未知)}"
    else
        emit_status "installed:stopped" "⚠️ Incus 已安装但服务未运行 ${ver:-(版本未知)}"
    fi
    emit_version "${ver#v}"
}

do_help() {
    cat <<'EOF'
Incus —— 系统容器与虚拟化管理（LXD 社区分支，仅 Linux）

用法: install.sh {install|uninstall|status|help}

  install    安装并启动服务（Deb 系: Zabbly 稳定仓；RHEL 系: 发行版/EPEL 包）
  uninstall  卸载（/var/lib/incus 数据默认保留，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

说明：装完先 sudo incus admin init 初始化存储/网络；
lxd 命令的等价替代，镜像源可用 images: 远程。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
