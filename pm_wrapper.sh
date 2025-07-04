#!/bin/bash

#
# pm_wrapper.sh
#
# 进程管理工具的包装脚本，提供更智能的路径检测和跨平台兼容性
#

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 日志函数 ---
info() { echo -e "${BLUE}[信息]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }

# --- 智能检测 process_manager 位置 ---
find_process_manager() {
    local locations=(
        # 系统安装位置（优先级最高）
        "$HOME/.tools/bin/process_manager"
        "$HOME/.local/bin/process_manager"
        "/usr/local/bin/process_manager"
        
        # 开发环境位置
        "$(dirname "$0")/process_manager"
        "$(dirname "$0")/process_manager.sh"
        "./process_manager"
        "./process_manager.sh"
        
        # 当前目录和常见位置
        "process_manager"
        "process_manager.sh"
    )
    
    for location in "${locations[@]}"; do
        if [[ -x "$location" ]]; then
            echo "$location"
            return 0
        fi
    done
    
    # 最后尝试使用 which 或 command 查找
    if command -v process_manager >/dev/null 2>&1; then
        echo "process_manager"
        return 0
    fi
    
    return 1
}

# --- 检查系统依赖 ---
check_dependencies() {
    local missing_deps=()
    
    # 检查基本命令
    if ! command -v ps >/dev/null 2>&1; then
        missing_deps+=("ps")
    fi
    
    # 检查平台特定工具
    case "$(uname -s)" in
        Darwin)
            if ! command -v lsof >/dev/null 2>&1; then
                missing_deps+=("lsof")
            fi
            ;;
        Linux)
            if ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1; then
                missing_deps+=("ss 或 netstat")
            fi
            ;;
    esac
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "缺少以下依赖命令: ${missing_deps[*]}"
        echo ""
        echo "请安装缺少的依赖:"
        case "$(uname -s)" in
            Darwin)
                echo "  macOS 通常已预装所需工具"
                ;;
            Linux)
                echo "  Ubuntu/Debian: sudo apt-get install iproute2 net-tools"
                echo "  CentOS/RHEL:   sudo yum install iproute net-tools"
                echo "  Arch Linux:    sudo pacman -S iproute2 net-tools"
                ;;
        esac
        return 1
    fi
    
    return 0
}

# --- 显示使用帮助 ---
show_help() {
    echo "进程管理工具 (Process Manager)"
    echo ""
    echo "用法:"
    echo "  $0 [搜索词]           # 搜索并管理进程"
    echo "  $0 --help            # 显示此帮助信息"
    echo "  $0 --version         # 显示版本信息"
    echo "  $0 --install         # 运行安装程序"
    echo "  $0 --config          # 显示配置信息"
    echo ""
    echo "示例:"
    echo "  $0 node              # 搜索 Node.js 进程"
    echo "  $0 3000              # 搜索使用端口 3000 的进程"
    echo "  $0 chrome            # 搜索 Chrome 浏览器"
    echo ""
    echo "交互式模式:"
    echo "  $0                   # 不带参数启动交互式界面"
}

# --- 显示版本信息 ---
show_version() {
    echo "进程管理工具 v1.0.0"
    echo "支持平台: macOS, Linux"
    echo "Shell支持: Bash, Zsh, Fish"
}

# --- 显示配置信息 ---
show_config() {
    echo "配置信息:"
    echo "=================="
    echo "操作系统: $(uname -s)"
    echo "Shell: $SHELL"
    echo "用户: $USER"
    echo "主目录: $HOME"
    echo ""
    
    local pm_path
    if pm_path=$(find_process_manager); then
        echo "进程管理器位置: $pm_path"
    else
        echo "进程管理器位置: 未找到"
    fi
    
    echo ""
    echo "工具目录结构:"
    if [[ -d "$HOME/.tools" ]]; then
        echo "✅ ~/.tools 目录已创建"
        if [[ -d "$HOME/.tools/bin" ]]; then
            echo "✅ ~/.tools/bin 目录已创建"
            if [[ -f "$HOME/.tools/bin/process_manager" ]]; then
                echo "✅ process_manager 已安装"
            else
                echo "❌ process_manager 未安装"
            fi
        else
            echo "❌ ~/.tools/bin 目录不存在"
        fi
    else
        echo "❌ ~/.tools 目录不存在"
    fi
    
    echo ""
    echo "环境变量:"
    if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
        echo "✅ PATH 包含 ~/.tools/bin"
    else
        echo "❌ PATH 不包含 ~/.tools/bin"
    fi
}

# --- 运行安装程序 ---
run_installer() {
    local installer_path
    local possible_installers=(
        "$(dirname "$0")/install_process_manager.sh"
        "./install_process_manager.sh"
        "install_process_manager.sh"
    )
    
    for installer in "${possible_installers[@]}"; do
        if [[ -f "$installer" ]]; then
            installer_path="$installer"
            break
        fi
    done
    
    if [[ -n "$installer_path" ]]; then
        info "运行安装程序: $installer_path"
        bash "$installer_path"
    else
        error "未找到安装程序 install_process_manager.sh"
        echo "请确保在项目目录中运行此命令"
        return 1
    fi
}

# --- 主函数 ---
main() {
    # 处理特殊参数
    case "$1" in
        --help|-h|help)
            show_help
            exit 0
            ;;
        --version|-v|version)
            show_version
            exit 0
            ;;
        --config|config)
            show_config
            exit 0
            ;;
        --install|install)
            run_installer
            exit $?
            ;;
    esac
    
    # 检查系统依赖
    if ! check_dependencies; then
        exit 1
    fi
    
    # 查找进程管理器
    local pm_command
    if pm_command=$(find_process_manager); then
        # 执行进程管理器
        exec "$pm_command" "$@"
    else
        error "未找到进程管理工具"
        echo ""
        echo "可能的解决方案:"
        echo "1. 运行安装程序: $0 --install"
        echo "2. 手动安装: ./install_process_manager.sh"
        echo "3. 确保在项目目录中运行"
        echo ""
        exit 1
    fi
}

# --- 脚本入口 ---
main "$@"
