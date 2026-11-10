#!/usr/bin/env bash
#
# 校验模块里没有残留的硬编码中文。
#
# 用法：
#   bash tools/check_i18n_drift.sh          # 扫所有模块
#   bash tools/check_i18n_drift.sh services # 只扫 services
#
# 白名单（允许硬编码的串）：内部注释、.manifest 里的 LABEL / DESC / NEXT_STEPS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
BATCH="${1:-all}"

if [ "$BATCH" = "all" ]; then
  DIRS=(services sys-tools dev-tools essentials ai-tools)
else
  DIRS=("$BATCH")
fi

violation=0
for dir in "${DIRS[@]}"; do
  for script in "$ROOT/$dir"/*/install.sh "$ROOT/$dir"/*/*.sh; do
    [ -f "$script" ] || continue
    # 排除 .manifest 与 README.md（这两个本来就是给人看的，不进 _t）
    case "$script" in
      *.manifest|*.md) continue ;;
    esac
    # 匹配硬编码中文（不在 _t '...' 里，不在注释 # 行里）
    # 先把 _t '...' 的内容抠掉，再查剩下的中文
    stripped="$(sed -E "s/_t '[^']*'//g; s/_t \"[^\]*\"//g" "$script")"
    if echo "$stripped" | grep -q '[一-龥]'; then
      echo "check_i18n_drift: $script 含硬编码中文（应改为 _t）"
      violation=1
    fi
  done
done

if [ "$violation" -eq 1 ]; then
  exit 1
fi
echo "check_i18n_drift: ok"
