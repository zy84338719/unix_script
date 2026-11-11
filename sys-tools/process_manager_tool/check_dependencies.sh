#!/bin/bash

#
# check_dependencies.sh
#
# 检查进程管理工具的系统依赖和兼容性
#

# --- unix_script 公共库（提供 _t 翻译）---
# 本脚本在仓库内直接运行（不会被复制到用户环境），所以直接 source 拿 _t。
# 颜色与日志函数在下面对齐定义，会覆盖 common.sh 里的同名定义。
_UXS_CD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$_UXS_CD_DIR/../../lib/common.sh"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
# 无颜色
NC='\033[0m'

# --- 日志函数 ---
info() { echo -e "${BLUE}[$(_t 'Info]')${NC} $1"; }
success() { echo -e "${GREEN}[$(_t 'Success]')${NC} $1"; }
error() { echo -e "${RED}[$(_t 'Error]')${NC} $1"; }
warn() { echo -e "${YELLOW}[$(_t 'Warning]')${NC} $1"; }
header() { echo -e "${CYAN}${BOLD}$1${NC}"; }

# --- 检测操作系统 ---
detect_system() {
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            OS_VERSION=$(sw_vers -productVersion 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
            ;;
        Linux)
            OS="Linux"
            if [[ -f /etc/os-release ]]; then
                OS_VERSION=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
            else
                OS_VERSION="$(_t 'Unknown distribution')"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS="Windows"
            OS_VERSION="$(uname -r)"
            ;;
        *)
            OS="$(_t 'Other')"
            OS_VERSION="$(uname -r)"
            ;;
    esac
    
    printf '%s\n' "$(_tf 'Operating system: %s' "$OS")"
    printf '%s\n' "$(_tf 'Version: %s' "$OS_VERSION")"
    printf '%s\n' "$(_t 'Kernel'): $(uname -r)"
    printf '%s\n' "$(_t 'Architecture'): $(uname -m)"
}

# --- 检测Shell ---
detect_shell() {
    echo ""
    header "$(_t '🐚 Shell environment detection')"
    echo "=================="
    
    printf '%s\n' "$(_tf 'Current shell: %s' "$SHELL")"
    local shell_ver
    shell_ver=$($SHELL --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Cannot get the version')")
    printf '%s\n' "$(_tf 'Shell version: %s' "$shell_ver")"
    
    # 检测可用的Shell
    local shells=("bash" "zsh" "fish")
    echo ""
    printf '%s\n' "$(_t 'Installed shells:')"
    for shell in "${shells[@]}"; do
        if command -v "$shell" >/dev/null 2>&1; then
            local version
            version=$("$shell" --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Version unknown')")
            success "✅ $shell - $version"
        else
            warn "$(_tf '❌ %s - not installed' "$shell")"
        fi
    done
}

# --- 检测基本命令 ---
check_basic_commands() {
    echo ""
    header "$(_t '🔧 Basic command detection')"
    echo "=================="
    
    local commands=("ps" "grep" "awk" "sed" "head" "tail" "cut" "sort" "uniq")
    local missing=()
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            success "✅ $cmd"
        else
            error "❌ $cmd"
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        success "$(_t 'All the basic commands are available')"
        return 0
    else
        error "$(_tf 'The following commands are missing: %s' "${missing[*]}")"
        return 1
    fi
}

# --- 检测网络工具 ---
check_network_tools() {
    echo ""
    header "$(_t '🌐 Network tool detection')"
    echo "=================="
    
    case "$OS" in
        macOS)
            if command -v lsof >/dev/null 2>&1; then
                success "$(_t '✅ lsof (macOS network port detection)')"
            else
                error "$(_t '❌ lsof - required on macOS')"
                return 1
            fi
            ;;
        Linux)
            local has_network_tool=false
            
            if command -v ss >/dev/null 2>&1; then
                success "$(_t '✅ ss (modern network statistics tool)')"
                has_network_tool=true
            else
                warn "$(_t '❌ ss - recommended')"
            fi
            
            if command -v netstat >/dev/null 2>&1; then
                success "$(_t '✅ netstat (traditional network statistics tool)')"
                has_network_tool=true
            else
                warn "$(_t '❌ netstat - fallback tool')"
            fi
            
            if command -v lsof >/dev/null 2>&1; then
                success "$(_t '✅ lsof (files and network connections)')"
                has_network_tool=true
            else
                warn "$(_t '❌ lsof - optional tool')"
            fi
            
            if ! $has_network_tool; then
                error "$(_t 'At least one of ss, netstat or lsof must be installed')"
                return 1
            fi
            ;;
        Windows)
            if command -v netstat >/dev/null 2>&1; then
                success "$(_t '✅ netstat (Windows network tool)')"
            else
                error "$(_t '❌ netstat - required on Windows')"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# --- 检测权限 ---
check_permissions() {
    echo ""
    header "$(_t '🔒 Permission detection')"
    echo "=================="
    
    # 检查是否能访问进程信息
    if ps aux >/dev/null 2>&1; then
        success "$(_t '✅ The process information can be read')"
    else
        error "$(_t '❌ The process information cannot be read')"
        return 1
    fi
    
    # 检查是否能发送信号
    if kill -0 $$ >/dev/null 2>&1; then
        success "$(_t '✅ The process signals can be sent')"
    else
        error "$(_t '❌ The process signals cannot be sent')"
        return 1
    fi
    
    # 检查用户目录权限
    if [[ -w "$HOME" ]]; then
        success "$(_t '✅ The user directory can be written')"
    else
        error "$(_t '❌ The user directory cannot be written')"
        return 1
    fi
    
    # 检查 ~/.tools 目录
    if [[ -d "$HOME/.tools" ]]; then
        if [[ -w "$HOME/.tools" ]]; then
            success "$(_t '✅ The ~/.tools directory is writable')"
        else
            warn "$(_t '⚠️  The ~/.tools directory exists but is not writable')"
        fi
    else
        info "$(_t 'ℹ️  The ~/.tools directory does not exist (it will be created at install time)')"
    fi
    
    return 0
}

# --- 检测环境变量 ---
check_environment() {
    echo ""
    header "$(_t '🌍 Environment variable detection')"
    echo "=================="
    
    echo "PATH: $PATH"
    echo ""
    
    # 检查 ~/.tools/bin 是否在 PATH 中
    if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
        success "$(_t '✅ ~/.tools/bin is already in PATH')"
    else
        info "$(_t 'ℹ️  ~/.tools/bin is not in PATH (it will be added at install time)')"
    fi
    
    # 检查 ~/.local/bin 是否在 PATH 中
    if echo "$PATH" | grep -q "$HOME/.local/bin"; then
        success "$(_t '✅ ~/.local/bin is already in PATH')"
    else
        info "$(_t 'ℹ️  ~/.local/bin is not in PATH')"
    fi
    
    # 检查系统二进制目录
    if echo "$PATH" | grep -q "/usr/local/bin"; then
        success "$(_t '✅ /usr/local/bin is already in PATH')"
    else
        warn "$(_t '⚠️  /usr/local/bin is not in PATH')"
    fi
}

# --- 性能测试 ---
performance_test() {
    echo ""
    header "$(_t '⚡ Performance test')"
    echo "=================="
    
    info "$(_t 'Testing the process list performance...')"
    local start_time
    start_time=$(date +%s.%N)
    ps aux >/dev/null 2>&1
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || printf '%s\n' "$(_t 'Cannot compute')")
    
    if [[ "$duration" != "$(_t 'Cannot compute')" ]]; then
        success "$(_tf '✅ ps aux execution time: %ss' "${duration}")"
    else
        info "$(_t 'ℹ️  The performance of the ps command cannot be measured')"
    fi
    
    # 测试网络工具性能
    case "$OS" in
        macOS)
            if command -v lsof >/dev/null 2>&1; then
                info "$(_t 'Testing the port scan performance...')"
                start_time=$(date +%s.%N 2>/dev/null || date +%s)
                lsof -i >/dev/null 2>&1
                end_time=$(date +%s.%N 2>/dev/null || date +%s)
                if [[ "$start_time" != "$end_time" ]]; then
                    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || printf '%s\n' "$(_t 'Cannot compute')")
                    success "$(_tf '✅ lsof -i execution time: %ss' "${duration}")"
                fi
            fi
            ;;
        Linux)
            if command -v ss >/dev/null 2>&1; then
                info "$(_t 'Testing the port scan performance...')"
                start_time=$(date +%s.%N 2>/dev/null || date +%s)
                ss -tulnp >/dev/null 2>&1
                end_time=$(date +%s.%N 2>/dev/null || date +%s)
                if [[ "$start_time" != "$end_time" ]]; then
                    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || printf '%s\n' "$(_t 'Cannot compute')")
                    success "$(_tf '✅ ss -tulnp execution time: %ss' "${duration}")"
                fi
            fi
            ;;
    esac
}

# --- 生成安装建议 ---
generate_recommendations() {
    echo ""
    header "$(_t '💡 Installation suggestions')"
    echo "=================="
    
    case "$OS" in
        macOS)
            echo "macOS $(_t 'System suggestions:')"
            printf '%s\n' "$(_t '• Make sure the Xcode Command Line Tools are installed')"
            printf '%s\n' "$(_t '• Use Homebrew to install the extra tools (optional)')"
            printf '%s\n' "$(_t '• iTerm2 or Terminal.app is recommended')"
            ;;
        Linux)
            echo "Linux $(_t 'System suggestions:')"
            echo "• Ubuntu/Debian: sudo apt-get install iproute2 net-tools lsof"
            echo "• CentOS/RHEL: sudo yum install iproute net-tools lsof"
            echo "• Arch Linux: sudo pacman -S iproute2 net-tools lsof"
            printf '%s\n' "$(_t '• A modern terminal emulator is recommended')"
            ;;
        Windows)
            echo "Windows $(_t 'System suggestions:')"
            printf '%s\n' "$(_t '• Use WSL2 or Git Bash')"
            printf '%s\n' "$(_t '• Install Windows Terminal')"
            printf '%s\n' "$(_t '• Consider using PowerShell Core')"
            ;;
    esac
    
    echo ""
    echo "Shell $(_t 'Configuration suggestions:')"
    printf '%s\n' "$(_t '• Use Zsh + Oh My Zsh (recommended)')"
    printf '%s\n' "$(_t '• Or use the Fish shell')"
    printf '%s\n' "$(_t '• Configure a suitable terminal theme')"
    echo ""
    
    printf '%s\n' "$(_t 'Configuration after the installation:')"
    printf '%s\n' "$(_t '• Reload the shell configuration or restart the terminal')"
    printf '%s\n' "$(_t '• Test whether the pm command works')"
    printf '%s\n' "$(_t '• See the documentation: ~/.tools/docs/process_manager_README.md')"
}

# --- 主函数 ---
main() {
    header "$(_t '🔍 Process manager dependency detection')"
    echo "=============================="
    echo ""
    
    # 系统信息
    header "$(_t '💻 System information')"
    echo "=================="
    detect_system
    
    # 各项检测
    local errors=0
    
    detect_shell
    
    if ! check_basic_commands; then
        ((errors++))
    fi
    
    if ! check_network_tools; then
        ((errors++))
    fi
    
    if ! check_permissions; then
        ((errors++))
    fi
    
    check_environment
    
    # 性能测试（可选）
    if [[ "$1" == "--performance" || "$1" == "-p" ]]; then
        performance_test
    fi
    
    # 结果总结
    echo ""
    header "$(_t '📋 Detection results')"
    echo "=================="
    
    if [[ $errors -eq 0 ]]; then
        success "$(_t '🎉 All the dependency checks passed!')"
        printf '%s\n' "$(_t 'Your system is compatible with the process manager.')"
        echo ""
        printf '%s\n' "$(_t 'Next step: run the installation script')"
        echo "  ./install_process_manager.sh"
    else
        error "$(_tf '❌ %s problem(s) found' "$errors")"
        printf '%s\n' "$(_t 'Please fix the problems above and try installing again.')"
    fi
    
    # 生成建议
    generate_recommendations
    
    return "$errors"
}

# --- 脚本入口 ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
