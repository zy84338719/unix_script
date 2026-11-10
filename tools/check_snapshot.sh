#!/usr/bin/env bash
#
# 行为快照门禁：重新采集 unix_script 的确定性输出，与入库基线逐字比对。
#
# 有差异就红 —— 重构不得改变这些输出的形状。
#
# 判定分三段（顺序固定）：
#   1. 基线缺失：基线目录不存在，或目录里一个基线文件都没有             → exit 2
#   2. 集合不一致：采集到的文件集合与基线文件集合不相等                  → exit 2
#      （比较集合由 **采集结果** 决定，不是由基线目录决定：
#        少一个基线文件 ⇒ 点名它并判红，不会静默少比一个；
#        采集器新增了输出而基线没重生成 ⇒ 同样判红，不会被静默忽略。）
#   3. 逐字比对 + 变更登记检查                                          → exit 1
#      3a. 登记检查：每个基线文件的 sha256 必须与 .approved 里登记的一致；
#          不一致 ⇒ 「基线内容被改过但没有登记」。
#          效果：有意改行为必须「重跑 snapshot.sh 生成新基线 + 更新 .approved 登记」
#          两处都进同一个 diff，评审看得见；只改代码不重生成基线 ⇒ 逐字比对失败；
#          只改基线不更新登记 ⇒ 登记检查失败。两条路都堵住。
#      3b. 逐字比对：基线文件与本次采集结果必须完全相同。
#
# 退出码：0 一致；1 有差异（含登记不符）；2 基线缺失或集合不一致；3 采集失败
#
# 用法：bash tools/check_snapshot.sh
set -euo pipefail

# LC_ALL=C：排序与 glob 受 locale 影响，不固定就会在不同机器上排出不同顺序，
# 报错信息与比对顺序随之漂移。
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# 基线目录与 sha256 都由采集器给出（唯一真相源，避免两处各算一遍算出岔子）。
if ! BASE_DIR="$(bash "$ROOT/tools/snapshot.sh" --print-baseline-dir)"; then
  printf 'check_snapshot: 无法确定基线目录\n' >&2
  exit 3
fi

if [ ! -d "$BASE_DIR" ]; then
  printf 'check_snapshot: 基线目录不存在：%s\n' "${BASE_DIR#"$ROOT/"}" >&2
  printf 'check_snapshot: 该平台缺基线，请本地跑 bash tools/snapshot.sh 生成后提交\n' >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/uxs-snapshot.XXXXXX")"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/uxs-snapshot-log.XXXXXX")"
trap 'rm -rf "$TMP_DIR" "$LOG_FILE"' EXIT

# 采集器输出留在临时文件里：失败时把尾部若干行打出来，
# 不要一上来就 >/dev/null 2>&1 把现场全吞了。
if ! bash "$ROOT/tools/snapshot.sh" "$TMP_DIR" >"$LOG_FILE" 2>&1; then
  printf 'check_snapshot: 采集失败\n' >&2
  printf '%s\n' '--- 采集器输出（末尾 20 行）---' >&2
  tail -n 20 "$LOG_FILE" >&2
  exit 3
fi

COLLECTED_LIST="$TMP_DIR/.collected"
if [ ! -f "$COLLECTED_LIST" ]; then
  printf 'check_snapshot: 采集器没有产出 .collected 清单，无法确定本次采集了哪些文件\n' >&2
  exit 3
fi

# --- 基线文件集合 B（基线目录里的非点文件；.approved / .collected 不算基线） ---
BASE_LIST="$TMP_DIR/base-files"
: >"$BASE_LIST"
for f in "$BASE_DIR"/*; do
  [ -f "$f" ] || continue
  printf '%s\n' "${f##*/}" >>"$BASE_LIST"
done
if [ ! -s "$BASE_LIST" ]; then
  printf 'check_snapshot: 基线目录没有可比对的基线文件：%s\n' "${BASE_DIR#"$ROOT/"}" >&2
  printf 'check_snapshot: 该平台缺基线，请本地跑 bash tools/snapshot.sh 生成后提交\n' >&2
  exit 2
fi

# --- 集合比对：采集结果 C vs 基线 B（集合相等才进入逐字比对） ---
sort "$COLLECTED_LIST" >"$TMP_DIR/c.sorted"
sort "$BASE_LIST" >"$TMP_DIR/b.sorted"
comm -23 "$TMP_DIR/c.sorted" "$TMP_DIR/b.sorted" >"$TMP_DIR/missing"
comm -13 "$TMP_DIR/c.sorted" "$TMP_DIR/b.sorted" >"$TMP_DIR/extra"

if [ -s "$TMP_DIR/missing" ] || [ -s "$TMP_DIR/extra" ]; then
  if [ -s "$TMP_DIR/missing" ]; then
    printf 'check_snapshot: 采集器产出但基线里没有的文件：\n' >&2
    sed 's/^/  - /' "$TMP_DIR/missing" >&2
  fi
  if [ -s "$TMP_DIR/extra" ]; then
    printf 'check_snapshot: 基线里有但采集器不再产出的文件：\n' >&2
    sed 's/^/  - /' "$TMP_DIR/extra" >&2
  fi
  printf 'check_snapshot: 基线与采集结果不一致，请重新生成基线后提交\n' >&2
  exit 2
fi

# --- 变更登记检查（.approved）：每个基线文件的 sha256 必须与登记的一致 ---
APPROVED="$BASE_DIR/.approved"
approved_hash() {
  local want="$1" name hash
  while IFS=$'\t' read -r name hash; do
    if [ "$name" = "$want" ]; then
      printf '%s\n' "$hash"
      return 0
    fi
  done <"$APPROVED"
  return 1
}

rc=0
if [ ! -f "$APPROVED" ]; then
  printf 'check_snapshot: 缺少变更登记文件：%s\n' "${APPROVED#"$ROOT/"}" >&2
  printf 'check_snapshot: 有意变更必须同时更新登记（bash tools/snapshot.sh --approve）\n' >&2
  rc=1
else
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    registered="$(approved_hash "$f" || true)"
    actual="$(bash "$ROOT/tools/snapshot.sh" --sha256 "$BASE_DIR/$f" || true)"
    if [ -z "$actual" ]; then
      printf 'check_snapshot: 无法计算 %s 的 sha256（工具不可用或文件不可读）\n' "$f" >&2
      rc=1
    elif [ -z "$registered" ]; then
      printf 'check_snapshot: 基线内容被改过但没有登记：%s（.approved 里没有这一条）\n' "$f" >&2
      rc=1
    elif [ "$registered" != "$actual" ]; then
      printf 'check_snapshot: 基线内容被改过但没有登记：%s\n' "$f" >&2
      printf '%s\n' "  登记 sha256：$registered" >&2
      printf '%s\n' "  实际 sha256：$actual" >&2
      rc=1
    fi
  done <"$BASE_LIST"

  # 登记里有、基线里没有的条目 ⇒ 登记与基线不同步，同样判红。
  while IFS=$'\t' read -r name hash; do
    [ -n "$name" ] || continue
    if ! grep -F -x -- "$name" "$BASE_LIST" >/dev/null 2>&1; then
      printf 'check_snapshot: 登记里有基线不存在的条目：%s\n' "$name" >&2
      rc=1
    fi
  done <"$APPROVED"
fi

# --- 逐字比对（比对集合 = 本次采集结果）---
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if diff -u "$BASE_DIR/$f" "$TMP_DIR/$f" >"$TMP_DIR/diff.out" 2>&1; then
    :
  else
    drc=$?
    if [ "$drc" -eq 1 ]; then
      printf 'check_snapshot: %s 与基线不一致\n' "$f" >&2
      cat "$TMP_DIR/diff.out" >&2
      rc=1
    else
      printf 'check_snapshot: %s 比对失败（diff 退出码 %s，不是「内容不同」）\n' "$f" "$drc" >&2
      cat "$TMP_DIR/diff.out" >&2
      rc=1
    fi
  fi
done <"$TMP_DIR/c.sorted"

if [ "$rc" -ne 0 ]; then
  printf 'check_snapshot: 行为与基线不一致（有意变更请重新生成基线 + 更新登记，并写明改了什么）\n' >&2
  exit 1
fi
printf 'check_snapshot: ok\n' >&2
exit 0
