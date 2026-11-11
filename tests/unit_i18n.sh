#!/usr/bin/env bash
#
# tests/unit_i18n.sh — i18n 单测
#
# 校验 _t 能查到译文（纯 bash 兜底表，不依赖 gettext）。
# 独立运行：bash tests/unit_i18n.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
#
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
uxs_i18n_init "$REPO_DIR"

PASS=0
FAIL=0

t_translate() { # t_translate <msgid> <期望译文>
    local out
    out="$(_t "$1")"
    if [ "$out" = "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1 → 期望 '$2' 实际 '$out'"
    fi
}

# docker 试点的关键 msgid
t_translate "Detected installed Docker" "检测到已安装 Docker"
t_translate "Install failed" "安装失败"
t_translate "Cancelled" "已取消"

# 1panel 的关键 msgid
t_translate "1Panel is Linux-only. Current: " "1Panel 仅支持 Linux。当前："
t_translate "Party popper 1Panel installation complete!" "🎉 1Panel 安装完成！"

# ---------------------------------------------------------------------------
# 占位符一致性：译文的 %s 数量必须与原文一致。
#
# 错配的两种后果都很难查：
#   译文多一个 %s → printf 报「too few arguments」，错误消息直接消失
#   译文少一个 %s → printf 把剩下的参数原样追加，消息变成「未知操作: 未知操作: x」
# 这类问题在 po 里就能静态查出来 —— 下面这条断言把「带占位符的 msgid 译文
# 必须也有同样多的占位符」钉死。
# ---------------------------------------------------------------------------
t_placeholder_count() { # t_placeholder_count <msgid>
    local msgid="$1" zh en
    zh="$(_t "$msgid")"
    en="$msgid"
    local zc ec
    zc=$(printf '%s' "$zh" | grep -o '%[0-9]*[sd]' | wc -l | tr -d ' ')
    ec=$(printf '%s' "$en" | grep -o '%[0-9]*[sd]' | wc -l | tr -d ' ')
    if [ "$zc" = "$ec" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: 占位符个数不一致 [$msgid] 原文 $ec 个 / 译文 $zc 个"
    fi
}

# ---------------------------------------------------------------------------
# 全量扫一遍：所有带占位符的 msgid，译文都得有同样多的占位符。
#
# 扫的是**纯 bash 兜底表**（locale/<lang>/messages/<domain>.sh），不是 po：
# _t 在没有 gettext 的机器上查的就是这张表，而 po 只是它的来源。
# 扫 po 会出现假绿 —— 改坏 po 但没重生成表时，运行时用的表还是好的，
# 断言却按 po 判，于是「查表拿译文、按 po 判个数」，两边对不上。
#
# 表的一行长这样（键和值都是单引号包起来的）：
#     'Unknown action: %s') printf '%s' '未知操作: %s' ;;
# 键里也可能带单引号（转义成 '\\''），这里只取到第一个未转义的引号为止。
# ---------------------------------------------------------------------------
table="$REPO_DIR/locale/zh_CN/messages/unix_script.sh"
if [ -f "$table" ]; then
    while IFS= read -r msgid; do
        [ -n "$msgid" ] || continue
        t_placeholder_count "$msgid"
    done < <(sed -n "s/^    '\([^']*\)'.*/\1/p" "$table" | grep -E '%[0-9]*[sd]')
fi

echo "unit_i18n: 通过 $PASS / 失败 $FAIL"
[[ "$FAIL" -eq 0 ]]
