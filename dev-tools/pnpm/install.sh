#!/usr/bin/env bash
#
# pnpm/install.sh
#
# 安装 pnpm —— 快速、节省磁盘的 Node.js 包管理器。
# Linux + macOS。包装官方独立安装脚本（不依赖 Node）。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://get.pnpm.io/install.sh"
PNPM_DIR="$HOME/.local/share/pnpm"

preflight() {
    detect_os
    check_commands curl
}

install_pnpm() {
    preflight
    info "📦 安装 pnpm（Node.js 包管理器）"

    if command_exists pnpm; then
        local cur
        cur=$(pnpm --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 pnpm（$cur）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 pnpm..."
        brew install pnpm
    else
        info "通过官方独立脚本安装（$OFFICIAL_INSTALLER）..."
        # get.pnpm.io 的脚本需要 sh - 接收管道
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")" -; then
            error "官方安装脚本执行失败，请参考 https://pnpm.io/installation"
            exit 1
        fi
    fi

    if ! command_exists pnpm && [[ -x "$PNPM_DIR/pnpm" ]]; then
        warn "pnpm 已装到 $PNPM_DIR/pnpm，但不在当前 PATH"
        info "请添加到 shell 配置：export PATH=\"$PNPM_DIR:\$PATH\""
    fi
    success "🎉 pnpm 安装完成！"
    info "快速开始："
    echo "  pnpm install         # 安装依赖"
    echo "  pnpm run dev         # 运行脚本"
    echo "  pnpm add <包名>       # 添加依赖"
}

uninstall_pnpm() {
    preflight
    local removed=false
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall pnpm 2>/dev/null && removed=true
    fi
    if [[ -x "$PNPM_DIR/pnpm" ]]; then
        rm -rf "$PNPM_DIR"
        removed=true
    fi
    if $removed; then
        success "pnpm 已卸载"
    else
        warn "未找到 pnpm 安装"
    fi
}

status_pnpm() {
    detect_os
    if command_exists pnpm || [[ -x "$PNPM_DIR/pnpm" ]]; then
        local ver
        ver=$(pnpm --version 2>/dev/null || "$PNPM_DIR/pnpm" --version 2>/dev/null || echo "")
        echo -e "${GREEN}✅ 已安装${NC} ${ver:+(v$ver)}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 pnpm（默认动作）
  uninstall   卸载
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_pnpm ;;
        uninstall) uninstall_pnpm ;;
        status)    status_pnpm ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
