#!/usr/bin/env bash
#
# code-lint/scripts/py-lint.sh
#
# 运行 Python 代码分析（ruff + mypy + bandit）。
# 用法: py-lint.sh [项目路径]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/common.sh
source "$SCRIPT_DIR/../../../lib/common.sh"

TARGET="${1:-.}"
ERRORS=0

header "🔍 Python 代码分析：$TARGET"
echo

# 检查是否有 Python 源码
if ! find "$TARGET" -maxdepth 5 -name "*.py" -print -quit 2>/dev/null | grep -q .; then
    warn "未找到 Python 源文件，跳过 Python 分析"
    exit 0
fi

# ruff（linter + formatter check）
if command_exists ruff; then
    info "运行 ruff check..."
    if ruff check "$TARGET" 2>&1; then
        success "  ruff check：通过"
    else
        warn "  ruff check：发现问题"
        ERRORS=$((ERRORS + 1))
    fi

    echo
    info "运行 ruff format --check..."
    if ruff format --check "$TARGET" 2>&1; then
        success "  ruff format：通过"
    else
        warn "  ruff format：格式不一致（运行 ruff format 修复）"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ ruff 未安装，跳过"
fi

echo

# mypy（类型检查）
if command_exists mypy; then
    info "运行 mypy（类型检查）..."
    if mypy "$TARGET" --ignore-missing-imports 2>&1; then
        success "  mypy：通过"
    else
        warn "  mypy：发现类型问题"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ mypy 未安装，跳过"
fi

echo

# bandit（安全扫描）
if command_exists bandit; then
    info "运行 bandit（安全扫描）..."
    if bandit -r "$TARGET" -q 2>&1; then
        success "  bandit：通过"
    else
        warn "  bandit：发现安全问题"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ bandit 未安装，跳过"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "Python 分析完成：$ERRORS 个工具报告了问题"
    exit 1
else
    success "✅ Python 分析全部通过"
fi
