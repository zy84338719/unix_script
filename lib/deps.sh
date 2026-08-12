#!/usr/bin/env bash
#
# lib/deps.sh
#
# 模块依赖图（阶段 E）。基于 .manifest 的 REQUIRES 字段做：
#   - resolve_deps <mod>      传递依赖（拓扑序、不含自身）
#   - topo_sort_all           全模块安全安装序
#   - 循环依赖检测（遇环报错退出）
#
# bash 3.2 兼容：用空格分隔字符串模拟 visited 集合与 DFS 栈（不用关联数组）。
# 详见 docs/superpowers/specs/2026-08-07-status-contract-deps-profile-design.md 阶段 E。
#

# 幂等保护
if [[ -n "${_DEPS_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_DEPS_SH_LOADED=1

# --- 内部 DFS 状态（每次 resolve_deps / topo_sort_all 前重置）---
_DEPS_VISITED=""   # 已完成访问的节点集合（空格分隔）
_DEPS_RESULT=""    # 后序结果（拓扑序：被依赖者在前）
_DEPS_PATH=""      # 当前递归栈（用于环检测）

# _resolve_deps_visit <mod>
# 后序 DFS：先递归依赖，再把自身追加到结果。结果天然为拓扑序。
# 环检测：若 mod 已在当前 _DEPS_PATH 栈中 → 循环依赖，报错退出。
_resolve_deps_visit() {
    local mod="$1"

    # 环检测：在当前递归路径上再次遇到 → 循环
    if [[ " ${_DEPS_PATH} " == *" $mod "* ]]; then
        error "检测到循环依赖：${_DEPS_PATH# } → $mod"
        error "请检查对应模块 .manifest 的 REQUIRES 字段"
        exit 1
    fi

    # 已完成访问的节点跳过（去重）
    [[ " ${_DEPS_VISITED} " == *" $mod "* ]] && return 0
    _DEPS_VISITED="${_DEPS_VISITED} $mod"
    _DEPS_PATH="${_DEPS_PATH} $mod"

    local dep
    for dep in $(registry_requires "$mod"); do
        # 引用了未注册的模块：警告并跳过（不致整体崩溃）
        if ! echo "${_REGISTRY_MODULES}" | grep -qw "$dep"; then
            warn "模块 $mod 声明了未知依赖：${dep}（已忽略）"
            continue
        fi
        _resolve_deps_visit "$dep"
    done

    _DEPS_RESULT="${_DEPS_RESULT} $mod"
    # 弹栈：移除末尾的 " $mod"（$mod 需引号，否则按模式匹配，见 SC2295）
    _DEPS_PATH="${_DEPS_PATH% "$mod"}"
}

# resolve_deps <mod> -> 输出 mod 的全部传递依赖（拓扑序、不含 mod 自身、空格分隔）。
resolve_deps() {
    local mod="$1"
    _DEPS_VISITED=""
    _DEPS_RESULT=""
    _DEPS_PATH=""
    _resolve_deps_visit "$mod"
    # 从后序结果中剔除 mod 自身（mod 作为 root 最后入结果，但保险起见全量过滤）
    local out="" m
    for m in $_DEPS_RESULT; do
        [[ "$m" != "$mod" ]] && out="${out} $m"
    done
    echo "${out# }"
}

# topo_sort_all -> 输出全部已注册模块的安全安装序（拓扑序、空格分隔）。
# 对每个模块各起一次 DFS；已访问节点会去重，最终覆盖全部模块。
topo_sort_all() {
    _DEPS_VISITED=""
    _DEPS_RESULT=""
    _DEPS_PATH=""
    local mod
    for mod in $_REGISTRY_MODULES; do
        _resolve_deps_visit "$mod"
    done
    echo "${_DEPS_RESULT# }"
}
