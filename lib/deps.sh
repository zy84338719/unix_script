#!/usr/bin/env bash
#
# lib/deps.sh
#
# 模块依赖图（阶段 E）。基于 .manifest 的 REQUIRES 字段做：
#   - resolve_deps <mod>      传递依赖（拓扑序、不含自身）
#   - topo_sort_all           全模块安全安装序
#   - 循环依赖检测（遇环报错退出）
#
# 依赖遍历与拓扑排序已下沉到 shellkit 的 registry 模块（registry_deps / registry_topo）：
# 它们做后序 DFS、拓扑序与环检测，字段名（REQUIRES）由这里传进去 ——
# 通用库不该知道 unix_script 的字段名。
#
# bash 3.2 兼容：不使用关联数组与大写展开语法。
#

# 幂等保护
if [[ -n "${_DEPS_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_DEPS_SH_LOADED=1

# resolve_deps <mod> -> 输出 mod 的全部传递依赖（拓扑序、不含 mod 自身、空格分隔）。
# 有环时报错退出（环检测由 registry_deps 负责）。
resolve_deps() {
    registry_deps "$1" REQUIRES || {
        error "检测到循环依赖，请检查对应模块 .manifest 的 REQUIRES 字段"
        exit 1
    }
}

# ensure_module_deps <模块名> —— 安装模块的缺失依赖（阶段 E）。
# resolve_deps 返回拓扑序（被依赖者在前），逐个检查状态，缺则先装。
# UNIX_SCRIPT_NO_DEPS=1 跳过（等价 CLI v2 的 --no-deps）。
ensure_module_deps() {
    local mod="$1"
    [[ "${UNIX_SCRIPT_NO_DEPS:-0}" == "1" ]] && return 0
    local deps
    deps=$(resolve_deps "$mod")
    [[ -z "$deps" ]] && return 0
    local dep dep_path dep_entry dep_state
    for dep in $deps; do
        # 依赖不适用当前系统时明确报错，而非装到一半失败
        if ! uxs_module_visible "$dep"; then
            error "模块 $mod 依赖 ${dep}，但 $dep 不支持当前系统（仅支持：$(registry_platforms "$dep")）"
            exit "$SK_PRECOND"
        fi
        dep_state=$(module_status_machine "$dep")
        if [[ "$dep_state" == "not_installed" ]]; then
            info "自动安装依赖模块：${dep}（被 $mod 需要）"
            dep_path=$(registry_path "$dep")
            dep_entry=$(registry_entry_script "$dep")
            run_in_dir "$dep_path" "$dep_entry" install
        fi
    done
}

# topo_sort_all -> 输出全部已注册模块的安全安装序（拓扑序、空格分隔）。
topo_sort_all() {
    registry_topo REQUIRES || {
        error "检测到循环依赖，请检查对应模块 .manifest 的 REQUIRES 字段"
        exit 1
    }
}
