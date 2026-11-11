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
        info "$(_t 'Set up the rootless prerequisites: /etc/subuid /etc/subgid user mappings...')"
        sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER" 2>/dev/null \
            || warn "$(_tf 'The automatic setup failed, run it manually: sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 %s' "$USER")"
    fi
    info "$(_t 'Optional: to start rootless containers on boot you need loginctl enable-linger')"
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
        yes_no "$(_tf 'podman %s detected, reinstall?' "${cur:-}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        info "$(_t 'Installing the podman CLI via Homebrew...')"
        pkg_install podman || { error "brew $(_t 'Installation failed')"; exit 1; }
        if ! has_machine; then
            if [[ -t 0 ]] && yes_no "$(_t 'Initialize the podman machine now (it downloads a GB sized system image and takes a while)?')"; then
                podman machine init && podman machine start && success "podman machine $(_t 'Ready')"
            else
                info "$(_t 'Skipped. Run it manually later: podman machine init && podman machine start')"
            fi
        else
            info "$(_t 'An existing podman machine was detected, skipping the initialization')"
        fi
    else
        info "$(_t 'Installing podman from the system repositories...')"
        pkg_update || true
        pkg_install podman || { error "podman $(_t 'Installation failed')"; exit 1; }
        # podman-compose 可选：部分仓库没有该包，失败不阻断
        pkg_install podman-compose 2>/dev/null || warn "$(_t 'The repository has no podman-compose, you can install it later with pipx install podman-compose')"
        setup_rootless
        success "podman $(_t 'Installation complete. Try it: podman run --rm quay.io/podman/hello')"
    fi
    info "$(_t 'Pulling docker.io images is slow? Use a domestic mirror: ./install.sh podman mirror')"
}

do_mirror() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local conf_dir="$HOME/.config/containers"
        mkdir -p "$conf_dir"
        printf '%s\n' "$MIRRORS_CONTENT" > "$conf_dir/registries.conf"
        success "$(_tf 'Written to %s/registries.conf' "$conf_dir")"
        if has_machine; then
            info "machine $(_t 'It takes effect after a restart: podman machine stop && podman machine start')"
        fi
    else
        local conf_dir="/etc/containers/registries.conf.d"
        sudo mkdir -p "$conf_dir"
        printf '%s\n' "$MIRRORS_CONTENT" | sudo tee "$conf_dir/$MIRROR_CONF_NAME" >/dev/null
        success "$(_tf 'Written to %s/%s, it takes effect on the next pull' "$conf_dir" "${MIRROR_CONF_NAME}")"
    fi
}

do_unmirror() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if [[ -f "$HOME/.config/containers/registries.conf" ]]; then
            rm -f "$HOME/.config/containers/registries.conf" && success "$(_t 'The mirror configuration was removed')"
        else
            warn "$(_t 'No mirror configuration detected')"
        fi
    else
        if [[ -f "/etc/containers/registries.conf.d/$MIRROR_CONF_NAME" ]]; then
            sudo rm -f "/etc/containers/registries.conf.d/$MIRROR_CONF_NAME" && success "$(_t 'The mirror configuration was removed')"
        else
            warn "$(_t 'No mirror configuration detected')"
        fi
    fi
}

do_uninstall() {
    preflight
    if ! command_exists podman; then
        warn "podman $(_t 'Not installed')"
        exit 0
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if has_machine; then
            if yes_no "$(_t 'Delete the podman machine disk (it holds all the container/image data)?')"; then
                podman machine stop 2>/dev/null || true
                podman machine rm -f && success "machine $(_t 'Deleted')"
            else
                info "$(_t 'Keeping the machine and the data')"
            fi
        fi
        brew uninstall podman 2>/dev/null || pkg_remove podman 2>/dev/null || true
        success "podman CLI $(_t 'Uninstalled')"
    else
        yes_no "$(_t 'Confirm uninstall of podman?')" || { info "$(_t 'Cancelled')"; exit 0; }
        pkg_remove podman-compose 2>/dev/null || true
        pkg_remove podman || { error "$(_t 'Uninstall failed')"; exit 1; }
        success "podman $(_t 'Uninstalled')"
        printf '%s\n' "$(_tf 'Container storage directories: /var/lib/containers, %s/.local/share/containers' "$HOME")"
        if yes_no "$(_t 'Delete the container storage data (images/volumes, irreversible)?')"; then
            sudo rm -rf /var/lib/containers "$HOME/.local/share/containers"
            success "$(_t 'Storage data deleted')"
        else
            info "$(_t 'Keeping the storage data')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if ! command_exists podman; then
        emit_status "not_installed" "$(_t '❌ podman not installed')"
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
        emit_status "installed" "$(_t '✅ podman installed') ${ver:-$(_t '(unknown version)')}$(_tf '(machine: %s)' "${mstate}")"
        emit_version "$ver"
        emit_extra "machine=$mstate"
    else
        local mode="root"
        [[ $EUID -ne 0 ]] && mode="rootless"
        emit_status "installed" "$(_t '✅ podman installed') ${ver:-$(_t '(unknown version)')}$(_tf '(%s)' "${mode}")"
        emit_version "$ver"
        emit_extra "mode=$mode"
    fi
}

do_help() {
    cat <<EOF
podman $(_t '— Daemonless container engine (rootless)')

用法: install.sh {install|mirror|unmirror|uninstall|status|help}

  install    $(_t 'Install (Linux: system repositories including podman-compose; macOS: brew, the machine init is optional)')
  mirror     docker.io $(_t 'Pull through a domestic image mirror (write the containers registries configuration)')
  unmirror   $(_t 'Remove the image mirror configuration')
  uninstall  $(_t 'Uninstall (the container storage data is kept by default, deletion needs a second confirmation)')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: this module does not install podman-docker (it would hijack the docker command and conflict with the docker module).')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    mirror)         do_mirror ;;
    unmirror)       do_unmirror ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
