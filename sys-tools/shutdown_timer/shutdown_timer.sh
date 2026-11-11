#!/bin/bash
# 注：仅 nounset + pipefail，不加 errexit（-e）：本脚本是交互式菜单，
# 菜单项命令偶发返回非零不应整体退出。
set -uo pipefail

#
# shutdown_timer.sh
#
# 一个在 macOS 和 Linux 上计划或取消临时及每日系统关机的脚本。
#

# 引入公共函数库（颜色 / 打印函数等）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# --- 全局变量 ---
# 将在 main 函数中设置为 "Darwin" 或 "Linux"
OS=""
# macOS-specific
PLIST_FILE="/Library/LaunchDaemons/com.user.dailyshutdown.plist"
PLIST_LABEL="com.user.dailyshutdown"
# Linux-specific
# 用于识别 cron 任务
CRON_COMMENT="# AUTO_SHUTDOWN_SCRIPT"

# --- 核心函数 ---

# 验证时间格式 (HH:MM)
validate_time() {
    if ! [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        error "$(_t 'Invalid time format. Please enter the HH:MM format (for example, 23:00).')"
        return 1
    fi
    return 0
}

# 设置临时关机
set_temporary_shutdown() {
    local time
    read -r -p "$(_t 'Please enter the shutdown time for today (HH:MM):') " time
    validate_time "$time" || return 1

    if [[ "$OS" == "Darwin" ]]; then
        # macOS 需要将 HH:MM 转换为 +m (从现在开始的分钟数)
        local current_epoch
        local target_epoch
        current_epoch=$(date +%s)
        target_epoch=$(date -j -f "%H:%M" "$time" +%s)
        
        if [[ $target_epoch -le $current_epoch ]]; then
            error "$(_t 'The given time has already passed. Please enter a time in the future.')"
            return 1
        fi
        
        local diff_minutes
        diff_minutes=$(( (target_epoch - current_epoch) / 60 ))
        info "$(_tf 'The system will shut down in %s minutes.' "${diff_minutes}")"
        info "$(_t 'The system will ask you for the password to run the shutdown command.')"
        
        if sudo shutdown -h "+${diff_minutes}"; then
            success "$(_tf 'The system is scheduled to shut down in %s minutes.' "${diff_minutes}")"
            info "$(_t 'To cancel it, choose the cancel temporary shutdown option in the main menu.')"
        else
            error "$(_t 'Failed to schedule the temporary shutdown. Please check the error.')"
        fi
    else
        # Linux可以直接使用 HH:MM 格式
        info "$(_tf 'The system will shut down today at %s.' "${time}")"
        info "$(_t 'The system will ask you for the password to run the shutdown command.')"
        
        if sudo shutdown "$time"; then
            success "$(_tf 'The system is scheduled to shut down today at %s.' "${time}")"
            info "$(_t 'To cancel it, choose the cancel temporary shutdown option in the main menu.')"
        else
            error "$(_t 'Failed to schedule the temporary shutdown. Please check the error.')"
        fi
    fi
}

# 取消临时关机
cancel_temporary_shutdown() {
    info "$(_t 'Trying to cancel the scheduled temporary shutdown.')"
    info "$(_t 'The system will ask you for the password.')"

    if [[ "$OS" == "Darwin" ]]; then
        # macOS 使用 killall
        if sudo killall shutdown 2>/dev/null; then
            success "$(_t 'The scheduled temporary shutdown has been cancelled.')"
        else
            local result
            result=$(sudo killall shutdown 2>&1)
            if [[ "$result" == *"No matching processes were found"* ]]; then
                info "$(_t 'No temporary shutdown to cancel was found.')"
            else
                error "$(_t 'An error occurred while cancelling the temporary shutdown.')"
                error "$(_tf 'Details: %s' "$result")"
            fi
        fi
    else
        # Linux 使用 shutdown -c
        if sudo shutdown -c 2>/dev/null; then
            success "$(_t 'The scheduled temporary shutdown has been cancelled.')"
        else
            local result
            result=$(sudo shutdown -c 2>&1)
            if [[ "$result" == *"shutdown: Not scheduled."* ]]; then
                info "$(_t 'No temporary shutdown to cancel was found.')"
            else
                error "$(_t 'An error occurred while cancelling the temporary shutdown.')"
                error "$(_tf 'Details: %s' "$result")"
            fi
        fi
    fi
}

# 检查关机状态
check_shutdown_status() {
    info "--- $(_t 'Shutdown status check ---')"
    local found_temp=false
    local found_daily=false

    # 检查临时关机
    if [[ "$OS" == "Darwin" ]]; then
        if pgrep -f "/sbin/shutdown" >/dev/null; then
            info "$(_t 'A scheduled temporary shutdown was detected.')"
            found_temp=true
        fi
    else # Linux
        # 优先检查 systemd 的关机计划文件（现代 Linux 发行版）
        if [ -f "/run/systemd/shutdown/scheduled" ]; then
            info "$(_t 'A scheduled temporary shutdown was detected (systemd).')"
            found_temp=true
        # 备用方案：检查是否有正在运行的 shutdown 进程
        elif pgrep -f "/usr/sbin/shutdown\|/sbin/shutdown" >/dev/null; then
            info "$(_t 'A scheduled temporary shutdown was detected.')"
            found_temp=true
        fi
    fi
    if ! $found_temp; then
        info "$(_t 'No scheduled temporary shutdown was found.')"
    fi

    # 检查每日定时关机
    if [[ "$OS" == "Darwin" ]]; then
        if sudo launchctl list | grep -q "$PLIST_LABEL"; then
            info "$(_t 'A daily scheduled shutdown task was detected (launchd).')"
            found_daily=true
        fi
    else # Linux
        if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
            info "$(_t 'A daily scheduled shutdown task was detected (cron).')"
            found_daily=true
        fi
    fi
    if ! $found_daily; then
        info "$(_t 'No daily scheduled shutdown task was found.')"
    fi
    
    if ! $found_temp && ! $found_daily; then
        success "$(_t 'No shutdown task is currently set.')"
    fi
    info "---------------------"
}


# 设置每日定时关机
set_daily_shutdown() {
    local time
    read -r -p "$(_t 'Please enter the daily shutdown time (HH:MM):') " time
    validate_time "$time" || return 1

    if [[ "$OS" == "Darwin" ]]; then
        set_daily_shutdown_macos "$time"
    else
        set_daily_shutdown_linux "$time"
    fi
}

# 取消每日定时关机
cancel_daily_shutdown() {
    info "$(_t 'Cancelling the daily scheduled shutdown task...')"
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

    info "$(_tf 'Setting up the daily %s scheduled shutdown task for macOS.' "${time}")"
    warn "$(_t 'This creates a system-wide launchd task. Administrator privileges are required.')"

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
        success "$(_tf 'The daily scheduled shutdown task has been set successfully for every day at %s.' "${time}")"
    else
        error "$(_t 'Failed to load the launchd task. Please check the system log.')"
        sudo rm -f "$PLIST_FILE"
    fi
}

cancel_daily_shutdown_macos() {
    if [ ! -f "$PLIST_FILE" ]; then
        info "$(_t 'The configuration file of the daily scheduled shutdown task was not found (launchd).')"
        return 0
    fi
    warn "$(_t 'This removes the system-wide launchd task. Administrator privileges are required.')"
    sudo launchctl bootout system "$PLIST_FILE" &>/dev/null
    sudo rm -f "$PLIST_FILE"
    success "$(_t 'The daily scheduled shutdown task has been cancelled successfully.')"
}

# --- Linux 特定函数 ---
set_daily_shutdown_linux() {
    local time=$1
    local hour=${time%%:*}
    local minute=${time#*:}

    info "$(_tf 'Setting up the daily %s scheduled shutdown task for Linux.' "${time}")"
    warn "$(_t 'This adds an entry to your crontab.')"

    # 为避免重复，先移除旧的条目
    (crontab -l 2>/dev/null | grep -v "$CRON_COMMENT") | crontab -
    # 添加新条目
    (crontab -l 2>/dev/null; echo "$minute $hour * * * /sbin/shutdown -h now $CRON_COMMENT") | crontab -

    if crontab -l | grep -q "$CRON_COMMENT"; then
        success "$(_tf 'The daily scheduled shutdown task has been set successfully for every day at %s.' "${time}")"
    else
        error "$(_t 'Failed to set up the cron task. Please check that the cron service is running and that you have the required permissions.')"
    fi
}

cancel_daily_shutdown_linux() {
    if ! crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        info "$(_t 'The daily scheduled shutdown task was not found (cron).')"
        return 0
    fi
    warn "$(_t 'This removes the task from your crontab. Administrator privileges are required.')"
    (crontab -l | grep -v "$CRON_COMMENT") | crontab -
    success "$(_t 'The daily scheduled shutdown task has been cancelled successfully.')"
}

# 机器可读状态（供 status --json / module_status_machine 复用）。
# 契约：UXS_STATUS_MODE=machine 时输出 STATE=，否则输出人类可读中文（uxs_emit_status 双轨）。
status_shutdown_timer() {
    detect_os
    local is_configured=false state human
    if [[ "$OS_TYPE" == "darwin" ]]; then
        [ -f "$PLIST_FILE" ] && is_configured=true
    elif [[ "$OS_TYPE" == "linux" ]]; then
        # crontab -l 无 crontab 时返回非零，整条 if 即判否（正确：未配置）
        if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
            is_configured=true
        fi
    fi
    if $is_configured; then
        state="configured"
        human="${GREEN}$(_t '✅ The daily scheduled shutdown is configured')${NC}"
    else
        state="not_configured"
        human="${RED}$(_t '❌ Not configured')${NC}"
    fi
    uxs_emit_status "$state" "$human"
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
            error "$(_t 'Unsupported operating system'): $(uname -s)"
            exit 1
            ;;
    esac

    # 处理非交互式参数
    case "${1:-}" in
        cancel_daily_shutdown_internal)
            cancel_daily_shutdown; exit 0 ;;
        status)
            status_shutdown_timer; exit 0 ;;
        uninstall)
            # 取消每日关机即等价于「卸载」本模块配置
            cancel_daily_shutdown; exit 0 ;;
        install)
            # shutdown_timer 需交互式选择关机时间，非交互模式仅给出引导
            info "shutdown_timer $(_t 'The shutdown time must be configured interactively. Please run the interactive menu:')"
            info "  ./install.sh   $(_t '(Main menu → System tools → shutdown_timer)')"
            exit 0 ;;
        help|--help|-h)
            printf '%s\n' "$(_tf 'Usage: %s [install|uninstall|status|help]' "$0")"
            echo "  install                       $(_t 'Go to the interactive menu to configure the shutdown time')"
            echo "  uninstall                     $(_t 'Cancel the daily scheduled shutdown (≈ cancel_daily_shutdown)')"
            echo "  status                        $(_t 'View the current shutdown configuration')"
            echo "  cancel_daily_shutdown_internal $(_t 'Cancel the daily shutdown (legacy interface)')"
            echo "  help                          $(_t 'Display this help')"
            echo "  ($(_t 'no arguments)                      enter the interactive menu')"
            exit 0 ;;
    esac

    while true; do
        echo ""
        printf '%s\n' "$(_t 'Automatic shutdown management script')"
        echo "------------------------"
        echo "1. $(_t 'Set a temporary shutdown (today)')"
        echo "2. $(_t 'Cancel the temporary shutdown')"
        echo "3. $(_t 'Set the daily scheduled shutdown')"
        echo "4. $(_t 'Cancel the daily scheduled shutdown')"
        echo "5. $(_t 'Check the shutdown status')"
        echo "6. $(_t 'Exit')"
        echo "------------------------"
        read -r -p "$(_t 'Please choose an option [1-6]:') " choice

        case $choice in
            1) set_temporary_shutdown ;;
            2) cancel_temporary_shutdown ;;
            3) set_daily_shutdown ;;
            4) cancel_daily_shutdown ;;
            5) check_shutdown_status ;;
            6) exit 0 ;;
            *) error "$(_t 'Invalid option, please enter a number between 1 and 6.')" ;;
        esac
    done
}

# --- 脚本入口 ---
main "$@"
