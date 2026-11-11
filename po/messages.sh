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
BATCH="all"

# 参数：bash po/messages.sh [批次] [--check]
#   --check 可以是**第一个**参数（之前只认第二个 ⇒ "po/messages.sh --check"
#   会把 "--check" 当成批次名，find 报 illegal option，xgettext 收不到输入文件，
#   pot 直接被写成空的 —— 一次误用就能把产物清空）。
for _arg in "$@"; do
  case "$_arg" in
    --check) CHECK_ONLY=1 ;;
    -*) printf 'po: 未知参数: %s\n' "$_arg" >&2; exit 2 ;;
    *) BATCH="$_arg" ;;
  esac
done

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

# 抽取范围：每个模块目录下的所有 .sh —— 不只是 install.sh。
# 有些模块把**独立脚本**复制到用户环境里跑（safe-rm 的 lib_trash.sh、
# process_manager_tool 的 pm 脚本），它们的文案也走 _t，必须一起进 po，
# 否则安装时烘不进译文。
if [ "$BATCH" = "all" ]; then
  BATCH_DIRS=(services sys-tools dev-tools essentials ai-tools)
else
  BATCH_DIRS=("$BATCH")
fi

# 抽取范围：每个模块目录下**所有层级的** .sh —— 不只是 install.sh。
# 有些模块把**独立脚本**复制到用户环境里跑（safe-rm 的 lib_trash.sh、
# process_manager_tool 的 pm 脚本），它们的文案也走 _t，必须一起进 po，
# 否则安装时烘不进译文。
# 也要覆盖**子目录**（zsh_setup 的 lib/ 与 frameworks/、sys-setup 的 platform/）：
# 那些文件里的 _t 是运行时文案，漏抽 ⇒ 运行时静默回落英文。
# 只扫一层（$_dir/*/*.sh）会让子目录里的文案整个漏掉 —— 2026-11-11 实测。
SOURCES=()
for _dir in "${BATCH_DIRS[@]}"; do
  while IFS= read -r _f; do
    [ -f "$_f" ] && SOURCES+=("$_f")
  done < <(find "$_dir" -type f -name '*.sh' | LC_ALL=C sort)
done

if [ "$HAVE_XGETTEXT" = "1" ]; then
  XGETTEXT_ARGS=(
    --language=Shell --keyword=_t --keyword=_tf:1 --from-code=UTF-8 --no-location
    --package-name=unix_script --package-version="$(tr -d '[:space:]' <VERSION)"
  )
  # _tf 的第 1 个参数是 msgid，其余是 printf 的实参 —— 只抽第 1 个。
  # --flag 把带占位符的 msgid 标成 c-format，msgfmt --check 据此校验
  # 「译文的占位符与原文一致」：漏掉 %s 会在编译期就红，而不是上线后
  # 打印出「未知操作: 」这种缺了变量的文案。
  #
  # ★ 必须用 c-format，不能用 sh-printf-format：
  #   sh-printf-format 是 gettext 0.23+ 才引入的 flag 名。gettext 0.19/0.21/0.22
  #   （CI 的 ubuntu/debian/centos/almalinux 矩阵都还在这区间）见到它会直接报
  #   「A --flag argument doesn't have the <keyword>:<argnum>:[pass-]<flag> syntax」
  #   并以非 0 退出 —— 抽取整体失败，门禁红。
  #   c-format 就是 printf 占位符语义，且 gettext 0.19 → 1.0 全都认。
  #   （sh-format 不行：它的语义是 shell 的 $var 替换，不是 printf 占位符。）
  XGETTEXT_FLAGS=(--flag=_tf:1:c-format)

  if [ "$CHECK_ONLY" = "1" ]; then
    TMP_CLEAN="$(mktemp -d "${TMPDIR:-/tmp}/uxs-po.XXXXXX")"
    tmp="$TMP_CLEAN/pot"
    xgettext "${XGETTEXT_ARGS[@]}" "${XGETTEXT_FLAGS[@]}" -o "$tmp" "${SOURCES[@]}"
    # 只比内容：注释行（#: 行号）与 POT-Creation-Date 每次生成都会变
    strip_header() { grep -v '^#' "$1" | grep -v '^"POT-Creation-Date:'; }
    if [ -f "$POT" ] && ! diff -q <(strip_header "$POT") <(strip_header "$tmp") >/dev/null; then
      printf 'po: messages changed, run bash po/messages.sh\n' >&2
      exit 1
    fi
  else
    xgettext "${XGETTEXT_ARGS[@]}" "${XGETTEXT_FLAGS[@]}" --add-comments=TRANSLATORS -o "$POT" "${SOURCES[@]}"
    printf 'po: wrote %s\n' "${POT#"$ROOT"/}"

    need_msgfmt=0
    for po in "$ROOT"/locale/*/LC_MESSAGES/unix_script.po; do
      [ -f "$po" ] || continue
      if command -v msgmerge >/dev/null 2>&1; then
        # -N（--no-fuzzy-matching）：新增 msgid 一律留空，绝不猜译文。
        # 默认的模糊匹配会把新 msgid 猜匹配到别的模块的旧条目上（如「检测到 Certbot 已安装（」
        # 被猜成「检测到 1Panel 已安装（」），标 fuzzy 后 msgfmt 会排除它 ——
        # 结果是运行时静默回落英文 msgid，译文表里还留着一条看着像对的错译文。
        msgmerge --quiet --update --backup=none -N "$po" "$POT"
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
