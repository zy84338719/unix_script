#!/bin/bash
#
# 进程管理工具快捷访问脚本
# 用法: ./pm_quick.sh [参数]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PM_TOOL_DIR="$SCRIPT_DIR/process_manager_tool"

# 检查进程管理工具目录是否存在
if [ ! -d "$PM_TOOL_DIR" ]; then
    echo "错误: 进程管理工具目录不存在: $PM_TOOL_DIR"
    exit 1
fi

# 智能选择运行方式
if [ -f "$HOME/.tools/bin/pm" ] && command -v pm >/dev/null 2>&1; then
    # 如果已安装，使用系统安装版本
    pm "$@"
else
    # 否则使用开发版本
    cd "$PM_TOOL_DIR" && bash pm_wrapper.sh "$@"
fi
