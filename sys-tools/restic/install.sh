#!/usr/bin/env bash
#
# restic/install.sh
#
# 安装与管理 Restic 备份工具。
# 支持 Linux（apt/dnf/yum 或 GitHub 二进制）与 macOS（Homebrew）。
#
# 子命令：
#   install           安装/更新 Restic
#   uninstall         卸载 Restic
#   status            查看状态
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

RESTIC_BIN="/usr/local/bin/restic"

# --- 检查已有安装 ---
handle_existing_installation() {
    if ! command_exists restic; then
        return 0
    fi
    local current_version
    current_version=$(restic version 2>/dev/null | head -1 || echo "未知版本")
    warn "检测到已安装 Restic（${current_version}）"
    if ! yes_no "是否继续并覆盖安装最新版本？"; then
        info "安装已取消"
        exit 0
    fi
}

# --- 从 GitHub 下载二进制（Linux 备选） ---
install_from_github() {
    require_sudo
    check_commands curl

    info "正在获取最新版本信息..."
    local latest
    latest=$(github_latest_tag "restic/restic")
    if [[ -z "$latest" ]]; then
        error "无法获取最新版本信息，请检查网络连接"
        exit 1
    fi
    success "最新版本：v$latest"

    # 确定架构后缀
    local arch_suffix
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)         arch_suffix="linux_amd64" ;;
        aarch64|arm64)  arch_suffix="linux_arm64" ;;
        armv7l)         arch_suffix="linux_arm" ;;
        *) error "不支持的架构：$arch"; exit 1 ;;
    esac

    local url="https://github.com/restic/restic/releases/download/v${latest}/restic_${latest}_${arch_suffix}.bz2"
    info "下载地址：$url"

    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    if ! curl -SL "$url" -o "$tmpdir/restic.bz2"; then
        error "下载失败"
        exit 1
    fi

    info "正在解压..."
    if ! bunzip2 "$tmpdir/restic.bz2"; then
        error "解压失败，尝试安装 bzip2..."
        pkg_install bzip2
        bunzip2 "$tmpdir/restic.bz2"
    fi

    sudo mv "$tmpdir/restic" "$RESTIC_BIN"
    sudo chmod 755 "$RESTIC_BIN"
    if [[ "$OS_TYPE" == "darwin" ]]; then
        sudo chown root:wheel "$RESTIC_BIN"
    else
        sudo chown root:root "$RESTIC_BIN"
    fi

    rm -rf "$tmpdir"
    trap - EXIT
    success "二进制文件安装完成"
}

# --- 安装 Restic ---
install_restic() {
    detect_os
    handle_existing_installation

    info "🚀 Restic 备份工具安装脚本"
    echo "=========================================="

    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS 优先 brew
        if command_exists brew; then
            info "通过 Homebrew 安装 Restic..."
            brew install restic
        else
            error "macOS 上需要先安装 Homebrew：https://brew.sh/"
            exit 1
        fi
    else
        # Linux：优先使用包管理器，失败则从 GitHub 下载
        detect_pkg_manager
        case "$PKG_MANAGER" in
            apt-get)
                info "通过 apt 安装 Restic..."
                require_sudo
                pkg_update
                if pkg_install restic; then
                    success "apt 安装完成"
                else
                    warn "apt 安装失败，改用 GitHub 二进制..."
                    install_from_github
                fi
                ;;
            dnf|yum)
                info "通过 $PKG_MANAGER 安装 Restic..."
                require_sudo
                if pkg_install restic; then
                    success "$PKG_MANAGER 安装完成"
                else
                    warn "$PKG_MANAGER 安装失败，改用 GitHub 二进制..."
                    install_from_github
                fi
                ;;
            *)
                warn "当前包管理器不直接提供 restic，从 GitHub 下载..."
                install_from_github
                ;;
        esac
    fi

    if ! command_exists restic; then
        error "安装后找不到 restic 命令，请检查 PATH"
        exit 1
    fi

    local version
    version=$(restic version 2>/dev/null | head -1 || echo "未知")

    echo
    echo "=========================================="
    success "🎉 Restic 安装完成！"
    echo
    info "版本信息：$version"
    echo
    info "快速上手："
    echo "  # 初始化本地备份仓库"
    echo "  restic init --repo /path/to/backup-repo"
    echo
    echo "  # 备份目录"
    echo "  restic -r /path/to/backup-repo backup /home/user/docs"
    echo
    echo "  # 查看备份快照"
    echo "  restic -r /path/to/backup-repo snapshots"
    echo
    echo "  # 恢复文件"
    echo "  restic -r /path/to/backup-repo restore latest --target /tmp/restore"
    echo
    echo "  # 初始化远程仓库（S3 示例）"
    echo "  restic -r s3:s3.amazonaws.com/bucket-name init"
    echo
    info "更多用法：https://restic.readthedocs.io/"
}

# --- 卸载 Restic ---
uninstall_restic() {
    detect_os
    warn "即将卸载 Restic。"
    if ! yes_no "确认卸载？"; then
        info "已取消"
        return 0
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall restic 2>/dev/null || true
    elif [[ -f "$RESTIC_BIN" ]]; then
        require_sudo
        sudo rm -f "$RESTIC_BIN"
    else
        detect_pkg_manager
        pkg_remove restic 2>/dev/null || true
    fi

    success "Restic 已卸载。"
}

# --- 状态检查 ---
status_restic() {
    detect_os
    local installed=false version=""
    if command_exists restic; then
        installed=true
        version=$(restic version 2>/dev/null | head -1 || echo "未知版本")
    fi
    if $installed; then
        emit_status "installed" "${GREEN}✅ 已安装${NC} ($version)"
        emit_version "$version"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

# --- 用法 ---
usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装或更新 Restic（默认动作）
  uninstall   卸载 Restic
  status      查看安装与运行状态
  help        显示本帮助
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_restic ;;
        uninstall) uninstall_restic ;;
        status)    status_restic ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
