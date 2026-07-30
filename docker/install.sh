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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

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
        cur=$(docker --version 2>/dev/null || echo "未知版本")
        warn "检测到已安装 Docker（$cur）"
        if ! yes_no "是否继续并尝试更新？"; then
            info "已取消"
            return 0
        fi
    fi

    # 选择安装源：官方 或 国内镜像源（linuxmirrors.cn，含镜像加速）
    local use_mirror=false
    if yes_no "是否使用国内镜像源安装（linuxmirrors.cn，含镜像加速，国内网络推荐）？"; then
        use_mirror=true
    fi

    if $use_mirror; then
        info "使用国内镜像源一键脚本（linuxmirrors.cn）安装/换源 Docker..."
        # 官方脚本自带交互；通过 bash <(curl ...) 形式调用
        if ! bash <(curl -sSL "$MIRROR_INSTALLER"); then
            error "国内镜像源安装脚本执行失败，可改用官方源重试"
            exit 1
        fi
    else
        info "使用官方一键脚本安装 Docker Engine（get.docker.com）..."
        if ! curl -fsSL "$DOCKER_INSTALLER" | sudo sh; then
            error "官方安装脚本执行失败，请检查网络或参考 https://docs.docker.com/engine/install/ 手动安装"
            exit 1
        fi
    fi

    info "启用并启动 docker 服务..."
    sudo systemctl enable --now docker

    # 将当前用户加入 docker 组，使其免 sudo 使用 docker
    if id -nG "$USER" 2>/dev/null | grep -qw docker; then
        info "当前用户已在 docker 组中"
    else
        if yes_no "是否将当前用户 '$USER' 加入 docker 组（免 sudo 使用 docker，需重新登录生效）？"; then
            sudo usermod -aG docker "$USER"
            warn "请注销并重新登录（或执行 newgrp docker）后生效。"
        fi
    fi

    # 可选：安装 docker-compose 插件（官方脚本在较新版本已自带 compose 插件）
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        warn "未检测到 docker compose 子命令。新版 Docker 已内置 compose 插件；"
        warn "如需独立 docker-compose，请参考 https://docs.docker.com/compose/install/"
    fi
}

# macOS 引导
install_macos() {
    if command_exists docker; then
        success "Docker 已安装：$(docker --version)"
        return 0
    fi
    info "macOS 上推荐使用 Docker Desktop。"
    if command_exists brew; then
        if yes_no "是否通过 Homebrew 安装 Docker Desktop（--cask）？"; then
            brew install --cask docker
            success "安装完成，请启动 Docker Desktop 应用以完成初始化。"
            return 0
        fi
    fi
    warn "请手动下载安装：https://www.docker.com/products/docker-desktop/"
}

install_docker() {
    preflight
    info "🚀 开始安装 Docker"
    if [[ "$OS_TYPE" == "linux" ]]; then
        install_linux
    else
        install_macos
    fi

    echo
    success "🎉 Docker 安装流程结束"
    info "验证："
    echo "  docker --version"
    if [[ "$OS_TYPE" == "linux" ]]; then
        echo "  sudo systemctl status docker"
        echo "  sudo docker run hello-world     # 测试运行（首次拉取镜像较慢）"
    fi
}

uninstall_docker() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            brew uninstall --cask docker || warn "Docker Desktop 可能未通过 brew 安装，请手动卸载。"
        else
            warn "请手动卸载 Docker Desktop。"
        fi
        return 0
    fi

    require_sudo
    warn "卸载将停止 docker 服务并移除软件包。"
    warn "镜像/容器/卷数据保留在 /var/lib/docker，需另行手动清理。"
    if ! yes_no "确认卸载 Docker Engine？"; then
        info "已取消"
        return 0
    fi

    sudo systemctl disable --now docker 2>/dev/null || true
    detect_pkg_manager
    case "$PKG_MANAGER" in
        apt-get) sudo apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras 2>/dev/null || sudo apt-get remove --purge -y docker docker-engine docker.io containerd runc ;;
        dnf)     sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ;;
        yum)     sudo yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ;;
        *)       error "无法识别包管理器，请手动卸载"; exit 1 ;;
    esac

    if yes_no "是否同时删除所有镜像/容器/卷（/var/lib/docker, /var/lib/containerd）？此操作不可逆！"; then
        sudo rm -rf /var/lib/docker /var/lib/containerd
        success "数据目录已删除。"
    fi
    success "Docker 已卸载。"
}

status_docker() {
    if ! command_exists docker; then
        echo -e "${RED}❌ 未安装${NC}"
        return
    fi
    local ver
    ver=$(docker --version 2>/dev/null || echo "")
    if [[ "$OS_TYPE" == "linux" ]]; then
        if systemctl is-active --quiet docker 2>/dev/null; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($ver)"
        else
            echo -e "${YELLOW}⚠️  已安装但服务未运行${NC} ($ver)"
        fi
    else
        if docker info >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($ver)"
        else
            echo -e "${YELLOW}⚠️  已安装，但 Docker 守护进程未运行（请启动 Docker Desktop）${NC}"
        fi
    fi
}

# 仅更换镜像加速器（不重装 Docker）：调用 linuxmirrors 官方脚本 --only-registry
configure_registry() {
    detect_os
    check_commands curl
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "镜像加速器换源（linuxmirrors）仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
    if ! command_exists docker; then
        warn "未检测到 Docker。镜像加速器配置写入 /etc/docker/daemon.json 后需安装并启动 Docker 才会生效。"
        if ! yes_no "仍然继续？"; then
            info "已取消"
            return 0
        fi
    fi
    info "调用 linuxmirrors 官方脚本仅更换镜像加速器（--only-registry）..."
    info "（脚本会备份现有 daemon.json 并写入国内加速地址）"
    if ! bash <(curl -sSL "$MIRROR_INSTALLER") --only-registry; then
        error "镜像加速器换源失败，请检查网络或参考 https://linuxmirrors.cn/other/ 手动配置"
        exit 1
    fi
    success "镜像加速器换源完成。"
    info "如已运行 Docker，可重启使配置生效："
    echo "  sudo systemctl restart docker"
}

# 安装/换源 Docker（国内镜像源，含镜像加速）：调用 linuxmirrors 官方脚本
install_via_mirror() {
    detect_os
    check_commands curl
    if [[ "$OS_TYPE" != "linux" ]]; then
        error "国内镜像源安装（linuxmirrors）仅支持 Linux。当前：$OS_TYPE"
        exit 1
    fi
    require_sudo
    info "调用 linuxmirrors 官方脚本安装/换源 Docker（含国内镜像加速）..."
    if ! bash <(curl -sSL "$MIRROR_INSTALLER"); then
        error "国内镜像源安装脚本执行失败，请检查网络"
        exit 1
    fi
    success "Docker 镜像源安装/换源完成。"
    info "常用命令："
    echo "  sudo systemctl status docker"
    echo "  sudo docker run hello-world"
    echo "  sudo docker info | grep -A5 'Registry Mirrors'   # 查看镜像加速器"
}

usage() {
    cat <<EOF
用法: $0 {install|mirror|registry|uninstall|status|help}

  install     安装或更新 Docker（可选国内镜像源）
  mirror      使用国内镜像源（linuxmirrors.cn）安装/换源 Docker，含镜像加速
  registry    仅更换 Docker 镜像加速器（不重装 Docker，仅 Linux）
  uninstall   卸载 Docker
  status      查看安装与运行状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
