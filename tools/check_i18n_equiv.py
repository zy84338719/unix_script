#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""文案保真门禁：迁移后的输出必须与迁移前逐字等价。

背景
----
i18n 迁移把中文文案换成 _t/_tf 调用，译文进 po。手工改写最容易出两类错：

1. **漏字**：原文里的一段中文在译文里没了（或者被 msgmerge 猜到了别的模块的译文）。
2. **吞装饰**：emoji（🚀 🎉 ✅ ❌ ⚠️）被当噪声删掉，或者原文里的 ASCII 装饰
   （``**`` 之类）丢掉。help/status 的等价比对查不到它们 —— 那些字符串只在
   install 路径上出现。

判据（都是「不许变少」的单向约束，不会误报）：

* **中文用字**：基线里被引号包裹的中文字符，必须都出现在本模块用到的 msgid 的
  译文里。少了 ⇒ 那段输出变了。
* **装饰符号**：基线里的 emoji/符号（含变体选择符）计数，必须与迁移后一致。
  少了 ⇒ 输出变了。

基线默认取 Stage 3 之前的提交（7729437），可用环境变量 UXS_I18N_BASELINE 覆盖。
没有 git 或基线不存在时跳过（不当失败）。
"""
import collections
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.environ.get('UXS_I18N_BASELINE', '7729437')
BATCH_DIRS = ['services', 'sys-tools', 'dev-tools', 'essentials', 'ai-tools']

HAN = re.compile(r'[\u4e00-\u9fff]')
DQUOTE = re.compile(r'"(?:[^"\\\n]|\\.)*"')
SQUOTE = re.compile(r"'(?:[^'\\\n]|\\.)*'")
HEREDOC_START = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
MSGID_USE = re.compile(r"(?<![A-Za-z0-9_])_t(f)?\s+('([^']*)'|\"([^\"]*)\")")


def is_decoration(ch):
    """装饰符号：非 CJK 的符号/emoji（不算中文，也不算全角标点）。"""
    cp = ord(ch)
    if 0x4E00 <= cp <= 0x9FFF:      # CJK 统一表意文字
        return False
    if 0x3000 <= cp <= 0x303F:      # CJK 标点
        return False
    if 0xFF00 <= cp <= 0xFFEF:      # 全角形式
        return False
    if 0x00A0 <= cp <= 0x00FF:      # Latin-1 补充
        return False
    if cp < 0x2000:
        return False
    return True


def strip_heredocs(text):
    """把 heredoc 正文整段挖掉（那里面多半是写盘的配置模板，不是 UI 文案）。"""
    out = []
    in_here = None
    for line in text.split('\n'):
        if in_here is not None:
            if line.strip() == in_here:
                in_here = None
            continue
        m = HEREDOC_START.search(line)
        if m:
            in_here = m.group(2)
            continue
        out.append(line)
    return '\n'.join(out)


def quoted_literals(text):
    """取出被引号包裹的中文字面量（跳过注释行）。

    嵌套的引号串只算**外层**那个。
    背景（2026-11-11 实录）：双引号里套单引号
    （"journal：$(… || echo '读取失败')"）会被 DQUOTE 与 SQUOTE 各数一次
    ⇒ 同一个汉字被数两遍 ⇒ 门禁误报「译文少了汉字」。
    故先收集全部引号区间，再丢掉被别的区间**包含**的那些。
    """
    lits = []
    for line in strip_heredocs(text).split('\n'):
        if line.lstrip().startswith('#'):
            continue
        spans = []
        for rx in (DQUOTE, SQUOTE):
            for mm in rx.finditer(line):
                spans.append((mm.start(), mm.end(), mm.group(0)[1:-1]))
        for (s, e, content) in spans:
            nested = False
            for (s2, e2, _) in spans:
                if (s2, e2) == (s, e):
                    continue
                if s2 <= s and e <= e2:
                    nested = True
                    break
            if nested:
                continue
            if HAN.search(content):
                lits.append(content)
    return lits


def all_chars(text):
    return collections.Counter(c for c in text if HAN.match(c))


def decorations(text):
    return collections.Counter(c for c in text if is_decoration(c))


def used_msgids(text):
    out = []
    for mm in MSGID_USE.finditer(text):
        lit = mm.group(2)
        out.append(lit[1:-1])
    return out


# 有意的行为变更：基线里用**中文**做 sed 匹配模式，迁移后必须换成语言无关的
# 标记（否则英文环境下卸载删不掉 rc 里的残留行）⇒ 基线的中文片段不再出现。
# 这些是刻意改的，不该被保真门禁反复报。
EXEMPT_FILES = {
    # go：rc 里写的是「# >>> unix_script go >>>」，基线是「Go 环境」
    'dev-tools/go/install.sh': ('Go 环境',),
    # nvm：卸载时的 sed 模式不再匹配中文「nvm 配置」
    'essentials/nvm/install.sh': ('nvm 配置',),
}
EXEMPT_LITERALS = (
    # go：rc 里写的是「# >>> unix_script go >>>」，基线是「Go 环境」
    (r'Go 环境',
     r'/usr/local/go/bin',
     r'GOPATH'),
    # nvm：卸载时的 sed 模式不再匹配中文「nvm 配置」
    (r'NVM_DIR',
     r'nvm.sh',
     r'nvm 配置'),
)


def is_exempt(rel, lit):
    kws = EXEMPT_FILES.get(rel)
    if not kws:
        return False
    return any(k in lit for k in kws)


def parse_po(path):
    """解析 .po：返回 {msgid: msgstr}（支持折行）。"""
    table = {}
    if not os.path.isfile(path):
        return table
    msgid = None
    msgstr = None
    state = None

    def flush():
        if msgid is not None:
            table[msgid] = msgstr if msgstr is not None else ''

    for line in io.open(path, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('msgid '):
            flush()
            msgid = eval_po_string(line[len('msgid '):])
            msgstr = None
            state = 'id'
        elif line.startswith('msgstr '):
            msgstr = eval_po_string(line[len('msgstr '):])
            state = 'str'
        elif line.startswith('"'):
            piece = eval_po_string(line)
            if state == 'id':
                msgid = (msgid or '') + piece
            elif state == 'str':
                msgstr = (msgstr or '') + piece
    flush()
    return table


def eval_po_string(text):
    text = text.strip()
    try:
        return eval(text)  # noqa: S307 - po 里的字符串字面量，格式固定
    except Exception:
        return ''


def git_show(ref, rel):
    proc = subprocess.run(['git', 'show', '%s:%s' % (ref, rel)],
                          cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        return None
    return proc.stdout.decode('utf-8', 'replace')


def main():
    po = os.path.join(ROOT, 'locale/zh_CN/LC_MESSAGES/unix_script.po')
    table = parse_po(po)
    if not table:
        print('check_i18n_equiv: 无法解析 %s，跳过' % po)
        return 0

    if subprocess.run(['git', 'cat-file', '-e', '%s^{commit}' % BASELINE],
                      cwd=ROOT, stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode != 0:
        print('check_i18n_equiv: 基线 %s 不存在，跳过' % BASELINE)
        return 0

    violations = 0
    checked = 0
    for d in BATCH_DIRS:
        ddir = os.path.join(ROOT, d)
        if not os.path.isdir(ddir):
            continue
        for name in sorted(os.listdir(ddir)):
            rel = '%s/%s/install.sh' % (d, name)
            path = os.path.join(ddir, name, 'install.sh')
            if not os.path.isfile(path):
                continue
            old = git_show(BASELINE, rel)
            if old is None:
                continue
            new = io.open(path, encoding='utf-8').read()
            # 模块级聚合：基线侧与当前侧都取「该模块目录下所有 .sh」。
            # 有些模块把逻辑拆到子文件（safe-rm 的 guard.sh、zsh_setup 的 lib/），
            # 只看 install.sh 会把「文案搬到另一个文件」误判成「文案丢了」。
            mod_dir = os.path.join(ddir, name)
            agg_old, agg_new, agg_mids = [], [], []
            for _f in sorted(os.listdir(mod_dir)):
                if not _f.endswith('.sh'):
                    continue
                _old_f = git_show(BASELINE, '%s/%s/%s' % (d, name, _f))
                _new_f = io.open(os.path.join(mod_dir, _f), encoding='utf-8').read()
                if _old_f is not None:
                    agg_old.append(_old_f)
                agg_new.append(_new_f)
                agg_mids.extend(used_msgids(_new_f))
            agg_old_text = '\n'.join(agg_old)
            agg_new_text = '\n'.join(agg_new)
            if '_t ' not in new and '_t(' not in new:
                continue  # 还没迁的模块，不在本门禁范围
            checked += 1

            # --- 1. 中文用字不许少 ---
            old_han = all_chars('\n'.join(
                lit for lit in quoted_literals(old) if not is_exempt(rel, lit)))
            mids = used_msgids(new)
            new_han = collections.Counter()
            for mid in mids:
                new_han += all_chars(table.get(mid, ''))
            missing_han = old_han - new_han
            if missing_han:
                violations += 1
                print('check_i18n_equiv: %s 译文少了汉字 %s'
                      % (rel, ''.join(sorted(missing_han))))
                for mid in mids:
                    ms = table.get(mid, '')
                    if not ms:
                        print('    未译 msgid: %r' % mid)

            # --- 1b. 每条基线字面量都要有「对应」的译文 ---
            # 聚合判据（1）只能查出「整体少了字」；这一条查「某条字面量没有对应译文」
            # —— 典型症状是 msgid 写对了、msgstr 却被灌成了别的模块的说法
            # （实测 caddy 的「服务状态：」被灌成「查看状态」）。
            # 一条字面量可能被拆成几个 msgid（变量在中间断开），所以只要求
            # 「至少有一条译文的汉字是这条字面量汉字的子集」。
            for lit in quoted_literals(old):
                # 含变量展开的片段是「变量把中文切开」留下的残片
                # （"已为 $(basename " 这种），它本身不是一条文案 ⇒ 跳过。
                if '$(' in lit or '\${' in lit:
                    continue
                if is_exempt(rel, lit):
                    continue
                lh = set(all_chars(lit))
                if not lh:
                    continue
                # 覆盖率判据：译文汉字里至少 60% 出现在原字面量里。
                # 用覆盖率而不是「子集」，是为了容忍「以下链接」这类补词；
                # 但「查看状态」对「服务状态：」只有 50% ⇒ 仍判失败。
                hit = False
                for mid in mids:
                    sh = set(all_chars(table.get(mid, '')))
                    if not sh:
                        continue
                    # 只有一个字的译文（如「（经 lima/colima/SSH）」里的「经」）
                    # 要求它确实出现在原字面量里，否则容易撞车
                    if len(sh) == 1 and not sh <= lh:
                        continue
                    # 「字面量的字都在译文里」—— 这是「没少字」的判据，
                    # 比覆盖率更贴近「这条文案有对应译文」。
                    if lh <= sh:
                        hit = True
                        break
                    # 覆盖率判据：译文汉字里至少 60% 出现在原字面量里。
                    # 容忍「以下链接」这类补词；但「查看状态」对「服务状态：」
                    # 只有 50% ⇒ 仍判失败。
                    if len(sh & lh) * 10 >= len(sh) * 6:
                        hit = True
                        break
                if not hit:
                    violations += 1
                    print('check_i18n_equiv: %s 字面量没有对应译文: %r' % (rel, lit))
                    for mid in mids:
                        print('    候选 msgid: %r -> %r' % (mid, table.get(mid, '')))

            # --- 2. 装饰符号不许变 ---
            # 用户看到的是「译文」，不是英文 msgid —— 所以先把新源码里的 msgid
            # 字面量摘掉（它们是英文，可能用不同的标点），再把译文里的装饰加回来。
            new_out = MSGID_USE.sub('', agg_new_text)
            old_dec = decorations(agg_old_text)
            new_dec = decorations(new_out)
            for mid in agg_mids:
                new_dec += decorations(table.get(mid, ''))
            lost = old_dec - new_dec
            if lost:
                violations += 1
                print('check_i18n_equiv: %s 丢了装饰符号 %s'
                      % (rel, ''.join(sorted(lost))))

    if violations:
        return 1
    print('check_i18n_equiv: ok（%d 个模块）' % checked)
    return 0


if __name__ == '__main__':
    sys.exit(main())
