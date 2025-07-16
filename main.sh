#!/usr/bin/env bash
#
# 跨平台系统工具集合 - 统一入口
# 自动检测操作系统并加载对应的功能模块
#

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 导入通用工具
source "${SCRIPT_DIR}/common/utils.sh"
source "${SCRIPT_DIR}/common/colors.sh"

# 检测操作系统
detect_os() {
    local os_name=$(uname -s)
    case "$os_name" in
        "Darwin")
            echo "macos"
            ;;
        "Linux")
            echo "linux"
            ;;
        *)
            print_error "不支持的操作系统：$os_name"
            exit 1
            ;;
    esac
}

# 检测架构
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "armv7"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# 显示系统信息
show_system_info() {
    local os_type="$1"
    local arch_type="$2"
    
    print_header "🖥️  系统信息"
    echo "───────────────────────────────"
    echo "操作系统: $([ "$os_type" = "macos" ] && echo "macOS" || echo "Linux")"
    echo "CPU架构:  $arch_type"
    echo "───────────────────────────────"
    echo
}

# 主函数
main() {
    local os_type=$(detect_os)
    local arch_type=$(detect_arch)
    local platform_dir="${SCRIPT_DIR}/${os_type}"
    
    # 检查平台目录是否存在
    if [[ ! -d "$platform_dir" ]]; then
        print_error "平台目录不存在：$platform_dir"
        exit 1
    fi
    
    # 检查平台入口脚本是否存在
    local platform_script="${platform_dir}/main.sh"
    if [[ ! -f "$platform_script" ]]; then
        print_error "平台入口脚本不存在：$platform_script"
        exit 1
    fi
    
    # 清屏并显示欢迎信息
    clear
    print_header "🚀 跨平台系统工具集合"
    echo "========================================"
    show_system_info "$os_type" "$arch_type"
    
    # 导入并执行对应平台的脚本
    export SYSTEM_OS="$os_type"
    export SYSTEM_ARCH="$arch_type"
    export COMMON_DIR="${SCRIPT_DIR}/common"
    
    source "$platform_script" "$@"
}

# 执行主函数
main "$@"
