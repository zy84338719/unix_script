#!/bin/bash

#
# check_dependencies.sh
#
# 检查进程管理工具的系统依赖和兼容性
#

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # 无颜色

# --- 日志函数 ---
info() { echo -e "${BLUE}[信息]${NC} $1"; }
success() { echo -e "${GREEN}[成功]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
header() { echo -e "${CYAN}${BOLD}$1${NC}"; }

# --- 检测操作系统 ---
detect_system() {
    case "$(uname -s)" in
        Darwin)
            OS="macOS"
            OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "未知")
            ;;
        Linux)
            OS="Linux"
            if [[ -f /etc/os-release ]]; then
                OS_VERSION=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
            else
                OS_VERSION="未知发行版"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS="Windows"
            OS_VERSION="$(uname -r)"
            ;;
        *)
            OS="其他"
            OS_VERSION="$(uname -r)"
            ;;
    esac
    
    echo "操作系统: $OS"
    echo "版本: $OS_VERSION"
    echo "内核: $(uname -r)"
    echo "架构: $(uname -m)"
}

# --- 检测Shell ---
detect_shell() {
    echo ""
    header "🐚 Shell 环境检测"
    echo "=================="
    
    echo "当前Shell: $SHELL"
    echo "Shell版本: $($SHELL --version 2>/dev/null | head -1 || echo '无法获取版本')"
    
    # 检测可用的Shell
    local shells=("bash" "zsh" "fish")
    echo ""
    echo "已安装的Shell:"
    for shell in "${shells[@]}"; do
        if command -v "$shell" >/dev/null 2>&1; then
            local version
            version=$("$shell" --version 2>/dev/null | head -1 || echo "版本未知")
            success "✅ $shell - $version"
        else
            warn "❌ $shell - 未安装"
        fi
    done
}

# --- 检测基本命令 ---
check_basic_commands() {
    echo ""
    header "🔧 基本命令检测"
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
        success "所有基本命令都可用"
        return 0
    else
        error "缺少以下命令: ${missing[*]}"
        return 1
    fi
}

# --- 检测网络工具 ---
check_network_tools() {
    echo ""
    header "🌐 网络工具检测"
    echo "=================="
    
    case "$OS" in
        macOS)
            if command -v lsof >/dev/null 2>&1; then
                success "✅ lsof (macOS网络端口检测)"
            else
                error "❌ lsof - macOS系统必需"
                return 1
            fi
            ;;
        Linux)
            local has_network_tool=false
            
            if command -v ss >/dev/null 2>&1; then
                success "✅ ss (现代网络统计工具)"
                has_network_tool=true
            else
                warn "❌ ss - 推荐安装"
            fi
            
            if command -v netstat >/dev/null 2>&1; then
                success "✅ netstat (传统网络统计工具)"
                has_network_tool=true
            else
                warn "❌ netstat - 备用工具"
            fi
            
            if command -v lsof >/dev/null 2>&1; then
                success "✅ lsof (文件和网络连接)"
                has_network_tool=true
            else
                warn "❌ lsof - 可选工具"
            fi
            
            if ! $has_network_tool; then
                error "至少需要安装 ss、netstat 或 lsof 中的一个"
                return 1
            fi
            ;;
        Windows)
            if command -v netstat >/dev/null 2>&1; then
                success "✅ netstat (Windows网络工具)"
            else
                error "❌ netstat - Windows系统必需"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# --- 检测权限 ---
check_permissions() {
    echo ""
    header "🔒 权限检测"
    echo "=================="
    
    # 检查是否能访问进程信息
    if ps aux >/dev/null 2>&1; then
        success "✅ 可以读取进程信息"
    else
        error "❌ 无法读取进程信息"
        return 1
    fi
    
    # 检查是否能发送信号
    if kill -0 $$ >/dev/null 2>&1; then
        success "✅ 可以发送进程信号"
    else
        error "❌ 无法发送进程信号"
        return 1
    fi
    
    # 检查用户目录权限
    if [[ -w "$HOME" ]]; then
        success "✅ 可以写入用户目录"
    else
        error "❌ 无法写入用户目录"
        return 1
    fi
    
    # 检查 ~/.tools 目录
    if [[ -d "$HOME/.tools" ]]; then
        if [[ -w "$HOME/.tools" ]]; then
            success "✅ ~/.tools 目录可写"
        else
            warn "⚠️  ~/.tools 目录存在但不可写"
        fi
    else
        info "ℹ️  ~/.tools 目录不存在（将在安装时创建）"
    fi
    
    return 0
}

# --- 检测环境变量 ---
check_environment() {
    echo ""
    header "🌍 环境变量检测"
    echo "=================="
    
    echo "PATH: $PATH"
    echo ""
    
    # 检查 ~/.tools/bin 是否在 PATH 中
    if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
        success "✅ ~/.tools/bin 已在 PATH 中"
    else
        info "ℹ️  ~/.tools/bin 不在 PATH 中（将在安装时添加）"
    fi
    
    # 检查 ~/.local/bin 是否在 PATH 中
    if echo "$PATH" | grep -q "$HOME/.local/bin"; then
        success "✅ ~/.local/bin 已在 PATH 中"
    else
        info "ℹ️  ~/.local/bin 不在 PATH 中"
    fi
    
    # 检查系统二进制目录
    if echo "$PATH" | grep -q "/usr/local/bin"; then
        success "✅ /usr/local/bin 已在 PATH 中"
    else
        warn "⚠️  /usr/local/bin 不在 PATH 中"
    fi
}

# --- 性能测试 ---
performance_test() {
    echo ""
    header "⚡ 性能测试"
    echo "=================="
    
    info "测试进程列表性能..."
    local start_time
    start_time=$(date +%s.%N)
    ps aux >/dev/null 2>&1
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "无法计算")
    
    if [[ "$duration" != "无法计算" ]]; then
        success "✅ ps aux 执行时间: ${duration}s"
    else
        info "ℹ️  无法测量 ps 命令性能"
    fi
    
    # 测试网络工具性能
    case "$OS" in
        macOS)
            if command -v lsof >/dev/null 2>&1; then
                info "测试端口扫描性能..."
                start_time=$(date +%s.%N 2>/dev/null || date +%s)
                lsof -i >/dev/null 2>&1
                end_time=$(date +%s.%N 2>/dev/null || date +%s)
                if [[ "$start_time" != "$end_time" ]]; then
                    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "无法计算")
                    success "✅ lsof -i 执行时间: ${duration}s"
                fi
            fi
            ;;
        Linux)
            if command -v ss >/dev/null 2>&1; then
                info "测试端口扫描性能..."
                start_time=$(date +%s.%N 2>/dev/null || date +%s)
                ss -tulnp >/dev/null 2>&1
                end_time=$(date +%s.%N 2>/dev/null || date +%s)
                if [[ "$start_time" != "$end_time" ]]; then
                    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "无法计算")
                    success "✅ ss -tulnp 执行时间: ${duration}s"
                fi
            fi
            ;;
    esac
}

# --- 生成安装建议 ---
generate_recommendations() {
    echo ""
    header "💡 安装建议"
    echo "=================="
    
    case "$OS" in
        macOS)
            echo "macOS 系统建议:"
            echo "• 确保已安装 Xcode Command Line Tools"
            echo "• 使用 Homebrew 安装额外工具(可选)"
            echo "• 建议使用 iTerm2 或 Terminal.app"
            ;;
        Linux)
            echo "Linux 系统建议:"
            echo "• Ubuntu/Debian: sudo apt-get install iproute2 net-tools lsof"
            echo "• CentOS/RHEL: sudo yum install iproute net-tools lsof"
            echo "• Arch Linux: sudo pacman -S iproute2 net-tools lsof"
            echo "• 建议使用现代终端模拟器"
            ;;
        Windows)
            echo "Windows 系统建议:"
            echo "• 使用 WSL2 或 Git Bash"
            echo "• 安装 Windows Terminal"
            echo "• 考虑使用 PowerShell Core"
            ;;
    esac
    
    echo ""
    echo "Shell 配置建议:"
    echo "• 使用 Zsh + Oh My Zsh (推荐)"
    echo "• 或使用 Fish shell"
    echo "• 配置合适的终端主题"
    echo ""
    
    echo "安装后配置:"
    echo "• 重新加载 shell 配置或重启终端"
    echo "• 测试 'pm' 命令是否可用"
    echo "• 查看文档: ~/.tools/docs/process_manager_README.md"
}

# --- 主函数 ---
main() {
    header "🔍 进程管理工具依赖检测"
    echo "=============================="
    echo ""
    
    # 系统信息
    header "💻 系统信息"
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
    header "📋 检测结果"
    echo "=================="
    
    if [[ $errors -eq 0 ]]; then
        success "🎉 所有依赖检测通过！"
        echo "您的系统兼容进程管理工具。"
        echo ""
        echo "下一步: 运行安装脚本"
        echo "  ./install_process_manager.sh"
    else
        error "❌ 发现 $errors 个问题"
        echo "请解决上述问题后再尝试安装。"
    fi
    
    # 生成建议
    generate_recommendations
    
    return $errors
}

# --- 脚本入口 ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
