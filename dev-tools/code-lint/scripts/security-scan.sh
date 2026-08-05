#!/usr/bin/env bash
#
# code-lint/scripts/security-scan.sh
#
# 跨语言安全扫描（semgrep）。
# 用法: security-scan.sh [项目路径]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/common.sh
source "$SCRIPT_DIR/../../../lib/common.sh"

TARGET="${1:-.}"

header "🔍 跨语言安全扫描（semgrep）：$TARGET"
echo

if ! command_exists semgrep; then
    error "semgrep 未安装"
    info "安装：./install.sh install-semgrep"
    exit 1
fi

info "运行 semgrep（自动规则检测）..."
if semgrep scan --config auto --quiet "$TARGET" 2>&1; then
    success "✅ semgrep 扫描通过"
else
    error "semgrep 发现安全问题"
    exit 1
fi
