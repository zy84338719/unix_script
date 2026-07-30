#!/usr/bin/env bash
#
# check_issues.sh
#
# 本地脚本质量检查工具。
#   - 优先使用系统 shellcheck 对所有 .sh 做静态检查（与 CI 一致，排除 SC2164）。
#   - 同时对所有 .sh 运行 bash -n 语法检查。
#   - 若未安装 shellcheck，回退到 grep 启发式检查，并提示安装方法。
#
# 用法:
#   ./check_issues.sh              # 检查全部
#   ./check_issues.sh <文件...>    # 仅检查指定文件
#   ./check_issues.sh --strict     # 不排除 SC2164（更严格）
#   ./check_issues.sh -h|--help
#
# 退出码：发现任何问题返回 1，全部通过返回 0。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 收集待检查的脚本
collect_scripts() {
    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$@"
    else
        find "$SCRIPT_DIR" -type f -name "*.sh" \
             -not -path "*/node_modules/*" \
             -not -path "*/.git/*" \
             -not -path "*/.tools/*" \
             | sort
    fi
}

show_help() {
    sed -n '2,18p' "$0"
}

main() {
    local args=()
    local strict=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit 0 ;;
            --strict)  strict=true; shift ;;
            *)         args+=("$1"); shift ;;
        esac
    done

    local scripts
    if [[ ${#args[@]} -gt 0 ]]; then
        scripts=$(collect_scripts "${args[@]}")
    else
        scripts=$(collect_scripts)
    fi
    if [[ -z "$scripts" ]]; then
        echo "未找到任何 .sh 脚本。"
        exit 0
    fi

    local total=0 fail=0
    echo "========================================"
    echo "本地脚本质量检查"
    echo "========================================"

    # ---- 1. bash -n 语法检查 ----
    echo
    echo "[1/2] 语法检查 (bash -n)"
    echo "----------------------------------------"
    while IFS= read -r f; do
        total=$((total + 1))
        if bash -n "$f" 2>/dev/null; then
            printf "  ✓  %s\n" "$f"
        else
            printf "  ✗  %s\n" "$f"
            bash -n "$f" || true
            fail=$((fail + 1))
        fi
    done <<< "$scripts"

    # ---- 2. shellcheck（若可用） ----
    echo
    if command -v shellcheck >/dev/null 2>&1; then
        echo "[2/2] ShellCheck 静态检查"
        echo "----------------------------------------"
        local sc_args=(-x)
        [[ "$strict" == false ]] && sc_args+=(-e SC2164)
        local sc_failed=0
        while IFS= read -r f; do
            if shellcheck "${sc_args[@]}" "$f" >/tmp/sc_out.$$ 2>&1; then
                printf "  ✓  %s\n" "$f"
            else
                printf "  ✗  %s\n" "$f"
                sed 's/^/      /' /tmp/sc_out.$$
                sc_failed=$((sc_failed + 1))
            fi
        done <<< "$scripts"
        rm -f /tmp/sc_out.$$
        if [[ $sc_failed -gt 0 ]]; then fail=$((fail + sc_failed)); fi
    else
        echo "[2/2] ShellCheck 静态检查（未安装，使用 grep 启发式回退）"
        echo "----------------------------------------"
        warn_note "建议安装 shellcheck 以获得更准确的检查："
        echo "      macOS:  brew install shellcheck"
        echo "      Debian: sudo apt-get install shellcheck"
        echo "      或:     https://github.com/koalaman/shellcheck#installing"
        heuristic_check "$scripts"
    fi

    echo
    echo "========================================"
    if [[ $fail -eq 0 ]]; then
        echo "✅ 全部通过（共 $total 个脚本）"
        exit 0
    else
        echo "❌ 发现问题（$fail 项，共 $total 个脚本）"
        exit 1
    fi
}

warn_note() { echo "[!] $1"; }

# grep 启发式回退检查（shellcheck 缺失时）
heuristic_check() {
    local scripts="$1"
    local found=0
    while IFS= read -r f; do
        local hits=""
        # SC2155: local 与 $(...) 同行声明（单引号字面匹配 \$，SC2016 误报）
        # shellcheck disable=SC2016
        if grep -Hn 'local.*=\$(' "$f" >/dev/null 2>&1; then
            hits+=$'\n      SC2155(疑似): local 与命令替换同行'
        fi
        # SC2086: sudo $VAR 未加引号
        if grep -Hn 'sudo \$[A-Z_]*' "$f" >/dev/null 2>&1; then
            hits+=$'\n      SC2086(疑似): sudo 后变量未加引号'
        fi
        if [[ -n "$hits" ]]; then
            printf "  ~  %s%s\n" "$f" "$hits"
            found=$((found + 1))
        fi
    done <<< "$scripts"
    return $found
}

main "$@"
