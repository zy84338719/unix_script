#!/usr/bin/env bash
#
# dev-tui/install.sh
#
# 安装终端 TUI 开发工具：lazydocker（Docker TUI）与 lazygit（Git TUI）。
# 下载 Go 二进制到 ~/.local/bin（纯用户态，无需 sudo），Linux + macOS 均可。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

INSTALL_DIR="$HOME/.local/bin"
TOOLS=(lazydocker lazygit)

preflight() {
    detect_os
    check_commands curl tar
}

# 解析架构 -> lazydocker/lazygit 发布后缀格式（Go_X86_64 / Go_arm64）
arch_go_suffix() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)         echo "x86_64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l)         echo "armv7" ;;
        *) error "不支持的架构：$arch"; exit 1 ;;
    esac
}

# 安装单个工具：参数 <repo> <工具名>
install_one() {
    local repo="$1" tool="$2"
    local arch version url tmpdir suffix capos
    version=$(github_latest_tag "$repo")
    if [[ -z "$version" ]]; then
        error "无法获取 $tool 最新版本（请检查网络或设置 GH_TOKEN）"
        return 1
    fi
    suffix=$(arch_go_suffix)
    # 大写的 OS（Linux/Darwin）+ 大写架构是 lazydocker/lazygit 的命名约定
    case "$OS_TYPE" in
        linux)  capos="Linux" ;;
        darwin) capos="Darwin" ;;
    esac
    url="https://github.com/${repo}/releases/download/v${version}/${tool}_${version}_${capos}_${suffix}.tar.gz"
    info "下载 $tool v$version ..."
    tmpdir=$(mktemp -d)
    if ! curl -fSL "$url" -o "$tmpdir/pkg.tar.gz"; then
        error "$tool 下载失败：$url"
        rm -rf "$tmpdir"; return 1
    fi
    if ! tar -xzf "$tmpdir/pkg.tar.gz" -C "$tmpdir" 2>/dev/null; then
        # 部分版本可能是 .tar.xz 或裸二进制，兜底尝试
        if ! tar -xJf "$tmpdir/pkg.tar.gz" -C "$tmpdir" 2>/dev/null; then
            error "$tool 解压失败"
            rm -rf "$tmpdir"; return 1
        fi
    fi
    mkdir -p "$INSTALL_DIR"
    if [ -f "$tmpdir/$tool" ]; then
        mv "$tmpdir/$tool" "$INSTALL_DIR/$tool"
    else
        # 某些 lazydocker 包把二进制放在子目录
        local found
        found=$(find "$tmpdir" -name "$tool" -type f | head -1)
        if [[ -n "$found" ]]; then
            mv "$found" "$INSTALL_DIR/$tool"
        else
            error "$tool 二进制未在压缩包中找到"
            rm -rf "$tmpdir"; return 1
        fi
    fi
    chmod +x "$INSTALL_DIR/$tool"
    rm -rf "$tmpdir"
    success "$tool v$version 已安装到 $INSTALL_DIR/$tool"
}

install_dev_tui() {
    preflight
    info "🚀 开始安装终端 TUI 工具（lazydocker + lazygit）"

    # macOS 优先 brew
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装..."
        brew install lazydocker lazygit
        success "lazydocker + lazygit 安装完成（brew 管理）"
        info "使用：lazydocker / lazygit"
        return 0
    fi

    mkdir -p "$INSTALL_DIR"
    install_one "jesseduffield/lazydocker" "lazydocker" || warn "lazydocker 安装失败"
    install_one "jesseduffield/lazygit" "lazygit" || warn "lazygit 安装失败"

    # PATH 配置提示
    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        warn "$INSTALL_DIR 不在 PATH 中。请添加到 shell 配置："
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi

    echo
    info "使用方法："
    echo "  lazydocker    # Docker 终端 UI"
    echo "  lazygit       # Git 终端 UI"
}

uninstall_dev_tui() {
    preflight
    if ! yes_no "确认卸载 lazydocker 与 lazygit？"; then
        info "已取消"; return 0
    fi
    local t
    for t in "${TOOLS[@]}"; do
        if [[ -f "$INSTALL_DIR/$t" ]]; then
            rm -f "$INSTALL_DIR/$t"
            success "已删除 $INSTALL_DIR/$t"
        fi
    done
    success "TUI 工具已卸载。"
}

status_dev_tui() {
    detect_os
    local installed=0
    local t
    for t in "${TOOLS[@]}"; do
        if [[ -x "$INSTALL_DIR/$t" ]]; then
            installed=$((installed + 1))
        fi
    done
    if [[ $installed -eq ${#TOOLS[@]} ]]; then
        emit_status "installed" "${GREEN}✅ lazydocker + lazygit 已安装${NC}"
    elif [[ $installed -gt 0 ]]; then
        emit_status "installed" "${YELLOW}⚠️  部分已安装（$installed/${#TOOLS[@]}）${NC}"
        emit_extra "installed=$installed/${#TOOLS[@]}"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 lazydocker + lazygit 到 $INSTALL_DIR
  uninstall   卸载
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_dev_tui ;;
        uninstall) uninstall_dev_tui ;;
        status)    status_dev_tui ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
