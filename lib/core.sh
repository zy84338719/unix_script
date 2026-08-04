#!/usr/bin/env bash
#
# lib/core.sh
#
# 框架核心函数：子目录执行、通用子菜单循环。
# 被 install.sh 及各 lib 模块 source 使用。
#

# 在子 shell 中执行某目录下的脚本（避免 cd 污染当前工作目录）
run_in_dir() {
    local dir="$1"; shift
    ( cd "$SCRIPT_DIR/$dir" && bash "$@" )
}

# ============================================================
# 通用子菜单框架
# ============================================================
# 用法: run_submenu <标题> <状态回调> <选项回调> <动作回调>
#   标题:     菜单标题字符串
#   状态回调: 打印状态信息的函数名（可传 "" 跳过）
#   选项回调: 打印菜单选项的函数名
#   动作回调: 处理用户选择的函数名，接收 $1=用户输入，
#             返回 0 继续循环，非 0 退出菜单
run_submenu() {
    local title="$1" status_fn="$2" display_fn="$3" action_fn="$4"
    while true; do
        clear
        header "$title"
        echo "========================================"
        if [[ -n "$status_fn" ]] && type "$status_fn" &>/dev/null; then
            "$status_fn"
        fi
        echo
        menu "请选择操作："
        "$display_fn"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项: " _choice
        if [[ "$_choice" == "0" ]]; then
            break
        fi
        "$action_fn" "$_choice"
        local _rc=$?
        if [[ $_rc -eq 2 ]]; then
            break
        fi
    done
}
