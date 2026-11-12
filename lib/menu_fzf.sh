#!/usr/bin/env bash
#
# lib/menu_fzf.sh
#
# fzf 交互菜单：模糊搜索 + TAB 多选 + 右侧 README 预览。
# 依赖 fzf（可选）：由 lib/menu.sh 的 resolve_menu_mode 保证仅在 fzf 存在时进入。
# 行格式（TAB 分隔）：图标\t模块名\tLABEL\tDESC\t物理路径
#

# 幂等保护
if [[ -n "${_MENU_FZF_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_MENU_FZF_SH_LOADED=1

# fzf ≥ 0.20.0 才有 --preview；1.x 及以上恒真
_fzf_preview_supported() {
    command -v fzf >/dev/null 2>&1 || return 1
    local v maj min
    v=$(fzf --version 2>/dev/null | awk '{print $1}')
    maj=${v%%.*}
    min=${v#*.}; min=${min%%.*}
    [[ "$maj" =~ ^[0-9]+$ ]] || return 1
    if (( maj > 0 )); then return 0; fi
    [[ "$min" =~ ^[0-9]+$ ]] && (( min >= 20 ))
}

# ---------------- 管理项（与 bash 菜单的 s/u/c/f 一一对应） ----------------
# ★ 为什么必须有：fzf 模式接管后，bash 菜单（分类导航 + 状态/卸载/更新/刷新）
#   整个到不了 —— 列表里只有模块、选中只能执行默认动作（装），
#   「uxs 退化成只能装的搜索框」，老的交互手感全没了。
#   这里把四个管理入口补回列表顶部，与 bash 菜单对齐。
#
# 行格式（6 段）：图标	标题	说明	(空)	(空)	动作键
# 动作键放第 6 段，配合 --with-nth=1..5 隐藏 ⇒ 列表里不出现内部标识。
menu_fzf_admin_rows() {
    printf '⚙\t状态总览\t查看所有模块的安装状态\t\t\t__uxs_admin_status__\n'
    printf '🗑\t卸载服务/环境\t交互式卸载已安装的模块\t\t\t__uxs_admin_uninstall__\n'
    printf '🔄\t检查更新\t检查并更新到最新版本\t\t\t__uxs_admin_update__\n'
    printf '⟳\t刷新状态缓存\t重新检测所有模块的安装状态\t\t\t__uxs_admin_refresh__\n'
}

# 管理项 → 实际动作（与 bash 菜单同款）
menu_fzf_run_admin() {
    case "$1" in
        __uxs_admin_status__) show_installed_services ;;
        __uxs_admin_uninstall__) uninstall_menu_loop ;;
        __uxs_admin_update__) menu_check_update ;;
        __uxs_admin_refresh__) menu_refresh_status_cache ;;
        *)
            menu_error "未知管理项: $1"
            return 1
            ;;
    esac
}

# 构造 fzf 列表：管理项在最前，模块行随后（纯函数，可测）
menu_fzf_build_list() {
    local lines="" mod state icon label desc path
    lines=$(menu_fzf_admin_rows)
    for mod in $(registry_visible_modules); do
        state=$(status_state_get "$mod")
        icon=$(status_icon "$state")
        label=$(_reg_get "$mod" LABEL)
        desc=$(registry_desc "$mod")
        path=$(registry_path "$mod")
        lines+="${icon}	${mod}	${label}	${desc}	${path}	"$'\n'
    done
    printf '%s' "$lines"
}

menu_fzf_main() {
    menu_status_ensure
    # preview 子 shell 需要仓库绝对路径
    export UXS_REPO_DIR="$SCRIPT_DIR"

    local -a fzf_args=(--multi --header="TAB 多选 · 回车执行默认动作 · ESC 退出" --delimiter=$'\t' --with-nth=1..5)
    if _fzf_preview_supported; then
        # shellcheck disable=SC2016  # $UXS_REPO_DIR 由 fzf preview 子 shell 展开，非本 shell
        fzf_args+=(
            --preview 'head -30 "$UXS_REPO_DIR/{5}/README.md" 2>/dev/null || echo "（无模块 README）"'
            --preview-window "right:40%:wrap"
        )
    fi

    local selected admin mods
    while true; do
        local lines
        lines=$(menu_fzf_build_list)

        if ! selected=$(printf '%s' "$lines" | fzf "${fzf_args[@]}"); then
            # ESC / Ctrl-C / 无选择：静默返回
            return 0
        fi

        # 第 6 段非空 ⇒ 管理项；否则第 2 段是模块名。
        # 用 awk 解析而不是 read：IFS=TAB 时连续 TAB 会被当成一个分隔符，
        # 空字段会被吞掉（管理项的第 4/5 段就是空的）。
        admin=$(printf '%s\n' "$selected" | awk -F'\t' '$6 != "" {print $6; exit}')
        mods=$(printf '%s\n' "$selected" | awk -F'\t' '$6 == "" {print $2}' | tr '\n' ' ')

        if [[ -n "$admin" ]]; then
            # 管理项是「页面」不是「动作」：执行完回到选择器，可以接着操作
            menu_fzf_run_admin "$admin" || true
            continue
        fi

        local -a mod_list
        read -ra mod_list <<< "$mods"
        if [[ ${#mod_list[@]} -eq 0 ]]; then continue; fi
        menu_exec_actions "${mod_list[@]}"
        return 0
    done
}
