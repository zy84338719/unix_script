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
