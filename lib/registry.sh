#!/usr/bin/env bash
#
# lib/registry.sh
#
# 模块注册表引擎：扫描各分类子目录下的 .manifest 文件，
# 提供统一的元数据查询 API。
#
# Manifest 格式（纯文本 key=value）：
#   LABEL=显示名称          （必填）
#   DESC=一句话中文描述      （可选，≤20 字，菜单/补全/--list-modules 展示用）
#   NEXT_STEPS=条目1;条目2  （可选，安装成功后的下一步提示；分号分隔，条目内冒号分隔「说明:命令」）
#   CATEGORY=分类           （必填：服务/装机必备/开发环境/AI工具/系统工具）
#   ALIASES=别名1,别名2     （可选，逗号分隔）
#   DEFAULT_ACTION=install  （可选，默认 install）
#   HAS_SUBMENU=docker      （可选，非空则交互菜单进入子菜单）
#   PLATFORMS=linux,darwin  （可选，声明适用 OS；缺省=全平台，不适用当前系统的模块在各出口隐藏）
#
# 目录结构：模块按分类组织在子目录中：
#   services/    → 服务
#   essentials/  → 装机必备
#   dev-tools/   → 开发环境
#   ai-tools/    → AI工具
#   sys-tools/   → 系统工具
#
# 实现：用 eval 创建动态变量（兼容 bash 3.2，macOS 默认版本）。
#

# 幂等保护
if [[ -n "${_REGISTRY_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_REGISTRY_LOADED=1

# 模块名的有序列表（按发现顺序）
_REGISTRY_MODULES=""

# 分类顺序（用于菜单展示排序）
CATEGORY_ORDER="服务 装机必备 开发环境 AI工具 系统工具"

# 分类目录名列表（与 CATEGORY_ORDER 一一对应）
_CATEGORY_DIRS="services essentials dev-tools ai-tools sys-tools"




# --- 内部：解析单个 manifest 文件 ---
_parse_manifest() {
    local mod="$1" manifest="$2"
    # 登记进 shellkit 的索引：字段取值统一走 registry_get（不再自己存一份）
    registry_add "$mod" "$manifest"
    # 必填字段校验
    local lbl cat
    lbl="$(registry_get "$mod" LABEL)"
    cat="$(registry_get "$mod" CATEGORY)"
    if [[ -z "$lbl" || -z "$cat" ]]; then
        warn "manifest 缺少必填字段: $manifest" >&2
        return 1
    fi
    return 0
}

# _uxs_manifest_path <模块名> —— 该模块清单文件的绝对路径；找不到返回 1
_uxs_manifest_path() {
    local mod="$1" category_dir
    for category_dir in $_CATEGORY_DIRS; do
        [[ -f "$SCRIPT_DIR/$category_dir/$mod/.manifest" ]] || continue
        printf '%s
' "$SCRIPT_DIR/$category_dir/$mod/.manifest"
        return 0
    done
    return 1
}

# --- 扫描所有分类子目录下的 .manifest 文件 ---
registry_scan() {
    local category_dir mod lbl cat manifest
    local -a roots=()
    _REGISTRY_MODULES=""
    # 清单分散在多个分类目录（<分类>/<模块>/.manifest 是两层）：
    # shellkit 的 registry_scan_multi 一次扫多个根目录，索引是累加的，顺序跟着根目录走。
    for category_dir in $_CATEGORY_DIRS; do
        [[ -d "$SCRIPT_DIR/$category_dir" ]] || continue
        roots[${#roots[@]}]="$SCRIPT_DIR/$category_dir"
    done
    registry_scan_multi '.manifest' ${roots[@]+"${roots[@]}"}

    # 只收必填字段齐全的模块（缺 LABEL / CATEGORY 的要告警并跳过）
    for mod in $(registry_list); do
        manifest="$(_uxs_manifest_path "$mod")"
        lbl="$(registry_get "$mod" LABEL)"
        cat="$(registry_get "$mod" CATEGORY)"
        if [[ -z "$lbl" || -z "$cat" ]]; then
            warn "manifest 缺少必填字段: $manifest" >&2
            continue
        fi
        _REGISTRY_MODULES="$_REGISTRY_MODULES $mod"
    done
    _REGISTRY_MODULES="${_REGISTRY_MODULES# }"
}

# _reg_get <模块名> <字段> —— 旧调用点的兼容入口
# 字段取值已经下沉到 shellkit 的 registry_get（不再自己用 eval 存一份）。
_reg_get() {
    registry_get "$1" "$2"
}

# --- 查询 API ---
registry_label()           { registry_get "$1" LABEL; }
registry_desc()            { registry_get "$1" DESC; }
registry_category()        { registry_get "$1" CATEGORY; }
registry_aliases()         { registry_get "$1" ALIASES; }
registry_next_steps()      { registry_get "$1" NEXT_STEPS; }

# registry_search <关键字...> — 全注册表搜索（批次③）。
# 匹配域：模块名+别名+LABEL+DESC 拼接；大小写不敏感子串；多关键字 AND。
# 输出命中模块名（注册表序，每行一个）；无匹配输出空。
registry_search() {
    [[ $# -eq 0 ]] && return 0
    local mod hay kw ok
    for mod in $_REGISTRY_MODULES; do
        hay="$mod|$(registry_aliases "$mod")|$(registry_label "$mod")|$(registry_desc "$mod")"
        hay=$(printf '%s' "$hay" | tr '[:upper:]' '[:lower:]')
        ok=1
        for kw in "$@"; do
            kw=$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')
            if [[ "$hay" != *"$kw"* ]]; then ok=0; break; fi
        done
        [[ "$ok" -eq 1 ]] && printf '%s\n' "$mod"
    done
    return 0
}
registry_default_action()  { local v; v=$(registry_get "$1" DEFAULT_ACTION); echo "${v:-install}"; }
registry_has_submenu()     { registry_get "$1" HAS_SUBMENU; }
registry_entry_script()    { local v; v=$(registry_get "$1" ENTRY_SCRIPT); echo "${v:-install.sh}"; }
# 阶段 E：模块声明的依赖（空格分隔，便于直接 for 遍历；manifest 中是逗号分隔）
registry_requires()        { local v; v=$(registry_get "$1" REQUIRES); echo "${v//,/ }"; }
# 阶段 D：模块可导出的配置键（空格分隔）
registry_exportable()      { local v; v=$(registry_get "$1" EXPORTABLE); echo "${v//,/ }"; }

# 平台可见性：模块声明的适用 OS（空格分隔；空=全平台适用）
registry_platforms()       { local v; v=$(registry_get "$1" PLATFORMS); echo "${v//,/ }"; }

# uxs_module_supported <模块名> — 当前 OS 是否适用（rc 0=适用/未声明，1=不适用）。
# OS_TYPE 未初始化时兜底 detect_os（单测等直接 source registry 的场景）。
uxs_module_supported() {
    registry_visible "$1" PLATFORMS
}

# uxs_module_visible <模块名> — escape hatch：UNIX_SCRIPT_SHOW_ALL=1 恒可见
uxs_module_visible() {
    [[ "${UNIX_SCRIPT_SHOW_ALL:-0}" == "1" ]] && return 0
    uxs_module_supported "$1"
}

# platform_gate_or_die <解析后的模块名> [用户输入的模块名]
# 模块不适用当前系统时拦截并给指引（UNIX_SCRIPT_SHOW_ALL=1 放行）。
# 放行路径 return 0；拦截路径 error + exit $SK_PRECOND（3，平台不适用=前置不满足）。
platform_gate_or_die() {
    local resolved="$1" input="${2:-$1}"
    uxs_module_visible "$resolved" && return 0
    local sup
    sup=$(registry_platforms "$resolved")
    error "模块 ${input} 不支持当前系统（${OS_TYPE:-未知}，仅支持：${sup:-无}）"
    info "查看适用模块: uxs list --grouped ｜ 强制显示全量: UNIX_SCRIPT_SHOW_ALL=1 uxs install ${input}"
    exit "$SK_PRECOND"
}

# registry_visible_modules — 当前系统可见的模块名（单个空格分隔串，注册序）。
# 仅呈现层使用；dispatch/别名/依赖解析继续用全量 ${_REGISTRY_MODULES}。
registry_visible_modules() {
    local mod out=""
    for mod in $_REGISTRY_MODULES; do
        uxs_module_visible "$mod" && out="$out $mod"
    done
    echo "${out# }"
}

# 获取模块的物理相对路径（如 "services/docker"）
registry_path() {
    local mod="$1" category_dir
    for category_dir in $_CATEGORY_DIRS; do
        [[ -f "$SCRIPT_DIR/$category_dir/$mod/.manifest" ]] || continue
        printf '%s
' "$category_dir/$mod"
        return 0
    done
    return 1
}

# 所有已注册模块名（空格分隔）
registry_all_modules() { echo "$_REGISTRY_MODULES"; }

# 某分类下的模块名（空格分隔，保持注册顺序）
registry_modules_in_category() {
    local want="$1" mod result=""
    for mod in $_REGISTRY_MODULES; do
        if [[ "$(registry_category "$mod")" == "$want" ]]; then
            result="$result $mod"
        fi
    done
    echo "${result# }"
}

# 别名解析：输入别名或正式名，输出正式名。无匹配返回原值。
# 正式名优先两段解析：先全表比对模块名再回落别名——若单趟逐模块「先比正式名再比别名」，
# 注册表序在先的模块可凭同名别名遮蔽后续模块的正式名（disk-usage 的 disk 曾挡住 disk 模块）。
registry_resolve_alias() {
    local name="$1" mod aliases alias
    for mod in $_REGISTRY_MODULES; do
        if [[ "$mod" == "$name" ]]; then
            echo "$mod"; return 0
        fi
    done
    for mod in $_REGISTRY_MODULES; do
        aliases=$(registry_aliases "$mod")
        if [[ -n "$aliases" ]]; then
            IFS=',' read -ra _alias_arr <<< "$aliases"
            for alias in "${_alias_arr[@]}"; do
                if [[ "$alias" == "$name" ]]; then
                    echo "$mod"; return 0
                fi
            done
        fi
    done
    echo "$name"
    return 1
}

# 模块是否有子菜单
registry_has_submenu_flag() {
    [[ -n "$(_reg_get "$1" HAS_SUBMENU)" ]]
}

# 分类列表（去重，保持 CATEGORY_ORDER 顺序）
registry_categories() {
    local seen="" cat mod result=""
    for cat in $CATEGORY_ORDER; do
        for mod in $_REGISTRY_MODULES; do
            if [[ "$(registry_category "$mod")" == "$cat" ]]; then
                result="$result $cat"
                break
            fi
        done
    done
    for mod in $_REGISTRY_MODULES; do
        cat=$(registry_category "$mod")
        if [[ -n "$cat" ]] && ! echo "$result" | grep -qw "$cat"; then
            result="$result $cat"
        fi
    done
    echo "${result# }"
}