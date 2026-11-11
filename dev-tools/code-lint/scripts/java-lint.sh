#!/usr/bin/env bash
#
# code-lint/scripts/java-lint.sh
#
# 运行 Java 代码分析（spotbugs + pmd + checkstyle）。
# 用法: java-lint.sh [项目路径]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/common.sh
source "$SCRIPT_DIR/../../../lib/common.sh"

TARGET="${1:-.}"
ERRORS=0

header "🔍 $(_tf 'Java code analysis: %s' "$TARGET")"
echo

# 检查是否有 Java 源码
if ! find "$TARGET" -maxdepth 5 -name "*.java" -print -quit 2>/dev/null | grep -q .; then
    warn "$(_t 'No Java source files found, skipping Java analysis')"
    exit 0
fi

# spotbugs
if command_exists spotbugs; then
    info "$(_t 'Running spotbugs (bytecode analysis)...')"
    info "  $(_t 'Tip: spotbugs needs .class files, run mvn compile or gradle build first')"
    # spotbugs 需要编译后的 class 文件，这里给出提示
    if find "$TARGET" -maxdepth 5 -name "*.class" -print -quit 2>/dev/null | grep -q .; then
        if spotbugs -textui -low "$TARGET" 2>&1; then
            success "  $(_t 'spotbugs: passed')"
        else
            warn "  $(_t 'spotbugs: problems found')"
            ERRORS=$((ERRORS + 1))
        fi
    else
        warn "  ⚠️ $(_t 'No .class files found, compile the project first')"
    fi
else
    warn "  ⚠️ $(_t 'spotbugs not installed, skipping')"
fi

echo

# pmd
if command_exists pmd; then
    info "$(_t 'Running pmd (source analysis)...')"
    if pmd check -d "$TARGET" -R rulesets/java/quickstart.xml -f text 2>&1; then
        success "  $(_t 'pmd: passed')"
    else
        warn "  $(_t 'pmd: problems found')"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ $(_t 'pmd not installed, skipping')"
fi

echo

# checkstyle
if command_exists checkstyle; then
    info "$(_t 'Running checkstyle (code style check)...')"
    # 查找 Java 源文件并运行 checkstyle
    java_files=$(find "$TARGET" -maxdepth 5 -name "*.java" 2>/dev/null | head -100)
    if [[ -n "$java_files" ]]; then
        if echo "$java_files" | xargs checkstyle -c /google_checks.xml 2>&1; then
            success "  $(_t 'checkstyle: passed')"
        else
            warn "  $(_t 'checkstyle: style issues found')"
            ERRORS=$((ERRORS + 1))
        fi
    fi
else
    warn "  ⚠️ $(_t 'checkstyle not installed, skipping')"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "$(_tf 'Java analysis complete: %s tools reported problems' "$ERRORS")"
    exit 1
else
    success "✅ $(_t 'Java analysis all passed')"
fi
