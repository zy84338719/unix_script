#!/usr/bin/env bash
#
# deno/install.sh
#
# 安装 Deno —— 安全的 JavaScript/TypeScript/WebAssembly 运行时与工具链。
# Linux + macOS。包装官方安装脚本。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OFFICIAL_INSTALLER="https://deno.land/install.sh"
DENO_DIR="$HOME/.deno"
DENO_BIN="$DENO_DIR/bin/deno"

preflight() {
    detect_os
    check_commands curl
}

install_deno() {
    preflight
    info "🦕 安装 Deno（JavaScript/TypeScript 运行时）"

    if command_exists deno; then
        local cur
        cur=$(deno --version 2>/dev/null | head -1 || echo "已安装")
        warn "检测到已安装 Deno（$cur）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 deno..."
        brew install deno
    else
        info "通过官方脚本安装（$OFFICIAL_INSTALLER）..."
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
            error "官方安装脚本执行失败，请参考 https://deno.land"
            exit 1
        fi
    fi

    if ! command_exists deno && [[ -x "$DENO_BIN" ]]; then
        warn "deno 已装到 $DENO_BIN，但不在当前 PATH"
        info "请添加到 shell 配置：export PATH=\"$DENO_DIR/bin:\$PATH\""
    fi
    success "🎉 Deno 安装完成！"
    info "快速开始："
    echo "  deno run https://deno.land/std/examples/welcome.ts"
    echo "  deno serve main.ts          # 启动服务"
    echo "  deno test                   # 运行测试"
    echo "  deno compile app.ts         # 编译为单文件可执行"
}

uninstall_deno() {
    preflight
    local removed=false
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall deno 2>/dev/null && removed=true
    fi
    if [[ -x "$DENO_BIN" ]]; then
        rm -f "$DENO_BIN"
        removed=true
    fi
    if [[ -d "$DENO_DIR" ]] && yes_no "是否删除 $DENO_DIR（含缓存）？"; then
        rm -rf "$DENO_DIR"
    fi
    if $removed; then
        success "Deno 已卸载"
    else
        warn "未找到 Deno 安装"
    fi
}

status_deno() {
    detect_os
    if command_exists deno || [[ -x "$DENO_BIN" ]]; then
        local ver
        ver=$(deno --version 2>/dev/null | head -1 || "$DENO_BIN" --version 2>/dev/null | head -1 || echo "")
        echo -e "${GREEN}✅ 已安装${NC} ${ver:+($ver)}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Deno（默认动作）
  uninstall   卸载
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_deno ;;
        uninstall) uninstall_deno ;;
        status)    status_deno ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
