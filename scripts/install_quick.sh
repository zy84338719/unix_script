#!/bin/bash
#
# 主安装菜单快捷访问脚本
# 用法: ./install_quick.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查主安装脚本是否存在
if [ ! -f "$SCRIPT_DIR/install.sh" ]; then
    echo "错误: 主安装脚本不存在: $SCRIPT_DIR/install.sh"
    exit 1
fi

# 运行主安装脚本
cd "$SCRIPT_DIR" && bash install.sh "$@"
