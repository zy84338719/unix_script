#!/usr/bin/env bash
#
# safe-rm/install.sh
#
# 安装安全删除（回收站）与可选的 rm 危险路径保护。
# Linux + macOS。纯 shell 函数实现，不依赖外部工具。
#
# 安装后提供命令（写入 shell rc，重新加载生效）:
#   t / trash <文件...>       安全删除（移到回收站）
#   tls / trashlist           查看回收站
#   trash-restore / restore   恢复
#   trash-empty               清空回收站
#   trash-size                查看占用
#
# rm 保护（可选）:
#   safe-rm-on    为 rm 增加危险路径拦截（根/家/系统目录 + -rf 时二次确认）
#   safe-rm-off   还原原始 rm
#
# 子命令：install | status | uninstall | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 安装目标（独立于源码树，shell rc 会 source 它）
INSTALL_DIR="$HOME/.local/share/unix-script"
TARGET_SH="$INSTALL_DIR/trash.sh"
MARK="# >>> unix-script safe-rm >>>"

# 在 shell rc 文件中插入 source 行
ensure_rc_source() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    if ! grep -q "$MARK" "$rc" 2>/dev/null; then
        {
            echo ""
            echo "$MARK"
            echo "[ -f \"$TARGET_SH\" ] && source \"$TARGET_SH\""
            echo "# <<< unix-script safe-rm <<<"
        } >> "$rc"
        info "$(_t 'trash configuration has been added to') $(basename "$rc") $(_t 'by the safe-rm installer')"
    fi
}

# 从 shell rc 移除 source 行
remove_rc_source() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    if grep -q "$MARK" "$rc" 2>/dev/null; then
        # 用 sed 删除 MARK 之间的行（含 MARK 行）
        sed -i.bak "/$MARK/,/# <<< unix-script safe-rm <<</d" "$rc" 2>/dev/null || true
        info "$(_t 'trash configuration has been removed from') $(basename "$rc") $(_t 'by the safe-rm uninstaller')"
    fi
}

install_safe_rm() {
    detect_os
    info "$(_t '🗑️  Installing the safe delete (trash) feature')"

    mkdir -p "$INSTALL_DIR"
    # trash.sh 也是被用户 shell 直接 source 的独立文件 ⇒ 译文在安装时烘进去
    uxs_i18n_localize_file "$SCRIPT_DIR/lib_trash.sh" "$TARGET_SH"
    chmod 644 "$TARGET_SH"
    success "$(_tf 'Trash function library installed to %s' "$TARGET_SH")"

    # 配置 shell rc
    ensure_rc_source "$HOME/.bashrc"
    ensure_rc_source "$HOME/.zshrc"
    ensure_rc_source "$HOME/.profile"

    echo
    success "$(_t '🎉 Installation complete! Reload your shell to take effect:')"
    echo "  source ~/.bashrc    # bash"
    echo "  source ~/.zshrc     # zsh"
    echo
    info "$(_t 'Available commands:')"
    printf '%s\n' "  t <$(_t 'file>            # Safe delete (move to trash)')"
    printf '%s\n' "  tls                 # $(_t 'View the trash')"
    printf '%s\n' "  restore <$(_t 'index>      # Restore (the index comes from tls)')"
    printf '%s\n' "  trash-empty         # $(_t 'Empty the trash')"
    printf '%s\n' "  trash-size          # $(_t 'Show the trash disk usage')"

    echo
    info "rm $(_t 'stays unchanged (so scripts that rely on rm really deleting keep working).')"
    if yes_no "$(_t 'Enable the rm dangerous-path protection (ask again before rm -rf hits a dangerous path)?')"; then
        enable_rm_guard
    fi
}

# 启用 rm 危险路径保护（向 trash.sh 追加 guard 定义 + rm 别名）
enable_rm_guard() {
    # guard.sh 会被追加进 trash.sh —— 那是被用户 shell 直接 source 的文件，
    # 运行时没有 unix_script 的 _t ⇒ 用 uxs_i18n_localize_file 把译文烘进去。
    local guard_tmp
    guard_tmp="$(mktemp "${TMPDIR:-/tmp}/uxs-guard.XXXXXX")"
    if uxs_i18n_localize_file "$SCRIPT_DIR/guard.sh" "$guard_tmp"; then
        cat "$guard_tmp" >> "$TARGET_SH"
    else
        warn "$(_tf 'Failed to write the rm dangerous-path protection: %s' "$guard_tmp")"
    fi
    rm -f "$guard_tmp"

    # 在 rc 里 source 之后追加 rm 别名（覆盖 rm）
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q "alias rm='_safe_rm_guard'" "$rc" 2>/dev/null; then
            echo "alias rm='_safe_rm_guard'" >> "$rc"
        fi
    done
    success "$(_t 'rm dangerous-path protection enabled (reload the shell to take effect)')"
    info "$(_t 'To turn it off run: safe-rm off')"
}

# 禁用 rm 保护
disable_rm_guard() {
    # 重写 trash.sh（去掉 GUARD 段之后的内容）
    if grep -q "_safe_rm_guard" "$TARGET_SH" 2>/dev/null; then
        # 截断到 guard.sh 的标记行之前（标记行以 '# === rm ' 开头，见 guard.sh）
        sed -i.bak '/^# === rm /,$d' "$TARGET_SH" 2>/dev/null || true
    fi
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]]; then
            sed -i.bak "/alias rm='_safe_rm_guard'/d" "$rc" 2>/dev/null || true
        fi
    done
    success "$(_t 'rm dangerous-path protection disabled')"
}

status_safe_rm() {
    detect_os
    if [[ -f "$TARGET_SH" ]]; then
        local guard enabled="no"
        guard="($(_t 'not enabled)')"
        if grep -q "_safe_rm_guard" "$TARGET_SH" 2>/dev/null; then
            guard="($(_t 'rm protection enabled)')"
            enabled="yes"
        fi
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} $guard"
        emit_extra "enabled=$enabled"
        # 回收站大小（仅人类模式）
        if ! uxs_is_machine_mode; then
            local trash_root="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
            if [[ -d "$trash_root/files" ]]; then
                local sz
                sz=$(du -sh "$trash_root/files" 2>/dev/null | cut -f1)
                printf '%s\n' "   $(_tf 'Trash disk usage: %s' "$sz")"
            fi
        fi
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

uninstall_safe_rm() {
    detect_os
    if [[ ! -f "$TARGET_SH" ]]; then
        warn "$(_t 'safe-rm is not installed')"; return 0
    fi
    if ! yes_no "$(_t 'Confirm uninstalling safe-rm?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi

    # 卸载前询问是否清空回收站数据
    local trash_root="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
    if [[ -d "$trash_root/files" ]] && [[ -n "$(ls -A "$trash_root/files" 2>/dev/null)" ]]; then
        local sz
        sz=$(du -sh "$trash_root/files" 2>/dev/null | cut -f1)
        info "$(_tf 'Current trash disk usage: %s (path %s)' "${sz}" "${trash_root}")"
        if yes_no "$(_t 'Empty the trash data as well (it cannot be recovered)?')"; then
            rm -rf "${trash_root}/files/"* "${trash_root}/info/"* 2>/dev/null || true
            success "$(_t 'Trash emptied')"
        else
            info "$(_tf 'Trash data kept (delete %s manually)' "${trash_root}")"
        fi
    else
        info "$(_t 'The trash is already empty, nothing to clean up')"
    fi

    disable_rm_guard 2>/dev/null || true
    rm -f "$TARGET_SH"
    remove_rc_source "$HOME/.bashrc"
    remove_rc_source "$HOME/.zshrc"
    remove_rc_source "$HOME/.profile"
    success "safe-rm $(_t 'Uninstalled')"
}

usage() {
    cat <<EOF
用法: $0 {install|on|off|status|uninstall|help}

  install     $(_t 'Install the trash functions and configure the shell rc (default action)')
  on          $(_t 'Enable the rm dangerous-path protection (ask again before rm -rf hits a critical path)')
  off         $(_t 'Disable the rm dangerous-path protection')
  status      $(_t 'Show the install status and the trash disk usage')
  uninstall   $(_t 'Uninstall (the deleted trash data is kept)')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_safe_rm ;;
        on)        enable_rm_guard ;;
        off)       disable_rm_guard ;;
        status)    status_safe_rm ;;
        uninstall) uninstall_safe_rm ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
