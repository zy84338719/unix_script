#!/bin/bash

# 简单的 ShellCheck 替代脚本，用于检查常见问题

echo "检查常见的 Shell 脚本问题..."

# 检查 SC2155: 变量声明和赋值应该分开
echo "检查 SC2155 (变量声明和赋值分离):"
find . -name "*.sh" -exec grep -Hn "local.*=\$(" {} \; | head -5

echo ""

# 检查 SC2162: read 缺少 -r
echo "检查 SC2162 (read 缺少 -r):"
find . -name "*.sh" -exec grep -Hn "read -p" {} \; | head -5

echo ""

# 检查 SC2086: 变量需要引号
echo "检查 SC2086 (变量缺少引号):"
find . -name "*.sh" -exec grep -Hn "sudo \$[A-Z_]*" {} \; | head -5

echo ""

echo "检查完成！"
