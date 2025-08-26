# 通用工具函数

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查是否为root用户
is_root() {
    [[ $EUID -eq 0 ]]
}

# 请求确认
confirm() {
    local prompt="${1:-确认吗?}"
    local default="${2:-n}"
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt [Y/n]: " choice
            choice=${choice:-y}
        else
            read -p "$prompt [y/N]: " choice
            choice=${choice:-n}
        fi
        
        case "$choice" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

# 安全下载文件
safe_download() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-3}"
    
    for ((i=1; i<=max_retries; i++)); do
        print_info "下载 $url (尝试 $i/$max_retries)"
        
        if command_exists curl; then
            if curl -fSL "$url" -o "$output"; then
                return 0
            fi
        elif command_exists wget; then
            if wget -O "$output" "$url"; then
                return 0
            fi
        else
            print_error "未找到 curl 或 wget 命令"
            return 1
        fi
        
        if [[ $i -lt $max_retries ]]; then
            print_warning "下载失败，3秒后重试..."
            sleep 3
        fi
    done
    
    print_error "下载失败，已尝试 $max_retries 次"
    return 1
}

# 创建目录（如果不存在）
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        print_info "创建目录: $dir"
        mkdir -p "$dir"
    fi
}

# 备份文件
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "备份文件: $file -> $backup"
        cp "$file" "$backup"
        echo "$backup"
    fi
}

# 检查端口是否占用
check_port() {
    local port="$1"
    if command_exists netstat; then
        netstat -tuln | grep -q ":$port "
    elif command_exists ss; then
        ss -tuln | grep -q ":$port "
    elif command_exists lsof; then
        lsof -i ":$port" >/dev/null 2>&1
    else
        return 1
    fi
}

# 等待用户按键
wait_for_key() {
    local prompt="${1:-按任意键继续...}"
    read -n 1 -s -r -p "$prompt"
    echo
}

# 进度条显示
show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    
    printf "\r["
    printf "%*s" "$completed" "" | tr ' ' '█'
    printf "%*s" $((width - completed)) "" | tr ' ' '░'
    printf "] %d%% (%d/%d)" "$percentage" "$current" "$total"
}

# 清理临时文件
cleanup_temp() {
    local temp_files=("$@")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
        fi
    done
}

# 设置陷阱清理
setup_cleanup() {
    local temp_files=("$@")
    trap "cleanup_temp ${temp_files[*]}" EXIT INT TERM
}
