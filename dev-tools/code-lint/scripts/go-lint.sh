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

header "🔍 Go 代码分析：$TARGET"
echo

# golangci-lint
if command_exists golangci-lint; then
    info "运行 golangci-lint..."
    if golangci-lint run "$TARGET/..." 2>&1; then
        success "  golangci-lint：通过"
    else
        warn "  golangci-lint：发现问题"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ golangci-lint 未安装，跳过"
fi

echo

# gosec
if command_exists gosec; then
    info "运行 gosec（安全扫描）..."
    if gosec "$TARGET/..." 2>&1; then
        success "  gosec：通过"
    else
        warn "  gosec：发现安全问题"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ gosec 未安装，跳过"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "Go 分析完成：$ERRORS 个工具报告了问题"
    exit 1
else
    success "✅ Go 分析全部通过"
fi
