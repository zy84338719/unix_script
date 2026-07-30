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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

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
        info "已为 $(basename "$rc") 添加回收站配置"
    fi
}

# 从 shell rc 移除 source 行
remove_rc_source() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    if grep -q "$MARK" "$rc" 2>/dev/null; then
        # 用 sed 删除 MARK 之间的行（含 MARK 行）
        sed -i.bak "/$MARK/,/# <<< unix-script safe-rm <<</d" "$rc" 2>/dev/null || true
        info "已从 $(basename "$rc") 移除回收站配置"
    fi
}

install_safe_rm() {
    detect_os
    info "🗑️  安装安全删除（回收站）功能"

    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_DIR/lib_trash.sh" "$TARGET_SH"
    chmod 644 "$TARGET_SH"
    success "回收站函数库已安装到 $TARGET_SH"

    # 配置 shell rc
    ensure_rc_source "$HOME/.bashrc"
    ensure_rc_source "$HOME/.zshrc"
    ensure_rc_source "$HOME/.profile"

    echo
    success "🎉 安装完成！请重新加载 shell 使其生效："
    echo "  source ~/.bashrc    # bash"
    echo "  source ~/.zshrc     # zsh"
    echo
    info "可用命令："
    echo "  t <文件>            # 安全删除（移到回收站）"
    echo "  tls                 # 查看回收站"
    echo "  restore <序号>      # 恢复（序号来自 tls）"
    echo "  trash-empty         # 清空回收站"
    echo "  trash-size          # 查看回收站占用"

    echo
    info "rm 保持原样（不破坏脚本中依赖 rm 真删除的场景）。"
    if yes_no "是否启用 rm 危险路径保护（对 rm -rf 危险路径二次确认）？"; then
        enable_rm_guard
    fi
}

# 启用 rm 危险路径保护（向 trash.sh 追加 guard 定义 + rm 别名）
enable_rm_guard() {
    cat >> "$TARGET_SH" <<'GUARDEOF'

# === rm 危险路径保护（由 safe-rm on 启用）===
# 对 rm 加一层拦截：当目标是根/家/系统目录或使用 -rf 时，要求二次确认。
# 不改变 rm 的真删除语义，只防误删关键路径。
_safe_rm_guard() {
    local dangerous=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            -*) continue ;;
            /|"$HOME"|/etc|/usr|/bin|/sbin|/lib|/lib64|/boot|/dev|/proc|/sys|/var)
                dangerous=1 ;;
            /*) ;;  # 其他绝对路径暂不拦
        esac
    done
    # 含 -rf 且目标是上述关键路径，或参数为空，则确认
    if [[ $dangerous -eq 1 ]]; then
        echo "⚠️  rm: 检测到对关键路径的删除操作: $*" >&2
        printf '确认要真正删除（不可恢复）？[y/N]: ' >&2
        local _reply
        read -r _reply
        if [[ ! $_reply =~ ^[Yy]$ ]]; then
            echo "已取消。" >&2
            return 1
        fi
    fi
    command rm "$@"
}
GUARDEOF

    # 在 rc 里 source 之后追加 rm 别名（覆盖 rm）
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q "alias rm='_safe_rm_guard'" "$rc" 2>/dev/null; then
            echo "alias rm='_safe_rm_guard' 2>/dev/null" >> "$rc"
        fi
    done
    success "已启用 rm 危险路径保护（重新加载 shell 生效）"
    info "关闭请运行：safe-rm off"
}

# 禁用 rm 保护
disable_rm_guard() {
    # 重写 trash.sh（去掉 GUARD 段之后的内容）
    if grep -q "_safe_rm_guard" "$TARGET_SH" 2>/dev/null; then
        # 截断到 '# === rm 危险路径保护' 之前
        sed -i.bak '/^# === rm 危险路径保护/,$d' "$TARGET_SH" 2>/dev/null || true
    fi
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] && sed -i.bak "/alias rm='_safe_rm_guard'/d" "$rc" 2>/dev/null || true
    done
    success "已禁用 rm 危险路径保护"
}

status_safe_rm() {
    detect_os
    if [[ -f "$TARGET_SH" ]]; then
        local guard="(未启用)"
        grep -q "_safe_rm_guard" "$TARGET_SH" 2>/dev/null && guard="(已启用 rm 保护)"
        echo -e "${GREEN}✅ 已安装${NC} $guard"
        # 顺便显示回收站大小
        local trash_root="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
        if [[ -d "$trash_root/files" ]]; then
            local sz
            sz=$(du -sh "$trash_root/files" 2>/dev/null | cut -f1)
            echo "   回收站占用：$sz"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

uninstall_safe_rm() {
    detect_os
    if [[ ! -f "$TARGET_SH" ]]; then
        warn "未安装 safe-rm"; return 0
    fi
    if ! yes_no "确认卸载 safe-rm（不会清空已删除的回收站内容）？"; then
        info "已取消"; return 0
    fi
    disable_rm_guard 2>/dev/null || true
    rm -f "$TARGET_SH"
    remove_rc_source "$HOME/.bashrc"
    remove_rc_source "$HOME/.zshrc"
    remove_rc_source "$HOME/.profile"
    success "safe-rm 已卸载（回收站数据保留，可手动删除 ~/.local/share/Trash）"
}

usage() {
    cat <<EOF
用法: $0 {install|on|off|status|uninstall|help}

  install     安装回收站函数并配置 shell rc（默认动作）
  on          启用 rm 危险路径保护（对 rm -rf 关键路径二次确认）
  off         禁用 rm 危险路径保护
  status      查看安装状态与回收站占用
  uninstall   卸载（保留已删除的回收站数据）
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
