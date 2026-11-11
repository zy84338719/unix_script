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

echo "unit_i18n: 通过 $PASS / 失败 $FAIL"
[[ "$FAIL" -eq 0 ]]
