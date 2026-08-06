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
module_status_machine() {
    local mod="$1"
    # P5 特殊模块：状态逻辑在 lib 内的 check_*_status 函数（无标准 install.sh status）
    # 注意：必须显式注入 UXS_STATUS_MODE=machine，否则 check_*_status 走人类模式输出
    # 中文/emoji，sed 提取不到 STATE=（与 module_status_raw 的 P5 分支保持一致）。
    case "$mod" in
        shutdown_timer)       UXS_STATUS_MODE=machine check_shutdown_timer_status | sed -n 's/^STATE=//p' | head -1; return ;;
        process_manager_tool) UXS_STATUS_MODE=machine check_process_manager_status | sed -n 's/^STATE=//p' | head -1; return ;;
    esac
    local entry_script mod_path script
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>/dev/null \
        | sed -n 's/^STATE=//p' | head -1
}

# module_status_raw <模块名> -> 输出完整机器模式原始输出（STATE=/VERSION=/EXTRA=）
module_status_raw() {
    local mod="$1"
    # P5 特殊模块：走 lib 内的 check_*_status（已用 emit_status 输出 STATE=）
    case "$mod" in
        shutdown_timer)       UXS_STATUS_MODE=machine check_shutdown_timer_status; return ;;
        process_manager_tool) UXS_STATUS_MODE=machine check_process_manager_status; return ;;
    esac
    local entry_script mod_path script
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "STATE=not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>/dev/null
}

# --- 特殊模块状态（非标准接口）---
check_shutdown_timer_status() {
    local is_configured=false state human
    if [[ "$OS_TYPE" == "darwin" ]]; then
        [ -f "/Library/LaunchDaemons/com.user.dailyshutdown.plist" ] && is_configured=true
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if crontab -l 2>/dev/null | grep -q "# AUTO_SHUTDOWN_SCRIPT"; then
            is_configured=true
        fi
    fi
    if $is_configured; then
        state="configured"
        human="${GREEN}✅ 已配置每日定时关机${NC}"
    else
        state="not_configured"
        human="${RED}❌ 未配置${NC}"
    fi
    emit_status "$state" "$human"
}

check_process_manager_status() {
    local is_installed=false state human
    if [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ]; then
        is_installed=true
    fi
    if $is_installed; then
        if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
            state="installed"
            human="${GREEN}✅ 已安装并配置${NC}"
        else
            state="installed"   # 已装但 PATH 未配，仍算 installed（用 EXTRA 标注）
            human="${YELLOW}⚠️  已安装但 PATH 未配置${NC}"
        fi
    else
        state="not_installed"
        human="${RED}❌ 未安装${NC}"
    fi
    emit_status "$state" "$human"
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
            # 特殊模块用自定义状态函数
            case "$mod" in
                shutdown_timer)  printf "  %-16s %s\n" "$label:" "$(check_shutdown_timer_status)" ;;
                process_manager_tool) printf "  %-16s %s\n" "$label:" "$(check_process_manager_status)" ;;
                *)               printf "  %-16s %s\n" "$label:" "$(module_status "$mod")" ;;
            esac
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
