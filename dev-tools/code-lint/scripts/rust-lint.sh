#!/usr/bin/env bash
#
# code-lint/scripts/rust-lint.sh
#
# 运行 Rust 代码分析（cargo clippy + cargo-audit）。
# 用法: rust-lint.sh [项目路径]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/common.sh
source "$SCRIPT_DIR/../../../lib/common.sh"

TARGET="${1:-.}"
ERRORS=0

header "🔍 $(_tf 'Rust code analysis: %s' "$TARGET")"
echo

# 检查是否是 Cargo 项目
if [[ ! -f "$TARGET/Cargo.toml" ]]; then
    warn "$(_t 'Cargo.toml not found, skipping Rust analysis')"
    exit 0
fi

# cargo clippy
if os_has_cmd cargo; then
    info "$(_t 'Running cargo clippy...')"
    if (cd "$TARGET" && cargo clippy -- -D warnings 2>&1); then
        success "  $(_t 'clippy: passed')"
    else
        warn "  $(_t 'clippy: problems found')"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ $(_t 'cargo not installed, skipping')"
fi

echo

# cargo-audit
if os_has_cmd cargo-audit; then
    info "$(_t 'Running cargo-audit (dependency vulnerability scan)...')"
    if (cd "$TARGET" && cargo audit 2>&1); then
        success "  $(_t 'cargo-audit: passed')"
    else
        warn "  $(_t 'cargo-audit: vulnerabilities found')"
        ERRORS=$((ERRORS + 1))
    fi
elif os_has_cmd cargo; then
    warn "  ⚠️ $(_t 'cargo-audit not installed, skipping (run ./install.sh install-rust)')"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "$(_tf 'Rust analysis complete: %s tools reported problems' "$ERRORS")"
    exit 1
else
    success "✅ $(_t 'Rust analysis all passed')"
fi
