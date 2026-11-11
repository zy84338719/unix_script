#!/bin/bash

#
# pm_wrapper.sh
#
# 进程管理工具的包装脚本，提供更智能的路径检测和跨平台兼容性
#

# --- 颜色定义 ---
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 日志函数 ---
info() { echo -e "${BLUE}[$(_t 'Info]')${NC} $1"; }
error() { echo -e "${RED}[$(_t 'Error]')${NC} $1"; }
warn() { echo -e "${YELLOW}[$(_t 'Warning]')${NC} $1"; }

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
                missing_deps+=("ss $(_t 'or netstat')")
            fi
            ;;
    esac
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "$(_tf 'The following dependency commands are missing: %s' "${missing_deps[*]}")"
        echo ""
        printf '%s\n' "$(_t 'Please install the missing dependencies:')"
        case "$(uname -s)" in
            Darwin)
                echo "  macOS $(_t 'The required tools are usually pre-installed')"
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
    printf '%s\n' "$(_t 'Process Manager')"
    echo ""
    printf '%s\n' "$(_t 'Usage:')"
    echo "  $0 [$(_t 'search term]           # search and manage processes')"
    echo "  $0 --help            # $(_t 'Show this help information')"
    echo "  $0 --version         # $(_t 'Show the version information')"
    echo "  $0 --install         # $(_t 'Run the installer')"
    echo "  $0 --config          # $(_t 'Show the configuration information')"
    echo ""
    printf '%s\n' "$(_t 'Examples:')"
    echo "  $0 node              # $(_t 'Search the Node.js processes')"
    echo "  $0 3000              # $(_t 'Search the processes using port 3000')"
    echo "  $0 chrome            # $(_t 'Search the Chrome browser')"
    echo ""
    printf '%s\n' "$(_t 'Interactive mode:')"
    echo "  $0                   # $(_t 'Start the interactive interface without arguments')"
}

# --- 显示版本信息 ---
show_version() {
    printf '%s\n' "$(_t 'Process Manager v1.0.0')"
    printf '%s\n' "$(_t 'Supported platforms: macOS, Linux')"
    echo "Shell$(_t 'Supported shells: Bash, Zsh, Fish')"
}

# --- 显示配置信息 ---
show_config() {
    printf '%s\n' "$(_t 'Configuration information:')"
    echo "=================="
    printf '%s\n' "$(_t 'Operating system'): $(uname -s)"
    echo "Shell: $SHELL"
    printf '%s\n' "$(_tf 'User: %s' "$USER")"
    printf '%s\n' "$(_tf 'Home directory: %s' "$HOME")"
    echo ""
    
    local pm_path
    if pm_path=$(find_process_manager); then
        printf '%s\n' "$(_tf 'Process manager location: %s' "$pm_path")"
    else
        printf '%s\n' "$(_t 'Process manager location: not found')"
    fi
    
    echo ""
    printf '%s\n' "$(_t 'Tool directory structure:')"
    if [[ -d "$HOME/.tools" ]]; then
        printf '%s\n' "$(_t '✅ The ~/.tools directory has been created')"
        if [[ -d "$HOME/.tools/bin" ]]; then
            printf '%s\n' "$(_t '✅ The ~/.tools/bin directory has been created')"
            if [[ -f "$HOME/.tools/bin/process_manager" ]]; then
                printf '%s\n' "$(_t '✅ process_manager has been installed')"
            else
                printf '%s\n' "$(_t '❌ process_manager is not installed')"
            fi
        else
            printf '%s\n' "$(_t '❌ The ~/.tools/bin directory does not exist')"
        fi
    else
        printf '%s\n' "$(_t '❌ The ~/.tools directory does not exist')"
    fi
    
    echo ""
    printf '%s\n' "$(_t 'Environment variables:')"
    if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
        printf '%s\n' "$(_t '✅ PATH contains ~/.tools/bin')"
    else
        printf '%s\n' "$(_t '❌ PATH does not contain ~/.tools/bin')"
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
        info "$(_tf 'Run the installer: %s' "$installer_path")"
        bash "$installer_path"
    else
        error "$(_t 'The installer install_process_manager.sh was not found')"
        printf '%s\n' "$(_t 'Make sure this command is run in the project directory')"
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
        error "$(_t 'The process manager was not found')"
        echo ""
        printf '%s\n' "$(_t 'Possible solutions:')"
        echo "1. $(_tf 'Run the installer: %s --install' "$0")"
        echo "2. $(_t 'Manual installation: ./install_process_manager.sh')"
        echo "3. $(_t 'Make sure you run it in the project directory')"
        echo ""
        exit 1
    fi
}

# --- 脚本入口 ---
main "$@"
