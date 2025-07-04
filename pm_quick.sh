#!/bin/bash
# 快速访问进程管理工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/process_manager_tool" && bash pm_wrapper.sh "$@"
