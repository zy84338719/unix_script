#!/usr/bin/env bash
#
# opencode/install.sh
#
# 安装 OpenCode（sst/opencode）—— 开源终端 AI 编程助手。
# Linux + macOS。包装官方安装脚本 / Homebrew。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://opencode.ai/install"

preflight() {
    detect_os
    check_commands curl
}

install_opencode() {
    preflight
    info "🤖 安装 OpenCode（终端 AI 编程助手）"

    if command_exists opencode; then
        local cur
        cur=$(opencode --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 OpenCode（${cur}）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 opencode..."
        brew install opencode
    else
        info "通过官方脚本安装（${OFFICIAL_INSTALLER}）..."
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
            error "官方安装脚本执行失败，请检查网络或参考 https://opencode.ai/docs/"
            exit 1
        fi
    fi

    if ! command_exists opencode; then
        # 官方脚本可能装到 ~/.local/bin，可能不在当前 PATH
        if [[ -x "$HOME/.local/bin/opencode" ]]; then
            warn "opencode 已装到 ~/.local/bin/opencode，但不在当前 PATH"
            info "请添加到 shell 配置：export PATH=\"$HOME/.local/bin:\$PATH\""
        else
            error "安装后仍找不到 opencode，请重新打开终端或检查 PATH"
            exit 1
        fi
    fi

    success "🎉 OpenCode 安装完成！"
    info "快速开始："
    echo "  opencode          # 在项目目录启动 AI 编程会话"
    echo "  opencode --help   # 查看帮助"
    echo
    info "配置模型/API Key：参考 https://opencode.ai/docs/"
}

uninstall_opencode() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall opencode 2>/dev/null && success "已通过 brew 卸载 opencode" && return 0
    fi
    # 官方脚本安装的通常在 ~/.local/bin
    local removed=false
    for p in "$HOME/.local/bin/opencode" "/usr/local/bin/opencode"; do
        if [[ -x "$p" ]]; then
            rm -f "$p"
            removed=true
        fi
    done
    if $removed; then
        success "已删除 opencode 二进制"
    else
        warn "未找到 opencode 二进制（可能通过其他方式安装，请手动卸载）"
    fi
    info "配置目录保留：~/.config/opencode（可手动删除）"
}

status_opencode() {
    detect_os
    if command_exists opencode || [[ -x "$HOME/.local/bin/opencode" ]]; then
        local ver
        ver=$(opencode --version 2>/dev/null || "$HOME/.local/bin/opencode" --version 2>/dev/null || echo "")
        emit_status "installed" "${GREEN}✅ 已安装${NC} ${ver:+($ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 OpenCode（终端 AI 编程助手，默认动作）
  uninstall   卸载
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_opencode ;;
        uninstall) uninstall_opencode ;;
        status)    status_opencode ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
