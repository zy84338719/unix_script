#!/usr/bin/env bash
#
# 进程管理工具 - Linux 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 搜索进程
search_processes() {
    local search_term="$1"
    local temp_file="/tmp/process_search_$$"
    
    setup_cleanup "$temp_file"
    
    print_info "搜索包含 '$search_term' 的进程..."
    
    # 使用 ps 命令搜索进程
    if [[ "$search_term" =~ ^[0-9]+$ ]]; then
        # 如果是数字，按端口搜索
        print_info "搜索监听端口 $search_term 的进程..."
        if command_exists ss; then
            ss -tulpn | grep ":$search_term " | awk '{print $7}' | sed 's/.*pid=\([0-9]*\).*/\1/' | sort -u > "$temp_file"
        elif command_exists netstat; then
            netstat -tulpn | grep ":$search_term " | awk '{print $7}' | cut -d'/' -f1 | sort -u > "$temp_file"
        elif command_exists lsof; then
            lsof -i ":$search_term" -t | sort -u > "$temp_file"
        else
            print_error "未找到合适的网络工具 (ss/netstat/lsof)"
            return 1
        fi
    else
        # 按进程名搜索
        ps aux | grep -i "$search_term" | grep -v grep | awk '{print $2}' > "$temp_file"
    fi
    
    if [[ ! -s "$temp_file" ]]; then
        print_warning "未找到匹配的进程"
        return 1
    fi
    
    echo "$temp_file"
}

# 显示进程详情
show_process_details() {
    local pid_file="$1"
    local pids=()
    
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && pids+=("$pid")
    done < "$pid_file"
    
    if [[ ${#pids[@]} -eq 0 ]]; then
        print_warning "没有找到有效的进程"
        return 1
    fi
    
    print_header "📋 找到 ${#pids[@]} 个匹配的进程："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-6s %-8s %-10s %-15s %s\n" "序号" "PID" "用户" "CPU%" "命令"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local index=1
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            local proc_info
            proc_info=$(ps -p "$pid" -o pid,user,pcpu,comm --no-headers 2>/dev/null)
            if [[ -n "$proc_info" ]]; then
                printf "%-6d %s\n" "$index" "$proc_info"
                ((index++))
            fi
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo "${pids[@]}"
}

# 终止进程
kill_process() {
    local pid="$1"
    local signal="${2:-TERM}"
    
    if ! kill -0 "$pid" 2>/dev/null; then
        print_error "进程 $pid 不存在或已经停止"
        return 1
    fi
    
    # 获取进程信息
    local proc_name
    proc_name=$(ps -p "$pid" -o comm --no-headers 2>/dev/null | tr -d ' ')
    
    print_info "准备终止进程 $pid ($proc_name)..."
    
    # 发送信号
    if kill -"$signal" "$pid" 2>/dev/null; then
        print_success "信号 $signal 已发送给进程 $pid"
        
        # 等待进程结束
        local count=0
        while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
            sleep 1
            ((count++))
            printf "."
        done
        echo
        
        if kill -0 "$pid" 2>/dev/null; then
            print_warning "进程 $pid 仍在运行，可能需要强制终止"
            return 1
        else
            print_success "进程 $pid 已成功终止"
            return 0
        fi
    else
        print_error "无法终止进程 $pid"
        return 1
    fi
}

# 批量处理进程
batch_kill_processes() {
    local pids=("$@")
    local failed_pids=()
    
    print_header "🔥 批量终止进程"
    
    for pid in "${pids[@]}"; do
        print_info "处理进程 $pid..."
        
        # 首先尝试优雅终止
        if kill_process "$pid" "TERM"; then
            continue
        fi
        
        # 如果优雅终止失败，询问是否强制终止
        if confirm "进程 $pid 无法优雅终止，是否强制终止？" "n"; then
            if kill_process "$pid" "KILL"; then
                print_success "进程 $pid 已强制终止"
            else
                failed_pids+=("$pid")
            fi
        else
            failed_pids+=("$pid")
        fi
    done
    
    if [[ ${#failed_pids[@]} -gt 0 ]]; then
        print_warning "以下进程终止失败：${failed_pids[*]}"
        return 1
    else
        print_success "所有进程已成功终止"
        return 0
    fi
}

# 显示帮助信息
show_help() {
    print_header "🔧 Linux 进程管理工具"
    echo "用法："
    echo "  $0 [选项] <搜索词>"
    echo
    echo "选项："
    echo "  -h, --help     显示此帮助信息"
    echo "  -p, --port     按端口号搜索进程"
    echo "  -n, --name     按进程名搜索进程"
    echo "  -k, --kill     搜索后直接终止匹配的进程"
    echo "  -f, --force    使用 SIGKILL 强制终止进程"
    echo
    echo "示例："
    echo "  $0 nginx                # 搜索名称包含 nginx 的进程"
    echo "  $0 -p 80               # 搜索监听 80 端口的进程"
    echo "  $0 -k python           # 搜索并终止 python 进程"
    echo "  $0 -f -k node          # 强制终止 node 进程"
    echo
}

# 交互式进程管理
interactive_mode() {
    local search_term="$1"
    local temp_file
    
    temp_file=$(search_processes "$search_term")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local pids
    pids=$(show_process_details "$temp_file")
    read -ra pid_array <<< "$pids"
    
    if [[ ${#pid_array[@]} -eq 0 ]]; then
        return 1
    fi
    
    echo
    print_menu "请选择操作："
    echo "  1) 终止选定的进程 (SIGTERM)"
    echo "  2) 强制终止选定的进程 (SIGKILL)"
    echo "  3) 终止所有匹配的进程"
    echo "  4) 刷新进程列表"
    echo "  0) 返回"
    echo
    
    read -p "请输入选择 [0-4]: " choice
    
    case "$choice" in
        1|2)
            local signal="TERM"
            [[ "$choice" == "2" ]] && signal="KILL"
            
            read -p "请输入要终止的进程序号 (用空格分隔): " selection
            local selected_pids=()
            
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#pid_array[@]} ]]; then
                    selected_pids+=("${pid_array[$((num-1))]}")
                else
                    print_warning "无效的序号：$num"
                fi
            done
            
            if [[ ${#selected_pids[@]} -gt 0 ]]; then
                for pid in "${selected_pids[@]}"; do
                    kill_process "$pid" "$signal"
                done
            fi
            ;;
        3)
            if confirm "确认终止所有 ${#pid_array[@]} 个匹配的进程？"; then
                batch_kill_processes "${pid_array[@]}"
            fi
            ;;
        4)
            interactive_mode "$search_term"
            return
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

# 主函数
main() {
    local search_term=""
    local kill_mode=false
    local force_mode=false
    local port_mode=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                return 0
                ;;
            -p|--port)
                port_mode=true
                shift
                ;;
            -n|--name)
                port_mode=false
                shift
                ;;
            -k|--kill)
                kill_mode=true
                shift
                ;;
            -f|--force)
                force_mode=true
                shift
                ;;
            -*)
                print_error "未知选项：$1"
                show_help
                return 1
                ;;
            *)
                search_term="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$search_term" ]]; then
        print_error "请提供搜索词"
        show_help
        return 1
    fi
    
    # 执行搜索
    local temp_file
    temp_file=$(search_processes "$search_term")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local pids
    pids=$(show_process_details "$temp_file")
    read -ra pid_array <<< "$pids"
    
    if [[ ${#pid_array[@]} -eq 0 ]]; then
        return 1
    fi
    
    # 处理结果
    if $kill_mode; then
        local signal="TERM"
        $force_mode && signal="KILL"
        
        echo
        if confirm "确认终止所有 ${#pid_array[@]} 个匹配的进程？"; then
            batch_kill_processes "${pid_array[@]}"
        fi
    else
        interactive_mode "$search_term"
    fi
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
