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

exec python3 "$ROOT/tools/check_i18n_extract.py" "$@"