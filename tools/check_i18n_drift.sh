#!/usr/bin/env bash
#
# 校验模块里没有残留的硬编码中文。
#
# 用法：
#   bash tools/check_i18n_drift.sh          # 扫所有模块
#   bash tools/check_i18n_drift.sh services # 只扫 services
#
# 白名单（允许保留原文的串）：
#   - 注释行（含行首空白+#）：给人看的说明，不进 _t
#   - 「用法:」/「Usage:」行：module_subcommands 解析子命令的锚点
#   - .manifest / README.md：本来就是给人看的元数据
#   - locale/*/messages/*.sh：po/messages.sh 的纯 bash 兜底表（生成物）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
BATCH="${1:-all}"

if [ "$BATCH" = "all" ]; then
  DIRS=(services sys-tools dev-tools essentials ai-tools)
else
  DIRS=("$BATCH")
fi

# awk 脚本写成临时文件，避免单引号嵌套地狱
AWK_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/uxs-drift.XXXXXX.awk")
trap 'rm -f "$AWK_SCRIPT"' EXIT

cat > "$AWK_SCRIPT" <<'AWK_EOF'
{
  line = $0
  gsub(/_t '[^']*'/, "", line)
  gsub(/_t "[^"]*"/, "", line)
  if (line ~ /^[[:space:]]*#/) next
  if (line ~ /^用法:/ || line ~ /^Usage:/) next
  # 只查汉字：emoji（⚠️❌✅ 等）会触发 [一-龥] 的字节区间，但它们不是硬编码文案。
  # 汉字是 3 字节 UTF-8（E4-E9 开头），逐个 byte 检查。
  if (line ~ /[一-龥]/) {
    n = split(line, bytes, "")
    for (i = 1; i <= n; i++) {
      c = bytes[i]
      # 直接用区间比较：awk 的 if (c >= "ä" && c <= "é") 对单字节成立
      if (c >= "一" && c <= "鿿") { print FILENAME; exit 1 }
    }
  }
}
AWK_EOF

# LC_ALL=C：C.UTF-8 的 awk 字符类会把 ASCII 字节误判成「含中文」，
# 只有传统 C locale 下 [一-龥] 才是多字节区间（逐字节比较）。
export LC_ALL=C
export LC_CTYPE=C.UTF-8

violation=0
for dir in "${DIRS[@]}"; do
  for script in "$ROOT/$dir"/*/install.sh "$ROOT/$dir"/*/*.sh; do
    [ -f "$script" ] || continue
    case "$script" in
      *.manifest|*.md) continue ;;
      */messages/*.sh) continue ;;
    esac
    if awk -f "$AWK_SCRIPT" "$script"; then
      :
    else
      echo "check_i18n_drift: $script 含硬编码中文（应改为 _t）"
      violation=1
    fi
  done
done

if [ "$violation" -eq 1 ]; then
  exit 1
fi
echo "check_i18n_drift: ok"
