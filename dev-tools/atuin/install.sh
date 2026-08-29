#!/usr/bin/env bash
set -euo pipefail
#
# dev-tools/atuin/install.sh
#
# Atuin：SQLite 化 shell 历史（全量模糊搜索、跨机端到端加密同步）。
# 默认纯本地（UXS_CONFIG_SYNC=0）；UXS_CONFIG_SYNC=1 时提示用户自行注册（不代注册）。
#
# 子命令：install | sync | uninstall | status | help
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

MARK="# >>> unix_script atuin >>>"
ENDMARK="# <<< unix_script atuin <<<"

atuin_bin() {
    if command_exists atuin; then
        command -v atuin
    elif [[ -x "$HOME/.atuin/bin/atuin" ]]; then
        echo "$HOME/.atuin/bin/atuin"
    else
        return 1
    fi
}

install_atuin() {
    detect_os
    if ! atuin_bin >/dev/null; then
        if [[ "$OS_TYPE" == "darwin" ]]; then
            command_exists brew || { error "macOS 需要 Homebrew"; return 1; }
            brew install atuin
        else
            if ! pkg_install atuin >/dev/null 2>&1; then
                # 信任模型：setup.atuin.sh 为官方安装器（HTTPS），装到 $HOME/.atuin/bin（实测）
                local ver
                ver=$(github_latest_tag "atuinsh/atuin" 2>/dev/null || echo "latest")
                info "仓库无 atuin 包，走官方脚本（目标版本：${ver}）..."
                curl -fsSL https://setup.atuin.sh | sh || { error "atuin 安装失败"; return 1; }
            fi
        fi
    fi
    atuin_bin >/dev/null || { error "atuin 仍未可用"; return 1; }

    configure_rc
    import_history

    if [[ "${UXS_CONFIG_SYNC:-0}" == "1" ]]; then
        info "已按 UXS_CONFIG_SYNC=1 配置：请运行  atuin register  注册账号（交互式，需自行操作）"
        info "其他机器  atuin login <用户名> && atuin sync  即可同步历史"
    fi
    success "🎉 Atuin 安装完成（sync=${UXS_CONFIG_SYNC:-0}）"
    info "新开终端或 exec zsh 生效；Ctrl+R 改为 atuin 全量模糊搜索"
}

configure_rc() {
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        [[ -f "$rc" ]] || continue
        grep -q "$MARK" "$rc" 2>/dev/null && continue
        {
            echo ""
            echo "$MARK"
            [[ -x "$HOME/.atuin/bin/atuin" ]] && echo "export PATH=\"\$HOME/.atuin/bin:\$PATH\""
            echo "command -v atuin >/dev/null 2>&1 && eval \"\$(atuin init \$(basename \$SHELL))\""
            echo "$ENDMARK"
        } >> "$rc"
        info "已为 $(basename "$rc") 添加 atuin 集成"
    done
}

import_history() {
    # 首次安装时迁移旧历史；标记文件保证幂等
    local flag="$HOME/.config/atuin/.uxs_imported"
    [[ -f "$flag" ]] && return 0
    if "$(atuin_bin)" import auto >/dev/null 2>&1; then
        info "旧 shell 历史已导入 atuin"
    else
        warn "旧历史导入失败（可稍后手动执行: atuin import auto）"
    fi
    mkdir -p "$(dirname "$flag")"
    touch "$flag"
}

cmd_sync() {
    if [[ "${UXS_CONFIG_SYNC:-0}" != "1" ]]; then
        warn "当前为纯本地模式（UXS_CONFIG_SYNC 未开启），无需同步"
        return 0
    fi
    "$(atuin_bin)" sync
}

uninstall_atuin() {
    detect_os
    warn "atuin 卸载说明："
    echo "  程序:   brew uninstall atuin 或 sudo <pkgmgr> remove atuin"
    echo "  脚本装: rm -rf ~/.atuin（并从 rc 的 PATH 行移除 \$HOME/.atuin/bin）"
    echo "  shell:  删除 rc 中 '$MARK' 标记块"
    echo "  数据:   rm -rf ~/.local/share/atuin ~/.config/atuin"
    info "（按需手动清理）"
}

status_atuin() {
    if atuin_bin >/dev/null; then
        local sync="off"
        grep -qs "$MARK" "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null && sync="on"
        emit_status "installed" "${GREEN}✅ atuin 已安装（shell 集成: ${sync}）${NC}"
        emit_extra "sync=$sync"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
    return 0
}

usage() {
    cat <<EOF
用法: $0 {install|sync|uninstall|status|help}

  install     安装 atuin + rc 集成 + 旧历史导入（UXS_CONFIG_SYNC=1 开启同步提示）
  sync        手动同步（需已开启同步并注册）
  uninstall   显示卸载说明
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_atuin ;;
        sync)      cmd_sync ;;
        uninstall) uninstall_atuin ;;
        status)    status_atuin ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
