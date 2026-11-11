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

# python3 与 git 都是硬依赖：
#   python3 —— 门禁本体是 python 脚本
#   git     —— 要 git show 读「迁移前」的基线提交
# 缺任何一个都不是「通过」而是「没跑」。
# 退出码 3 = 「工具没装，本门禁没跑」（CI 里认成 skip，不是失败）；1 = 真有问题。
command -v python3 >/dev/null 2>&1 || {
    printf 'check_i18n_equiv: 需要 python3（没装 ⇒ 本门禁没跑，不等于「通过」）\n' >&2
    exit 3
}
command -v git >/dev/null 2>&1 || {
    printf 'check_i18n_equiv: 需要 git（要读基线提交；没装 ⇒ 本门禁没跑，不等于「通过」）\n' >&2
    exit 3
}

python3 "$ROOT/tools/check_i18n_equiv.py"
