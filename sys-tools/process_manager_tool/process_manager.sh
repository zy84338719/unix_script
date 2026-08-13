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
NC='\033[0m' # 无颜色

# --- 日志函数 ---
info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
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
            error "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac
}

# --- 搜索进程 ---
search_processes() {
    local search_term="$1"
    local temp_file="/tmp/process_search_$$"
    
    info "搜索包含 '$search_term' 的进程..."
    
    if [[ "$OS" == "macOS" ]]; then
        # macOS 使用 ps 和 lsof
        {
            echo "=== 按进程名搜索 ==="
            pgrep -f "$search_term" | while read -r pid; do
                ps -p "$pid" -o pid,user,comm,args 2>/dev/null || true
            done
            echo ""
            echo "=== 按端口搜索 ==="
            if [[ "$search_term" =~ ^[0-9]+$ ]]; then
                lsof -i ":$search_term" 2>/dev/null || echo "端口 $search_term 未被占用"
            else
                echo "搜索词不是数字，跳过端口搜索"
            fi
        } > "$temp_file"
    else
        # Linux 使用 ps 和 netstat/ss
        {
            echo "=== 按进程名搜索 ==="
            pgrep -f "$search_term" | while read -r pid; do
                ps -p "$pid" -o pid,user,comm,args 2>/dev/null || true
            done
            echo ""
            echo "=== 按端口搜索 ==="
            if [[ "$search_term" =~ ^[0-9]+$ ]]; then
                if command -v ss >/dev/null 2>&1; then
                    ss -tulnp | grep ":$search_term " 2>/dev/null || echo "端口 $search_term 未被占用"
                elif command -v netstat >/dev/null 2>&1; then
                    netstat -tulnp | grep ":$search_term " 2>/dev/null || echo "端口 $search_term 未被占用"
                else
                    echo "未找到 ss 或 netstat 命令"
                fi
            else
                echo "搜索词不是数字，跳过端口搜索"
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
        warn "未找到匹配的进程"
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
        error "进程 $pid 不存在或无权限访问"
        return 1
    fi
    
    echo "----------------------------------------"
    highlight "进程详细信息 (PID: $pid)"
    echo "----------------------------------------"
    
    if [[ "$OS" == "macOS" ]]; then
        ps -p "$pid" -o pid,ppid,user,comm,args
        echo ""
        echo "监听的端口:"
        lsof -P -i -p "$pid" 2>/dev/null | grep LISTEN || echo "  无监听端口"
        echo ""
        echo "打开的文件数:"
        local file_count
        file_count=$(lsof -p "$pid" 2>/dev/null | wc -l)
        echo "  $file_count 个文件描述符"
    else
        ps -p "$pid" -o pid,ppid,user,comm,args
        echo ""
        echo "监听的端口:"
        ss -tulnp | grep "pid=$pid," 2>/dev/null || echo "  无监听端口"
        echo ""
        echo "进程状态:"
        grep -E "^(Name|State|Threads):" "/proc/$pid/status" 2>/dev/null || echo "  无法读取状态"
    fi
    echo "----------------------------------------"
}

# --- 智能终止进程 ---
terminate_process() {
    local pid="$1"
    local force="$2"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        error "进程 $pid 不存在或已退出"
        return 1
    fi
    
    if [[ "$force" == "force" ]]; then
        warn "强制杀死进程 $pid (SIGKILL)"
        if kill -9 "$pid" 2>/dev/null; then
            success "进程 $pid 已被强制杀死"
            return 0
        else
            error "无法杀死进程 $pid (权限不足或进程保护)"
            return 1
        fi
    else
        info "尝试优雅地终止进程 $pid (SIGTERM)"
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
                warn "进程 $pid 在 10 秒内未响应 SIGTERM"
                echo ""
                read -r -p "是否强制杀死进程? [y/N]: "
                if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                    terminate_process "$pid" "force"
                else
                    info "已取消强制杀死操作"
                    return 1
                fi
            else
                success "进程 $pid 已优雅退出"
                return 0
            fi
        else
            error "无法发送 SIGTERM 到进程 $pid (权限不足)"
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
        warn "未找到匹配的进程"
        return 1
    elif [[ $pid_count -eq 1 ]]; then
        local pid=${pid_array[0]}
        info "找到唯一匹配进程 PID: $pid"
        show_process_details "$pid"
        echo ""
        read -r -p "确认要终止这个进程吗? [y/N]: "
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            terminate_process "$pid"
        else
            info "已取消操作"
        fi
    else
        info "找到 $pid_count 个匹配的进程:"
        echo ""
        
        # 显示进程列表
        local i=1
        for pid in "${pid_array[@]}"; do
            echo "$i) PID $pid:"
            ps -p "$pid" -o pid,user,comm,args 2>/dev/null | tail -n 1 | sed 's/^/   /'
            ((i++))
        done
        echo "$i) 显示所有进程的详细信息"
        echo "$((i+1))) 取消操作"
        echo ""
        
        while true; do
            read -r -p "请选择要操作的进程 [1-$((i+1))]: " choice
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 && $choice -le $((i+1)) ]]; then
                if [[ $choice -eq $i ]]; then
                    # 显示所有进程详细信息
                    for pid in "${pid_array[@]}"; do
                        show_process_details "$pid"
                        echo ""
                    done
                elif [[ $choice -eq $((i+1)) ]]; then
                    # 取消操作
                    info "已取消操作"
                    return 0
                else
                    # 选择具体进程
                    local selected_pid=${pid_array[$((choice-1))]}
                    show_process_details "$selected_pid"
                    echo ""
                    read -r -p "确认要终止进程 $selected_pid 吗? [y/N]: "
                    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                        terminate_process "$selected_pid"
                    else
                        info "已取消操作"
                    fi
                    break
                fi
            else
                error "无效选择，请输入 1 到 $((i+1)) 之间的数字"
            fi
        done
    fi
}

# --- 主菜单 ---
show_main_menu() {
    clear
    header "🔧 智能进程管理工具"
    echo "=================================="
    echo "支持的搜索方式："
    echo "  • 进程名称 (模糊匹配)"
    echo "  • 端口号 (精确匹配)"
    echo "  • 进程ID (精确匹配)"
    echo ""
    echo "操作系统: $OS"
    echo "=================================="
}

# --- 主函数 ---
main() {
    detect_os
    
    # 检查参数
    if [[ $# -eq 1 ]]; then
        # 直接搜索模式
        local search_term="$1"
        info "搜索模式: $search_term"
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
        read -r -p "请输入搜索词 (进程名/端口号/PID，或输入 'q' 退出): " search_input
        
        if [[ "$search_input" == "q" || "$search_input" == "quit" || "$search_input" == "exit" ]]; then
            info "再见！"
            exit 0
        fi
        
        if [[ -z "$search_input" ]]; then
            error "搜索词不能为空"
            echo ""
            read -r -p "按回车键继续..."
            continue
        fi
        
        echo ""
        if search_processes "$search_input"; then
            echo ""
            interactive_process_selection "$search_input"
        fi
        
        echo ""
        read -r -p "按回车键返回主菜单..."
    done
}

# --- 脚本入口 ---
main "$@"
