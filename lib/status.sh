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
