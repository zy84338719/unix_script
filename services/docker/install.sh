#!/usr/bin/env bash
#
# docker/install.sh
#
# 安装与管理 Docker Engine（Linux 为主）。
#   - Linux: 使用官方 get.docker.com 一键脚本，启用 systemd 服务，可选将当前用户加入 docker 组。
#   - macOS: 检测并引导安装 Docker Desktop（brew --cask），不强制自动安装。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

DOCKER_INSTALLER="https://get.docker.com"
# 国内镜像源（linuxmirrors.cn）一键脚本：安装/换源 Docker，附带国内加速
MIRROR_INSTALLER="https://linuxmirrors.cn/docker.sh"

preflight() {
    detect_os
    check_commands curl
}

# Linux 安装
install_linux() {
    require_sudo
    if command_exists docker; then
        local cur
        cur=$(docker --version 2>/dev/null || printf '%s' "$(_t 'Unknown version')")
        warn "$(_t 'Detected installed Docker')（${cur}）"
        if ! yes_no "$(_t 'Continue and try to update?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi

    # 选择安装源：官方 或 国内镜像源（linuxmirrors.cn，含镜像加速）
    local use_mirror=false
    if yes_no "$(_t 'Install from a domestic mirror (linuxmirrors.cn, includes registry acceleration, recommended for China network)?')"; then
        use_mirror=true
    fi

    if $use_mirror; then
        info "$(_t 'Installing Docker via domestic mirror script (linuxmirrors.cn)...')"
        # 官方脚本自带交互；通过 bash <(curl ...) 形式调用
        if ! bash <(curl -sSL "$MIRROR_INSTALLER"); then
            error "$(_t 'Domestic mirror script failed, try the official installer instead')"
            exit 1
        fi
    else
        detect_pkg_manager
        # Arch/Alpine/openSUSE：get.docker.com 不支持，改用系统包管理器
        case "$PKG_MANAGER" in
            pacman)
                info "$(_t 'Installing Docker via pacman...')"
                pkg_install docker docker-compose || { error "$(_t 'Install failed')"; exit 1; }
                ;;
            apk)
                info "$(_t 'Installing Docker via apk...')"
                pkg_install docker docker-cli-compose || { error "$(_t 'Install failed')"; exit 1; }
                # Alpine 需开启 community 仓库（默认已开）
                ;;
            zypper)
                info "$(_t 'Installing Docker via zypper...')"
                pkg_install docker docker-compose || { error "$(_t 'Install failed')"; exit 1; }
                ;;
            *)
                info "$(_t 'Installing Docker Engine via official script (get.docker.com)...')"
                if ! curl -fsSL "$DOCKER_INSTALLER" | sudo sh; then
                    error "$(_t 'Official installer failed, check the network or install manually:') https://docs.docker.com/engine/install/"
                    exit 1
                fi
                ;;
        esac
    fi

    info "$(_t 'Enabling and starting docker service...')"
    uxs_svc enable-now docker

    # 将当前用户加入 docker 组，使其免 sudo 使用 docker
    if id -nG "$USER" 2>/dev/null | grep -qw docker; then
        info "$(_t 'Current user is already in the docker group')"
    else
        if yes_no "$(_t 'Add user')' $USER' $(_t 'to the docker group (passwordless docker, requires re-login)?')"; then
            sudo usermod -aG docker "$USER"
            warn "$(_t 'Log out and back in (or run newgrp docker) for the change to take effect.')"
        fi
    fi

    # 可选：安装 docker-compose 插件（官方脚本在较新版本已自带 compose 插件）
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        warn "$(_t 'docker compose subcommand not detected. Recent Docker includes the compose plugin.')"
        warn "$(_t 'For standalone docker-compose, see:') https://docs.docker.com/compose/install/"
    fi
}

# macOS 引导
install_macos() {
    if command_exists docker; then
        success "$(_t 'Docker installed: ')$(docker --version)"
        return 0
    fi
    info "$(_t 'Docker Desktop is recommended on macOS.')"
    if command_exists brew; then
        if yes_no "$(_t 'Install Docker Desktop via Homebrew (--cask)?')"; then
            brew install --cask docker
            success "$(_t 'Installation complete. Please launch Docker Desktop to finish setup.')"
            return 0
        fi
    fi
    warn "$(_t 'Please download and install manually:') https://www.docker.com/products/docker-desktop/"
}

install_docker() {
    preflight
    info "$(_t 'Rocket Starting Docker installation')"
    if [[ "$OS_TYPE" == "linux" ]]; then
        install_linux
    else
        install_macos
    fi

    echo
    success "$(_t 'Party popper Docker installation flow complete')"
    info "$(_t 'Verify:')"
    echo "  docker --version"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status docker"
        echo "  sudo docker run hello-world     # $(_t 'Test run (first pull is slow)')"
    fi
}

uninstall_docker() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            brew uninstall --cask docker || warn "$(_t 'Docker Desktop may not have been installed via brew, please uninstall manually.')"
        else
            warn "$(_t 'Please uninstall Docker Desktop manually.')"
        fi
        return 0
    fi

    require_sudo
    warn "$(_t 'Uninstalling will stop the docker service and remove the package.')"
    warn "$(_t 'Image/container/volume data is kept in /var/lib/docker, please clean it up manually.')"
    if ! yes_no "$(_t 'Confirm uninstall of Docker Engine?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi

    uxs_svc disable-now docker 2>/dev/null || true
    detect_pkg_manager
    # 尝试卸载 Docker 相关包（包名因发行版/安装方式不同，逐个尝试）
    local docker_pkgs=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker docker-engine docker.io runc)
    case "$PKG_MANAGER" in
        apt-get|dnf|yum)
            # apt/dnf/yum 可能装的是 docker-ce 系
            pkg_remove "${docker_pkgs[@]}" 2>/dev/null || true
            ;;
        *)
            # 其他发行版（zypper/pacman/apk）通常包名为 docker
            pkg_remove docker containerd 2>/dev/null || true
            ;;
    esac

    if yes_no "$(_t 'Also delete all images/containers/volumes (/var/lib/docker, /var/lib/containerd)? This is irreversible!')"; then
        sudo rm -rf /var/lib/docker /var/lib/containerd
        success "$(_t 'Data directory deleted.')"
    fi
    success "$(_t 'Docker uninstalled.')"
}

status_docker() {
    if ! command_exists docker; then
        emit_status "not_installed" "${RED}❌ $(_t 'Not installed')${NC}"
        return
    fi
    local ver
    ver=$(docker --version 2>/dev/null || echo "")
    if [[ "$OS_TYPE" == "linux" ]]; then
        if uxs_svc is-active docker 2>/dev/null; then
            emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC} ($ver)"
        else
            emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed but service not running')${NC} ($ver)"
        fi
    else
        # docker info 在守护进程挂起/socket 无响应时实测可阻塞 90s+（黑洞地址实测 93.3s），
        # 套 5s 超时护栏：超时(rc=124)按未运行降级，避免拖垮 status --json 并行批查
        if uxs_with_timeout 5 docker info >/dev/null 2>&1; then
            emit_status "installed:running" "${GREEN}✅ $(_t 'Installed and running')${NC} ($ver)"
        else
            emit_status "installed:stopped" "${YELLOW}⚠️  $(_t 'Installed, but the Docker daemon is not running (please start Docker Desktop)')${NC}"
        fi
    fi
    emit_version "$ver"
}

# 仅更换镜像加速器（不重装 Docker）：调用 linuxmirrors 官方脚本 --only-registry
configure_registry() {
    detect_os
    check_commands curl
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_t 'Registry mirror configuration (linuxmirrors) is Linux-only. Current: ')$OS_TYPE"
        exit 1
    fi
    if ! command_exists docker; then
        warn "$(_t 'Docker not detected. The registry mirror configuration will only take effect after Docker is installed and started.')"
        if ! yes_no "$(_t 'Still continue?')"; then
            info "$(_t 'Cancelled')"
            return 0
        fi
    fi
    info "$(_t 'Calling linuxmirrors script to configure registry mirror only (--only-registry)...')"
    info "$(_t '(The script will back up daemon.json and write a domestic mirror address)')"
    if ! bash <(curl -sSL "$MIRROR_INSTALLER") --only-registry; then
        error "$(_t 'Registry mirror configuration failed, check the network or configure manually:') https://linuxmirrors.cn/other/"
        exit 1
    fi
    success "$(_t 'Registry mirror configuration complete.')"
    info "$(_t 'If Docker is already running, restart it to apply:')"
    echo "  sudo systemctl restart docker"
}

# 安装/换源 Docker（国内镜像源，含镜像加速）：调用 linuxmirrors 官方脚本
install_via_mirror() {
    detect_os
    check_commands curl
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "$(_t 'Domestic mirror installation (linuxmirrors) is Linux-only. Current: ')$OS_TYPE"
        exit 1
    fi
    require_sudo
    info "$(_t 'Calling linuxmirrors script to install/replace Docker mirror (includes registry acceleration)...')"
    if ! bash <(curl -sSL "$MIRROR_INSTALLER"); then
        error "$(_t 'Domestic mirror script failed, check the network')"
        exit 1
    fi
    success "$(_t 'Docker mirror installation/replacement complete.')"
    info "$(_t 'Common commands:')"
    echo "  sudo systemctl status docker"
    echo "  sudo docker run hello-world"
    echo "  sudo docker info | grep -A5 'Registry Mirrors'   # $(_t 'View registry mirror')"
}

usage() {
    cat <<EOF
用法: \$0 {install|mirror|registry|uninstall|status|help}

  install     $(_t 'Install or update Docker (optional domestic mirror)')
  mirror      $(_t 'Install/replace Docker via domestic mirror (linuxmirrors.cn), includes registry acceleration')
  registry    $(_t 'Configure registry mirror only (no reinstall, Linux only)')
  uninstall   $(_t 'Uninstall Docker')
  status      $(_t 'View installation and running status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)    install_docker ;;
        mirror)     install_via_mirror ;;
        registry)   configure_registry ;;
        uninstall)  uninstall_docker ;;
        status)     status_docker ;;
        help|--help|-h) usage ;;
        *) error "$(_t 'Unknown action: ')$action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
