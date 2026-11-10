#!/usr/bin/env bash
#
# lib/cli_v2.sh
#
# CLI v2：分组子命令面。
#
# 分发规则（两层）：
#   1) 首参是保留词 → 当命令解析；每个命令有自己的 flag 集合。
#   2) 首参不是保留词 → 当模块名直通（uxs <mod> [subcmd...]）。
#
# 旧扁平写法一次性删除（无兼容期）：命中即退出 2 并给一行迁移指引 ——
# 命令照样失败，指引只告诉用户新写法，不构成兼容路径。
#
# 退出码口径（AGENTS.md「退出码约定」）：
#   0 成功 / 1 一般错误 / 2 用法错 / 3 前置不满足 / 4 网络失败 / 5 校验失败
#
# 依赖：registry（注册表与可见性）/ deps（依赖拓扑）/ status（状态契约）/
#       core（run_in_dir）/ menu（呈现）/ profile / uxs_cli / doctor / scaffold
#
# bash 3.2 兼容：不用关联数组、不用大写展开、不用 nameref；
# 空数组展开一律写 ${arr[@]+"${arr[@]}"}。

if [[ -n "${_CLI_V2_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_CLI_V2_LOADED=1

# ---------------- 保留词表 ----------------
# 首参命中即当命令，不当模块名（78 个模块已逐个核对，无一撞名）。
CLI_V2_COMMANDS="install remove status list search info doctor export apply update scaffold completions cli help version"

# cli_v2_is_command <词> — 是否保留词
cli_v2_is_command() {
    local w="${1:-}" c
    for c in $CLI_V2_COMMANDS; do
        [[ "$w" == "$c" ]] && return 0
    done
    return 1
}

# cli_v2_migration_for <旧写法> — 输出新写法；查不到返回 1
# 用 case 而不是数据串：新写法里带空格（"uxs list --full"），数据串会被分词拆坏。
cli_v2_migration_for() {
    case "${1:-}" in
        --list)            printf '%s' "uxs list" ;;
        --list-modules)    printf '%s' "uxs list --full" ;;
        --list-categories) printf '%s' "uxs list --grouped" ;;
        --status)          printf '%s' "uxs status" ;;
        --status-json)     printf '%s' "uxs status --json" ;;
        --dry-run)         printf '%s' "uxs install <模块> --dry-run" ;;
        --no-deps)         printf '%s' "uxs install <模块> --no-deps" ;;
        search)            printf '%s' "uxs search" ;;
        export)            printf '%s' "uxs export" ;;
        export-profile)    printf '%s' "uxs export" ;;
        apply)             printf '%s' "uxs apply" ;;
        apply-profile)     printf '%s' "uxs apply" ;;
        check-update)      printf '%s' "uxs update --check" ;;
        update)            printf '%s' "uxs update" ;;
        scaffold)          printf '%s' "uxs scaffold" ;;
        doctor)            printf '%s' "uxs doctor" ;;
        completions)       printf '%s' "uxs completions" ;;
        cli)               printf '%s' "uxs cli install" ;;
        install-cli)       printf '%s' "uxs cli install" ;;
        uninstall-cli)     printf '%s' "uxs cli uninstall" ;;
        remove-cli)        printf '%s' "uxs cli uninstall" ;;
        *)                 return 1 ;;
    esac
}

# ---------------- 诊断输出 ----------------
# 本文件的诊断一律走 stderr：stdout 只给数据（list --full / status --json / info）。
cli_v2_bad_option() {
    local opt="${1:-}" hint
    hint=$(cli_v2_migration_for "$opt" || true)
    error "未知选项: $opt" >&2
    if [[ -n "$hint" ]]; then
        info "该写法已删除，请改用: $hint" >&2
    fi
    exit "$SK_USAGE"
}

cli_v2_unknown_module() {
    local name="${1:-}"
    error "未知模块: $name" >&2
    local -a cand=()
    read -ra cand <<< "$(suggest_module "$name")"
    if [[ ${#cand[@]} -gt 0 ]]; then
        printf '  你是想输入 %s 吗？（uxs install %s）\n' "${cand[0]}" "${cand[0]}" >&2
        if [[ ${#cand[@]} -gt 1 ]]; then
            printf '  其他候选: %s\n' "${cand[*]:1}" >&2
        fi
    fi
    info "查看全部模块: uxs list --grouped" >&2
    exit "$SK_PRECOND"
}

# ---------------- 模块动作 ----------------
# cli_v2_module_action <模块名> <动作...> —— 按**显式**动作执行模块
# 与 dispatch_module 的差别：不套 DEFAULT_ACTION（显式动作优先）；
# 动作是 install 时先补齐缺失依赖（阶段 E）——与默认动作路径保持一致。
cli_v2_module_action() {
    local name="${1:-}"
    shift
    local resolved mod_path entry_script rc
    resolved=$(registry_resolve_alias "$name" || true)
    if [[ "$resolved" == "$name" ]] && ! echo "$_REGISTRY_MODULES" | grep -qw "$name"; then
        cli_v2_unknown_module "$name"
    fi
    platform_gate_or_die "$resolved" "$name"
    mod_path=$(registry_path "$resolved")
    entry_script=$(registry_entry_script "$resolved")
    if [[ "${1:-}" == "install" ]]; then
        ensure_module_deps "$resolved"
    fi
    run_in_dir "$mod_path" "$entry_script" "$@"
    rc=$?
    if [[ "$rc" -eq 0 ]] && [[ "${1:-}" == "install" ]]; then
        show_next_steps "$resolved"
    fi
    return "$rc"
}

# ---------------- 各命令 ----------------

# cli_v2_install <模块>... [--no-deps] [--dry-run]
cli_v2_install() {
    local dry=0 nodeps=0
    local -a mods=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry=1; shift ;;
            --no-deps) nodeps=1; shift ;;
            -*) cli_v2_bad_option "$1" ;;
            *) mods[${#mods[@]}]="$1"; shift ;;
        esac
    done
    if [[ ${#mods[@]} -eq 0 ]]; then
        error "用法: uxs install <模块>... [--no-deps] [--dry-run]" >&2
        exit "$SK_USAGE"
    fi
    if [[ "$dry" -eq 1 ]]; then
        export UNIX_SCRIPT_DRY_RUN=1
        uxs_install_sudo_shim
    fi
    if [[ "$nodeps" -eq 1 ]]; then
        export UNIX_SCRIPT_NO_DEPS=1
    fi
    local mod rc=0
    for mod in "${mods[@]}"; do
        cli_v2_module_action "$mod" install || rc=$?
    done
    return "$rc"
}

# cli_v2_remove <模块>...
cli_v2_remove() {
    local -a mods=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -*) cli_v2_bad_option "$1" ;;
            *) mods[${#mods[@]}]="$1"; shift ;;
        esac
    done
    if [[ ${#mods[@]} -eq 0 ]]; then
        error "用法: uxs remove <模块>..." >&2
        exit "$SK_USAGE"
    fi
    local mod rc=0
    for mod in "${mods[@]}"; do
        cli_v2_module_action "$mod" uninstall || rc=$?
    done
    return "$rc"
}

# cli_v2_status [模块...] [--json] [--all]
cli_v2_status() {
    local json=0 show_all=0
    local -a mods=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json=1; shift ;;
            --all) show_all=1; shift ;;
            -*) cli_v2_bad_option "$1" ;;
            *) mods[${#mods[@]}]="$1"; shift ;;
        esac
    done
    if [[ "$show_all" -eq 1 ]]; then
        export UNIX_SCRIPT_SHOW_ALL=1
    fi
    if [[ "$json" -eq 1 ]]; then
        if [[ ${#mods[@]} -eq 0 ]]; then
            show_status_json
            return 0
        fi
        local mod state version
        for mod in "${mods[@]}"; do
            state=$(module_status_machine "$mod") || state="not_installed"
            version=$(_uxs_version_get "$mod")
            if [[ -n "$version" ]]; then
                printf '%s:%s:%s\n' "$mod" "$state" "$version"
            else
                printf '%s:%s\n' "$mod" "$state"
            fi
        done
        return 0
    fi
    if [[ ${#mods[@]} -eq 0 ]]; then
        show_installed_services
        return 0
    fi
    local mod rc=0
    for mod in "${mods[@]}"; do
        cli_v2_module_action "$mod" status || rc=$?
    done
    return "$rc"
}

# cli_v2_list [--full] [--grouped] [--category <分类>] [--all]
cli_v2_list() {
    local full=0 grouped=0 category="" show_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full) full=1; shift ;;
            --grouped) grouped=1; shift ;;
            --category)
                category="${2:-}"
                shift 2
                ;;
            --all) show_all=1; shift ;;
            -*) cli_v2_bad_option "$1" ;;
            *) cli_v2_bad_option "$1" ;;
        esac
    done
    if [[ "$show_all" -eq 1 ]]; then
        export UNIX_SCRIPT_SHOW_ALL=1
    fi
    if [[ "$full" -eq 1 ]]; then
        show_list_modules
        return 0
    fi
    if [[ "$grouped" -eq 1 ]]; then
        show_list_categories "$category"
        return 0
    fi
    local mod
    for mod in $(registry_visible_modules); do
        if [[ -n "$category" ]]; then
            [[ "$(registry_category "$mod")" == "$category" ]] || continue
        fi
        printf '%s ' "$mod"
    done
    echo
    return 0
}

# cli_v2_search <关键字>...
cli_v2_search() {
    if [[ $# -eq 0 ]]; then
        error "用法: uxs search <关键字> [关键字...]（匹配模块名/别名/描述，多关键字 AND）" >&2
        exit "$SK_USAGE"
    fi
    show_search_results "$@"
    return $?
}

# cli_v2_info <模块>
cli_v2_info() {
    if [[ $# -ne 1 ]]; then
        error "用法: uxs info <模块>" >&2
        exit "$SK_USAGE"
    fi
    if ! show_module_info "$1"; then
        cli_v2_unknown_module "$1"
    fi
    return 0
}

# cli_v2_export [--out 文件]
cli_v2_export() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out)
                out="${2:-}"
                shift 2
                ;;
            -*) cli_v2_bad_option "$1" ;;
            *) cli_v2_bad_option "$1" ;;
        esac
    done
    export_profile "$out"
    return $?
}

# cli_v2_apply <profile> [--force] [--dry-run]
cli_v2_apply() {
    local file=""
    local -a extra=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) extra[${#extra[@]}]="--force"; shift ;;
            --dry-run) extra[${#extra[@]}]="--dry-run"; shift ;;
            -*) cli_v2_bad_option "$1" ;;
            *) file="$1"; shift ;;
        esac
    done
    if [[ -n "$file" ]]; then
        apply_profile "$file" ${extra[@]+"${extra[@]}"}
    else
        apply_profile ${extra[@]+"${extra[@]}"}
    fi
    return $?
}

# cli_v2_update [--check]
cli_v2_update() {
    local check=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check=1; shift ;;
            -*) cli_v2_bad_option "$1" ;;
            *) cli_v2_bad_option "$1" ;;
        esac
    done
    if [[ "$check" -eq 1 ]]; then
        # 只查不更：恒返回 0（网络不通也不是失败，只是查不到）
        info "检查远端最新版本..."
        if check_for_update 2>/dev/null; then
            warn "有新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST:-?}"
            info "运行 uxs update 一键更新"
        else
            if [[ -n "${REMOTE_LATEST:-}" ]]; then
                success "已是最新版本：$(get_local_version)（远端 ${REMOTE_LATEST}）"
            else
                warn "无法获取远端版本（网络问题或未发布 release），当前版本 $(get_local_version)"
            fi
        fi
        return 0
    fi
    do_self_update
    return $?
}

# cli_v2_scaffold <模块> [--category <分类>] [--label <标签>]
cli_v2_scaffold() {
    local mod="" category="" label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --category)
                category="${2:-}"
                shift 2
                ;;
            --label)
                label="${2:-}"
                shift 2
                ;;
            -*) cli_v2_bad_option "$1" ;;
            *) mod="$1"; shift ;;
        esac
    done
    if [[ -z "$mod" ]]; then
        error "用法: uxs scaffold <模块> [--category <分类>] [--label <标签>]" >&2
        exit "$SK_USAGE"
    fi
    scaffold_module "$mod" "$category" "$label"
    return $?
}

# cli_v2_completions [shell]
cli_v2_completions() {
    case "${1:-}" in
        "")
            install_completions
            ;;
        bash|zsh|fish)
            UXS_COMPLETIONS_SHELL="$1"
            export UXS_COMPLETIONS_SHELL
            install_completions
            ;;
        *)
            error "未知 shell: $1（支持 bash / zsh / fish）" >&2
            exit "$SK_USAGE"
            ;;
    esac
    return $?
}

# cli_v2_cli [install|uninstall]
cli_v2_cli() {
    case "${1:-}" in
        "") install_cli ;;
        install) install_cli ;;
        uninstall) uninstall_cli ;;
        *)
            error "未知子命令: $1（支持 install / uninstall）" >&2
            exit "$SK_USAGE"
            ;;
    esac
    return $?
}

# ---------------- 分发 ----------------
# cli_v2_dispatch <参数...> — CLI v2 分发；内部 exit，不 return
cli_v2_dispatch() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit "$SK_USAGE"
    fi
    local first="$1"
    case "$first" in
        -h | --help)
            show_usage
            exit 0
            ;;
        -v | --version)
            printf 'unix_script %s\n' "$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"
            exit 0
            ;;
        --list-all)
            cli_v2_list --full --all || exit $?
            exit 0
            ;;
        -*)
            cli_v2_bad_option "$first"
            ;;
    esac

    if cli_v2_is_command "$first"; then
        shift
        case "$first" in
            install) cli_v2_install "$@" || exit $? ;;
            remove) cli_v2_remove "$@" || exit $? ;;
            status) cli_v2_status "$@" || exit $? ;;
            list) cli_v2_list "$@" || exit $? ;;
            search) cli_v2_search "$@" || exit $? ;;
            info) cli_v2_info "$@" || exit $? ;;
            doctor) run_doctor || exit $? ;;
            export) cli_v2_export "$@" || exit $? ;;
            apply) cli_v2_apply "$@" || exit $? ;;
            update) cli_v2_update "$@" || exit $? ;;
            scaffold) cli_v2_scaffold "$@" || exit $? ;;
            completions) cli_v2_completions "$@" || exit $? ;;
            cli) cli_v2_cli "$@" || exit $? ;;
            help)
                show_usage
                exit 0
                ;;
            version)
                printf 'unix_script %s\n' "$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"
                exit 0
                ;;
        esac
        exit "$SK_USAGE"
    fi

    # 已删除的旧子命令（check-update / export-profile / install-cli …）：
    # 它们既不是保留词、也不是模块名 —— 必须拦在模块直通之前，
    # 否则会被当成「未知模块」报 3，迁移指引就丢了。
    if cli_v2_migration_for "$first" >/dev/null 2>&1; then
        cli_v2_bad_option "$first"
    fi

    # 非保留词 → 模块直通（uxs <mod> [子命令...]）
    local name="$first" resolved
    resolved=$(registry_resolve_alias "$name" || true)
    if [[ "$resolved" == "$name" ]] && ! echo "$_REGISTRY_MODULES" | grep -qw "$name"; then
        cli_v2_unknown_module "$name"
    fi
    shift
    if [[ $# -eq 0 ]]; then
        # 无子命令 → 走模块默认动作（等价旧的 ./install.sh <mod>）
        dispatch_module "$name" || exit $?
        exit 0
    fi
    if [[ "$1" == "install" ]]; then
        # 显式 install → 走 v2 动作路径（会先补齐缺失依赖）
        cli_v2_module_action "$name" "$@" || exit $?
        exit 0
    fi
    dispatch_module_or_passthrough "$name" "$@" || exit $?
    exit 0
}
