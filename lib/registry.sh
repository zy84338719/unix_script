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

# --- 内部：设置/获取模块字段 ---
# 模块名中的连字符替换为下划线（bash 变量名不允许连字符）
_reg_varname() {
    local mod="$1" key="$2"
    local safe_mod="${mod//-/_}"
    echo "_REG_${key}_${safe_mod}"
}

_reg_set() {
    local mod="$1" key="$2" value="$3"
    local varname
    varname=$(_reg_varname "$mod" "$key")
    # 威胁模型说明：此处用 eval 是为了在 bash 3.2（macOS 默认 bash，本项目明确支持）
    # 下实现动态变量，规避关联数组（bash 4+）依赖。安全性由两点保证：
    #   1) $varname 由本函数受控生成（_REG_<KEY>_<safe_mod>，仅字母数字下划线），不可注入；
    #   2) $value 来自仓库内 .manifest 文件（非外部不可信输入），且经 printf '%q' 单引号转义，
    #      任意特殊字符都被转义为字面量，无法逃逸出赋值上下文。
    eval "${varname}=$(printf '%q' "$value")"
}

_reg_get() {
    local mod="$1" key="$2"
    local varname
    varname=$(_reg_varname "$mod" "$key")
    eval "echo \"\${${varname}:-}\""
}

# --- 内部：解析单个 manifest 文件 ---
_parse_manifest() {
    local mod="$1" manifest="$2"
    local key value

    # 初始化默认值
    _reg_set "$mod" LABEL ""
    _reg_set "$mod" DESC ""
    _reg_set "$mod" NEXT_STEPS ""
    _reg_set "$mod" CATEGORY ""
    _reg_set "$mod" ALIASES ""
    _reg_set "$mod" DEFAULT_ACTION "install"
    _reg_set "$mod" HAS_SUBMENU ""
    _reg_set "$mod" ENTRY_SCRIPT "install.sh"
    _reg_set "$mod" REQUIRES ""
    _reg_set "$mod" EXPORTABLE ""

    # 解析 key=value
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$key" in
            LABEL)            _reg_set "$mod" LABEL "$value" ;;
            DESC)             _reg_set "$mod" DESC "$value" ;;
            NEXT_STEPS)       _reg_set "$mod" NEXT_STEPS "$value" ;;   # 批次②：安装成功后的下一步提示（分号分隔）
            CATEGORY)         _reg_set "$mod" CATEGORY "$value" ;;
            ALIASES)          _reg_set "$mod" ALIASES "$value" ;;
            DEFAULT_ACTION)   _reg_set "$mod" DEFAULT_ACTION "$value" ;;
            HAS_SUBMENU)      _reg_set "$mod" HAS_SUBMENU "$value" ;;
            ENTRY_SCRIPT)     _reg_set "$mod" ENTRY_SCRIPT "$value" ;;
            REQUIRES)         _reg_set "$mod" REQUIRES "$value" ;;     # 阶段 E：依赖的模块（逗号分隔）
            EXPORTABLE)       _reg_set "$mod" EXPORTABLE "$value" ;;   # 阶段 D：可导出配置键（逗号分隔）
        esac
    done < "$manifest"

    # 必填字段校验
    local lbl cat
    lbl=$(_reg_get "$mod" LABEL)
    cat=$(_reg_get "$mod" CATEGORY)
    if [[ -z "$lbl" || -z "$cat" ]]; then
        warn "manifest 缺少必填字段: $manifest" >&2
        return 1
    fi

    return 0
}

# --- 扫描所有分类子目录下的 .manifest 文件 ---
registry_scan() {
    _REGISTRY_MODULES=""
    local dir manifest mod category_dir

    # 扫描分类子目录
    for category_dir in $_CATEGORY_DIRS; do
        [[ -d "$SCRIPT_DIR/$category_dir" ]] || continue
        for dir in "$SCRIPT_DIR/$category_dir"/*/; do
            [[ -d "$dir" ]] || continue
            mod=$(basename "$dir")
            manifest="$dir/.manifest"
            [[ -f "$manifest" ]] || continue

            # 记录模块的物理相对路径
            _reg_set "$mod" PHYSICAL_PATH "$category_dir/$mod"

            if _parse_manifest "$mod" "$manifest"; then
                _REGISTRY_MODULES="$_REGISTRY_MODULES $mod"
            fi
        done
    done

    _REGISTRY_MODULES="${_REGISTRY_MODULES# }"
}

# --- 查询 API ---
registry_label()           { _reg_get "$1" LABEL; }
registry_desc()            { _reg_get "$1" DESC; }
registry_category()        { _reg_get "$1" CATEGORY; }
registry_aliases()         { _reg_get "$1" ALIASES; }
registry_next_steps()      { _reg_get "$1" NEXT_STEPS; }

# registry_search <关键字...> — 全注册表搜索（批次③）。
# 匹配域：模块名+别名+LABEL+DESC 拼接；大小写不敏感子串；多关键字 AND。
# 输出命中模块名（注册表序，每行一个）；无匹配输出空。
registry_search() {
    [[ $# -eq 0 ]] && return 0
    local mod hay kw ok
    for mod in $_REGISTRY_MODULES; do
        hay="$mod|$(_reg_get "$mod" ALIASES)|$(_reg_get "$mod" LABEL)|$(_reg_get "$mod" DESC)"
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
registry_default_action()  { local v; v=$(_reg_get "$1" DEFAULT_ACTION); echo "${v:-install}"; }
registry_has_submenu()     { _reg_get "$1" HAS_SUBMENU; }
registry_entry_script()    { local v; v=$(_reg_get "$1" ENTRY_SCRIPT); echo "${v:-install.sh}"; }
# 阶段 E：模块声明的依赖（空格分隔，便于直接 for 遍历；manifest 中是逗号分隔）
registry_requires()        { local v; v=$(_reg_get "$1" REQUIRES); echo "${v//,/ }"; }
# 阶段 D：模块可导出的配置键（空格分隔）
registry_exportable()      { local v; v=$(_reg_get "$1" EXPORTABLE); echo "${v//,/ }"; }

# 获取模块的物理相对路径（如 "services/docker"）
registry_path() {
    _reg_get "$1" PHYSICAL_PATH
}

# 所有已注册模块名（空格分隔）
registry_all_modules() { echo "$_REGISTRY_MODULES"; }

# 某分类下的模块名（空格分隔，保持注册顺序）
registry_modules_in_category() {
    local want="$1" mod result=""
    for mod in $_REGISTRY_MODULES; do
        if [[ "$(_reg_get "$mod" CATEGORY)" == "$want" ]]; then
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
        aliases=$(_reg_get "$mod" ALIASES)
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
            if [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]]; then
                result="$result $cat"
                break
            fi
        done
    done
    for mod in $_REGISTRY_MODULES; do
        cat=$(_reg_get "$mod" CATEGORY)
        if [[ -n "$cat" ]] && ! echo "$result" | grep -qw "$cat"; then
            result="$result $cat"
        fi
    done
    echo "${result# }"
}
