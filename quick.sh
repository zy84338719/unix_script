#!/usr/bin/env bash
#
# 跨平台系统工具集合 - 快速启动脚本
# 用法: ./quick.sh [参数]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查主入口脚本是否存在
if [[ ! -f "$SCRIPT_DIR/main.sh" ]]; then
    echo "错误: 主入口脚本不存在: $SCRIPT_DIR/main.sh"
    exit 1
fi

# 使主入口脚本可执行
chmod +x "$SCRIPT_DIR/main.sh"

# 运行主入口脚本
cd "$SCRIPT_DIR" && bash main.sh "$@"
