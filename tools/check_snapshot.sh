#!/usr/bin/env bash
#
# 行为快照门禁：重新采集 unix_script 的确定性输出，与入库基线逐字比对。
#
# 有差异就红 —— 重构不得改变这些输出的形状。
# 有意的变更必须显式重新生成基线（bash tools/snapshot.sh）并在提交说明里写清改了什么。
#
# 退出码：0 一致；1 有差异；2 基线缺失；3 采集失败
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
BASE_DIR="$ROOT/tests/snapshot/${OS}-${ARCH}"

if [ ! -d "$BASE_DIR" ]; then
  printf 'check_snapshot: 基线目录不存在：%s\n' "${BASE_DIR#"$ROOT/"}" >&2
  printf 'check_snapshot: 先跑 bash tools/snapshot.sh 生成基线\n' >&2
  exit 2
fi

# 基线目录存在但没有 .txt（空目录 / 只剩占位文件）＝ 基线不可用。
# 放行等于「没有基线也判绿」，那是假绿，必须按基线缺失处理。
__baseline_count=0
for __f in "$BASE_DIR"/*.txt; do
  [ -f "$__f" ] || continue
  __baseline_count=$((__baseline_count + 1))
done
if [ "$__baseline_count" -eq 0 ]; then
  printf 'check_snapshot: 基线目录没有可比对的 .txt 文件：%s\n' "${BASE_DIR#"$ROOT/"}" >&2
  printf 'check_snapshot: 先跑 bash tools/snapshot.sh 生成基线\n' >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/uxs-snapshot.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! bash "$ROOT/tools/snapshot.sh" "$TMP_DIR" >/dev/null 2>&1; then
  printf 'check_snapshot: 采集失败\n' >&2
  exit 3
fi

rc=0
for __f in "$BASE_DIR"/*.txt; do
  [ -f "$__f" ] || continue
  __name="$(basename "$__f")"
  if ! diff -u "$__f" "$TMP_DIR/$__name" >/dev/null 2>&1; then
    printf 'check_snapshot: %s 与基线不一致\n' "$__name" >&2
    diff -u "$__f" "$TMP_DIR/$__name" >&2 || true
    rc=1
  fi
done

if [ "$rc" -ne 0 ]; then
  printf 'check_snapshot: 行为与基线不一致（有意变更请重新生成基线并写明）\n' >&2
  exit 1
fi
printf 'check_snapshot: ok\n'
exit 0
