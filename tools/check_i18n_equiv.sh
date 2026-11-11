#!/usr/bin/env bash
#
# 文案保真门禁（i18n 迁移专用）。
#
# 用法：
#   bash tools/check_i18n_equiv.sh
#
# 判据见 tools/check_i18n_equiv.py 的文档字符串：
#   1) 迁移前的被引号包裹的中文用字，迁移后必须都在译文里（不许漏字）
#   2) 迁移前的装饰符号（emoji 等），迁移后计数必须一致（不许吞 emoji）
#
# 基线提交用环境变量 UXS_I18N_BASELINE 覆盖（默认 7729437 = Stage 3 之前）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

python3 "$ROOT/tools/check_i18n_equiv.py"
