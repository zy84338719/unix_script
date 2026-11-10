#!/usr/bin/env bash
#
# 从模块源码抽取 msgid，生成 .pot 与 .po，再编译成纯 bash 兜底表。
#
#   bash po/messages.sh            # 重新生成 pot + 合并 po + 编译 mo + 生成兜底表
#   bash po/messages.sh --check    # 只检查：不写文件
#   bash po/messages.sh services   # 只处理 services 批次
#
# msgid 一律英文（源码里 _t '...' 的原样），译文只进 locale/zh_CN/LC_MESSAGES。
#
# 纯 bash 兜底表（locale/zh_CN/messages/unix_script.sh）也在这里生成：
# 没有 gettext 的机器靠它出译文。表是生成物，但必须入库。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
POT="$ROOT/locale/unix_script.pot"
PO_TO_SH="$ROOT/po/po_to_sh.awk"
CHECK_ONLY=0
BATCH="${1:-all}"

if [ "${2:-}" = "--check" ]; then
  CHECK_ONLY=1
fi

# 临时目录：退出时清掉
TMP_CLEAN=""
cleanup() {
  if [ -n "${TMP_CLEAN:-}" ]; then
    rm -rf "$TMP_CLEAN"
  fi
}
trap cleanup EXIT

# 缺 xgettext 的机器上跳过抽取（不当失败），但兜底表的比对照样要跑
HAVE_XGETTEXT=1
if ! command -v xgettext >/dev/null 2>&1; then
  printf 'po: xgettext not found, skipping message extraction\n' >&2
  HAVE_XGETTEXT=0
fi

cd "$ROOT"

if [ "$BATCH" = "all" ]; then
  SOURCES=(services/*/install.sh sys-tools/*/install.sh dev-tools/*/install.sh essentials/*/install.sh ai-tools/*/install.sh)
else
  SOURCES=("$BATCH"/*/install.sh)
fi

if [ "$HAVE_XGETTEXT" = "1" ]; then
  XGETTEXT_ARGS=(
    --language=Shell --keyword=_t --from-code=UTF-8 --no-location
    --package-name=unix_script --package-version="$(tr -d '[:space:]' <VERSION)"
  )

  if [ "$CHECK_ONLY" = "1" ]; then
    TMP_CLEAN="$(mktemp -d "${TMPDIR:-/tmp}/uxs-po.XXXXXX")"
    tmp="$TMP_CLEAN/pot"
    xgettext "${XGETTEXT_ARGS[@]}" -o "$tmp" "${SOURCES[@]}"
    # 只比内容：注释行（#: 行号）与 POT-Creation-Date 每次生成都会变
    strip_header() { grep -v '^#' "$1" | grep -v '^"POT-Creation-Date:'; }
    if [ -f "$POT" ] && ! diff -q <(strip_header "$POT") <(strip_header "$tmp") >/dev/null; then
      printf 'po: messages changed, run bash po/messages.sh\n' >&2
      exit 1
    fi
  else
    xgettext "${XGETTEXT_ARGS[@]}" --add-comments=TRANSLATORS -o "$POT" "${SOURCES[@]}"
    printf 'po: wrote %s\n' "${POT#"$ROOT"/}"

    need_msgfmt=0
    for po in "$ROOT"/locale/*/LC_MESSAGES/unix_script.po; do
      [ -f "$po" ] || continue
      if command -v msgmerge >/dev/null 2>&1; then
        msgmerge --quiet --update --backup=none "$po" "$POT"
      fi
      need_msgfmt=1
    done

    if [ "$need_msgfmt" = "1" ]; then
      if ! command -v msgfmt >/dev/null 2>&1; then
        printf 'po: msgfmt not found, .mo files were not rebuilt\n' >&2
      else
        for po in "$ROOT"/locale/*/LC_MESSAGES/unix_script.po; do
          [ -f "$po" ] || continue
          msgfmt --check -o "${po%.po}.mo" "$po"
          printf 'po: compiled %s\n' "${po#"$ROOT"/}"
        done
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 纯 bash 兜底表：locale/zh_CN/messages/unix_script.sh
# 由 locale/zh_CN/LC_MESSAGES/unix_script.po 经 po_to_sh.awk 生成
# ---------------------------------------------------------------------------
for po in "$ROOT"/locale/*/LC_MESSAGES/unix_script.po; do
  [ -f "$po" ] || continue
  lang="$(basename "$(dirname "$(dirname "$po")")")"
  outdir="$ROOT/locale/$lang/messages"
  [ -d "$outdir" ] || mkdir -p "$outdir"
  out="$outdir/unix_script.sh"
  if ! command -v awk >/dev/null 2>&1; then
    printf 'po: awk not found, skipping fallback table for %s\n' "$lang" >&2
    continue
  fi
  awk -f "$PO_TO_SH" -v domain=unix_script "$po" >"$out.tmp"
  mv "$out.tmp" "$out"
  printf 'po: wrote %s\n' "${out#"$ROOT"/}"
done
