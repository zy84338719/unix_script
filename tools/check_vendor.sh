#!/usr/bin/env bash
#
# 门禁：vendor/shellkit/ 这份副本必须与入库清单一致，且（有上游时）与上游一致。
#
# 为什么要这道门：vendor 出去的是**副本**，副本会被手改、被忘记同步。
# 一旦 unix_script 里的 shellkit 与上游分叉，两边的行为差异就没有第二处真相源可查。
#
# 三层：
#   L1 副本自洽（CI 里能跑，不需要上游）：副本内容 vs 入库的 vendor/shellkit.sha256
#      —— 抓「副本被手改」与「副本夹带清单外的文件」。
#   L2 副本 == 上游：用**上游的** CLI 跑 vendor --check。
#      上游要显式给出（SHELLKIT_UPSTREAM 或 SHELLKIT_REPO）——
#      ⚠️ 不能用副本自己的 CLI 比副本自己：它的 SELF_DIR 就是副本目录，永远一致。
#   L3 副本自检：副本自带的 CLI 要能跑起来（证明这份副本是可用的）。
#
# 清单由本脚本 --update 生成，生成物随提交入库。
# 清单缺失 => 硬失败（exit 2），**不许在检查模式里自动生成**：
# 自动生成等于「删了清单就等于重新认可当前内容」，那是假绿。
#
# 退出码：0 一致；1 有漂移；2 副本/清单缺失或缺工具
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
VENDOR_DIR="$ROOT/vendor/shellkit"
MANIFEST="$ROOT/vendor/shellkit.sha256"
UPDATE=0

if [ "${1:-}" = "--update" ]; then
  UPDATE=1
fi

# sha256：Linux 的 sha256sum 与 macOS 的 shasum 名字不一样，两个都认。
if command -v sha256sum >/dev/null 2>&1; then
  _sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  _sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  printf 'check_vendor: 缺 sha256sum 与 shasum，无法校验\n' >&2
  exit 2
fi

if [ ! -d "$VENDOR_DIR" ]; then
  printf 'check_vendor: 副本不存在：%s\n' "${VENDOR_DIR#"$ROOT/"}" >&2
  exit 2
fi

# 副本里的文件清单（相对 vendor/shellkit/ 的路径），排除 macOS 的 .DS_Store
_list_files() {
  local __f
  (
    cd "$VENDOR_DIR" || exit 1
    find . -type f ! -name '.DS_Store' | LC_ALL=C sort | while IFS= read -r __f; do
      printf '%s\n' "${__f#./}"
    done
  )
}

if [ "$UPDATE" = "1" ]; then
  mkdir -p "$(dirname "$MANIFEST")"
  : >"$MANIFEST"
  while IFS= read -r __f; do
    printf '%s  %s\n' "$(_sha256 "$VENDOR_DIR/$__f")" "$__f" >>"$MANIFEST"
  done < <(_list_files)
  printf 'check_vendor: 清单已更新：%s（%s 个文件）\n' "${MANIFEST#"$ROOT/"}" "$(wc -l <"$MANIFEST" | tr -d ' ')"
  exit 0
fi

if [ ! -f "$MANIFEST" ]; then
  printf 'check_vendor: 清单不存在：%s —— 跑 tools/check_vendor.sh --update 生成并提交\n' "${MANIFEST#"$ROOT/"}" >&2
  exit 2
fi

__drift=0

# --- L1a：清单里的文件，内容对不对 ---
while read -r __sum __f; do
  [ -n "${__sum:-}" ] || continue
  if [ ! -f "$VENDOR_DIR/$__f" ]; then
    printf 'check_vendor: 副本缺文件：%s\n' "$__f" >&2
    __drift=1
    continue
  fi
  if [ "$(_sha256 "$VENDOR_DIR/$__f")" != "$__sum" ]; then
    printf 'check_vendor: 副本文件被改：%s\n' "$__f" >&2
    __drift=1
  fi
done <"$MANIFEST"

# --- L1b：副本里有没有清单外的文件（夹带） ---
__tmp="$(mktemp -d "${TMPDIR:-/tmp}/uxs-vendor.XXXXXX")"
trap 'rm -rf "$__tmp"' EXIT
_list_files >"$__tmp/actual"
cut -c 67- "$MANIFEST" | LC_ALL=C sort >"$__tmp/manifest"
__extra="$(LC_ALL=C comm -23 "$__tmp/actual" "$__tmp/manifest")"
if [ -n "$__extra" ]; then
  printf 'check_vendor: 副本里有清单外的文件：\n' >&2
  printf '%s\n' "$__extra" | sed 's/^/  /' >&2
  __drift=1
fi

# --- L2：副本 == 上游（拿得到上游时才做） ---
# ⚠️ 这里必须用「上游的 CLI」。用副本自己的 CLI 比副本自己是恒绿的。
__upstream="${SHELLKIT_UPSTREAM:-${SHELLKIT_REPO:-}}"
if [ -n "$__upstream" ] && [ -x "$__upstream/shellkit" ]; then
  if ! bash "$__upstream/shellkit" vendor "$ROOT" --check; then
    printf 'check_vendor: 副本与上游不一致 —— 用上游 CLI 重新 vendor 一份\n' >&2
    __drift=1
  fi
else
  printf 'check_vendor: 提示 —— 没给上游（SHELLKIT_UPSTREAM / SHELLKIT_REPO），跳过 L2 比对\n' >&2
fi

# --- L3：副本自检（副本自带的 CLI 要能跑起来） ---
if [ ! -x "$VENDOR_DIR/shellkit" ]; then
  printf 'check_vendor: 副本缺 shellkit CLI，无法自检\n' >&2
  exit 2
fi
if ! bash "$VENDOR_DIR/shellkit" --version >/dev/null 2>&1; then
  printf 'check_vendor: 副本自检未通过（副本的 CLI 跑不起来）\n' >&2
  __drift=1
fi

if [ "$__drift" -ne 0 ]; then
  exit 1
fi
printf 'check_vendor: ok（副本与清单一致）\n'
exit 0
