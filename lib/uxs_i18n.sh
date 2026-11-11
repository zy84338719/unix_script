#!/usr/bin/env bash
#
# unix_script 的 i18n 配置。
#
# shellkit 的 _t 默认查 shellkit 域；unix_script 自己的文案走 unix_script 域。
# 两个域共用一套查找目录：先 unix_script 自己的 locale，再 shellkit 的 locale。
#
# SHELLKIT_LANG 默认 zh_CN：unix_script 的用户是中文优先；
# 没有 gettext 的机器靠 shellkit 的纯 bash 兜底表出中文。
#
# 幂等保护
if [[ -n "${_UXS_I18N_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_UXS_I18N_LOADED=1

# uxs_i18n_init ROOT —— 配置 i18n 域与查找目录
# ROOT 是 unix_script 仓库根（用来定位 locale/）。
uxs_i18n_init() {
    local root="${1:-.}"
    local sk_locale="${SHELLKIT_HOME:-}/locale"

    export SHELLKIT_I18N_DOMAIN="unix_script"
    export SHELLKIT_I18N_DIRS="$root/locale:$sk_locale"
    export SHELLKIT_LANG="${SHELLKIT_LANG:-zh_CN}"

    # 设置域与目录发生在 bootstrap 之后：把兜底表按新配置重载一次，
    # 否则「bootstrap 之后才设环境变量」的用法永远不生效。
    if declare -f _sk_i18n_load_tables >/dev/null 2>&1; then
        _SK_I18N_TABLES=""
        _SK_I18N_TABLES_KEY=""
        _sk_i18n_load_tables "$(_sk_i18n_lang _uxs_i18n_lang)" "unix_script" "$SHELLKIT_I18N_DIRS" || true
    fi
    return 0
}

# ---------------------------------------------------------------------------
# uxs_i18n_localize_file SRC DST —— 把译文烘进文件（安装时做一次）
#
# 为什么需要它：有些模块会把**独立脚本**复制到用户环境里跑
# （safe-rm 的 trash.sh、process_manager_tool 的 pm 包装脚本）。
# 那些脚本被用户的 shell 直接执行，运行时没有 unix_script 的 _t ——
# 译文进不了它们。只能在**安装时**把当前语言的文字烘进去。
#
# 改写规则：
#   $(_t  'msgid')           → $(printf '%s' '译文')
#   $(_tf 'msgid' ARG...)    → $(printf '译文' ARG...)
#
# 译文里的单引号按 shell 规则转义；译文里的 % 是 printf 占位符
# （msgfmt --check 保证占位符与 msgid 一致）。
# ---------------------------------------------------------------------------
uxs_i18n_sq() {
    # 单引号串：内部单引号转义成 ' \''
    local s="$1" out="" i c
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        if [ "$c" = "'" ]; then
            out="${out}'\\''"
        else
            out="${out}${c}"
        fi
    done
    printf "'%s'" "$out"
}

uxs_i18n_localize_file() {
    local src="$1" dst="$2"
    if [ ! -f "$src" ]; then
        printf 'uxs_i18n_localize_file: %s 不存在\n' "$src" >&2
        return 1
    fi
    local re_t re_tf line out mid args txt repl tmp
    re_t="[$][(][[:space:]]*_t[[:space:]]*'([^']*)'[[:space:]]*[)]"
    re_tf="[$][(][[:space:]]*_tf[[:space:]]*'([^']*)'([^)]*)[)]"
    tmp="${dst}.tmp.$$"
    : > "$tmp" || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        out="$line"
        while :; do
            if [[ "$out" =~ $re_tf ]]; then
                mid="${BASH_REMATCH[1]}"
                args="${BASH_REMATCH[2]}"
            elif [[ "$out" =~ $re_t ]]; then
                mid="${BASH_REMATCH[1]}"
                args=""
            else
                break
            fi
            txt="$(_t "$mid")"
            if [ -n "$args" ]; then
                repl="\$(printf $(uxs_i18n_sq "$txt")$args)"
            else
                repl="\$(printf '%s' $(uxs_i18n_sq "$txt"))"
            fi
            out="${out//"${BASH_REMATCH[0]}"/$repl}"
        done
        printf '%s\n' "$out" >> "$tmp"
    done < "$src"
    mv "$tmp" "$dst"
}
