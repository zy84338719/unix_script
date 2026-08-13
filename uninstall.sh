#!/usr/bin/env bash
#
# uninstall.sh
#
# 一键卸载入口：委托各模块的 install.sh uninstall 执行卸载。
# 注册表驱动，自动发现所有 .manifest 模块。
#
# 用法:
#   ./uninstall.sh             # 交互式逐项询问
#   ./uninstall.sh --all       # 卸载全部（需二次确认）
#   ./uninstall.sh <模块名>    # 仅卸载指定模块（同 install.sh 的模块名）
#   ./uninstall.sh -h          # 帮助
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/registry.sh
source "$SCRIPT_DIR/lib/registry.sh"

# 在子 shell 中执行某目录下的脚本（避免 cd 污染当前工作目录）
run_in_dir() {
    local dir="$1"; shift
    ( cd "$SCRIPT_DIR/$dir" && bash "$@" )
}

# 卸载单个模块（封装确认）
ask_and_uninstall() {
    local label="$1"; shift
    if yes_no "确认卸载 ${label}？"; then
        info "卸载 $label ..."
        "$@"
        success "$label 卸载流程结束。"
    else
        info "跳过 $label"
    fi
    echo
}

# --- 通用模块卸载（注册表驱动） ---
# 绝大多数模块只需调用 install.sh uninstall
uninstall_module() {
    local mod="$1"
    local entry_script
    entry_script=$(registry_entry_script "$mod")
    run_in_dir "$mod" "$entry_script" uninstall
}

# --- 特殊模块卸载（需要非标准命令） ---
uninstall_special() {
    local mod="$1"
    local mod_path
    mod_path=$(registry_path "$mod")
    case "$mod" in
        bbr)
            run_in_dir "$mod_path" install.sh disable
            ;;
        multi-net)
            run_in_dir "$mod_path" install.sh clear
            ;;
        shutdown_timer)
            local sp="$SCRIPT_DIR/$mod_path/shutdown_timer.sh"
            if [ -f "$sp" ]; then
                chmod +x "$sp"
                "$sp" cancel_daily_shutdown_internal
            fi
            ;;
        process_manager_tool)
            run_in_dir "$mod_path" install_process_manager.sh uninstall
            ;;
        dev-mirror)
            run_in_dir "$mod_path" install.sh uninstall all <<< "y"
            ;;
        *)
            uninstall_module "$mod"
            ;;
    esac
}

# --- 卸载全部 ---
uninstall_all() {
    warn "⚠️  即将卸载所有已安装的服务与环境！此操作不可逆。"
    if ! yes_no "再次确认卸载全部？"; then
        info "已取消"
        exit 0
    fi

    local mod
    for mod in $_REGISTRY_MODULES; do
        local label
        label=$(registry_label "$mod")
        info "卸载 $label ($mod) ..."
        uninstall_special "$mod" || warn "$mod 卸载失败，继续..."
    done

    echo
    success "全部卸载流程结束。"
}

show_usage() {
    local mod_list=""
    for mod in $_REGISTRY_MODULES; do
        mod_list="$mod_list | $mod"
    done
    mod_list="${mod_list# | }"

    cat <<EOF
用法: $0 [选项] [模块名]

选项:
  -h, --help    显示本帮助
  --all         卸载全部已安装项（需二次确认）

模块名:
  $mod_list

示例:
  $0                  # 逐项交互询问
  $0 docker           # 仅卸载 docker
  $0 --all            # 卸载全部
EOF
}

# --- 按模块名卸载（注册表驱动，支持别名） ---
dispatch() {
    local name="$1"
    local resolved
    resolved=$(registry_resolve_alias "$name")

    if [[ "$resolved" == "$name" ]] && ! echo "$_REGISTRY_MODULES" | grep -qw "$name"; then
        error "未知模块: $name"
        show_usage
        exit 1
    fi

    local label
    label=$(registry_label "$resolved")
    ask_and_uninstall "$label" uninstall_special "$resolved"
}

# --- 交互式逐项询问（注册表驱动，按分类展示） ---
interactive_all() {
    detect_os
    header "🗑️  一键卸载（逐项询问）"
    echo "========================================"
    echo

    local cat mod label
    for cat in $CATEGORY_ORDER; do
        local has_any=false
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] && { has_any=true; break; }
        done
        $has_any || continue

        echo "--- $cat ---"
        for mod in $_REGISTRY_MODULES; do
            [[ "$(_reg_get "$mod" CATEGORY)" == "$cat" ]] || continue
            label=$(registry_label "$mod")
            ask_and_uninstall "$label" uninstall_special "$mod"
        done
        echo
    done

    success "卸载流程结束。"
}

main() {
    detect_os
    registry_scan

    if [[ $# -eq 0 ]]; then
        interactive_all
        exit 0
    fi
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        --all)     uninstall_all ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)         dispatch "$1" ;;
    esac
}

main "$@"
