#!/usr/bin/env bash
#
# 进程管理工具快速启动脚本
# 用法: ./pm.sh [参数]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检测操作系统
detect_os() {
    case "$(uname -s)" in
        "Darwin") echo "macos" ;;
        "Linux") echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

# 获取操作系统
OS_TYPE=$(detect_os)

if [[ "$OS_TYPE" == "unknown" ]]; then
    echo "错误: 不支持的操作系统"
    exit 1
fi

# 确定平台特定的脚本路径
PM_SCRIPT="${SCRIPT_DIR}/${OS_TYPE}/tools/process_manager.sh"

# 检查脚本是否存在
if [[ ! -f "$PM_SCRIPT" ]]; then
    echo "错误: 进程管理工具脚本不存在: $PM_SCRIPT"
    exit 1
fi

# 设置环境变量
export COMMON_DIR="${SCRIPT_DIR}/common"

# 检查是否已安装系统版本
if [[ -f "$HOME/.tools/bin/pm" ]] && command -v pm >/dev/null 2>&1; then
    # 如果已安装，使用系统安装版本
    pm "$@"
else
    # 否则使用开发版本
    source "${SCRIPT_DIR}/common/colors.sh"
    source "${SCRIPT_DIR}/common/utils.sh"
    bash "$PM_SCRIPT" "$@"
fi
