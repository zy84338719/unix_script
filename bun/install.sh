#!/usr/bin/env bash
#
# bun/install.sh
#
# 安装 Bun —— 快速的 JavaScript/TypeScript 运行时与工具链（打包/运行/测试）。
# Linux + macOS。包装官方安装脚本 / Homebrew。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OFFICIAL_INSTALLER="https://bun.sh/install"
BUN_DIR="$HOME/.bun"

preflight() {
    detect_os
    check_commands curl
}

install_bun() {
    preflight
    info "🚀 安装 Bun（JavaScript/TypeScript 运行时与工具链）"

    if command_exists bun; then
        local cur
        cur=$(bun --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 Bun（$cur）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 bun..."
        brew install bun
    else
        info "通过官方脚本安装（$OFFICIAL_INSTALLER）..."
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
            error "官方安装脚本执行失败，请检查网络或参考 https://bun.sh/docs/installation"
            exit 1
        fi
    fi

    # 官方脚本装到 ~/.bun/bin/bun，可能不在当前 PATH
    if ! command_exists bun; then
        if [[ -x "$BUN_DIR/bin/bun" ]]; then
            warn "bun 已装到 $BUN_DIR/bin/bun，但不在当前 PATH"
            info "请添加到 shell 配置：export PATH=\"$BUN_DIR/bin:\$PATH\""
        else
            error "安装后仍找不到 bun，请重新打开终端或检查 PATH"
            exit 1
        fi
    fi

    success "🎉 Bun 安装完成！"
    info "快速开始："
    echo "  bun --version           # 查看版本"
    echo "  bun run dev             # 运行脚本（替代 npm run）"
    echo "  bun install             # 安装依赖（比 npm 快）"
    echo "  bun build ./index.ts    # 打包"
    echo "  bun test                # 运行测试"
    echo
    info "文档：https://bun.sh/docs"
}

uninstall_bun() {
    preflight
    local removed=false
    # brew 安装的
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall bun 2>/dev/null && removed=true
    fi
    # 官方脚本安装的（~/.bun）
    if [[ -d "$BUN_DIR" ]]; then
        if yes_no "确认删除 $BUN_DIR（含 bun 二进制与全局缓存）？"; then
            rm -rf "$BUN_DIR"
            removed=true
            success "已删除 $BUN_DIR"
        fi
    fi
    if $removed; then
        success "Bun 已卸载"
        info "若 shell 配置中有 BUN 相关的 PATH 行，请手动删除"
    else
        warn "未找到 Bun 安装（可能已卸载或通过其他方式安装）"
    fi
}

status_bun() {
    detect_os
    if command_exists bun || [[ -x "$BUN_DIR/bin/bun" ]]; then
        local ver
        ver=$(bun --version 2>/dev/null || "$BUN_DIR/bin/bun" --version 2>/dev/null || echo "")
        echo -e "${GREEN}✅ 已安装${NC} ${ver:+(v$ver)}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Bun（JavaScript/TypeScript 运行时，默认动作）
  uninstall   卸载
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_bun ;;
        uninstall) uninstall_bun ;;
        status)    status_bun ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
