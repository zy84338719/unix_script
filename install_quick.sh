#!/bin/bash
# 快速访问主安装菜单
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" && bash install.sh "$@"
