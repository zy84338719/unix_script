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

# topo_sort_all -> 输出全部已注册模块的安全安装序（拓扑序、空格分隔）。
topo_sort_all() {
    registry_topo REQUIRES || {
        error "检测到循环依赖，请检查对应模块 .manifest 的 REQUIRES 字段"
        exit 1
    }
}
