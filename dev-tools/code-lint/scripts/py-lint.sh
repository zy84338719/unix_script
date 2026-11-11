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

header "🔍 $(_tf 'Python code analysis: %s' "$TARGET")"
echo

# 检查是否有 Python 源码
if ! find "$TARGET" -maxdepth 5 -name "*.py" -print -quit 2>/dev/null | grep -q .; then
    warn "$(_t 'No Python source files found, skipping Python analysis')"
    exit 0
fi

# ruff（linter + formatter check）
if os_has_cmd ruff; then
    info "$(_t 'Running ruff check...')"
    if ruff check "$TARGET" 2>&1; then
        success "  $(_t 'ruff check: passed')"
    else
        warn "  $(_t 'ruff check: problems found')"
        ERRORS=$((ERRORS + 1))
    fi

    echo
    info "$(_t 'Running ruff format --check...')"
    if ruff format --check "$TARGET" 2>&1; then
        success "  $(_t 'ruff format: passed')"
    else
        warn "  $(_t 'ruff format: format mismatch (run ruff format to fix)')"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ $(_t 'ruff not installed, skipping')"
fi

echo

# mypy（类型检查）
if os_has_cmd mypy; then
    info "$(_t 'Running mypy (type check)...')"
    if mypy "$TARGET" --ignore-missing-imports 2>&1; then
        success "  $(_t 'mypy: passed')"
    else
        warn "  $(_t 'mypy: type issues found')"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ $(_t 'mypy not installed, skipping')"
fi

echo

# bandit（安全扫描）
if os_has_cmd bandit; then
    info "$(_t 'Running bandit (security scan)...')"
    if bandit -r "$TARGET" -q 2>&1; then
        success "  $(_t 'bandit: passed')"
    else
        warn "  $(_t 'bandit: security issues found')"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ $(_t 'bandit not installed, skipping')"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "$(_tf 'Python analysis complete: %s tools reported problems' "$ERRORS")"
    exit 1
else
    success "✅ $(_t 'Python analysis all passed')"
fi
