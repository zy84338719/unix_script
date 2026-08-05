#!/bin/bash

# 进程管理工具配置文件
# process_manager_config.sh
#
# 这个文件包含了一些预定义的进程搜索模式和常用命令别名

# --- 常用端口号映射 ---
declare -A COMMON_PORTS=(
    ["http"]="80"
    ["https"]="443"
    ["ssh"]="22"
    ["ftp"]="21"
    ["mysql"]="3306"
    ["postgres"]="5432"
    ["redis"]="6379"
    ["mongodb"]="27017"
    ["node"]="3000"
    ["react"]="3000"
    ["vue"]="8080"
    ["prometheus"]="9090"
    ["node_exporter"]="9100"
    ["grafana"]="3000"
    ["ddns-go"]="9876"
)

# --- 常用进程名称模式 ---
declare -A COMMON_PROCESSES=(
    ["chrome"]="Google Chrome|chrome|chromium"
    ["firefox"]="firefox"
    ["vscode"]="Code|code"
    ["docker"]="docker|containerd"
    ["nginx"]="nginx"
    ["apache"]="httpd|apache"
    ["mysql"]="mysqld"
    ["postgres"]="postgres"
    ["redis"]="redis-server"
    ["mongodb"]="mongod"
    ["node"]="node"
    ["python"]="python|python3"
    ["java"]="java"
    ["ssh"]="sshd"
)

# --- 快捷搜索函数 ---
quick_search() {
    local pattern="$1"
    local pm_command
    
    # 智能检测 process_manager 命令位置
    if command -v process_manager >/dev/null 2>&1; then
        pm_command="process_manager"
    elif [[ -x "$HOME/.tools/bin/process_manager" ]]; then
        pm_command="$HOME/.tools/bin/process_manager"
    elif [[ -x "./process_manager.sh" ]]; then
        pm_command="./process_manager.sh"
    else
        echo "错误: 未找到 process_manager 命令"
        echo "请确保已正确安装或在项目目录中运行"
        return 1
    fi
    
    # 检查是否是常用端口别名
    if [[ -n "${COMMON_PORTS[$pattern]}" ]]; then
        echo "搜索端口: ${COMMON_PORTS[$pattern]} ($pattern)"
        "$pm_command" "${COMMON_PORTS[$pattern]}"
        return
    fi
    
    # 检查是否是常用进程别名
    if [[ -n "${COMMON_PROCESSES[$pattern]}" ]]; then
        echo "搜索进程: ${COMMON_PROCESSES[$pattern]} ($pattern)"
        "$pm_command" "$pattern"
        return
    fi
    
    # 直接搜索
    "$pm_command" "$pattern"
}

# --- 使用示例 ---
show_examples() {
    echo "进程管理工具使用示例："
    echo ""
    echo "1. 直接模式（命令行参数）："
    echo "   ./process_manager.sh node          # 搜索包含 'node' 的进程"
    echo "   ./process_manager.sh 3000          # 搜索使用端口 3000 的进程"
    echo "   ./process_manager.sh 1234          # 搜索 PID 为 1234 的进程"
    echo ""
    echo "2. 交互式模式："
    echo "   ./process_manager.sh               # 启动交互式界面"
    echo ""
    echo "3. 使用配置文件快捷搜索："
    echo "   source process_manager_config.sh"
    echo "   quick_search chrome                # 搜索 Chrome 浏览器"
    echo "   quick_search http                  # 搜索使用 HTTP 端口的进程"
    echo ""
    echo "常用快捷别名："
    echo "   chrome, firefox, vscode, docker"
    echo "   nginx, apache, mysql, postgres, redis"
    echo "   http, https, ssh, node, react, vue"
    echo ""
}

# 如果直接运行此配置文件，显示使用示例
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_examples
fi
