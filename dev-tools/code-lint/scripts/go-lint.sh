#!/usr/bin/env bash
#
# code-lint/scripts/go-lint.sh
#
# 运行 Go 代码分析（golangci-lint + gosec）。
# 用法: go-lint.sh [项目路径]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/common.sh
source "$SCRIPT_DIR/../../../lib/common.sh"

TARGET="${1:-.}"
ERRORS=0
WARNINGS=0

header "🔍 $(_tf 'Go code analysis: %s' "$TARGET")"
echo

# golangci-lint
if os_has_cmd golangci-lint; then
    info "$(_t 'Running golangci-lint...')"
    if golangci-lint run "$TARGET/..." 2>&1; then
        success "  $(_t 'golangci-lint: passed')"
    else
        warn "  $(_t 'golangci-lint: problems found')"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ $(_t 'golangci-lint not installed, skipping')"
fi

echo

# gosec
if os_has_cmd gosec; then
    info "$(_t 'Running gosec (security scan)...')"
    if gosec "$TARGET/..." 2>&1; then
        success "  $(_t 'gosec: passed')"
    else
        warn "  $(_t 'gosec: security issues found')"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ $(_t 'gosec not installed, skipping')"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "$(_tf 'Go analysis complete: %s tools reported problems' "$ERRORS")"
    exit 1
else
    success "✅ $(_t 'Go analysis all passed')"
fi
