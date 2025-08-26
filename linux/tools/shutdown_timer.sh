#!/usr/bin/env bash
#
# 定时关机工具 - Linux 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 定时关机功能
shutdown_timer_menu() {
    print_header "⏰ 定时关机管理"
    
    echo "1. 设置临时关机计划"
    echo "2. 设置每日定时关机"
    echo "3. 查看当前关机计划"
    echo "4. 取消所有关机计划"
    echo "0. 返回上级菜单"
    echo
    
    read -p "请选择操作 [0-4]: " choice
    
    case $choice in
        1) set_temporary_shutdown ;;
        2) set_daily_shutdown ;;
        3) show_shutdown_status ;;
        4) cancel_all_shutdowns ;;
        0) return 0 ;;
        *) 
            print_error "无效选择"
            shutdown_timer_menu
            ;;
    esac
}

# 设置临时关机
set_temporary_shutdown() {
    print_info "设置今日临时关机..."
    
    read -p "请输入关机时间 (HH:MM): " time
    
    if ! [[ "$time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        print_error "无效的时间格式，请使用 HH:MM 格式"
        return 1
    fi
    
    # 计算关机时间
    local shutdown_time=$(date -d "today $time" "+%H:%M")
    local current_time=$(date "+%H:%M")
    
    if [[ "$shutdown_time" < "$current_time" ]]; then
        print_error "指定时间已过，请选择未来时间"
        return 1
    fi
    
    # 设置关机计划
    if sudo shutdown -h "$time" 2>/dev/null; then
        print_success "已设置今日 $time 关机"
    else
        print_error "设置关机失败"
        return 1
    fi
}

# 设置每日定时关机
set_daily_shutdown() {
    print_info "设置每日定时关机..."
    
    read -p "请输入每日关机时间 (HH:MM): " time
    
    if ! [[ "$time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        print_error "无效的时间格式，请使用 HH:MM 格式"
        return 1
    fi
    
    local hour=$(echo "$time" | cut -d':' -f1)
    local minute=$(echo "$time" | cut -d':' -f2)
    
    # 移除现有的定时关机 cron 任务
    crontab -l 2>/dev/null | grep -v "# AUTO_SHUTDOWN_SCRIPT" | crontab -
    
    # 添加新的 cron 任务
    (crontab -l 2>/dev/null; echo "$minute $hour * * * /sbin/shutdown -h now # AUTO_SHUTDOWN_SCRIPT") | crontab -
    
    if [[ $? -eq 0 ]]; then
        print_success "已设置每日 $time 自动关机"
    else
        print_error "设置每日关机失败"
        return 1
    fi
}

# 查看关机状态
show_shutdown_status() {
    print_header "📋 当前关机计划状态"
    
    # 检查临时关机
    local temp_shutdown
    temp_shutdown=$(systemctl list-timers | grep shutdown.target 2>/dev/null)
    
    if [[ -n "$temp_shutdown" ]]; then
        print_info "临时关机计划："
        echo "$temp_shutdown"
    else
        print_info "无临时关机计划"
    fi
    
    echo
    
    # 检查每日关机 cron
    local daily_shutdown
    daily_shutdown=$(crontab -l 2>/dev/null | grep "# AUTO_SHUTDOWN_SCRIPT")
    
    if [[ -n "$daily_shutdown" ]]; then
        print_info "每日关机计划："
        echo "$daily_shutdown"
    else
        print_info "无每日关机计划"
    fi
}

# 取消所有关机计划
cancel_all_shutdowns() {
    print_info "取消所有关机计划..."
    
    # 取消临时关机
    if sudo shutdown -c 2>/dev/null; then
        print_success "已取消临时关机"
    fi
    
    # 取消每日关机 cron
    crontab -l 2>/dev/null | grep -v "# AUTO_SHUTDOWN_SCRIPT" | crontab -
    
    if [[ $? -eq 0 ]]; then
        print_success "已取消每日关机计划"
    fi
    
    print_success "所有关机计划已取消"
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    shutdown_timer_menu
fi
