#!/usr/bin/env bash
#
# lib/status.sh
#
# 注册表驱动的状态检查函数。
# 用 module_status() 替代 36 个独立的 status_*_module() 函数。
#

# 幂等保护
if [[ -n "${_STATUS_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_STATUS_SH_LOADED=1

# --- 通用模块状态查询（注册表驱动）---
# 用法: module_status <模块目录名>
# 调用该模块的 install.sh status 子命令，输出一行状态。
module_status() {
    local mod="$1"
    local entry_script mod_path
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    local script="$SCRIPT_DIR/$mod_path/$entry_script"
    if [[ -f "$script" ]]; then
        bash "$script" status 2>/dev/null || echo "查询失败"
    else
        echo -e "${RED}❌ 脚本不存在${NC}"
    fi
}

# --- 机器模式查询（供 status-json / export / health 复用）---
# module_status_machine <模块名> -> 输出 STATE 值（单一状态码）
# 所有模块（含 shutdown_timer / process_manager_tool）均通过入口脚本的 status 子命令
# 在 UXS_STATUS_MODE=machine 下输出 STATE=，故此处不再需要任何 per-module 特判。
module_status_machine() {
    local mod="$1"
    local entry_script mod_path script
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>"$(uxs_stderr)" \
        | sed -n 's/^STATE=//p' | head -1
}

# module_status_raw <模块名> -> 输出完整机器模式原始输出（STATE=/VERSION=/EXTRA=）
module_status_raw() {
    local mod="$1"
    local entry_script mod_path script
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "STATE=not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>"$(uxs_stderr)"
}

# --- 已安装状态总览（注册表驱动）---
show_installed_services() {
    if $INTERACTIVE; then clear; fi
    header "📊 已安装状态"
    echo "========================================"

    local cat mod label
    for cat in $CATEGORY_ORDER; do
        local has_module=false
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] && { has_module=true; break; }
        done
        $has_module || continue

        echo
        echo "--- $cat ---"
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] || continue
            label=$(_reg_get "$mod" LABEL)
            printf "  %-16s %s\n" "$label:" "$(module_status "$mod")"
        done
    done

    echo
    echo "========================================"
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "Linux 服务管理命令："
        echo "  查看状态: sudo systemctl status <service-name>"
        echo "  查看日志: sudo journalctl -u <service-name> -f"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "macOS 服务管理命令："
        echo "  查看状态: sudo launchctl list | grep <service>"
        echo "  查看日志: tail -f /var/log/<service>.log"
    fi
    echo
    if $INTERACTIVE; then read -r -p "按回车键返回主菜单..."; fi
}

# ============================================================
# 菜单状态层：内存态 + 并行批查 + TTL 跨进程缓存（UX 改造）
#
# 实测串行全量 status 查询 ~5.4s（模块数随版本增长，菜单重画不可接受）。
# 三层：并行批查（UXS_STATUS_JOBS，默认 8）→ 内存变量 →
#       /tmp TTL 缓存（UXS_STATUS_CACHE_TTL 秒，默认 300，0=禁用；
#       UXS_STATUS_CACHE_DIR 可覆盖，测试用）。
# bash 3.2 兼容：动态变量名沿用 registry 的 eval 模式；并发用 jobs/wait（无 wait -n）。
# ============================================================

# --- 内存态（模块名连字符转下划线，同 _reg_varname 约定）---
_uxs_state_varname() {
    local safe_mod="${1//-/_}"
    echo "_UXS_STATE_${safe_mod}"
}

_uxs_state_set() {
    local varname
    varname=$(_uxs_state_varname "$1")
    eval "${varname}=\$2"
    # 已知模块清单（去重追加），供 cache_save 遍历
    case " ${_UXS_STATE_KNOWN:-} " in
        *" $1 "*) ;;
        *) _UXS_STATE_KNOWN="${_UXS_STATE_KNOWN:-} $1" ;;
    esac
}

status_state_get() {
    local varname
    varname=$(_uxs_state_varname "$1")
    eval "echo \"\${${varname}:-}\""
}

# --- 版本内存态（--status-json 的版本列用；镜像 _uxs_state_* 模式）---
_uxs_version_varname() {
    local safe_mod="${1//-/_}"
    echo "_UXS_VERSION_${safe_mod}"
}

_uxs_version_set() {
    local varname
    varname=$(_uxs_version_varname "$1")
    eval "${varname}=\$2"
}

_uxs_version_get() {
    local varname
    varname=$(_uxs_version_varname "$1")
    eval "echo \"\${${varname}:-}\""
}

# --- TTL 缓存目录：按仓库路径区分（多 clone 不互相污染）---
_uxs_cache_dir() {
    local base key
    base="${UXS_STATUS_CACHE_DIR:-/tmp/uxs-status-$(id -u)}"
    key=$(printf '%s' "${SCRIPT_DIR:-.}" | cksum | cut -d' ' -f1)
    echo "$base/$key"
}

_uxs_cache_file() {
    echo "$(_uxs_cache_dir)/cache"
}

# 命中：填充内存态返回 0；未命中/禁用/损坏：返回 1
status_cache_load() {
    local ttl="${UXS_STATUS_CACHE_TTL:-300}"
    if [[ "$ttl" == "0" ]]; then return 1; fi
    local file
    file=$(_uxs_cache_file)
    [[ -f "$file" ]] || return 1
    local ts now
    ts=$(sed -n 's/^#ts=//p' "$file" | head -1)
    now=$(date +%s)
    [[ "$ts" =~ ^[0-9]+$ ]] || return 1
    if (( now - ts > ttl )); then return 1; fi
    local mod state
    while IFS=$'\t' read -r mod state; do
        if [[ -z "$mod" || "$mod" == \#* ]]; then continue; fi
        _uxs_state_set "$mod" "$state"
    done < "$file"
    return 0
}

status_cache_save() {
    local ttl="${UXS_STATUS_CACHE_TTL:-300}"
    if [[ "$ttl" == "0" ]]; then return 0; fi
    local dir file mod
    dir=$(_uxs_cache_dir)
    mkdir -p "$dir" 2>/dev/null || return 0
    file="$dir/cache"
    {
        echo "#ts=$(date +%s)"
        for mod in ${_UXS_STATE_KNOWN:-}; do
            printf '%s\t%s\n' "$mod" "$(status_state_get "$mod")"
        done
    } > "$file" 2>/dev/null || true
}

# 单模块状态变更后更新缓存行（缓存不存在则不做任何事）
status_cache_update() {
    local mod="$1" state="$2" file
    file=$(_uxs_cache_file)
    [[ -f "$file" ]] || return 0
    if grep -q "^${mod}$(printf '\t')" "$file"; then
        grep -v "^${mod}$(printf '\t')" "$file" > "${file}.tmp" 2>/dev/null || true
        printf '%s\t%s\n' "$mod" "$state" >> "${file}.tmp"
        mv "${file}.tmp" "$file"
    else
        printf '%s\t%s\n' "$mod" "$state" >> "$file"
    fi
}

# --- 并行批查：固定并发跑 module_status_raw，解析 STATE+VERSION 进内存 ---
# 子进程整体受 UXS_STATUS_MODULE_TIMEOUT（默认 30s）封顶：未来某个模块 status
# 新出现挂起，只会拖慢自己所在的并发窗口，不会无限阻塞整轮批查。
status_batch_query() {
    local jobs="${UXS_STATUS_JOBS:-8}"
    if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then jobs=8; fi
    local timeout="${UXS_STATUS_MODULE_TIMEOUT:-30}"
    if ! [[ "$timeout" =~ ^[1-9][0-9]*$ ]]; then timeout=30; fi
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/uxs-status.XXXXXX")
    local mod running=0
    for mod in "$@"; do
        (
            local raw=""
            raw=$(uxs_func_with_timeout "$timeout" module_status_raw "$mod") || raw=""
            printf '%s' "$raw" > "$tmpdir/$mod"
        ) &
        running=$((running + 1))
        if (( running >= jobs )); then
            wait
            running=0
        fi
    done
    wait
    local state version
    for mod in "$@"; do
        state=""; version=""
        if [[ -f "$tmpdir/$mod" ]]; then
            state=$(sed -n 's/^STATE=//p' "$tmpdir/$mod" | head -1)
            version=$(sed -n 's/^VERSION=//p' "$tmpdir/$mod" | head -1)
        fi
        [[ -z "$state" ]] && state="unknown"
        _uxs_state_set "$mod" "$state"
        _uxs_version_set "$mod" "$version"
    done
    rm -rf "$tmpdir"
}

# 单模块即时刷新（动作执行成功后调用）
status_state_refresh() {
    local mod="$1" st
    st=$(module_status_machine "$mod" 2>/dev/null || echo unknown)
    [[ -z "$st" ]] && st=unknown
    _uxs_state_set "$mod" "$st"
    status_cache_update "$mod" "$st"
}

# 人类菜单状态图标
status_icon() {
    case "$1" in
        installed*|configured) echo "✓" ;;
        not_installed|not_configured) echo " " ;;
        "n/a") echo "·" ;;
        *) echo "?" ;;
    esac
}

# 菜单入口：优先吃缓存，否则并行批查全量并落盘
menu_status_ensure() {
    if status_cache_load; then
        return 0
    fi
    info "正在检查各模块安装状态（首次约数秒；UXS_STATUS_CACHE_TTL=0 可关闭缓存）..."
    # shellcheck disable=SC2086  # $_REGISTRY_MODULES 为受控模块名列表，需要分词
    status_batch_query $_REGISTRY_MODULES
    status_cache_save
}
