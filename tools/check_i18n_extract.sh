#!/usr/bin/env bash
#
# i18n 抽取完整性门禁：源码里的每条文案都进了 pot，且都有中文译文。
#
# 用法：bash tools/check_i18n_extract.sh
#
# 判据见 tools/check_i18n_extract.py 的文档字符串。
# 退出码：0 通过；1 有问题。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# python3 是硬依赖：缺了就不是「通过」而是「没跑」。
# 退出码 3 = 「工具没装，本门禁没跑」（CI 里认成 skip，不是失败）；1 = 真有问题。
command -v python3 >/dev/null 2>&1 || {
    printf 'check_i18n_extract: 需要 python3（没装 ⇒ 本门禁没跑，不等于「通过」）\n' >&2
    exit 3
}

exec python3 "$ROOT/tools/check_i18n_extract.py" "$@"