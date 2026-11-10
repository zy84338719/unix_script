#!/usr/bin/env bash
#
# 状态输出的结构判据。
#
# 为什么不做逐字基线：--status-json 与各模块 status 的内容依赖**本机实际安装状态**，
# 同一份代码在两台机器上必然不同。逐字基线会变成永远的红。
# 能固定的是**形状**：每行 key:value、状态码在有限集里。
#
# 状态码有限集 = 契约里的 7 个 + unknown
# （unknown 是框架在「模块没报出状态」时的兜底值，不是契约状态码）。
#
# 退出码：0 通过；1 不通过
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
VALID_STATES="not_installed installed installed:running installed:stopped configured not_configured n/a unknown"

cd "$ROOT"
OUT="$(./install.sh --status-json 2>/dev/null)" || {
    printf 'check_status_shape: --status-json 执行失败\n' >&2
    exit 1
}

bad=0

# 前 3 行是框架元数据（os / arch / version），键名固定
i=0
for __k in os arch version; do
    i=$((i + 1))
    __head="$(printf '%s\n' "$OUT" | sed -n "${i}p")"
    case "$__head" in
        "$__k":*) ;;
        *)
            printf 'check_status_shape: 第 %s 行应为 %s: 开头，实际：%s\n' "$i" "$__k" "$__head" >&2
            bad=1
            ;;
    esac
done

# 其余是模块行：key:state[:version]
BODY="$(printf '%s\n' "$OUT" | sed -n '4,$p')"
while IFS= read -r __line; do
    [ -n "$__line" ] || continue
    case "$__line" in
        *:*) ;;
        *)
            printf 'check_status_shape: 不是 key:value 形态：%s\n' "$__line" >&2
            bad=1
            continue
            ;;
    esac
    __key="${__line%%:*}"
    __rest="${__line#*:}"
    __val="${__rest%%:*}"
    case " $VALID_STATES " in
        *" $__val "*) ;;
        *)
            printf 'check_status_shape: %s 的状态码不在有限集里：%s\n' "$__key" "$__val" >&2
            bad=1
            ;;
    esac
done <<< "$BODY"

if [ "$bad" -ne 0 ]; then
    printf 'check_status_shape: 状态输出形状不对\n' >&2
    exit 1
fi
printf 'check_status_shape: ok\n'
exit 0
