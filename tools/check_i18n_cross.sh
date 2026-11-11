#!/usr/bin/env bash
#
# 校验译文没有「串味」—— msgid 说的是 A 模块，译文却写的是 B 模块的文案。
#
# 背景：msgmerge 默认做模糊匹配，把新增 msgid 猜匹配到别的条目的旧译文上。
# 带 fuzzy 标记的被 msgfmt 排除（运行时回落英文，这条还算好）；
# 但**没被标记**的那些会把错译文直接留下 —— 用户看到的是别的模块的文案
#（实测 buildah 的卸载说明写着「卸载面板…/www」，那是 CasaOS 的）。
#
# 用法：bash tools/check_i18n_cross.sh
#
# 判据：模块专属名词的集合必须一致。
#   msgid 里出现的专属名词（buildah / CasaOS / Caddy…），译文里必须都出现；
#   译文里可以多出现别的专属名词 —— 那是正当提及
#   （containerd 的说明提到 Docker CLI 是对的）。
#   ⇒ 判据是「msgid 的专属名词集合 ⊆ 译文的专属名词集合」。
#
# 另有一条独立判据：译文里同一句话重复两遍 ⇒ 灌译文时拼接过。
#
# 退出码：0 一致；1 有问题
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# python3 是硬依赖：缺了就不是「通过」而是「没跑」。
# 退出码 3 = 「工具没装，本门禁没跑」（CI 里认成 skip，不是失败）；1 = 真有问题。
command -v python3 >/dev/null 2>&1 || {
    printf 'check_i18n_cross: 需要 python3（没装 ⇒ 本门禁没跑，不等于「通过」）\n' >&2
    exit 3
}

exec python3 "$ROOT/tools/check_i18n_cross.py" "$@"
