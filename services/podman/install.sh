#!/usr/bin/env bash
#
# podman/install.sh
#
# 安装 podman —— 无守护进程容器引擎（rootless）。
# Linux: 发行版仓库（pkg_install）；macOS: brew + podman machine。
# 注意：刻意不装 podman-docker（会把 docker 命令改指向 podman，与 docker 模块冲突）。
#
# 用法: $0 {install|mirror|unmirror|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

MIRROR_CONF_NAME="uxs-mirror.conf"

# docker.io 国内镜像加速配置（containers 镜像栈原生格式，非 docker daemon.json）
MIRRORS_CONTENT='[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "docker.m.daocloud.io"

[[registry.mirror]]
location = "docker.1ms.run"

[[registry.mirror]]
location = "dockerpull.org"
'

preflight() {
    detect_os
    detect_arch
}

# rootless 前置：/etc/subuid、/etc/subgid 缺失时补齐当前用户映射段
setup_rootless() {
    if [[ ! -s /etc/subuid || ! -s /etc/subgid ]]; then
        info "补齐 rootless 前置：/etc/subuid /etc/subgid 用户映射..."
        sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER" 2>/dev/null \
            || warn "自动补齐失败，请手动执行：sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER"
    fi
    info "可选：开机自启 rootless 容器需 loginctl enable-linger"
}

# macOS 上是否有已创建的 podman machine
has_machine() {
    podman machine list 2>/dev/null | tail -n +2 | grep -q .
}

do_install() {
    preflight
    if command_exists podman; then
        local cur
        cur=$(podman --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
        yes_no "已检测到 podman ${cur:-}，是否重新安装？" || { info "已取消"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "通过 Homebrew 安装 podman CLI..."
        pkg_install podman || { error "brew 安装失败"; exit 1; }
        if ! has_machine; then
            if [[ -t 0 ]] && yes_no "是否立即初始化 podman machine（需下载 GB 级系统镜像，耗时较长）？"; then
                podman machine init && podman machine start && success "podman machine 已就绪"
            else
                info "已跳过。之后手动执行：podman machine init && podman machine start"
            fi
        else
            info "检测到已有 podman machine，跳过初始化"
        fi
    else
        info "通过系统仓库安装 podman..."
        pkg_update || true
        pkg_install podman || { error "podman 安装失败"; exit 1; }
        # podman-compose 可选：部分仓库没有该包，失败不阻断
        pkg_install podman-compose 2>/dev/null || warn "仓库无 podman-compose，可后续 pipx install podman-compose"
        setup_rootless
        success "podman 安装完成。试一下：podman run --rm quay.io/podman/hello"
    fi
    info "拉取 docker.io 镜像慢？换国内加速：./install.sh podman mirror"
}

do_mirror() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local conf_dir="$HOME/.config/containers"
        mkdir -p "$conf_dir"
        printf '%s\n' "$MIRRORS_CONTENT" > "$conf_dir/registries.conf"
        success "已写入 $conf_dir/registries.conf"
        if has_machine; then
            info "machine 需重启后生效：podman machine stop && podman machine start"
        fi
    else
        local conf_dir="/etc/containers/registries.conf.d"
        sudo mkdir -p "$conf_dir"
        printf '%s\n' "$MIRRORS_CONTENT" | sudo tee "$conf_dir/$MIRROR_CONF_NAME" >/dev/null
        success "已写入 $conf_dir/$MIRROR_CONF_NAME，下次拉取即生效"
    fi
}

do_unmirror() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -f "$HOME/.config/containers/registries.conf" ]]; then
            rm -f "$HOME/.config/containers/registries.conf" && success "已移除镜像加速配置"
        else
            warn "未检测到镜像加速配置"
        fi
    else
        if [[ -f "/etc/containers/registries.conf.d/$MIRROR_CONF_NAME" ]]; then
            sudo rm -f "/etc/containers/registries.conf.d/$MIRROR_CONF_NAME" && success "已移除镜像加速配置"
        else
            warn "未检测到镜像加速配置"
        fi
    fi
}

do_uninstall() {
    preflight
    if ! command_exists podman; then
        warn "podman 未安装"
        exit 0
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if has_machine; then
            if yes_no "是否删除 podman machine 磁盘（含全部容器/镜像数据）？"; then
                podman machine stop 2>/dev/null || true
                podman machine rm -f && success "machine 已删除"
            else
                info "保留 machine 与数据"
            fi
        fi
        brew uninstall podman 2>/dev/null || pkg_remove podman 2>/dev/null || true
        success "podman CLI 已卸载"
    else
        yes_no "确认卸载 podman？" || { info "已取消"; exit 0; }
        pkg_remove podman-compose 2>/dev/null || true
        pkg_remove podman || { error "卸载失败"; exit 1; }
        success "podman 已卸载"
        echo "容器存储目录：/var/lib/containers、$HOME/.local/share/containers"
        if yes_no "是否删除容器存储数据（镜像/卷，不可恢复）？"; then
            sudo rm -rf /var/lib/containers "$HOME/.local/share/containers"
            success "存储数据已删除"
        else
            info "保留存储数据"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists podman; then
        emit_status "not_installed" "❌ podman 未安装"
        return 0
    fi
    local ver
    ver=$(podman --version 2>/dev/null | grep -m1 -oE '[0-9]+(\.[0-9]+)+' || true)
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local mstate="none"
        if has_machine; then
            mstate=$(podman machine list 2>/dev/null | tail -n +2 | head -1 \
                | grep -oE 'Running|Stopped|Saved' | head -1 || true)
            [[ -z "$mstate" ]] && mstate="present"
        fi
        emit_status "installed" "✅ podman 已安装 ${ver:-(版本未知)}（machine: ${mstate}）"
        emit_version "$ver"
        emit_extra "machine=$mstate"
    else
        local mode="root"
        [[ $EUID -ne 0 ]] && mode="rootless"
        emit_status "installed" "✅ podman 已安装 ${ver:-(版本未知)}（${mode}）"
        emit_version "$ver"
        emit_extra "mode=$mode"
    fi
}

do_help() {
    cat <<'EOF'
podman —— 无守护进程容器引擎（rootless）

用法: install.sh {install|mirror|unmirror|uninstall|status|help}

  install    安装（Linux: 系统仓库含 podman-compose；macOS: brew，可选初始化 machine）
  mirror     docker.io 拉取走国内镜像加速（写 containers registries 配置）
  unmirror   移除镜像加速配置
  uninstall  卸载（默认保留容器存储数据，删除需二次确认）
  status     查看安装状态（支持 UXS_STATUS_MODE=machine）
  help       本帮助

注意：本模块不装 podman-docker（避免劫持 docker 命令，与 docker 模块冲突）。
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    mirror)         do_mirror ;;
    unmirror)       do_unmirror ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "未知子命令：$1"; do_help; exit 1 ;;
esac
