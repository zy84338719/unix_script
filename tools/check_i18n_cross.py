#!/usr/bin/env python3
"""校验译文没有「串味」—— msgid 说的是 A 模块，译文却写的是 B 模块的文案。

背景：msgmerge 默认做模糊匹配，把新增 msgid 猜匹配到别的条目的旧译文上。
带 fuzzy 标记的被 msgfmt 排除（运行时回落英文，这条还算好）；
但**没被标记**的那些会把错译文直接留下 —— 用户看到的是别的模块的文案
（实测 buildah 的卸载说明写着「卸载面板…/www」，那是 CasaOS 的）。

判据：模块专属名词的集合必须一致。
  msgid 里出现的专属名词（buildah / CasaOS / Caddy…），译文里必须都出现；
  译文里可以多出现别的专属名词 —— 那是正当提及
  （containerd 的说明提到 Docker CLI 是对的）。
  ⇒ 判据是「msgid 的专属名词集合 ⊆ 译文的专属名词集合」。

另有一条独立判据：译文里同一句话重复两遍 ⇒ 灌译文时拼接过。

用法：python3 tools/check_i18n_cross.py [兜底表路径]
退出码：0 一致；1 有问题
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEFAULT_TABLE = os.path.join(ROOT, 'locale', 'zh_CN', 'messages', 'unix_script.sh')
TABLE = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_TABLE

if not os.path.isfile(TABLE):
    sys.stderr.write('check_i18n_cross: 找不到兜底表 %s（先跑 bash po/messages.sh）\n' % TABLE)
    sys.exit(1)

# 模块专属名词：英文名 → 中文名（大小写不敏感匹配）。
# ⚠️ 加新模块时要同步这张表 —— 漏了它，新模块的串味就查不出来。
EXCLUSIVE = [
    ('buildah', 'buildah'),
    ('casaos', 'CasaOS'),
    ('1panel', '1Panel'),
    ('btpanel', '宝塔'),
    ('caddy', 'Caddy'),
    ('certbot', 'Certbot'),
    ('cockpit', 'Cockpit'),
    ('nerdctl', 'nerdctl'),
    ('ddns-go', 'ddns-go'),
    ('docker', 'Docker'),
    ('containerd', 'containerd'),
]

LINE_RE = re.compile(r"^    '((?:[^']|'')*)'\) printf '%s' '((?:[^']|'')*)' ;;$", re.M)

text = io.open(TABLE, encoding='utf-8').read()
pairs = LINE_RE.findall(text)

violations = []

for key, val in pairs:
    key = key.replace("''", "'")
    val = val.replace("''", "'")
    if not key.strip():
        continue

    kl = key.lower()
    vl = val.lower()
    missing = []
    for en, zh in EXCLUSIVE:
        if en in kl and zh.lower() not in vl:
            missing.append(zh)
    if missing:
        violations.append(('串味（译文没提 %s）' % '/'.join(missing), key, val))

    half = len(val) // 2
    if half > 8 and val[:half] == val[half:]:
        violations.append(('译文重复了两遍', key, val))

for kind, key, val in violations:
    sys.stderr.write('check_i18n_cross: %s\n' % kind)
    sys.stderr.write('  msgid = %s\n' % key)
    sys.stderr.write('  译文  = %s\n' % val)

if violations:
    sys.stderr.write('check_i18n_cross: 发现 %d 处问题\n' % len(violations))
    sys.exit(1)

print('check_i18n_cross: ok')
