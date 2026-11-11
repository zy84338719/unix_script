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

header "🔍 $(_tf 'Cross-language security scan (semgrep): %s' "$TARGET")"
echo

if ! command_exists semgrep; then
    error "$(_t 'semgrep is not installed')"
    info "$(_t 'Install: ./install.sh install-semgrep')"
    exit 1
fi

info "$(_t 'Running semgrep (automatic rule detection)...')"
if semgrep scan --config auto --quiet "$TARGET" 2>&1; then
    success "✅ $(_t 'semgrep scan passed')"
else
    error "$(_t 'semgrep found security issues')"
    exit 1
fi
