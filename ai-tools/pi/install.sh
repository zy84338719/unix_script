#!/usr/bin/env bash
#
# pi/install.sh
#
# 安装 Pi（pi.dev）—— 极简可定制的 AI 编程代理框架（Earendil Inc.）。
# 支持多模型、树状历史、扩展/技能/提示模板自定义。Linux + macOS。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://pi.dev/install.sh"

preflight() {
    detect_os
    check_commands curl
}

install_pi() {
    preflight
    info "🤖 安装 Pi（AI 编程代理框架，pi.dev）"

    if command_exists pi; then
        local cur
        cur=$(pi --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 Pi（${cur}）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    info "通过官方脚本安装（${OFFICIAL_INSTALLER}）..."
    if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
        error "官方安装脚本执行失败，请检查网络或参考 https://pi.dev"
        exit 1
    fi

    # Pi 可能装到 ~/.pi 或 npm 全局，检测一下
    if ! command_exists pi; then
        # 尝试常见路径
        local found=""
        for p in "$HOME/.pi/bin/pi" "$HOME/.local/bin/pi" "/usr/local/bin/pi"; do
            [[ -x "$p" ]] && found="$p" && break
        done
        if [[ -n "$found" ]]; then
            warn "pi 已装到 ${found}，但不在当前 PATH"
            info "请添加到 shell 配置：export PATH=\"$(dirname "$found"):\$PATH\""
        else
            warn "安装后未立即找到 pi 命令，请重新打开终端或检查 PATH"
            info "Pi 也支持通过 npm/pnpm/bun 安装：npm install -g @earendil-works/pi-coding-agent"
        fi
    fi

    success "🎉 Pi 安装完成！"
    info "快速开始："
    echo "  pi                         # 启动交互式 TUI 会话"
    echo "  pi '修复这个 bug'           # 直接给提示"
    echo "  pi --help                  # 查看帮助"
    echo
    info "配置模型/API Key 与扩展：参考 https://pi.dev"
}

uninstall_pi() {
    preflight
    local removed=false
    # 尝试 pi 自带卸载
    if command_exists pi; then
        pi uninstall >/dev/null 2>&1 && removed=true
    fi
    # 清理常见路径
    for p in "$HOME/.pi/bin/pi" "$HOME/.local/bin/pi" "/usr/local/bin/pi"; do
        if [[ -x "$p" ]]; then
            rm -f "$p"
            removed=true
        fi
    done
    if [[ -d "$HOME/.pi" ]] && yes_no "是否删除 $HOME/.pi（含配置与扩展）？"; then
        rm -rf "$HOME/.pi"
        success "已删除 $HOME/.pi"
    fi
    if $removed; then
        success "Pi 已卸载"
    else
        warn "未找到 Pi 二进制（可能通过 npm 全局安装，请用 npm uninstall -g @earendil-works/pi-coding-agent 卸载）"
    fi
}

status_pi() {
    detect_os
    if command_exists pi || [[ -x "$HOME/.pi/bin/pi" ]]; then
        local ver
        ver=$(pi --version 2>/dev/null || "$HOME/.pi/bin/pi" --version 2>/dev/null || echo "")
        emit_status "installed" "${GREEN}✅ 已安装${NC} ${ver:+($ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Pi（AI 编程代理框架，默认动作）
  uninstall   卸载
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_pi ;;
        uninstall) uninstall_pi ;;
        status)    status_pi ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
