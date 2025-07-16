#!/usr/bin/env bash
#
# 定时关机工具 - macOS 平台
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
    
    # 计算从现在到目标时间的分钟数
    local current_epoch=$(date "+%s")
    local target_epoch=$(date -j -f "%H:%M" "$time" "+%s" 2>/dev/null)
    
    if [[ -z "$target_epoch" ]]; then
        print_error "时间解析失败"
        return 1
    fi
    
    # 如果目标时间已过，设置为明天
    if [[ $target_epoch -le $current_epoch ]]; then
        target_epoch=$((target_epoch + 86400))
    fi
    
    local minutes_until=$(( (target_epoch - current_epoch) / 60 ))
    
    if [[ $minutes_until -le 0 ]]; then
        print_error "指定时间已过，请选择未来时间"
        return 1
    fi
    
    # 设置关机计划
    if sudo shutdown -h "+$minutes_until" 2>/dev/null; then
        print_success "已设置 $minutes_until 分钟后关机 (约 $time)"
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
    
    # 创建 LaunchDaemon plist 文件
    local plist_file="/Library/LaunchDaemons/com.user.dailyshutdown.plist"
    
    sudo tee "$plist_file" > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.dailyshutdown</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/shutdown</string>
        <string>-h</string>
        <string>now</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF
    
    # 设置权限并加载
    sudo chown root:wheel "$plist_file"
    sudo chmod 644 "$plist_file"
    
    if sudo launchctl load "$plist_file" 2>/dev/null; then
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
    temp_shutdown=$(ps aux | grep "[s]hutdown" | grep -v grep)
    
    if [[ -n "$temp_shutdown" ]]; then
        print_info "临时关机计划："
        echo "$temp_shutdown"
    else
        print_info "无临时关机计划"
    fi
    
    echo
    
    # 检查每日关机 LaunchDaemon
    local daily_shutdown="/Library/LaunchDaemons/com.user.dailyshutdown.plist"
    
    if [[ -f "$daily_shutdown" ]]; then
        print_info "每日关机计划已设置"
        if launchctl list | grep -q "com.user.dailyshutdown"; then
            print_success "每日关机服务正在运行"
        else
            print_warning "每日关机服务未运行"
        fi
    else
        print_info "无每日关机计划"
    fi
}

# 取消所有关机计划
cancel_all_shutdowns() {
    print_info "取消所有关机计划..."
    
    # 取消临时关机
    if sudo killall shutdown 2>/dev/null; then
        print_success "已取消临时关机"
    fi
    
    # 取消每日关机
    local plist_file="/Library/LaunchDaemons/com.user.dailyshutdown.plist"
    
    if [[ -f "$plist_file" ]]; then
        sudo launchctl unload "$plist_file" 2>/dev/null
        sudo rm -f "$plist_file"
        print_success "已取消每日关机计划"
    fi
    
    print_success "所有关机计划已取消"
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    shutdown_timer_menu
fi
