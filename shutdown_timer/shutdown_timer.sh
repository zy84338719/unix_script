#!/bin/bash

#
# shutdown_timer.sh
#
# 一个在 macOS 和 Linux 上计划或取消临时及每日系统关机的脚本。
#

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# --- 日志函数 ---
info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }

# --- 全局变量 ---
OS="" # 将在 main 函数中设置为 "Darwin" 或 "Linux"
# macOS-specific
PLIST_FILE="/Library/LaunchDaemons/com.user.dailyshutdown.plist"
PLIST_LABEL="com.user.dailyshutdown"
# Linux-specific
CRON_COMMENT="# AUTO_SHUTDOWN_SCRIPT" # 用于识别 cron 任务

# --- 核心函数 ---

# 验证时间格式 (HH:MM)
validate_time() {
    if ! [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        error "无效的时间格式。请输入 HH:MM 格式 (例如, 23:00)。"
        return 1
    fi
    return 0
}

# 设置临时关机
set_temporary_shutdown() {
    local time
    read -r -p "请输入今天的关机时间 (HH:MM): " time
    validate_time "$time" || return 1

    if [[ "$OS" == "Darwin" ]]; then
        # macOS 需要将 HH:MM 转换为 +m (从现在开始的分钟数)
        local current_epoch
        local target_epoch
        current_epoch=$(date +%s)
        target_epoch=$(date -j -f "%H:%M" "$time" +%s)
        
        if [[ $target_epoch -le $current_epoch ]]; then
            error "指定时间已过。请输入未来的时间。"
            return 1
        fi
        
        local diff_minutes
        diff_minutes=$(( (target_epoch - current_epoch) / 60 ))
        info "计划在 ${diff_minutes} 分钟后关闭系统。"
        info "系统将提示您输入密码以执行 'shutdown' 命令。"
        
        if sudo shutdown -h "+${diff_minutes}"; then
            success "系统已计划在 ${diff_minutes} 分钟后关机。"
            info "要取消，请选择主菜单中的 '取消临时关机' 选项。"
        else
            error "计划临时关机失败。请检查错误。"
        fi
    else
        # Linux可以直接使用 HH:MM 格式
        info "计划在今天 ${time} 关闭系统。"
        info "系统将提示您输入密码以执行 'shutdown' 命令。"
        
        if sudo shutdown "$time"; then
            success "系统已计划在今天 ${time} 关机。"
            info "要取消，请选择主菜单中的 '取消临时关机' 选项。"
        else
            error "计划临时关机失败。请检查错误。"
        fi
    fi
}

# 取消临时关机
cancel_temporary_shutdown() {
    info "正在尝试取消已计划的临时关机。"
    info "系统将提示您输入密码。"

    local result
    if [[ "$OS" == "Darwin" ]]; then
        # macOS 使用 killall
        result=$(sudo killall shutdown 2>&1)
        if [[ $? -eq 0 ]]; then
            success "已计划的临时关机已被取消。"
        else
            if [[ "$result" == *"No matching processes were found"* ]]; then
                info "未找到要取消的临时关机。"
            else
                error "尝试取消临时关机时发生错误。"
                error "详细信息: $result"
            fi
        fi
    else
        # Linux 使用 shutdown -c
        result=$(sudo shutdown -c 2>&1)
        if [[ $? -eq 0 ]]; then
            success "已计划的临时关机已被取消。"
        else
            if [[ "$result" == *"shutdown: Not scheduled."* ]]; then
                info "未找到要取消的临时关机。"
            else
                error "尝试取消临时关机时发生错误。"
                error "详细信息: $result"
            fi
        fi
    fi
}

# 检查关机状态
check_shutdown_status() {
    info "--- 关机状态检查 ---"
    local found_temp=false
    local found_daily=false

    # 检查临时关机
    if [[ "$OS" == "Darwin" ]]; then
        if pgrep -f "/sbin/shutdown" >/dev/null; then
            info "检测到已计划的临时关机。"
            found_temp=true
        fi
    else # Linux
        # 优先检查 systemd 的关机计划文件（现代 Linux 发行版）
        if [ -f "/run/systemd/shutdown/scheduled" ]; then
            info "检测到已计划的临时关机 (systemd)。"
            found_temp=true
        # 备用方案：检查是否有正在运行的 shutdown 进程
        elif pgrep -f "/usr/sbin/shutdown\|/sbin/shutdown" >/dev/null; then
            info "检测到已计划的临时关机。"
            found_temp=true
        fi
    fi
    if ! $found_temp; then
        info "未发现已计划的临时关机。"
    fi

    # 检查每日定时关机
    if [[ "$OS" == "Darwin" ]]; then
        if sudo launchctl list | grep -q "$PLIST_LABEL"; then
            info "检测到每日定时关机任务 (launchd)。"
            found_daily=true
        fi
    else # Linux
        if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
            info "检测到每日定时关机任务 (cron)。"
            found_daily=true
        fi
    fi
    if ! $found_daily; then
        info "未发现每日定时关机任务。"
    fi
    
    if ! $found_temp && ! $found_daily; then
        success "当前没有设置任何关机任务。"
    fi
    info "---------------------"
}


# 设置每日定时关机
set_daily_shutdown() {
    local time
    read -r -p "请输入每日的关机时间 (HH:MM): " time
    validate_time "$time" || return 1

    if [[ "$OS" == "Darwin" ]]; then
        set_daily_shutdown_macos "$time"
    else
        set_daily_shutdown_linux "$time"
    fi
}

# 取消每日定时关机
cancel_daily_shutdown() {
    info "正在取消每日定时关机任务..."
    if [[ "$OS" == "Darwin" ]]; then
        cancel_daily_shutdown_macos
    else
        cancel_daily_shutdown_linux
    fi
}

# --- macOS 特定函数 ---
set_daily_shutdown_macos() {
    local time=$1
    local hour=${time%%:*}
    local minute=${time#*:}
    hour=${hour#0}
    minute=${minute#0}

    info "正在为 macOS 设置每日 ${time} 的定时关机任务。"
    warn "这将创建一个系统级的 launchd 任务。需要管理员权限。"

    local plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/shutdown</string>
        <string>-h</string>
        <string>now</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${hour}</integer>
        <key>Minute</key>
        <integer>${minute}</integer>
    </dict>
</dict>
</plist>"

    echo "$plist_content" | sudo tee "$PLIST_FILE" > /dev/null
    sudo launchctl bootout system "$PLIST_FILE" &>/dev/null || true
    sudo launchctl bootstrap system "$PLIST_FILE"
    
    if sudo launchctl list | grep -q "$PLIST_LABEL"; then
        success "每日定时关机任务已成功设置在每天 ${time}。"
    else
        error "加载 launchd 任务失败。请检查系统日志。"
        sudo rm -f "$PLIST_FILE"
    fi
}

cancel_daily_shutdown_macos() {
    if [ ! -f "$PLIST_FILE" ]; then
        info "未找到每日定时关机任务的配置文件 (launchd)。"
        return 0
    fi
    warn "这将移除系统级的 launchd 任务。需要管理员权限。"
    sudo launchctl bootout system "$PLIST_FILE" &>/dev/null
    sudo rm -f "$PLIST_FILE"
    success "每日定时关机任务已成功取消。"
}

# --- Linux 特定函数 ---
set_daily_shutdown_linux() {
    local time=$1
    local hour=${time%%:*}
    local minute=${time#*:}

    info "正在为 Linux 设置每日 ${time} 的定时关机任务。"
    warn "这将在您的 crontab 中添加一个条目。"

    # 为避免重复，先移除旧的条目
    (crontab -l 2>/dev/null | grep -v "$CRON_COMMENT") | crontab -
    # 添加新条目
    (crontab -l 2>/dev/null; echo "$minute $hour * * * /sbin/shutdown -h now $CRON_COMMENT") | crontab -

    if crontab -l | grep -q "$CRON_COMMENT"; then
        success "每日定时关机任务已成功设置在每天 ${time}。"
    else
        error "设置 cron 任务失败。请检查 cron 服务是否运行及您的权限。"
    fi
}

cancel_daily_shutdown_linux() {
    if ! crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        info "未找到每日定时关机任务 (cron)。"
        return 0
    fi
    warn "这将从您的 crontab 中移除任务。需要管理员权限。"
    (crontab -l | grep -v "$CRON_COMMENT") | crontab -
    success "每日定时关机任务已成功取消。"
}


# --- 主菜单 ---
main() {
    # 检测操作系统
    case "$(uname -s)" in
        Darwin)
            OS="Darwin"
            ;;
        Linux)
            OS="Linux"
            ;;
        *)
            error "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac

    # 处理非交互式参数
    if [[ "$1" == "cancel_daily_shutdown_internal" ]]; then
        cancel_daily_shutdown
        exit 0
    fi

    while true; do
        echo ""
        echo "自动关机管理脚本"
        echo "------------------------"
        echo "1. 设置临时关机 (今天)"
        echo "2. 取消临时关机"
        echo "3. 设置每日定时关机"
        echo "4. 取消每日定时关机"
        echo "5. 检查关机状态"
        echo "6. 退出"
        echo "------------------------"
        read -r -p "请输入选项 [1-6]: " choice

        case $choice in
            1) set_temporary_shutdown ;;
            2) cancel_temporary_shutdown ;;
            3) set_daily_shutdown ;;
            4) cancel_daily_shutdown ;;
            5) check_shutdown_status ;;
            6) exit 0 ;;
            *) error "无效选项，请输入 1 到 6 之间的数字。" ;;
        esac
    done
}

# --- 脚本入口 ---
main "$@"
