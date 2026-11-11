#!/bin/bash

#
# process_manager.sh
#
# 一个智能的进程管理工具，支持模糊搜索进程名称或端口号，
# 提供二次确认，并能优雅地终止或强制杀死进程。
#
# 注意：本脚本是装到 ~/.tools/bin 的「运行时交互工具」（非 unix_script 安装契约脚本），
# 故刻意不启用 set -e/pipefail——交互式循环中命令偶发返回非零不应整体退出。
# 关键搜索管道已加 || true 兜底，便于未来若引入 pipefail 也不会误伤。
#

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
# 无颜色
NC='\033[0m'

# --- 日志函数 ---
info() { echo -e "${BLUE}[$(_t 'Info]')${NC} $1"; }
success() { echo -e "${GREEN}[$(_t 'Success]')${NC} $1"; }
error() { echo -e "${RED}[$(_t 'Error]')${NC} $1"; }
warn() { echo -e "${YELLOW}[$(_t 'Warning]')${NC} $1"; }
header() { echo -e "${CYAN}${BOLD}$1${NC}"; }
highlight() { echo -e "${PURPLE}$1${NC}"; }

# --- 检测操作系统 ---
detect_os() {
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            ;;
        Linux)
            OS="Linux"
            ;;
        *)
            error "$(_t 'Unsupported operating system'): $(uname -s)"
            exit 1
            ;;
    esac
}

# --- 搜索进程 ---
search_processes() {
    local search_term="$1"
    local temp_file="/tmp/process_search_$$"
    
    info "$(_tf 'Searching the processes that contain %s...' "$search_term")"
    
    if [[ "$OS" == "macOS" ]]; then
        # macOS 使用 ps 和 lsof
        {
            echo "=== $(_t 'Search by process name ===')"
            pgrep -f "$search_term" | while read -r pid; do
                ps -p "$pid" -o pid,user,comm,args 2>/dev/null || true
            done
            echo ""
            echo "=== $(_t 'Search by port ===')"
            if [[ "$search_term" =~ ^[0-9]+$ ]]; then
                lsof -i ":$search_term" 2>/dev/null || printf '%s\n' "$(_tf 'The port %s is not in use' "$search_term")"
            else
                printf '%s\n' "$(_t 'The search term is not a number, skipping the port search')"
            fi
        } > "$temp_file"
    else
        # Linux 使用 ps 和 netstat/ss
        {
            echo "=== $(_t 'Search by process name ===')"
            pgrep -f "$search_term" | while read -r pid; do
                ps -p "$pid" -o pid,user,comm,args 2>/dev/null || true
            done
            echo ""
            echo "=== $(_t 'Search by port ===')"
            if [[ "$search_term" =~ ^[0-9]+$ ]]; then
                if command -v ss >/dev/null 2>&1; then
                    ss -tulnp | grep ":$search_term " 2>/dev/null || printf '%s\n' "$(_tf 'The port %s is not in use' "$search_term")"
                elif command -v netstat >/dev/null 2>&1; then
                    netstat -tulnp | grep ":$search_term " 2>/dev/null || printf '%s\n' "$(_tf 'The port %s is not in use' "$search_term")"
                else
                    printf '%s\n' "$(_t 'The ss or netstat command was not found')"
                fi
            else
                printf '%s\n' "$(_t 'The search term is not a number, skipping the port search')"
            fi
        } > "$temp_file"
    fi
    
    # 显示搜索结果
    if [[ -s "$temp_file" ]]; then
        cat "$temp_file"
        rm -f "$temp_file"
        echo ""
        return 0
    else
        warn "$(_t 'No matching process was found')"
        rm -f "$temp_file"
        return 1
    fi
}

# --- 提取进程ID ---
extract_pids() {
    local search_term="$1"
    local pids=()
    
    # 从进程名搜索中提取PID，使用 pgrep 替代 ps | grep
    local process_pids
    process_pids=$(pgrep -f "$search_term" 2>/dev/null || true)
    
    # 从端口搜索中提取PID（如果搜索词是数字）
    local port_pids=""
    if [[ "$search_term" =~ ^[0-9]+$ ]]; then
        if [[ "$OS" == "macOS" ]]; then
            port_pids=$(lsof -t -i ":$search_term" 2>/dev/null)
        else
            if command -v ss >/dev/null 2>&1; then
                # grep 无匹配返回非零；本脚本未启用 set -e 故当前无碍，加 || true 以便
                # 未来若引入 pipefail 也不会在「无占用端口」时中止搜索。
                port_pids=$(ss -tulnp | grep ":$search_term " | grep -o 'pid=[0-9]*' | cut -d'=' -f2 | sort -u || true)
            elif command -v netstat >/dev/null 2>&1; then
                port_pids=$(netstat -tulnp | grep ":$search_term " | awk '{print $7}' | cut -d'/' -f1 | grep -E '^[0-9]+$' | sort -u || true)
            fi
        fi
    fi
    
    # 合并并去重PID（grep 无 PID 行时返回非零，|| true 兜底；本脚本未启用 set -e）
    local all_pids
    all_pids=$(echo -e "$process_pids\n$port_pids" | grep -E '^[0-9]+$' | sort -u || true)
    
    if [[ -n "$all_pids" ]]; then
        echo "$all_pids"
        return 0
    else
        return 1
    fi
}

# --- 显示进程详细信息 ---
show_process_details() {
    local pid="$1"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        error "$(_tf 'The process %s does not exist or cannot be accessed' "$pid")"
        return 1
    fi
    
    echo "----------------------------------------"
    highlight "$(_tf 'Process details (PID: %s)' "$pid")"
    echo "----------------------------------------"
    
    if [[ "$OS" == "macOS" ]]; then
        ps -p "$pid" -o pid,ppid,user,comm,args
        echo ""
        printf '%s\n' "$(_t 'Listening ports:')"
        lsof -P -i -p "$pid" 2>/dev/null | grep LISTEN || echo "  $(_t 'No listening ports')"
        echo ""
        printf '%s\n' "$(_t 'Number of open files:')"
        local file_count
        file_count=$(lsof -p "$pid" 2>/dev/null | wc -l)
        echo "  $file_count $(_t 'file descriptors')"
    else
        ps -p "$pid" -o pid,ppid,user,comm,args
        echo ""
        printf '%s\n' "$(_t 'Listening ports:')"
        ss -tulnp | grep "pid=$pid," 2>/dev/null || echo "  $(_t 'No listening ports')"
        echo ""
        printf '%s\n' "$(_t 'Process state:')"
        grep -E "^(Name|State|Threads):" "/proc/$pid/status" 2>/dev/null || echo "  $(_t 'Cannot read the state')"
    fi
    echo "----------------------------------------"
}

# --- 智能终止进程 ---
terminate_process() {
    local pid="$1"
    local force="$2"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        error "$(_tf 'The process %s does not exist or has already exited' "$pid")"
        return 1
    fi
    
    if [[ "$force" == "force" ]]; then
        warn "$(_tf 'Force killing the process %s (SIGKILL)' "$pid")"
        if kill -9 "$pid" 2>/dev/null; then
            success "$(_tf 'The process %s has been force killed' "$pid")"
            return 0
        else
            error "$(_tf 'Cannot kill the process %s (insufficient permissions or the process is protected)' "$pid")"
            return 1
        fi
    else
        info "$(_tf 'Trying to terminate the process %s gracefully (SIGTERM)' "$pid")"
        if kill -15 "$pid" 2>/dev/null; then
            # 等待进程退出
            local count=0
            while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
                sleep 1
                ((count++))
                echo -n "."
            done
            echo ""
            
            if kill -0 "$pid" 2>/dev/null; then
                warn "$(_tf 'The process %s did not respond to SIGTERM within 10 seconds' "$pid")"
                echo ""
                read -r -p "$(_t 'Force kill the process? [y/N]:') "
                if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                    terminate_process "$pid" "force"
                else
                    info "$(_t 'The force kill operation has been cancelled')"
                    return 1
                fi
            else
                success "$(_tf 'The process %s has exited gracefully' "$pid")"
                return 0
            fi
        else
            error "$(_tf 'Cannot send SIGTERM to the process %s (insufficient permissions)' "$pid")"
            return 1
        fi
    fi
}

# --- 交互式进程选择 ---
interactive_process_selection() {
    local search_term="$1"
    local pids
    
    # 提取所有匹配的PID
    if ! pids=$(extract_pids "$search_term"); then
        return 1
    fi
    
    # 使用 mapfile 来安全地处理数组
    local pid_array
    mapfile -t pid_array <<< "$pids"
    local pid_count=${#pid_array[@]}
    
    if [[ $pid_count -eq 0 ]]; then
        warn "$(_t 'No matching process was found')"
        return 1
    elif [[ $pid_count -eq 1 ]]; then
        local pid=${pid_array[0]}
        info "$(_tf 'Found a single matching process, PID: %s' "$pid")"
        show_process_details "$pid"
        echo ""
        read -r -p "$(_t 'Do you want to terminate this process? [y/N]:') "
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            terminate_process "$pid"
        else
            info "$(_t 'The operation has been cancelled')"
        fi
    else
        info "$(_tf 'Found %s matching processes:' "$pid_count")"
        echo ""
        
        # 显示进程列表
        local i=1
        for pid in "${pid_array[@]}"; do
            echo "$i) PID $pid:"
            ps -p "$pid" -o pid,user,comm,args 2>/dev/null | tail -n 1 | sed 's/^/   /'
            ((i++))
        done
        echo "$i) $(_t 'Show the details of all the processes')"
        echo "$((i+1))) $(_t 'Cancel the operation')"
        echo ""
        
        while true; do
            read -r -p "$(_t 'Please choose the process to operate on') [1-$((i+1))]: " choice
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 && $choice -le $((i+1)) ]]; then
                if [[ $choice -eq $i ]]; then
                    # 显示所有进程详细信息
                    for pid in "${pid_array[@]}"; do
                        show_process_details "$pid"
                        echo ""
                    done
                elif [[ $choice -eq $((i+1)) ]]; then
                    # 取消操作
                    info "$(_t 'The operation has been cancelled')"
                    return 0
                else
                    # 选择具体进程
                    local selected_pid=${pid_array[$((choice-1))]}
                    show_process_details "$selected_pid"
                    echo ""
                    read -r -p "$(_tf 'Do you want to terminate the process %s? [y/N]:' "$selected_pid") "
                    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                        terminate_process "$selected_pid"
                    else
                        info "$(_t 'The operation has been cancelled')"
                    fi
                    break
                fi
            else
                error "$(_tf 'Invalid choice, please enter a number between 1 and %s' "$((i+1))")"
            fi
        done
    fi
}

# --- 主菜单 ---
show_main_menu() {
    clear
    header "$(_t '🔧 Smart process manager')"
    echo "=================================="
    printf '%s\n' "$(_t 'Supported search methods:')"
    echo "  $(_t '• Process name (fuzzy match)')"
    echo "  $(_t '• Port number (exact match)')"
    echo "  $(_t '• Process ID (exact match)')"
    echo ""
    printf '%s\n' "$(_tf 'Operating system: %s' "$OS")"
    echo "=================================="
}

# --- 主函数 ---
main() {
    detect_os
    
    # 检查参数
    if [[ $# -eq 1 ]]; then
        # 直接搜索模式
        local search_term="$1"
        info "$(_tf 'Search mode: %s' "$search_term")"
        echo ""
        
        if search_processes "$search_term"; then
            echo ""
            interactive_process_selection "$search_term"
        fi
        exit 0
    fi
    
    # 交互式模式
    while true; do
        show_main_menu
        echo ""
        read -r -p "$(_t 'Please enter the search term (process name / port number / PID, or q to quit):') " search_input
        
        if [[ "$search_input" == "q" || "$search_input" == "quit" || "$search_input" == "exit" ]]; then
            info "$(_t 'Goodbye!')"
            exit 0
        fi
        
        if [[ -z "$search_input" ]]; then
            error "$(_t 'The search term must not be empty')"
            echo ""
            read -r -p "$(_t 'Press Enter to continue...')"
            continue
        fi
        
        echo ""
        if search_processes "$search_input"; then
            echo ""
            interactive_process_selection "$search_input"
        fi
        
        echo ""
        read -r -p "$(_t 'Press Enter to return to the main menu...')"
    done
}

# --- 脚本入口 ---
main "$@"
