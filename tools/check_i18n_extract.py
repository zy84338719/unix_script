#!/usr/bin/env python3
"""
i18n 抽取完整性门禁：防止「源码里有文案，运行时却显示英文」。

背景（2026-11-11 实测）：
  GNU gettext 1.0 的 Shell scanner 不是无损的 —— 它对某些字面量会整条丢弃，
  丢弃时**不报错、不警告**，pot 里就是没有这条。源码里照常调用 _t，
  运行时查不到译文 ⇒ 静默回落英文 msgid。
  msgmerge 也不会报警：pot 里没这条 ⇒ po 里的旧条目被标成 obsolete，
  而新 msgid 从未进过 po ⇒ 译文缺失这件事在 CI 上完全不可见。

本门禁的两条判据：
  1) 抽取完整性：源码里每条 _t/_tf 的 msgid 都必须出现在 pot 里。
     （漏抽 ⇒ 门禁红）
  2) 译文完整性：pot 里每条 msgid 在 po 里都必须有非空 msgstr。
     （漏抽或漏灌译文 ⇒ 门禁红）

第 2 条比第 1 条更强，且没有源码解析误差 —— 它只看 pot 与 po。
第 1 条用于定位「是抽取丢了还是译文没灌」。

退出码：0 通过；1 有问题。
"""

import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATS = ["services", "sys-tools", "dev-tools", "essentials", "ai-tools"]
BACKSLASH = chr(92)
QUOTE = chr(39)
DQ = chr(34)


def collect_sources():
    out = []
    for cat in CATS:
        base = os.path.join(ROOT, cat)
        if not os.path.isdir(base):
            continue
        for dp, _dn, fn in os.walk(base):
            for f in sorted(fn):
                if f.endswith(".sh"):
                    out.append(os.path.join(dp, f))
    return sorted(out)


def unescape(s):
    out = []
    i = 0
    simple = {"n": chr(10), "t": chr(9), "r": chr(13)}
    while i < len(s):
        c = s[i]
        if c == BACKSLASH and i + 1 < len(s):
            out.append(simple.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def parse_po(path):
    """返回 (entries, obsolete_ids)。entries 是 msgid -> msgstr。

    ⚠️ 保存条目的判据是「cur_id 非空」，**不能**用「刚读到 msgid」当判据：
    msgid 后面紧跟的是 msgstr，若把 state 翻成 "str"，条目就永远存不进去
    （2026-11-11 实测：解析出来 0 条，门禁把 3000+ 条全报成「没译文」）。
    """
    if not os.path.exists(path):
        return {}, []
    entries = {}
    obsolete = []
    cur_id = None
    cur_str = None
    # 折行 msgid 的第一行是 'msgid ""' -> cur_id 是空字符串。
    # 判「有没有条目」必须用独立标志：空串 falsy，会把折行的条目整条丢掉
    # -> 门禁把几千条全报成「没译文」（2026-11-11 实测）。
    has_id = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip(chr(10))
            if line.startswith("#~"):
                if has_id and cur_id:
                    obsolete.append(cur_id)
                cur_id, cur_str, has_id = None, None, False
                continue
            if line.startswith("#"):
                continue
            m = re.match(r'^msgid\s+"(.*)"$', line)
            if m:
                if has_id:
                    entries[cur_id] = cur_str or ""
                cur_id = unescape(m.group(1))
                cur_str = None
                has_id = True
                continue
            m = re.match(r'^msgstr(?:\[\d+\])?\s+"(.*)"$', line)
            if m:
                cur_str = unescape(m.group(1))
                continue
            m = re.match(r'^"(.*)"$', line)
            if m:
                # 折行续行：msgid 未配 msgstr 时续到 msgid，否则续到 msgstr
                if cur_str is None:
                    cur_id = (cur_id or "") + unescape(m.group(1))
                else:
                    cur_str += unescape(m.group(1))
                continue
            if not line.strip():
                if has_id:
                    entries[cur_id] = cur_str or ""
                cur_id, cur_str, has_id = None, None, False
    if has_id:
        entries[cur_id] = cur_str or ""
    entries.pop("", None)
    return entries, obsolete


def main():
    sources = collect_sources()
    if not sources:
        print("i18n-extract: no sources found", file=sys.stderr)
        return 1
    # 没装 gettext 的机器没法验证抽取 —— 跳过而不是判失败
    # （与 po/messages.sh 的处理一致：缺工具不当失败）。
    if not shutil.which("xgettext"):
        print("i18n-extract: xgettext not found, skipped")
        return 0
    pot_path = os.path.join(ROOT, "uxs_check_extract.pot")
    rel = [os.path.relpath(p, ROOT) for p in sources]
    # ★ 这条命令必须与 po/messages.sh 的抽取参数**逐字一致**（flag/keyword 都算）。
    #   两边一旦漂移，门禁核对的 pot 就不是真实产物那份 —— 门禁会替漂移背书。
    #   flag 用 c-format：sh-printf-format 是 gettext 0.23+ 才有的名字，
    #   旧版 xgettext（CI 矩阵里的 0.19/0.21/0.22）会直接报错退出。
    r = subprocess.run(
        ["xgettext", "--language=Shell", "--keyword=_t", "--keyword=_tf:1",
         "--from-code=UTF-8", "--no-location",
         "--flag=_tf:1:c-format", "-o", pot_path] + rel,
        cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print("i18n-extract: xgettext failed: " + r.stderr.strip()[:500], file=sys.stderr)
        return 1
    with open(pot_path, encoding="utf-8") as fh:
        pot_raw = fh.read()
    os.remove(pot_path)

    pot_ids = set()
    cur = None
    # ★ 折行的 msgid 由多段组成，只能在**整条读完**时才算一个 msgid。
    #   逐段 add 会产生「部分 msgid」的幽灵条目（"xxx tldr/" 这种），
    #   它们在 po 里当然不存在 -> 门禁误报「没译文」（2026-11-11 实测）。
    for line in pot_raw.splitlines():
        m = re.match(r'^msgid\s+"(.*)"$', line)
        if m:
            cur = unescape(m.group(1))
            continue
        m = re.match(r'^msgstr', line)
        if m:
            if cur is not None:
                pot_ids.add(cur)
            cur = None
            continue
        m = re.match(r'^"(.*)"$', line)
        if m and cur is not None:
            cur += unescape(m.group(1))
            continue
        if not line.strip() and cur is not None:
            pot_ids.add(cur)
            cur = None
    pot_ids.discard("")

    # 判据 1：源码里的每条 msgid 都进了 pot
    pat = re.compile(r"(?<![A-Za-z0-9_])_tf?\s+'(?:[^'\\]|\\.)*'")
    arg_pat = re.compile(r"(?<![A-Za-z0-9_])_tf?\s+'((?:[^'\\]|\\.)*)'")
    src_ids = {}
    for p in sources:
        relp = os.path.relpath(p, ROOT)
        with open(p, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                if line.lstrip().startswith("#"):
                    continue
                for m in arg_pat.finditer(line):
                    src_ids.setdefault(m.group(1), []).append("%s:%d" % (relp, lineno))

    missing = sorted(k for k in src_ids if k not in pot_ids)

    # 判据 2：pot 里每条都有非空译文
    po_entries, _obsolete = parse_po(
        os.path.join(ROOT, "locale/zh_CN/LC_MESSAGES/unix_script.po"))
    untranslated = sorted(k for k in pot_ids if not po_entries.get(k))

    failed = False
    if missing:
        failed = True
        print("i18n-extract: %d msgid(s) in source but NOT extracted into the pot"
              % len(missing), file=sys.stderr)
        print("  (gettext dropped them silently - runtime would fall back to English)",
              file=sys.stderr)
        for k in missing:
            print("  len=%d %r" % (len(k), k[:100]), file=sys.stderr)
            print("       at %s" % ", ".join(src_ids[k][:3]), file=sys.stderr)
    if untranslated:
        failed = True
        print("i18n-extract: %d msgid(s) in the pot have NO zh_CN translation"
              % len(untranslated), file=sys.stderr)
        for k in untranslated:
            print("  len=%d %r" % (len(k), k[:100]), file=sys.stderr)
    if failed:
        return 1
    print("i18n-extract: OK - %d source msgids, %d pot entries, all translated"
          % (len(src_ids), len(pot_ids)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
