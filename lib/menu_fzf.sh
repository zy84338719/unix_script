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

menu_fzf_main() {
    menu_status_ensure
    # preview 子 shell 需要仓库绝对路径
    export UXS_REPO_DIR="$SCRIPT_DIR"

    local lines="" mod state icon label desc path
    for mod in $(registry_visible_modules); do
        state=$(status_state_get "$mod")
        icon=$(status_icon "$state")
        label=$(_reg_get "$mod" LABEL)
        desc=$(registry_desc "$mod")
        path=$(registry_path "$mod")
        lines+="${icon}	${mod}	${label}	${desc}	${path}"$'\n'
    done

    local -a fzf_args=(--multi --header="TAB 多选 · 回车执行默认动作 · ESC 退出" --delimiter=$'\t')
    if _fzf_preview_supported; then
        # shellcheck disable=SC2016  # $UXS_REPO_DIR 由 fzf preview 子 shell 展开，非本 shell
        fzf_args+=(
            --preview 'head -30 "$UXS_REPO_DIR/{5}/README.md" 2>/dev/null || echo "（无模块 README）"'
            --preview-window "right:40%:wrap"
        )
    fi

    local selected
    if ! selected=$(printf '%s' "$lines" | fzf "${fzf_args[@]}"); then
        # ESC / Ctrl-C / 无选择：静默返回
        return 0
    fi
    local -a mods
    read -ra mods <<< "$(printf '%s\n' "$selected" | awk -F'\t' '{print $2}' | tr '\n' ' ')"
    if [[ ${#mods[@]} -eq 0 ]]; then return 0; fi
    menu_exec_actions "${mods[@]}"
}
