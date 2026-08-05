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

header "🔍 Java 代码分析：$TARGET"
echo

# 检查是否有 Java 源码
if ! find "$TARGET" -maxdepth 5 -name "*.java" -print -quit 2>/dev/null | grep -q .; then
    warn "未找到 Java 源文件，跳过 Java 分析"
    exit 0
fi

# spotbugs
if command_exists spotbugs; then
    info "运行 spotbugs（字节码分析）..."
    info "  提示：spotbugs 需要编译后的 .class 文件，请先运行 mvn compile 或 gradle build"
    # spotbugs 需要编译后的 class 文件，这里给出提示
    if find "$TARGET" -maxdepth 5 -name "*.class" -print -quit 2>/dev/null | grep -q .; then
        if spotbugs -textui -low "$TARGET" 2>&1; then
            success "  spotbugs：通过"
        else
            warn "  spotbugs：发现问题"
            ERRORS=$((ERRORS + 1))
        fi
    else
        warn "  ⚠️ 未找到 .class 文件，请先编译项目"
    fi
else
    warn "  ⚠️ spotbugs 未安装，跳过"
fi

echo

# pmd
if command_exists pmd; then
    info "运行 pmd（源码分析）..."
    if pmd check -d "$TARGET" -R rulesets/java/quickstart.xml -f text 2>&1; then
        success "  pmd：通过"
    else
        warn "  pmd：发现问题"
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "  ⚠️ pmd 未安装，跳过"
fi

echo

# checkstyle
if command_exists checkstyle; then
    info "运行 checkstyle（代码风格检查）..."
    # 查找 Java 源文件并运行 checkstyle
    java_files=$(find "$TARGET" -maxdepth 5 -name "*.java" 2>/dev/null | head -100)
    if [[ -n "$java_files" ]]; then
        if echo "$java_files" | xargs checkstyle -c /google_checks.xml 2>&1; then
            success "  checkstyle：通过"
        else
            warn "  checkstyle：发现风格问题"
            ERRORS=$((ERRORS + 1))
        fi
    fi
else
    warn "  ⚠️ checkstyle 未安装，跳过"
fi

echo
if [[ $ERRORS -gt 0 ]]; then
    error "Java 分析完成：$ERRORS 个工具报告了问题"
    exit 1
else
    success "✅ Java 分析全部通过"
fi
