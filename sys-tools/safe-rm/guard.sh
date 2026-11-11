# shellcheck shell=bash

# === rm 危险路径保护（由 safe-rm on 启用）===
# 对 rm 加一层拦截：当目标是根/家/系统目录或使用 -rf 时，要求二次确认。
# 不改变 rm 的真删除语义，只防误删关键路径。
#
# 本文件由 safe-rm/install.sh 用 uxs_i18n_localize_file 处理后追加到
# ~/.local/share/unix-script/trash.sh —— 那个文件被用户的 shell 直接 source，
# 运行时没有 unix_script 的 _t，所以译文只能在这里烘进去。
_safe_rm_guard() {
    local dangerous=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            -*) continue ;;
            /|"$HOME"|/etc|/usr|/bin|/sbin|/lib|/lib64|/boot|/dev|/proc|/sys|/var)
                dangerous=1 ;;
            # 其他绝对路径暂不拦
            /*) ;;
        esac
    done
    # 含 -rf 且目标是上述关键路径，或参数为空，则确认
    if [[ $dangerous -eq 1 ]]; then
        printf '%s\n' "⚠️  $(_tf 'rm: detected a delete on a critical path: %s' "$*")" >&2
        printf '%s' "$(_t 'Really delete (this cannot be undone)? [y/N]:') " >&2
        local _reply
        read -r _reply
        if [[ ! $_reply =~ ^[Yy]$ ]]; then
            printf '%s\n' "$(_t 'Cancelled.')" >&2
            return 1
        fi
    fi
    command rm "$@"
}
