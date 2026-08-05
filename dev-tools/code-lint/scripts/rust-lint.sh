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

header "🔍 Rust 代码分析：$TARGET"
echo

# 检查是否是 Cargo 项目
if [[ ! -f "$TARGET/Cargo.toml" ]]; then
    warn "未找到 Cargo.toml，跳过 Rust 分析"
    exit 0
fi

# cargo clippy
if command_exists cargo; then
    info "运行 cargo clippy..."
    if (cd "$TARGET" && cargo clippy -- -D warnings 2>&1); then
        success "  clippy：通过"
    else
        warn "  clippy：发现问题"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ cargo 未安装，跳过"
fi

echo

# cargo-audit
if command_exists cargo-audit; then
    info "运行 cargo-audit（依赖漏洞扫描）..."
    if (cd "$TARGET" && cargo audit 2>&1); then
        success "  cargo-audit：通过"
    else
        warn "  cargo-audit：发现漏洞"
        ERRORS=$((ERRORS + 1))
    fi
elif command_exists cargo; then
    warn "  ⚠️ cargo-audit 未安装，跳过（运行 ./install.sh install-rust 安装）"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "Rust 分析完成：$ERRORS 个工具报告了问题"
    exit 1
else
    success "✅ Rust 分析全部通过"
fi
