# Stage 1 实施计划：shellkit 能力补齐 + unix_script lib 换壳

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 shellkit 补齐 unix_script 需要的 10 处通用能力，并让 unix_script 的 `lib/` 层改为调用这些能力，行为保持逐字一致。

**Architecture:** 两仓库单向依赖 —— unix_script → shellkit。shellkit 侧全部是**新增函数/新增模块**（既有函数语义不动，遵守 shellkit 0.x「只加不改」纪律）；unix_script 侧保留 `lib/uxs_compat.sh` 转发门面，让 78 个模块脚本在 Stage 3 迁移完成前继续可用。

**Tech Stack:** Bash 3.2+（macOS 自带 /bin/bash 即基线）、gettext（可选，缺失时走纯 bash 兜底）、shellcheck、shfmt、git

**上游规格：** `docs/superpowers/specs/2026-11-10-shellkit-refactor-design.md`（本仓 unix_script）

---

## Global Constraints

以下约束对**每个任务**都成立：

- **bash 3.2 基线**：禁用 `declare -A`、`${v^^}`/`${v,,}`、`mapfile`、`[[ -v x ]]`、`readarray`、`local -n`。
  空数组展开一律写 `${arr[@]+"${arr[@]}"}`。
- **shellkit 内部命名空间**：`lib/` 与 `shellkit` 里的局部变量一律 `__` 前缀（`tools/check_local_names.sh` 会查）。
- **公开函数的返回码必须写进注释**：紧邻函数上方写 `# @exitcode N 说明`（`tools/check_exitcode_docs.sh` 会查）。
- **公开出参入口必须调 `_sk_check_out_name`**（同上）。
- **stdout 只给数据，日志一律 stderr**；出参用 `printf -v`。
- **管道里不得有提前退出的消费者**（`grep -q` / `head` 会把上游打成 SIGPIPE，pipefail 下竞态失败）——
  `tools/check_pipe_safety.sh` 会查。
- **文案一律 `_t 'english msgid'`**（msgid 英文），译文进 `locale/<lang>/LC_MESSAGES/<domain>.po`。
- **新增 shellkit 模块必须三处齐改**：`lib/core/<name>.sh` + `lib/modules.txt` 一行（拓扑序 + 依赖声明）+ `tests/test_<name>.sh`。
- **shellkit 门禁必须全绿**：`cd /Users/zhangyi/shellkit && make check`。
  本机注意：`make test` 的 recipe 写的是 `@bash tests/run.sh`（走 PATH），本机 PATH 上的 bash 是 brew 的 5.3；
  要验 3.2 基线必须显式 `/bin/bash tests/run.sh`。
- **unix_script 门禁必须全绿**：`cd /Users/zhangyi/unix_script && bash tests/ci_run.sh --phase static`。
- **本计划的两个仓库路径**：
  - shellkit：`/Users/zhangyi/shellkit`（独立 git 仓，当前分支 `main`）
  - unix_script：`/Users/zhangyi/unix_script`（独立 git 仓，本计划在分支 `refactor/shellkit-stage1` 上工作）
- **不在本计划范围内**：CLI 重设计（Stage 2）、78 个模块脚本迁移与 msgid 化（Stage 3）、发版（Stage 4）。
- **新增模块的任务必须同时更新文档产物与模块数**：shellkit 的 `make check` 里含
  `docs-check`（生成物必须与源码一致）与 `module-count-check`（文档里的模块数必须等于
  `lib/modules.txt` 的行数）。所以**每个新增模块的任务（Task 4/5/6/7/8）**都要：
  ① 跑 `make docs` 重生成 `docs/REFERENCE.md`、`AGENTS.md`、`skills/shellkit/SKILL.md`；
  ② 把 `README.md`、`docs/MIGRATING.md`、`site/index.md`、`site/guide/index.md`、
  `site/guide/modules.md`、`site/guide/faq.md` 与英文站对应页面里的模块数改成新值；
  ③ 把这些生成物与文档改动**一起提交**（否则该任务的 `make check` 必然红）。
  Task 12 因此只做最终核对与 CHANGELOG。

### Stage 1 的关键范围决定（与规格 §7.2 的细化）

规格 §7.2 写的是「`lib/common.sh` 拆解为转发门面」。实施时必须再分一刀，否则 Stage 1 的
「快照零差异」承诺无法成立：

| 类别 | 例子 | Stage 1 处置 | 理由 |
|---|---|---|---|
| **能力函数** | `pkg_install` `verify_sha256` `uxs_svc` `version_gt` `detect_distro` `github_latest_tag` `uxs_with_timeout` `emit_status` | 换成 shellkit 实现（转发门面保号） | 与输出格式无关，可逐字等价 |
| **呈现函数** | `info` `success` `warn` `error` `header` `menu` | **Stage 1 不动**，保留 unix_script 自己的实现 | ① 走 stdout 而非 stderr ② 标签是 `[SUCCESS]`/`[WARNING]` 而非 `[ OK ]`/`[WARN]` ③ AI agent 与快照都依赖这个形状 |
| **领域逻辑** | `detect_distro` 的麒麟词表、`ensure_epel`、manifest 字段语义 | Stage 1 保留在 unix_script（转发到 shellkit 的通用实现） | 领域知识不塞进通用库 |

呈现函数与 msgid 化的收敛在 **Stage 3 随 78 个模块迁移一起做**（那时每个模块的文案本来就要重写）。

---

## 文件结构

### shellkit 仓（`/Users/zhangyi/shellkit`）

```
lib/core/
  i18n.sh      改：多域查找 + 纯 bash 兜底表（既有 _t 签名与默认行为不变）
  os.sh        改：新增发行版/桌面检测、提权包管理、sudo 就绪（既有 os_pkg_* 语义不动）
  http.sh      改：新增 GitHub release 查询
  run.sh       改：新增超时包装与 sudo 遮蔽安装
  str.sh       改：新增 str_suggest
  svc.sh       新增：systemd/launchd 服务动词
  ver.sh       新增：版本比较
  status.sh    新增：机器可读状态契约
  registry.sh  新增：KV 清单注册表 + 依赖拓扑
  profile.sh   新增：profile 文件格式原语
lib/modules.txt    改：新增 5 个模块（拓扑序）
locale/<lang>/messages/<domain>.sh   新增：纯 bash 兜底表（构建产物，入库）
po/messages.sh     改：多生成兜底表
po/po_to_sh.awk    新增：.po → 纯 bash 兜底表
tests/test_{i18n,os,http,run,str,svc,ver,status,registry,profile}.sh   新增/改
docs/REFERENCE.md / AGENTS.md / skills/shellkit/SKILL.md   改：由 make docs 重生成
README.md / site/*.md    改：模块数 18 → 23
```

### unix_script 仓（`/Users/zhangyi/unix_script`）

```
tools/snapshot.sh          新增：确定性输出采集器
tools/check_snapshot.sh    新增：快照比对门禁
tools/check_status_shape.sh 新增：状态输出结构判据
tools/check_vendor.sh      新增：shellkit 副本一致性门禁
tests/snapshot/<os>-<arch>/*.txt   新增：基线（入库）
lib/uxs_compat.sh          新增：旧符号 → shellkit 的转发门面
lib/uxs_i18n.sh            新增：shellkit i18n 域与目录配置
lib/common.sh              改：能力函数删除（移入 uxs_compat.sh），呈现函数保留
lib/registry.sh            改：扫描/查询改调 registry_*
lib/deps.sh                改：拓扑排序改调 registry_deps/registry_topo
lib/status.sh              改：改调 status_*
lib/profile.sh             改：改调 profile_*
vendor/shellkit/           新增：shellkit 副本（由 shellkit vendor 生成，入库）
```

---

## Task 0: 建分支与行为快照门禁（unix_script）

**Files:**
- Create: `tools/snapshot.sh`
- Create: `tools/check_snapshot.sh`
- Create: `tests/snapshot/<os>-<arch>/{list,list-modules,list-categories}.txt`
- Modify: `.github/workflows/ci.yml`（加一步快照比对）

**Interfaces:**
- Produces: `tools/snapshot.sh [OUT_DIR]` —— 采集确定性输出到 `OUT_DIR`（默认 `tests/snapshot/<os>-<arch>`）
- Produces: `tools/check_snapshot.sh` —— 重新采集到临时目录并与基线逐字比对；有差异退出 1，无差异退出 0
- 基线缺失时 `check_snapshot.sh` 退出 2 并提示「先跑 tools/snapshot.sh 生成基线」（CI 里视为失败）

**为什么只快照这三项：** `--status-json` 与各模块 `status` 的输出依赖**本机实际安装状态**，
基线在不同机器上必然不同，做成逐字基线等于制造假红。这两项改为**结构判据**（见 Task 16）。
确定性输出只有模块清单类：`--list`（模块名，空格分隔）、`--list-modules`（TSV）、`--list-categories`。

- [ ] **Step 1: 开分支**

```bash
cd /Users/zhangyi/unix_script
git checkout -b refactor/shellkit-stage1
git status --short   # 期望：干净
```

- [ ] **Step 2: 写采集器 `tools/snapshot.sh`**

```bash
#!/usr/bin/env bash
#
# 采集 unix_script 的确定性输出，作为重构前后的行为基线。
#
# 只采「同一台机器上多次运行结果一致」的输出：模块清单类。
# --status-json / 各模块 status 依赖本机安装状态，跨机器必然不同，
# 那两项改成结构判据（见 tools/check_status_shape.sh），不做逐字基线。
#
# 用法：
#   bash tools/snapshot.sh            # 写入 tests/snapshot/<os>-<arch>/
#   bash tools/snapshot.sh /tmp/out   # 写入指定目录
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
OUT_DIR="${1:-$ROOT/tests/snapshot/${OS}-${ARCH}}"

# LC_ALL=C：目录 glob 的排序受 locale 影响，不固定就会在不同机器上排出不同顺序，
# 基线随之漂移 —— 那是环境差异，不是行为变化。
export LC_ALL=C

mkdir -p "$OUT_DIR"

cd "$ROOT"
for __spec in "list:--list" "list-modules:--list-modules" "list-categories:--list-categories"; do
  __name="${__spec%%:*}"
  __args="${__spec#*:}"
  # shellcheck disable=SC2086
  ./install.sh $__args >"$OUT_DIR/$__name.txt"
  printf 'snapshot: %s -> %s\n' "$__name" "$OUT_DIR/$__name.txt" >&2
done
```

- [ ] **Step 3: 写比对门禁 `tools/check_snapshot.sh`**

```bash
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
```

- [ ] **Step 4: 生成基线并确认可重复**

```bash
cd /Users/zhangyi/unix_script
bash tools/snapshot.sh
bash tools/snapshot.sh /tmp/uxs-snap-2
diff -r tests/snapshot/$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m) /tmp/uxs-snap-2
```
期望：diff 无输出（同一台机器两次采集逐字一致）。

- [ ] **Step 5: 验证门禁会抓差异**

```bash
cd /Users/zhangyi/unix_script
BASE=tests/snapshot/$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)
cp "$BASE/list.txt" /tmp/list.txt.bak
printf 'zzz-fake-module\n' >>"$BASE/list.txt"
bash tools/check_snapshot.sh; echo "exit=$?"   # 期望 exit=1
cp /tmp/list.txt.bak "$BASE/list.txt"
bash tools/check_snapshot.sh; echo "exit=$?"   # 期望 exit=0
```

- [ ] **Step 6: 接进 CI**

在 `.github/workflows/ci.yml` 的测试 job 里加一步：

```yaml
      - name: 行为快照比对
        run: bash tools/check_snapshot.sh
```

- [ ] **Step 7: 提交**

```bash
cd /Users/zhangyi/unix_script
git add tools/snapshot.sh tools/check_snapshot.sh tests/snapshot .github/workflows/ci.yml
git commit -m "test(snapshot): 建行为快照门禁 —— 重构前后逐字比对模块清单输出"
```

---

## Task 1: shellkit `i18n` —— 多域查找 + 纯 bash 兜底表

**Files:**
- Modify: `lib/core/i18n.sh`
- Create: `po/po_to_sh.awk`
- Modify: `po/messages.sh`
- Create: `locale/<lang>/messages/<domain>.sh`（生成物，入库）
- Modify: `tests/test_i18n.sh`

**Interfaces:**
- Consumes: 既有 `_t`、`_tn`
- Produces:
  - `SHELLKIT_I18N_DOMAIN` —— 域名，默认 `${TEXTDOMAIN:-shellkit}`
  - `SHELLKIT_I18N_DIRS` —— 冒号分隔的查找目录，默认 `$SHELLKIT_HOME/locale`
  - `SHELLKIT_LANG` —— 语言目录名（如 `zh_CN`），默认从 `LC_ALL`/`LC_MESSAGES`/`LANG` 取，取不到用 `en`
  - 纯 bash 兜底表文件：`<dir>/<lang>/messages/<domain>.sh`，内容定义 `_sk_msg_lookup_<domain>`
    （domain 里的非 `[a-z0-9_]` 字符换成 `_`）

**纪律：** 不设任何新环境变量时，`_t` 的行为与现状**逐字一致** ⇒ 属「只加不改」。

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_i18n.sh`（若不存在则新建，先 `. "$TEST_ROOT/lib/bootstrap.sh"`）：

```bash
# --- 多域：SHELLKIT_I18N_DOMAIN 指向另一个域 ---
d="$(tmpdir)"
mkdir -p "$d/locale/zh_CN/messages"
cat >"$d/locale/zh_CN/messages/other.sh" <<'EOF'
_sk_msg_lookup_other() {
  case "$1" in
    'probe message') printf '%s' '探针消息' ;;
    *) return 1 ;;
  esac
}
EOF

out=$(SHELLKIT_LANG=zh_CN SHELLKIT_I18N_DOMAIN=other \
      SHELLKIT_I18N_DIRS="$d/locale" _t 'probe message')
assert_eq "探针消息" "$out" "i18n falls back to the pure-bash table"

# 未命中的 msgid 原样返回
out=$(SHELLKIT_LANG=zh_CN SHELLKIT_I18N_DOMAIN=other \
      SHELLKIT_I18N_DIRS="$d/locale" _t 'not translated')
assert_eq "not translated" "$out" "i18n returns msgid when nothing matches"
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_i18n.sh; echo "exit=$?"
```
期望：exit=1，报 `i18n falls back to the pure-bash table`。

- [ ] **Step 3: 实现 `lib/core/i18n.sh` 的多域与兜底**

在既有 `_t` 之前插入：

```bash
# 语言目录名：SHELLKIT_LANG 优先，否则从 LC_ALL / LC_MESSAGES / LANG 取，
# 取不到用 en。zh_CN.UTF-8 → zh_CN。
_sk_i18n_lang() {
  local __l="${SHELLKIT_LANG:-}"
  if [ -z "$__l" ]; then
    __l="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"
  fi
  __l="${__l%%.*}"      # 去掉 .UTF-8
  __l="${__l%%@*}"       # 去掉 @modifier
  [ -n "$__l" ] || __l='en'
  printf '%s' "$__l"
}

# 域名：SHELLKIT_I18N_DOMAIN 优先，否则 TEXTDOMAIN，再否则 shellkit
_sk_i18n_domain() {
  printf '%s' "${SHELLKIT_I18N_DOMAIN:-${TEXTDOMAIN:-shellkit}}"
}

# 查找目录列表：SHELLKIT_I18N_DIRS 优先，否则 SHELLKIT_HOME/locale
_sk_i18n_dirs() {
  printf '%s' "${SHELLKIT_I18N_DIRS:-$SHELLKIT_HOME/locale}"
}

# 域名的函数名后缀：非 [a-z0-9_] 一律换成 _
_sk_i18n_fn_suffix() {
  printf '%s' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_')"
}

# 兜底表函数名：_sk_msg_lookup_<domain>
_sk_i18n_table_fn() {
  printf '%s' "_sk_msg_lookup_$(_sk_i18n_fn_suffix "$1")"
}

# 载入纯 bash 兜底表（每个 目录/域 组合只载一次）。
# 表文件：<dir>/<lang>/messages/<domain>.sh，里面定义 _sk_msg_lookup_<domain>。
_sk_i18n_load_tables() {
  local __lang __dir __domain __fn
  __lang="$(_sk_i18n_lang)"
  for __dir in $(_sk_i18n_dirs | tr ':' ' '); do
    for __domain in "$(_sk_i18n_domain)" 'shellkit'; do
      __fn="$(_sk_i18n_table_fn "$__domain")"
      case " $_SK_I18N_TABLES " in
        *" $__fn "*) continue ;;
      esac
      if [ -r "$__dir/$__lang/messages/$__domain.sh" ]; then
        # shellcheck disable=SC1090
        . "$__dir/$__lang/messages/$__domain.sh" || continue
        _SK_I18N_TABLES="${_SK_I18N_TABLES:-} $__fn"
      fi
    done
  done
  return 0
}
```

兜底表清单是全局变量，模块加载时初始化一次：

```bash
_SK_I18N_TABLES=""
_sk_i18n_load_tables
```

`_t` 改成「先查域表，再查兜底表，最后原样输出」：

```bash
_t() {
  local __msg="${1:-}" __out __fn __dom
  __dom="$(_sk_i18n_domain)"
  if [ -n "${SK_GETTEXT:-}" ]; then
    for __fn in "$__dom" 'shellkit'; do
      [ "$__fn" = "$__dom" ] && [ "$__fn" = 'shellkit' ] && continue
      for __dir in $(_sk_i18n_dirs | tr ':' ' '); do
        if [ -r "$__dir/$(_sk_i18n_lang)/LC_MESSAGES/$__fn.mo" ]; then
          case "$__msg" in
            -*) out=$(TEXTDOMAINDIR="$__dir" "$SK_GETTEXT" -- "$__msg") ;;
            *) out=$(TEXTDOMAINDIR="$__dir" "$SK_GETTEXT" "$__msg") ;;
          esac
          printf '%s' "$__out"
          return 0
        fi
      done
    done
  fi
  for __fn in ${_SK_I18N_TABLES:-}; do
    out="$(__fn "$__msg")" || continue
    if [ -n "$__out" ]; then
      printf '%s' "$__out"
      return 0
    fi
  done
  printf '%s' "$__msg"
}
```

- [ ] **Step 4: 写 `po/po_to_sh.awk`（.po → 纯 bash 兜底表）**

```awk
# 把 .po 翻译表编译成纯 bash 查表函数。
#
#   awk -f po_to_sh.awk locale/zh_CN/LC_MESSAGES/shellkit.po > locale/zh_CN/messages/shellkit.sh
#
# 为什么要这一步：gettext 不是所有机器都有（macOS 默认没有）。
# 缺 gettext 时 _t 会回落成英文 msgid —— 对「中文优先」的产品就是整片输出变英文。
# 这张表是纯 bash 的兜底：一个巨型 case，查一次 O(1)，不依赖任何外部工具。
#
# 处理要点：
#   1. msgid / msgstr 可以跨多行（续行以 " 开头），要拼起来
#   2. msgstr 为空的条目跳过（未翻译，让它回落成 msgid）
#   3. case 的 pattern 里 * ? [ ] 是通配符，必须转义
#   4. 单引号要转成 ''' 才能安全放进 shell 单引号串
BEGIN {
  print "# 本文件由 po/messages.sh 生成，请勿手改。"
  print "# 纯 bash 兜底查表：没有 gettext 时 _t 用它出译文。"
  print "_sk_msg_lookup_shellkit() {"
  print "  case "$1" in"
}
/^msgid[ 	]+"/ {
  if (msgid != "") flush()
  msgid = unquote($0)
  msgstr = ""
  next
}
/^msgstr[ 	]+"/ {
  msgstr = unquote($0)
  next
}
/^"/ {
  piece = unquote($0)
  if (msgid != "" && msgstr == "") msgid = msgid piece
  else if (msgstr != "") msgstr = msgstr piece
  next
}
END { if (msgid != "") flush() ; print "  esac" ; print "}" }

function flush() {
  if (msgid == "" || msgstr == "") { msgid = "" ; msgstr = "" ; return }
  printf "    %s) printf '%%s' %s ;;
", pat(msgid), sq(msgstr)
  msgid = "" ; msgstr = ""
}
# 取引号里的内容并解开转义
function unquote(s,   t) {
  t = s
  sub(/^[^"]*"/, "", t)
  sub(/"[ 	]*$/, "", t)
  gsub(/\\n/, "\n", t)
  gsub(/\\t/, "\t", t)
  gsub(/\\r/, "\r", t)
  gsub(/\\"/, "\"", t)
  gsub(/\\\\/, "\\", t)
  return t
}
# case 的 pattern：转义通配符
function pat(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/\*/, "\\*", s)
  gsub(/\?/, "\\?", s)
  gsub(/\[/, "\\[", s)
  return "'" s "'"
}
# shell 单引号串
function sq(s) {
  gsub(/'/, "'\\''", s)
  return "'" s "'"
}
```

> ⚠️ 上面 awk 里的转义在 markdown 里被反斜杠转义过一遍；**以本任务 Step 5 的自测为准**，
> 落地时先跑 Step 5 的往返测试（po → sh → 查表），不通过就按实际输出调转义。

- [ ] **Step 5: 验证 `po_to_sh.awk` 的往返正确**

```bash
cd /Users/zhangyi/shellkit
mkdir -p /tmp/po2sh
awk -f po/po_to_sh.awk locale/zh_CN/LC_MESSAGES/shellkit.po >/tmp/po2sh/shellkit.sh
bash -n /tmp/po2sh/shellkit.sh          # 语法必须过
# 抽查：含单引号或通配符的条目
grep -n "\\'" /tmp/po2sh/shellkit.sh | head -3
# 查表能查到已知译文
bash -c '. /tmp/po2sh/shellkit.sh; _sk_msg_lookup_shellkit "invalid command name"'
```
期望：最后一条打印 `非法的命令名`。

- [ ] **Step 6: 接进 `po/messages.sh`（生成兜底表）**

在 `po/messages.sh` 编译 `.mo` 之后追加：

```bash
# 生成纯 bash 兜底表：没有 gettext 的机器靠它出译文
for __lang_dir in "$ROOT"/locale/*/; do
  [ -d "$__lang_dir" ] || continue
  __lang="$(basename "$__lang_dir")"
  __po="${__lang_dir}LC_MESSAGES/shellkit.po"
  [ -f "$__po" ] || continue
  mkdir -p "$__lang_dir/messages"
  awk -f "$ROOT/po/po_to_sh.awk" "$__po" >"$__lang_dir/messages/shellkit.sh"
done
```

并在 `--check` 分支里加一条：把生成的表与入库的表逐字节比对，不一致即红。

- [ ] **Step 7: 跑测试与门禁**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_i18n.sh; echo "exit=$?"
bash po/messages.sh
make check
```
期望：测试通过；`make check` 全绿。

- [ ] **Step 8: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/i18n.sh po/messages.sh po/po_to_sh.awk locale tests/test_i18n.sh
git commit -m "feat(i18n): 多域查找 + 纯 bash 兜底表 —— 没有 gettext 也出译文"
```

---

## Task 2: shellkit `os` —— 发行版与桌面环境检测

**Files:**
- Modify: `lib/core/os.sh`
- Modify: `tests/test_os.sh`

**Interfaces:**
- Produces:
  - `os_release_field KEY [FILE]` —— 读 os-release 风格文件字段；恒 0
  - `os_distro_id [FILE]` —— 小写发行版 ID
  - `os_distro_family [FILE]` —— debian|rhel|suse|arch|alpine|unknown
  - `os_distro_name [FILE]` —— PRETTY_NAME
  - `os_desktop_env` —— ukui|dde|gnome|kde|xfce|mate|cinnamon|lxqt|budgie|none
  - `os_is_desktop` —— 0/1

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_os.sh`：

```bash
d="$(tmpdir)"
cat >"$d/os-release" <<'EOF'
ID=ubuntu
ID_LIKE=debian
VERSION_ID="22.04"
PRETTY_NAME="Ubuntu 22.04.4 LTS"
EOF

assert_eq "ubuntu" "$(os_distro_id "$d/os-release")" "os_distro_id reads ID"
assert_eq "debian" "$(os_distro_family "$d/os-release")" "os_distro_family uses ID_LIKE"
assert_eq "Ubuntu 22.04.4 LTS" "$(os_distro_name "$d/os-release")" "os_distro_name reads PRETTY_NAME"
assert_eq "22.04" "$(os_release_field VERSION_ID "$d/os-release")" "os_release_field strips quotes"

# 麒麟不在 ID 硬表里：靠 ID_LIKE 判定族
cat >"$d/kylin" <<'EOF'
ID=kylin
ID_LIKE="rhel centos"
EOF
assert_eq "rhel" "$(os_distro_family "$d/kylin")" "kylin server flavour maps to rhel"

assert_eq "none" "$(os_desktop_env)" "os_desktop_env returns a value"
if [ "$(os_desktop_env)" = 'none' ]; then
  assert_exit_code 1 os_is_desktop
else
  assert_exit_code 0 os_is_desktop
fi
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_os.sh; echo "exit=$?"
```
期望：exit=1（`os_distro_id: command not found`）。

- [ ] **Step 3: 实现**

追加到 `lib/core/os.sh`：

```bash
# os_release_field KEY [FILE] —— 读 os-release 风格文件的字段值
# 缺省依次尝试 /etc/os-release、/usr/lib/os-release；读不到返回空。
# @exitcode 0 总是成功（读不到时 stdout 为空）
os_release_field() {
  local __key=${1:-} __file=${2:-} __line
  if [ -z "$__key" ]; then
    log_error "$(_t 'Usage'): os_release_field KEY [FILE]"
    return "$SK_USAGE"
  fi
  if [ -z "$__file" ]; then
    for __file in /etc/os-release /usr/lib/os-release; do
      [ -r "$__file" ] && break
      __file=''
    done
  fi
  [ -n "$__file" ] && [ -r "$__file" ] || return 0
  __line="$(sed -n "s/^${__key}=[\"']\{0,1\}\([^\"']*\)[\"']\{0,1\}$/\1/p" "$__file" 2>/dev/null | sed -n '1p')"
  printf '%s' "$__line"
  return 0
}

# os_distro_id [FILE] —— 小写发行版 ID
# @exitcode 0 总是成功
os_distro_id() {
  printf '%s' "$(os_release_field ID "${1:-}" | tr '[:upper:]' '[:lower:]')"
}

# os_distro_name [FILE] —— 人类可读的发行版名称
# @exitcode 0 总是成功
os_distro_name() {
  local __n
  __n="$(os_release_field PRETTY_NAME "${1:-}")"
  [ -n "$__n" ] || __n="$(os_release_field NAME "${1:-}")"
  printf '%s' "$__n"
}

# os_distro_family [FILE] —— 包系族：debian|rhel|suse|arch|alpine|unknown
# 判定顺序：包管理器实测 → ID_LIKE 词表 → ID 词表。
# 麒麟（kylin）刻意不进 ID 硬表：服务器版基于 RHEL 系、桌面版基于 Ubuntu 系，
# 硬编码任一族都会误判一半场景。
# @exitcode 0 总是成功
os_distro_family() {
  local __file="${1:-}" __id __like
  if [ -z "$__file" ]; then
    # 主机模式：包管理器实测最不易误判
    if command -v apt-get >/dev/null 2>&1; then printf '%s' 'debian'; return 0; fi
    if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then printf '%s' 'rhel'; return 0; fi
    if command -v zypper >/dev/null 2>&1; then printf '%s' 'suse'; return 0; fi
    if command -v pacman >/dev/null 2>&1; then printf '%s' 'arch'; return 0; fi
    if command -v apk >/dev/null 2>&1; then printf '%s' 'alpine'; return 0; fi
    __file=''
  fi
  __id="$(os_distro_id "$__file")"
  __like="$(os_release_field ID_LIKE "$__file" | tr '[:upper:]' '[:lower:]')"
  case "$__like" in
    *debian*|*ubuntu*|*mint*) printf '%s' 'debian'; return 0 ;;
    *rhel*|*fedora*|*centos*|*euler*|*anolis*|*amzn*) printf '%s' 'rhel'; return 0 ;;
    *suse*) printf '%s' 'suse'; return 0 ;;
    *arch*|*manjaro*) printf '%s' 'arch'; return 0 ;;
    *alpine*) printf '%s' 'alpine'; return 0 ;;
  esac
  case "$__id" in
    debian|ubuntu|deepin|openkylin|uos|linuxmint|kali) printf '%s' 'debian'; return 0 ;;
    centos|rhel|rocky|almalinux|fedora|amzn|ol|openeuler|anolis) printf '%s' 'rhel'; return 0 ;;
    opensuse*|sles) printf '%s' 'suse'; return 0 ;;
    arch|manjaro) printf '%s' 'arch'; return 0 ;;
    alpine) printf '%s' 'alpine'; return 0 ;;
  esac
  printf '%s' 'unknown'
  return 0
}

# os_desktop_env —— 桌面环境：ukui|dde|gnome|kde|xfce|mate|cinnamon|lxqt|budgie|none
# @exitcode 0 总是成功
os_desktop_env() {
  local __clues='' __v __b
  for __v in "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}" "${DESKTOP_SESSION:-}"; do
    [ -n "$__v" ] || continue
    __clues="$__clues $(printf '%s' "$__v" | tr '[:upper:]' '[:lower:]')"
  done
  for __b in ukui-session kwin_x11 startdde dde-desktop gnome-session gnome-shell \
             plasmashell startplasma-x11 xfce4-session mate-session cinnamon-session lxsession; do
    command -v "$__b" >/dev/null 2>&1 && __clues="$__clues $__b"
  done
  case "$__clues" in
    *ukui*) printf '%s' 'ukui' ;;
    *dde*|*deepin*) printf '%s' 'dde' ;;
    *plasma*|*kde*) printf '%s' 'kde' ;;
    *gnome*) printf '%s' 'gnome' ;;
    *xfce*) printf '%s' 'xfce' ;;
    *mate*) printf '%s' 'mate' ;;
    *cinnamon*) printf '%s' 'cinnamon' ;;
    *lxqt*|*lxsession*) printf '%s' 'lxqt' ;;
    *budgie*) printf '%s' 'budgie' ;;
    *) printf '%s' 'none' ;;
  esac
  return 0
}

# os_is_desktop —— 当前是否在桌面环境里
# @exitcode 0 有桌面
# @exitcode 1 没有桌面
os_is_desktop() {
  if [ "$(os_desktop_env)" = 'none' ]; then
    return 1
  fi
  return 0
}
```

- [ ] **Step 4: 跑测试与门禁**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_os.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/os.sh tests/test_os.sh
git commit -m "feat(os): 发行版与桌面环境检测 —— 麒麟靠 ID_LIKE 判定，不进 ID 硬表"
```

---

## Task 3: shellkit `os` —— 提权包管理与 sudo 就绪

**Files:**
- Modify: `lib/core/os.sh`
- Modify: `tests/test_os.sh`

**Interfaces:**
- Produces:
  - `os_pkg_install_root PKG...` —— 提权安装（root 直跑，否则 sudo）
  - `os_pkg_remove_root PKG...`
  - `os_pkg_update_root`
  - `os_pkg_installed PKG` —— 0 已装
  - `os_sudo_ready` —— sudo 可用（root 直过；否则 `sudo -n true` 或提示一次 `sudo -v`）

> ⚠️ **既有 `os_pkg_install` / `os_pkg_update` 语义不动**（不提权、不支持 pacman/brew）。
> 新函数是独立入口 —— 这是 shellkit「只加不改」纪律的要求。
> 参数必须与 unix_script 现有 `pkg_install` **逐字一致**（见 Task 15 的等价要求）。

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_os.sh`：

```bash
# 提权包管理：用 stub 顶掉包管理器与 sudo，断言参数与提权方式
stub apt-get --body 'exit 0'
stub sudo --body 'exit 0'
os_pkg_install_root curl
assert_stub_called apt-get 1
assert_stub_args apt-get "install -y curl"
unstub apt-get
unstub sudo

# brew 不提权
stub brew --body 'exit 0'
os_pkg_install_root wget
assert_stub_called brew 1
unstub brew

if command -v curl >/dev/null 2>&1; then
  assert_exit_code 0 os_pkg_installed curl
fi
```

> ⚠️ `_sk_pkg_mgr` 不认 brew（brew 不是系统包管理器）。落地时给 `os_pkg_install_root` 等
> 四个函数补 brew 分支：brew 不提权，直接 `brew install`。测试里那两条 brew 断言依赖这一点。

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_os.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现**

追加到 `lib/core/os.sh`：

```bash
# _os_sudo_prefix —— 需要提权时的 sudo 前缀；已是 root 则为空
_os_sudo_prefix() {
  if [ "$(id -u 2>/dev/null)" = '0' ]; then
    printf '%s' ''
  else
    printf '%s' 'sudo'
  fi
}

# os_sudo_ready —— 确保 sudo 可用
# 已是 root 直接放行；否则先试免密（sudo -n true），不行则提示输入一次（sudo -v）。
# @exitcode 0 sudo 可用
# @exitcode 3 拿不到 sudo 权限
os_sudo_ready() {
  if [ "$(id -u 2>/dev/null)" = '0' ]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    log_error "$(_t 'sudo is not available')"
    return "$SK_PRECOND"
  fi
  if sudo -n true 2>/dev/null; then
    return 0
  fi
  log_info "$(_t 'This action needs sudo, please enter your password')"
  if sudo -v; then
    return 0
  fi
  log_error "$(_t 'Cannot obtain sudo permission')"
  return "$SK_PRECOND"
}

# os_pkg_install_root PKG... —— 提权安装
# @exitcode 0 安装成功
# @exitcode 2 没给包名
# @exitcode 3 没有受支持的包管理器
# @exitcode 其他 包管理器自身的退出码
os_pkg_install_root() {
  local __mgr __prefix
  _sk_need_args "$#" 1 "os_pkg_install_root PKG..." || return $?
  __mgr="$(_sk_pkg_mgr)" || __mgr=''
  if [ -z "$__mgr" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew install "$@"
      return $?
    fi
    log_error "$(_t 'no supported package manager found')"
    return "$SK_PRECOND"
  fi
  __prefix="$(_os_sudo_prefix)"
  case "$__mgr" in
    # DEBIAN_FRONTEND=noninteractive：容器/极简镜像里 tzdata 会弹 debconf 交互，
    # 无 TTY 时可能挂死（CI 与脚本场景必须避免）
    apt-get) $__prefix env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)     $__prefix dnf install -y "$@" ;;
    yum)     $__prefix yum install -y "$@" ;;
    zypper)  $__prefix zypper --non-interactive install "$@" ;;
    pacman)  $__prefix pacman -S --noconfirm --needed "$@" ;;
    apk)     $__prefix apk add --no-cache "$@" ;;
    *) log_error "$(_t 'Unsupported package manager'): $__mgr"; return "$SK_PRECOND" ;;
  esac
}

# os_pkg_remove_root PKG... —— 提权卸载
# @exitcode 0 卸载成功
# @exitcode 2 没给包名
# @exitcode 3 没有受支持的包管理器
os_pkg_remove_root() {
  local __mgr __prefix
  _sk_need_args "$#" 1 "os_pkg_remove_root PKG..." || return $?
  __mgr="$(_sk_pkg_mgr)" || __mgr=''
  if [ -z "$__mgr" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew uninstall "$@"
      return $?
    fi
    log_error "$(_t 'no supported package manager found')"
    return "$SK_PRECOND"
  fi
  __prefix="$(_os_sudo_prefix)"
  case "$__mgr" in
    apt-get) $__prefix env DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y "$@" ;;
    dnf)     $__prefix dnf remove -y "$@" ;;
    yum)     $__prefix yum remove -y "$@" ;;
    zypper)  $__prefix zypper --non-interactive remove "$@" ;;
    pacman)  $__prefix pacman -Rns --noconfirm "$@" ;;
    apk)     $__prefix apk del "$@" ;;
    *) log_error "$(_t 'Unsupported package manager'): $__mgr"; return "$SK_PRECOND" ;;
  esac
}

# os_pkg_update_root —— 提权刷新包索引
# @exitcode 0 成功
# @exitcode 3 没有受支持的包管理器
os_pkg_update_root() {
  local __mgr __prefix
  __mgr="$(_sk_pkg_mgr)" || __mgr=''
  if [ -z "$__mgr" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew update
      return $?
    fi
    log_error "$(_t 'no supported package manager found')"
    return "$SK_PRECOND"
  fi
  __prefix="$(_os_sudo_prefix)"
  case "$__mgr" in
    apt-get) $__prefix env DEBIAN_FRONTEND=noninteractive apt-get update -y ;;
    dnf)     $__prefix dnf makecache ;;
    yum)     $__prefix yum makecache ;;
    zypper)  $__prefix zypper --non-interactive refresh ;;
    pacman)  $__prefix pacman -Sy ;;
    apk)     $__prefix apk update ;;
  esac
}

# os_pkg_installed PKG —— 包是否已安装
# @exitcode 0 已安装
# @exitcode 1 未安装
# @exitcode 2 没给包名
# @exitcode 3 没有受支持的包管理器
os_pkg_installed() {
  local __mgr __pkg
  _sk_need_args "$#" 1 "os_pkg_installed PKG" || return $?
  __pkg="$1"
  __mgr="$(_sk_pkg_mgr)" || __mgr=''
  if [ -z "$__mgr" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew list "$__pkg" >/dev/null 2>&1
      return $?
    fi
    log_error "$(_t 'no supported package manager found')"
    return "$SK_PRECOND"
  fi
  case "$__mgr" in
    apt-get) dpkg -s "$__pkg" >/dev/null 2>&1 ;;
    dnf|yum) rpm -q "$__pkg" >/dev/null 2>&1 ;;
    zypper)  rpm -q "$__pkg" >/dev/null 2>&1 ;;
    pacman)  pacman -Qi "$__pkg" >/dev/null 2>&1 ;;
    apk)     apk info -e "$__pkg" >/dev/null 2>&1 ;;
  esac
}
```

- [ ] **Step 4: 跑测试与门禁**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_os.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/os.sh tests/test_os.sh
git commit -m "feat(os): 提权包管理与 sudo 就绪 —— 既有 os_pkg_* 语义不动"
```

---

## Task 4: shellkit 新模块 `svc`

**Files:**
- Create: `lib/core/svc.sh`
- Create: `tests/test_svc.sh`
- Modify: `lib/modules.txt`

**Interfaces:**
- Consumes: `os_name`、`log_*`、`_sk_need_args`、`run`
- Produces:
  - `svc_platform` —— systemd|launchd|none
  - `svc_start|svc_stop|svc_restart|svc_reload UNIT`
  - `svc_enable|svc_disable|svc_enable_now|svc_disable_now UNIT`
  - `svc_is_active UNIT` / `svc_is_enabled UNIT`
  - `svc_daemon_reload`
  - `svc_install_unit NAME` —— 从 stdin 读 unit 内容写入系统目录并 daemon-reload

- [ ] **Step 1: 写失败测试**

创建 `tests/test_svc.sh`：

```bash
#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"
. "$TEST_ROOT/lib/bootstrap.sh"

assert_eq "none" "$(svc_platform 2>/dev/null || echo none)" "svc_platform returns a value"

# 用 stub 顶掉 systemctl，断言动作与参数
stub systemctl --body 'exit 0'
svc_start nginx
assert_stub_called systemctl 1
assert_stub_args systemctl "start nginx"
unstub systemctl

# dry-run：只打印不执行
stub systemctl --body 'exit 0'
SHELLKIT_DRY_RUN=1 svc_restart nginx
assert_stub_not_called systemctl
unstub systemctl

# 用法错：缺 unit
assert_exit_code 2 svc_start
assert_exit_code 2 svc_start ""
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_svc.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现 `lib/core/svc.sh`

```bash
#!/usr/bin/env bash
#
# 服务管理：systemd（Linux）与 launchd（macOS）。
#
# 写类动作（start/stop/enable/...）在 SHELLKIT_DRY_RUN=1 时只打印不执行；
# 只读动作（is_active/is_enabled）直跑，不套 dry-run。
#
# 退出码口径：0 成功 / 2 用法错 / 3 当前平台没有服务管理器 / 4 服务管理器自身失败。

# svc_platform —— 当前平台的服务管理器
# @exitcode 0 总是成功（stdout 输出 systemd|launchd|none）
svc_platform() {
  case "$(os_name)" in
    linux) printf '%s\n' 'systemd' ;;
    darwin) printf '%s\n' 'launchd' ;;
    *) printf '%s\n' 'none' ;;
  esac
}

# _svc_need_unit ACTION UNIT —— 校验 unit 参数
_svc_need_unit() {
  local __action=${1:-} __unit=${2:-}
  if [ -z "$__unit" ]; then
    log_error "$(_t 'Usage'): svc_$__action UNIT"
    return "$SK_USAGE"
  fi
  return 0
}

# _svc_need_systemd —— 确认当前平台是 systemd
_svc_need_systemd() {
  if [ "$(svc_platform)" != 'systemd' ]; then
    log_error "$(_t 'This action requires systemd'): $(svc_platform)"
    return "$SK_PRECOND"
  fi
  return 0
}

# _svc_do ACTION UNIT... —— 真正执行 systemd 动作
_svc_do() {
  local __action="$1"; shift
  systemctl "$__action" "$@"
}

# svc_start UNIT —— 启动服务
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_start() {
  _svc_need_unit start "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do start "$@"
}

# svc_stop UNIT —— 停止服务
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_stop() {
  _svc_need_unit stop "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do stop "$@"
}

# svc_restart UNIT —— 重启服务
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_restart() {
  _svc_need_unit restart "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do restart "$@"
}

# svc_reload UNIT —— 重载服务配置
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_reload() {
  _svc_need_unit reload "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do reload "$@"
}

# svc_enable UNIT —— 开机自启
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_enable() {
  _svc_need_unit enable "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do enable "$@"
}

# svc_disable UNIT —— 取消开机自启
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_disable() {
  _svc_need_unit disable "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do disable "$@"
}

# svc_enable_now UNIT —— 开机自启并立即启动
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_enable_now() {
  _svc_need_unit enable-now "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do enable --now "$@"
}

# svc_disable_now UNIT —— 取消开机自启并立即停止
# @exitcode 0 成功
# @exitcode 2 缺 unit
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_disable_now() {
  _svc_need_unit disable-now "${1:-}" || return $?
  _svc_need_systemd || return $?
  run --no-die _svc_do disable --now "$@"
}

# svc_is_active UNIT —— 服务是否在跑
# @exitcode 0 在跑
# @exitcode 1 没在跑
# @exitcode 2 缺 unit
svc_is_active() {
  _svc_need_unit is-active "${1:-}" || return $?
  systemctl is-active --quiet "$@"
}

# svc_is_enabled UNIT —— 服务是否开机自启
# @exitcode 0 是
# @exitcode 1 不是
# @exitcode 2 缺 unit
svc_is_enabled() {
  _svc_need_unit is-enabled "${1:-}" || return $?
  systemctl is-enabled "$@"
}

# svc_daemon_reload —— 让 systemd 重新读 unit 文件
# @exitcode 0 成功
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 systemd 自身失败
svc_daemon_reload() {
  _svc_need_systemd || return $?
  run --no-die _svc_do daemon-reload
}

# svc_install_unit NAME —— 从 stdin 读 unit 内容写入系统目录并 daemon-reload
# @exitcode 0 成功
# @exitcode 2 缺 unit 名
# @exitcode 3 当前平台没有服务管理器
# @exitcode 4 写入或 daemon-reload 失败
svc_install_unit() {
  local __unit="${1:-}" __target
  if [ -z "$__unit" ]; then
    log_error "$(_t 'Usage'): svc_install_unit NAME"
    return "$SK_USAGE"
  fi
  _svc_need_systemd || return $?
  __target="/etc/systemd/system/$__unit"
  if [ "${SHELLKIT_DRY_RUN:-0}" = '1' ]; then
    log_info "$(_t 'writing unit file'): $__target"
    cat >/dev/null
  else
    os_sudo_ready || return $?
    if ! sudo tee "$__target" >/dev/null; then
      log_error "$(_t 'cannot write unit file'): $__target"
      return "$SK_NET"
    fi
  fi
  svc_daemon_reload
}
```

- [ ] **Step 4: 在 `lib/modules.txt` 注册**

在 `run` 行之后插入（拓扑序：svc 依赖 run）：

```
svc          error i18n log os run
```

- [ ] **Step 5: 跑测试与门禁**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_svc.sh; echo "exit=$?"
make check
```
期望：`make check` 全绿（模块顺序门禁会确认依赖声明完整）。

- [ ] **Step 6: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/svc.sh lib/modules.txt tests/test_svc.sh
git commit -m "feat(svc): systemd/launchd 服务动词 —— 写类动作支持 dry-run"
```

---

## Task 5: shellkit 新模块 `ver`

**Files:**
- Create: `lib/core/ver.sh`
- Create: `tests/test_ver.sh`
- Modify: `lib/modules.txt`

**Interfaces:**
- Produces: `ver_cmp A B`（输出 -1/0/1）、`ver_gt`、`ver_lt`、`ver_eq`

- [ ] **Step 1: 写失败测试**

创建 `tests/test_ver.sh`：

```bash
#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"
. "$TEST_ROOT/lib/bootstrap.sh"

assert_eq "0"  "$(ver_cmp 1.2.3 1.2.3)" "equal versions"
assert_eq "-1" "$(ver_cmp 1.2.3 1.2.4)" "left is smaller"
assert_eq "1"  "$(ver_cmp 1.3.0 1.2.9)" "left is bigger"
assert_eq "0"  "$(ver_cmp v1.2.3 1.2.3)" "leading v is stripped"

assert_true ver_gt 2.0.0 1.9.9
assert_false ver_gt 1.0.0 1.0.0
assert_true ver_lt 1.0.0 1.0.1
assert_true ver_eq 1.0 1.0.0

# 非法版本串保守判否（不误报有更新）
assert_false ver_gt "not-a-version" 1.0.0
assert_false ver_gt 1.0.0 ""
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_ver.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现 `lib/core/ver.sh`**

```bash
#!/usr/bin/env bash
#
# 版本比较。纯 bash 实现，不依赖 GNU sort -V（macOS 的 BSD sort 行为有差异）。
#
# 口径：只认「数字与点」组成的版本号；非法输入一律保守判否（不误报「有更新」）。
# 去前导 v / V。

# _ver_valid V —— 版本串是否合法（数字与点，且以数字开头）
_ver_valid() {
  case "${1:-}" in
    '' | *[!0-9.]*) return 1 ;;
  esac
  case "${1:-}" in
    [0-9]*) return 0 ;;
  esac
  return 1
}

# _ver_field V N —— 取第 N 段（0 起）；不足的段当 0
_ver_field() {
  local __v="$1" __n="$2" __i=0 __part
  while [ "$__i" -lt 32 ]; do
    if [ "$__i" -eq "$__n" ]; then
      printf '%s' "${__part:-0}"
      return 0
    fi
    case "$__v" in
      *.*) __part="${__v%%.*}"; __v="${__v#*.}" ;;
      *) printf '%s' '0'; return 0 ;;
    esac
    __i=$((__i + 1))
  done
  printf '%s' '0'
  return 0
}

# ver_cmp A B —— 比较两个版本号
# @exitcode 0 总是成功（stdout 输出 -1 / 0 / 1）
ver_cmp() {
  local __a="${1:-}" __b="${2:-}" __i=0 __x __y
  __a="${__a#v}"; __a="${__a#V}"
  __b="${__b#v}"; __b="${__b#V}"
  _ver_valid "$__a" || { printf '%s' '0'; return 0; }
  _ver_valid "$__b" || { printf '%s' '0'; return 0; }
  while [ "$__i" -lt 32 ]; do
    __x="$(_ver_field "$__a" "$__i")"
    __y="$(_ver_field "$__b" "$__i")"
    if [ "$__x" -lt "$__y" ]; then printf '%s' '-1'; return 0; fi
    if [ "$__x" -gt "$__y" ]; then printf '%s' '1'; return 0; fi
    __i=$((__i + 1))
  done
  printf '%s' '0'
  return 0
}

# ver_gt A B —— A 是否比 B 新
# @exitcode 0 A > B
# @exitcode 1 不是
ver_gt() {
  [ "$(ver_cmp "${1:-}" "${2:-}")" = '1' ]
}

# ver_lt A B —— A 是否比 B 旧
# @exitcode 0 A < B
# @exitcode 1 不是
ver_lt() {
  [ "$(ver_cmp "${1:-}" "${2:-}")" = '-1' ]
}

# ver_eq A B —— 两个版本是否相等
# @exitcode 0 相等
# @exitcode 1 不等
ver_eq() {
  [ "$(ver_cmp "${1:-}" "${2:-}")" = '0' ]
}
```

- [ ] **Step 4: 注册模块并跑门禁**

```bash
cd /Users/zhangyi/shellkit
# lib/modules.txt 加一行（依赖 i18n log）：
# ver          i18n log
/bin/bash tests/test_ver.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/ver.sh lib/modules.txt tests/test_ver.sh
git commit -m "feat(ver): 版本比较 —— 纯 bash，不依赖 GNU sort -V"
```

---

## Task 6: shellkit 新模块 `status`（机器可读状态契约）

**Files:**
- Create: `lib/core/status.sh`
- Create: `tests/test_status.sh`
- Modify: `lib/modules.txt`

**Interfaces:**
- Produces:
  - `status_emit STATE HUMAN_MSG`
  - `status_version VERSION`
  - `status_extra KEY=VALUE`
  - `status_is_machine`（机器模式 0 / 人类模式 1）
  - `status_state_valid STATE`
  - 环境变量 `SHELLKIT_STATUS_MODE=machine` 开启机器模式

- [ ] **Step 1: 写失败测试**

创建 `tests/test_status.sh`：

```bash
#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"
. "$TEST_ROOT/lib/bootstrap.sh"

# 人类模式：打印人类文案
out=$(status_emit not_installed "未安装")
assert_eq "未安装" "$out" "human mode prints the human message"

# 机器模式：打印规范字段
out=$(SHELLKIT_STATUS_MODE=machine status_emit not_installed "未安装")
assert_eq "STATE=not_installed" "$out" "machine mode prints STATE="

out=$(SHELLKIT_STATUS_MODE=machine status_version 1.2.3)
assert_eq "VERSION=1.2.3" "$out" "machine mode prints VERSION="

out=$(SHELLKIT_STATUS_MODE=machine status_extra registry=https://example.com)
assert_eq "EXTRA=registry=https://example.com" "$out" "machine mode prints EXTRA="

# 人类模式下 version/extra 不输出（不重复）
assert_stdout_empty status_version 1.2.3
assert_stdout_empty status_extra k=v

# 状态码有限集
assert_true status_state_valid not_installed
assert_true status_state_valid installed:running
assert_false status_state_valid whatever
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_status.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现 `lib/core/status.sh`**

```bash
#!/usr/bin/env bash
#
# 机器可读的状态契约。
#
# 双轨输出：
#   人类模式（默认）—— 打印人类可读的文案，向后兼容既有脚本；
#   机器模式（SHELLKIT_STATUS_MODE=machine）—— 打印规范字段行：
#       STATE=<状态码>
#       VERSION=<版本>      可选
#       EXTRA=<key=value>  可选
#
# 状态码有限集，见 status_state_valid。

# _status_is_machine —— 是否机器模式
_status_is_machine() {
  [ "${SHELLKIT_STATUS_MODE:-human}" = 'machine' ]
}

# status_is_machine —— 机器模式返回 0，人类模式返回 1
# @exitcode 0 机器模式
# @exitcode 1 人类模式
status_is_machine() {
  _status_is_machine
}

# status_state_valid STATE —— 状态码是否在有限集里
# @exitcode 0 合法
# @exitcode 1 非法
status_state_valid() {
  case "${1:-}" in
    not_installed|installed|installed:running|installed:stopped|configured|not_configured|n/a) return 0 ;;
  esac
  return 1
}

# status_emit STATE HUMAN_MSG —— 输出状态
# @exitcode 0 总是成功
status_emit() {
  local __state="${1:-}" __human="${2:-}"
  if _status_is_machine; then
    printf 'STATE=%s\n' "$__state"
  else
    printf '%s\n' "$__human"
  fi
  return 0
}

# status_version VERSION —— 机器模式下输出 VERSION 行
# @exitcode 0 总是成功
status_version() {
  if _status_is_machine; then
    printf 'VERSION=%s\n' "${1:-}"
  fi
  return 0
}

# status_extra KEY=VALUE —— 机器模式下输出 EXTRA 行
# @exitcode 0 总是成功
status_extra() {
  if _status_is_machine; then
    printf 'EXTRA=%s\n' "${1:-}"
  fi
  return 0
}
```

- [ ] **Step 4: 注册模块并跑门禁**

```bash
cd /Users/zhangyi/shellkit
# lib/modules.txt 加一行：
# status       i18n log
/bin/bash tests/test_status.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/status.sh lib/modules.txt tests/test_status.sh
git commit -m "feat(status): 机器可读状态契约 —— STATE/VERSION/EXTRA 双轨输出"
```

---

## Task 7: shellkit 新模块 `registry`（KV 清单 + 依赖拓扑）

**Files:**
- Create: `lib/core/registry.sh`
- Create: `tests/test_registry.sh`
- Modify: `lib/modules.txt`

**Interfaces:**
- Produces:
  - `registry_scan ROOT PATTERN` —— 扫描 ROOT 下匹配 PATTERN 的文件，用其所在目录名作为条目名
  - `registry_get NAME KEY` —— 取字段值
  - `registry_list` —— 列出条目名（每行一个）
  - `registry_visible NAME FIELD` —— 平台可见性（字段为空 ⇒ 全平台可见）
  - `registry_deps NAME FIELD` —— 传递依赖（拓扑序，空格分隔）
  - `registry_topo FIELD` —— 全体拓扑序（空格分隔）
  - 全局变量：`_REGISTRY_ENTRIES`（空格分隔的条目名）、`_REGISTRY_FILES`（`name=path` 对）

**边界：** shellkit 侧**不出现**任何领域字段名（`PLATFORMS`/`REQUIRES`/…）——
字段名由调用方传入。清单格式是「每行 KEY=VALUE」。

- [ ] **Step 1: 写失败测试**

创建 `tests/test_registry.sh`：

```bash
#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"
. "$TEST_ROOT/lib/bootstrap.sh"

d="$(tmpdir)"
mkdir -p "$d/alpha" "$d/beta" "$d/gamma"
printf 'LABEL=Alpha\nDEPS=beta\nPLATFORMS=linux,darwin\n' >"$d/alpha/.manifest"
printf 'LABEL=Beta\nDEPS=\nPLATFORMS=\n' >"$d/beta/.manifest"
printf 'LABEL=Gamma\nDEPS=beta\nPLATFORMS=linux\n' >"$d/gamma/.manifest"

registry_scan "$d" '.manifest'
assert_eq "Alpha" "$(registry_get alpha LABEL)" "registry_get reads a field"
assert_eq "beta" "$(registry_get alpha DEPS)" "registry_get reads a list field"

# 拓扑序：beta 是 alpha 的依赖
deps="$(registry_deps alpha DEPS)"
assert_eq "beta" "$deps" "registry_deps returns the dependency"

# 平台可见性：PLATFORMS 只列 linux 时，在 darwin 上不可见
if [ "$(os_name)" = 'darwin' ]; then
  assert_false registry_visible gamma PLATFORMS
  assert_true registry_visible alpha PLATFORMS
fi

# 环检测
mkdir -p "$d/x" "$d/y"
printf 'DEPS=y\n' >"$d/x/.manifest"
printf 'DEPS=x\n' >"$d/y/.manifest"
registry_scan "$d" '.manifest'
assert_false registry_deps x DEPS
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_registry.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现 `lib/core/registry.sh`**

```bash
#!/usr/bin/env bash
#
# 清单注册表：扫描「每行 KEY=VALUE」的清单文件，提供字段查询、
# 平台可见性判定与依赖拓扑排序。
#
# 边界：这个模块不认识任何领域字段名。哪些 KEY 是「平台」「依赖」，
# 由调用方在调用时传进来（registry_visible NAME FIELD / registry_deps NAME FIELD）。
# 清单格式与 unix_script 的 .manifest 同构，因此那 78 个模块的清单零改动即可用。

_REGISTRY_ROOT=""
_REGISTRY_ENTRIES=""
_REGISTRY_FILES=""

# registry_scan ROOT PATTERN —— 扫描清单文件并建立索引
# 条目名 = 清单文件所在目录名。PATTERN 是文件名模式（如 .manifest）。
# @exitcode 0 总是成功
registry_scan() {
  local __root="${1:-}" __pat="${2:-}" __f __dir __name
  _REGISTRY_ROOT="$__root"
  _REGISTRY_ENTRIES=""
  _REGISTRY_FILES=""
  [ -n "$__root" ] && [ -d "$__root" ] || return 0
  for __f in "$__root"/*/"$__pat"; do
    [ -f "$__f" ] || continue
    __dir="$(dirname "$__f")"
    __name="$(basename "$__dir")"
    case " $_REGISTRY_ENTRIES " in
      *" $__name "*) continue ;;
    esac
    _REGISTRY_ENTRIES="$_REGISTRY_ENTRIES $__name"
    _REGISTRY_FILES="$_REGISTRY_FILES $__name=$__f"
  done
  _REGISTRY_ENTRIES="${_REGISTRY_ENTRIES# }"
  return 0
}

# _registry_file NAME —— 条目对应的清单文件路径
_registry_file() {
  local __name="$1" __pair
  for __pair in ${_REGISTRY_FILES:-}; do
    case "$__pair" in
      "$__name="*) printf '%s' "${__pair#*=}"; return 0 ;;
    esac
  done
  return 1
}

# registry_get NAME KEY —— 取字段值（未声明时为空）
# @exitcode 0 总是成功（未声明时 stdout 为空）
registry_get() {
  local __name="${1:-}" __key="${2:-}" __file __line
  __file="$(_registry_file "$__name")" || return 0
  [ -r "$__file" ] || return 0
  __line="$(sed -n "s/^${__key}=//p" "$__file" 2>/dev/null | sed -n '1p')"
  __line="$(printf '%s' "$__line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf '%s' "$__line"
  return 0
}

# registry_list —— 列出全部条目名（每行一个）
# @exitcode 0 总是成功
registry_list() {
  local __e
  for __e in ${_REGISTRY_ENTRIES:-}; do
    printf '%s\n' "$__e"
  done
  return 0
}

# registry_visible NAME FIELD —— 条目在当前平台是否可见
# 字段为空 ⇒ 未声明平台限制 ⇒ 可见。
# @exitcode 0 可见
# @exitcode 1 不可见
registry_visible() {
  local __name="${1:-}" __field="${2:-}" __plats __p
  __plats="$(registry_get "$__name" "$__field")"
  [ -n "$__plats" ] || return 0
  for __p in ${__plats//,/ }; do
    [ "$__p" = "$(os_name)" ] && return 0
  done
  return 1
}

# _registry_deps_visit NAME FIELD —— 后序 DFS，环检测
_REGISTRY_VISITED=""
_REGISTRY_RESULT=""
_REGISTRY_PATH=""
_registry_deps_visit() {
  local __name="$1" __field="$2" __dep
  case " $_REGISTRY_PATH " in
    *" $__name "*)
      log_error "$(_t 'circular dependency detected'): ${_REGISTRY_PATH# } -> $__name"
      return 1
      ;;
  esac
  case " $_REGISTRY_VISITED " in
    *" $__name "*) return 0 ;;
  esac
  _REGISTRY_VISITED="$_REGISTRY_VISITED $__name"
  _REGISTRY_PATH="$_REGISTRY_PATH $__name"
  for __dep in $(registry_get "$__name" "$__field" | tr ',' ' '); do
    [ -n "$__dep" ] || continue
    if ! _registry_deps_visit "$__dep" "$__field"; then
      return 1
    fi
  done
  _REGISTRY_RESULT="$_REGISTRY_RESULT $__name"
  _REGISTRY_PATH="${_REGISTRY_PATH% "$__name"}"
  return 0
}

# registry_deps NAME FIELD —— 传递依赖（拓扑序，空格分隔，不含自身）
# @exitcode 0 成功
# @exitcode 1 有环
registry_deps() {
  local __name="${1:-}" __field="${2:-}" __m __out=""
  _REGISTRY_VISITED=""
  _REGISTRY_RESULT=""
  _REGISTRY_PATH=""
  _registry_deps_visit "$__name" "$__field" || return 1
  for __m in $_REGISTRY_RESULT; do
    [ "$__m" = "$__name" ] && continue
    __out="$__out $__m"
  done
  printf '%s\n' "${__out# }"
  return 0
}

# registry_topo FIELD —— 全体拓扑序（空格分隔）
# @exitcode 0 成功
# @exitcode 1 有环
registry_topo() {
  local __field="${1:-}" __m
  _REGISTRY_VISITED=""
  _REGISTRY_RESULT=""
  _REGISTRY_PATH=""
  for __m in ${_REGISTRY_ENTRIES:-}; do
    _registry_deps_visit "$__m" "$__field" || return 1
  done
  printf '%s\n' "${_REGISTRY_RESULT# }"
  return 0
}
```

- [ ] **Step 4: 注册模块并跑门禁**

```bash
cd /Users/zhangyi/shellkit
# lib/modules.txt 加一行：
# registry     error i18n log os
/bin/bash tests/test_registry.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/registry.sh lib/modules.txt tests/test_registry.sh
git commit -m "feat(registry): KV 清单注册表与依赖拓扑 —— 不认识任何领域字段名"
```

---

## Task 8: shellkit 新模块 `profile`

**Files:**
- Create: `lib/core/profile.sh`
- Create: `tests/test_profile.sh`
- Modify: `lib/modules.txt`

**Interfaces:**
- Produces:
  - `profile_write FILE` —— 创建/清空 profile 文件
  - `profile_append FILE MODULE [KEY=VALUE...]` —— 追加一行
  - `profile_parse FILE` —— 输出 `MODULE<TAB>k=v,k=v`（每行一个）
  - `profile_env MODULE_TAB_KV PREFIX` —— 输出 `PREFIX_KEY=VALUE`（每行一个）

> 规格 §6.7 写的是 `profile_export FILE MODULE...`/`profile_apply FILE`。
> 实施时细化为上面四个原语：**「导哪些模块、哪些键」「应用时怎么装」是领域逻辑，留 unix_script**；
> shellkit 只提供文件格式的读写与解析。

- [ ] **Step 1: 写失败测试**

创建 `tests/test_profile.sh`：

```bash
#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"
. "$TEST_ROOT/lib/bootstrap.sh"

d="$(tmpdir)"
f="$d/profile.txt"

profile_write "$f"
profile_append "$f" bun registry=https://registry.npmmirror.com
profile_append "$f" docker 'version=24.0'

out="$(profile_parse "$f")"
assert_contains "$out" "bun"
assert_contains "$out" "registry=https://registry.npmmirror.com"
assert_contains "$out" "docker"

env_out="$(profile_env "docker	version=24.0" UXS_CONFIG_)"
assert_eq "UXS_CONFIG_version=24.0" "$env_out" "profile_env builds env assignments"
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_profile.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现 `lib/core/profile.sh`**

```bash
#!/usr/bin/env bash
#
# profile 文件格式原语。
#
# 文件每行一条：<模块名> [key=value ...]   # 注释
# 解析结果用 TAB 分隔「模块名」与「逗号分隔的键值对」，方便 shell 逐行处理。

# profile_write FILE —— 创建/清空 profile 文件
# @exitcode 0 成功
# @exitcode 2 缺参数
# @exitcode 1 写不了
profile_write() {
  local __file="${1:-}"
  if [ -z "$__file" ]; then
    log_error "$(_t 'Usage'): profile_write FILE"
    return "$SK_USAGE"
  fi
  : >"$__file" || return 1
  return 0
}

# profile_append FILE MODULE [KEY=VALUE...] —— 追加一条
# @exitcode 0 成功
# @exitcode 2 缺参数
# @exitcode 1 写不了
profile_append() {
  local __file="${1:-}" __mod="${2:-}" __line
  if [ -z "$__file" ] || [ -z "$__mod" ]; then
    log_error "$(_t 'Usage'): profile_append FILE MODULE [KEY=VALUE...]"
    return "$SK_USAGE"
  fi
  shift 2
  __line="$__mod"
  if [ "$#" -gt 0 ]; then
    __line="$__line $*"
  fi
  printf '%s\n' "$__line" >>"$__file" || return 1
  return 0
}

# profile_parse FILE —— 解析 profile
# 输出：<模块名><TAB><k=v,k=v>（每行一个）
# @exitcode 0 总是成功
profile_parse() {
  local __file="${1:-}" __line __mod __rest
  if [ -z "$__file" ] || [ ! -r "$__file" ]; then
    return 0
  fi
  while IFS= read -r __line || [ -n "$__line" ]; do
    __line="$(printf '%s' "$__line" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$__line" ] || continue
    __mod="${__line%% *}"
    __rest="${__line#* }"
    [ "$__rest" = "$__line" ] && __rest=''
    __rest="$(printf '%s' "$__rest" | tr ' ' ',' | sed 's/,^//; s/,$//')"
    printf '%s\t%s\n' "$__mod" "$__rest"
  done <"$__file"
  return 0
}

# profile_env MODULE_TAB_KV PREFIX —— 把键值对变成环境变量赋值
# @exitcode 0 总是成功
profile_env() {
  local __line="${1:-}" __prefix="${2:-}" __kv __k __v
  __kv="${__line#*	}"
  [ "$__kv" = "$__line" ] && __kv=''
  for __kv in ${__kv//,/ }; do
    [ -n "$__kv" ] || continue
    __k="${__kv%%=*}"
    __v="${__kv#*=}"
    [ "$__k" = "$__kv" ] && continue
    printf '%s%s=%s\n' "$__prefix" "$__k" "$__v"
  done
  return 0
}
```

- [ ] **Step 4: 注册模块并跑门禁**

```bash
cd /Users/zhangyi/shellkit
# lib/modules.txt 加一行：
# profile      error fs i18n log
/bin/bash tests/test_profile.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/profile.sh lib/modules.txt tests/test_profile.sh
git commit -m "feat(profile): profile 文件格式原语 —— 导哪些、怎么装留给调用方"
```

---

## Task 9: shellkit `http` —— GitHub release 查询

**Files:**
- Modify: `lib/core/http.sh`
- Modify: `tests/test_http.sh`

**Interfaces:**
- Produces:
  - `http_github_latest_tag REPO` —— 最新 release 的 tag（去 v/V 前缀）
  - `http_github_release_asset REPO PATTERN` —— 匹配 `browser_download_url` 的第一个资产 URL

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_http.sh`：

```bash
# 用 stub 顶掉 curl，验证解析
stub curl --stdout '{"tag_name":"v1.2.3"}'
assert_eq "1.2.3" "$(http_github_latest_tag owner/repo)" "github latest tag strips v"
unstub curl
```

> ⚠️ 先读 `lib/core/http.sh` 里 `net_request`/`net_json` 的真实签名，再确定 stub 的返回位置
> （stub 的是 curl，不是 net_json）。若 `net_json --path` 不支持数组下钻，
> `http_github_release_asset` 改成 `net_request` + 本地解析（参照 unix_script 的
> `github_release_asset_url` 做法，但用 shellkit 的 JSON 工具而不是 jq）。

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_http.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现**

追加到 `lib/core/http.sh`：

```bash
# http_github_latest_tag REPO —— 最新 release 的 tag（去 v/V 前缀）
# @exitcode 0 成功（stdout 输出 tag）
# @exitcode 2 缺参数
# @exitcode 4 网络失败
http_github_latest_tag() {
  local __repo="${1:-}" __tag
  if [ -z "$__repo" ]; then
    log_error "$(_t 'Usage'): http_github_latest_tag REPO"
    return "$SK_USAGE"
  fi
  __tag="$(net_json GET "https://api.github.com/repos/$__repo/releases/latest" --path tag_name 2>/dev/null)" || return "$SK_NET"
  __tag="${__tag#v}"; __tag="${__tag#V}"
  printf '%s' "$__tag"
  return 0
}

# http_github_release_asset REPO PATTERN —— 匹配资产的下载地址
# @exitcode 0 成功（stdout 输出 URL）
# @exitcode 2 缺参数
# @exitcode 4 网络失败
http_github_release_asset() {
  local __repo="${1:-}" __pat="${2:-}" __url
  if [ -z "$__repo" ] || [ -z "$__pat" ]; then
    log_error "$(_t 'Usage'): http_github_release_asset REPO PATTERN"
    return "$SK_USAGE"
  fi
  __url="$(net_json GET "https://api.github.com/repos/$__repo/releases/latest" --path assets 2>/dev/null)" || return "$SK_NET"
  printf '%s' "$__url"
  return 0
}
```

> ⚠️ 认证头：`GH_TOKEN`/`GITHUB_TOKEN` 存在时要带上 `Authorization: Bearer`。
> 落地时把 token 参数加进上面的 `net_json` 调用（参照 `net_request` 的 `--header` 写法）。

- [ ] **Step 4: 跑测试与门禁**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_http.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/http.sh tests/test_http.sh
git commit -m "feat(http): GitHub release 查询 —— 不依赖 jq"
```

---

## Task 10: shellkit `run` —— 超时包装与 sudo 遮蔽

**Files:**
- Modify: `lib/core/run.sh`
- Modify: `tests/test_run.sh`

**Interfaces:**
- Produces:
  - `run_timeout SEC CMD...` —— 超时返回 124
  - `run_func_timeout SEC FN [ARG...]` —— 超时返回 143
  - `run_install_sudo_shim` —— 安装同名 bash 函数遮蔽 `sudo` 二进制（**显式调用才生效**）

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_run.sh`：

```bash
# 超时：跑一个睡很久的命令
assert_exit_code 124 run_timeout 1 sleep 5

# 正常结束
assert_exit_code 0 run_timeout 5 true

# 函数超时
_slow_fn() { sleep 5; }
assert_exit_code 143 run_func_timeout 1 _slow_fn

# sudo 遮蔽：装上之后 sudo 不再真的执行
run_install_sudo_shim
out="$(sudo touch /tmp/should-not-exist-$$ 2>&1)"
assert_contains "$out" "dry-run"
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_run.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现**

追加到 `lib/core/run.sh`：

```bash
# run_timeout SEC CMD... —— 带超时执行命令
# 超时返回 124（与 GNU timeout 对齐）；没有 perl 时退化为无超时（直接执行）。
# @exitcode 0 命令成功
# @exitcode 2 参数错（秒数非法或没给命令）
# @exitcode 124 超时
# @exitcode 其他 命令自身的退出码
run_timeout() {
  local __secs=${1:-}
  if ! printf '%s' "$__secs" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
    log_error "$(_t 'Usage'): run_timeout SEC CMD..."
    return "$SK_USAGE"
  fi
  shift
  if [ "$#" -eq 0 ]; then
    log_error "$(_t 'Usage'): run_timeout SEC CMD..."
    return "$SK_USAGE"
  fi
  if [ "$__secs" = '0' ]; then
    "$@"; return $?
  fi
  if ! command -v perl >/dev/null 2>&1; then
    "$@"; return $?
  fi
  perl -e '
    my $secs = shift @ARGV;
    my @cmd  = @ARGV;
    my $pid = fork();
    exit 125 unless defined $pid;
    if ($pid == 0) { exec(@cmd); exit 127; }
    $SIG{ALRM} = sub {
      kill "TERM", $pid;
      select(undef, undef, undef, 1);
      kill "KILL", $pid;
      exit 124;
    };
    alarm $secs;
    waitpid $pid, 0;
    alarm 0;
    my $st = $?;
    exit(128 + ($st & 127)) if ($st & 127);
    exit($st >> 8);
  ' "$__secs" "$@"
}

# run_func_timeout SEC FN [ARG...] —— 带超时执行当前 shell 里的函数
# 后台执行 + watchdog（sleep 后 kill），bash 3.2 兼容。
# 超时返回 143（128+SIGTERM）；否则透传函数的退出码。
# @exitcode 0 函数正常结束
# @exitcode 2 参数错
# @exitcode 143 超时
run_func_timeout() {
  local __secs=${1:-} __fn=${2:-} __outfile __rc
  if ! printf '%s' "$__secs" | grep -Eq '^[0-9]+([.][0-9]+)?$' || [ -z "$__fn" ]; then
    log_error "$(_t 'Usage'): run_func_timeout SEC FN [ARG...]"
    return "$SK_USAGE"
  fi
  shift 2
  __outfile="$(mktemp "${TMPDIR:-/tmp}/shellkit-func.XXXXXX")" || return "$SK_ERR"
  "$__fn" "$@" >"$__outfile" 2>/dev/null &
  local __pid=$!
  # watchdog 必须全重定向：否则它与 sleep 子进程持有外层管道写端，
  # 函数结束后外层还要等 sleep 睡满才返回。
  ( sleep "$__secs"; kill "$__pid" 2>/dev/null ) >/dev/null 2>&1 </dev/null &
  local __wd=$!
  wait "$__pid" 2>/dev/null
  __rc=$?
  kill "$__wd" 2>/dev/null
  wait "$__wd" 2>/dev/null
  cat "$__outfile"
  rm -f "$__outfile"
  return "$__rc"
}

# run_install_sudo_shim —— 用同名 bash 函数遮蔽 sudo 二进制
#
# 为什么需要：脚本里常有直接书写的 sudo apt-get ...，只靠 run 的 dry-run
# 包装拦不住它们。这个函数让 dry-run 期间的 sudo 变成「只打印」。
#
# 这是**全局副作用**（改了当前 shell 的命令解析），所以必须显式调用才生效，
# shellkit 自己不调用 —— 保持「不改变调用方 shell 行为」的既有纪律。
# @exitcode 0 总是成功
run_install_sudo_shim() {
  sudo() {
    printf '[dry-run] sudo %s\n' "$*" >&2
    return 0
  }
  return 0
}
```

- [ ] **Step 4: 跑测试与门禁**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_run.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/run.sh tests/test_run.sh
git commit -m "feat(run): 超时包装与 sudo 遮蔽 —— 遮蔽需显式调用，不改默认行为"
```

---

## Task 11: shellkit `str` —— 相似词建议

**Files:**
- Modify: `lib/core/str.sh`
- Modify: `tests/test_str.sh`

**Interfaces:**
- Produces: `str_suggest WORD [CANDIDATE...]` —— 编辑距离最小的候选；无候选返回 1

- [ ] **Step 1: 写失败测试**

追加到 `tests/test_str.sh`：

```bash
assert_eq "docker" "$(str_suggest dockr docker nginx redis)" "closest candidate wins"
assert_eq "nginx" "$(str_suggest ngx docker nginx redis)" "closest candidate wins"
assert_exit_code 1 str_suggest zzzzz
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_str.sh; echo "exit=$?"
```

- [ ] **Step 3: 实现**

追加到 `lib/core/str.sh`：

```bash
# _str_edit_distance A B —— 编辑距离（Levenshtein），纯 bash
# 用两个平行字符串变量当滚动数组（bash 3.2 没有关联数组）。
_str_edit_distance() {
  local __a="${1:-}" __b="${2:-}" __i __j __prev __cur __m
  local __la=${#__a} __lb=${#__b}
  local __prev_row="" __cur_row=""
  for ((__j = 0; __j <= __lb; __j++)); do
    __prev_row="$__prev_row $__j"
  done
  for ((__i = 1; __i <= __la; __i++)); do
    __cur_row=" $__i"
    for ((__j = 1; __j <= __lb; __j++)); do
      eval "__prev=${__prev_row#* }"
      eval "__cur=${__prev_row}"
      eval "__prev_row=${__prev_row#* }"
      eval "__cur_row=${__cur_row#* }"
      if [ "${__a:__i-1:1}" = "${__b:__j-1:1}" ]; then
        __cur_row="$__cur_row $__prev"
      else
        eval "__cur=${__cur_row}"
        __m=$__cur
        [ "$__prev" -lt "$__m" ] && __m=$__prev
        eval "__prev=${__prev_row}"
        [ "$__prev" -lt "$__m" ] && __m=$__prev
        __cur_row="$__cur_row $((__m + 1))"
      fi
    done
    __prev_row="$__cur_row"
  done
  eval "__last=${__prev_row##* }"
  printf '%s' "$__last"
}

# str_suggest WORD [CANDIDATE...] —— 最接近的候选
# @exitcode 0 找到（stdout 输出候选）
# @exitcode 1 没有候选
str_suggest() {
  local __word="${1:-}" __cand __best='' __bestd='' __d
  shift
  for __cand in "$@"; do
    [ -n "$__cand" ] || continue
    __d="$(_str_edit_distance "$__word" "$__cand")"
    if [ -z "$__bestd" ] || [ "$__d" -lt "$__bestd" ]; then
      __best="$__cand"
      __bestd="$__d"
    fi
  done
  [ -n "$__best" ] || return 1
  printf '%s' "$__best"
  return 0
}
```

> ⚠️ 上面用字符串当滚动数组是为了绕开 bash 3.2 没有关联数组。
> **落地时必须先跑 Step 4 的测试**；如果距离算错，改用两个平行数组
> （`local -a prev cur`，bash 3.2 支持数组，只是不能用 `declare -A`）。

- [ ] **Step 4: 跑测试与门禁**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/test_str.sh; echo "exit=$?"
make check
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/shellkit
git add lib/core/str.sh tests/test_str.sh
git commit -m "feat(str): str_suggest —— 纯 bash 编辑距离，bash 3.2 兼容"
```

---

## Task 12: shellkit 门禁同步与文档重生成

**Files:**
- Modify: `README.md`、`docs/MIGRATING.md`、`site/index.md`、`site/guide/index.md`、`site/guide/modules.md`、`site/guide/faq.md`
- Modify: `site/en/*.md`、`site/en/guide/*.md`（模块数）
- Modify: `docs/REFERENCE.md`、`AGENTS.md`、`skills/shellkit/SKILL.md`（生成物）

**Interfaces:**
- Consumes: Task 1–11 新增的模块与函数
- Produces: 门禁全绿的 shellkit 仓

- [ ] **Step 1: 数一下模块数**

```bash
cd /Users/zhangyi/shellkit
grep -vE '^\s*(#|$)' lib/modules.txt | wc -l
```
期望：23（18 + svc/ver/status/registry/profile）。

- [ ] **Step 2: 核对文档里的模块数**

模块数已由 Task 4/5/6/7/8 各自更新（见 Global Constraints）。这里只核对残留：

```bash
cd /Users/zhangyi/shellkit
grep -rn '18 个模块\|18 modules\|19 个模块\|19 modules\|20 个模块\|20 modules\|21 个模块\|21 modules\|22 个模块\|22 modules' README.md docs site | cat
```
期望：无输出。有输出说明某个模块任务漏改，按 Step 3 定位。

- [ ] **Step 3: 跑门禁**

```bash
cd /Users/zhangyi/shellkit
make module-count-check
make check
```
期望：全绿。若 `module-count-check` 仍红，说明还有文档漏改。

- [ ] **Step 4: 重生成 API 参考**

```bash
cd /Users/zhangyi/shellkit
make docs
make docs-check
git status --short
```
期望：`docs/REFERENCE.md`、`AGENTS.md`、`skills/shellkit/SKILL.md` 无未提交变更
（各模块任务已经生成并提交过；这里只是确认没有漂移）。

- [ ] **Step 5: 补 CHANGELOG**

在 `CHANGELOG.md` 的 Unreleased 段加一条：

```markdown
### 新增
- 新增 5 个模块：`svc`（systemd/launchd 服务动词）、`ver`（版本比较）、`status`（机器可读状态契约）、
  `registry`（KV 清单注册表与依赖拓扑）、`profile`（profile 文件格式原语）
- `os` 新增发行版/桌面环境检测与提权包管理（既有 `os_pkg_*` 语义不变）
- `i18n` 新增多域查找与纯 bash 兜底表：没有 gettext 的机器也能出译文
- `http` 新增 GitHub release 查询、`run` 新增超时包装与 sudo 遮蔽、`str` 新增 `str_suggest`
```

- [ ] **Step 6: 提交**

```bash
cd /Users/zhangyi/shellkit
git add -A
git commit -m "docs: 补齐 23 个模块的文档与 API 参考"
```

---

## Task 13: unix_script vendor 接入与副本一致性门禁

**Files:**
- Create: `vendor/shellkit/`（由 `shellkit vendor` 生成，整目录入库）
- Create: `tools/check_vendor.sh`
- Modify: `.gitignore`（确认 `vendor/` **没有**被忽略）

**Interfaces:**
- Produces: `tools/check_vendor.sh` —— 副本与上游不一致时退出 1
- Produces: unix_script 侧加载 shellkit 的唯一入口：`vendor/shellkit/lib/bootstrap.sh`

- [ ] **Step 1: vendor 一份进仓**

```bash
cd /Users/zhangyi/unix_script
# SHELLKIT_REPO = 上游 shellkit 仓的根目录（开发期指向本地 clone；CI 里指向 checkout 出来的仓）。
# 不要把某个人的绝对路径写死在脚本里 —— 用环境变量传进来。
: "${SHELLKIT_REPO:?先 export SHELLKIT_REPO=/path/to/shellkit}"
"$SHELLKIT_REPO/shellkit" vendor .
ls vendor/shellkit
```
期望：`vendor/shellkit/` 下有 `lib/`、`locale/`、`templates/`、`tests/`、`VERSION`、`shellkit`、`LICENSE`、`NOTICE`。

- [ ] **Step 2: 确认 .gitignore 没排除 vendor**

```bash
cd /Users/zhangyi/unix_script
git check-ignore -v vendor/shellkit/VERSION || echo "not ignored (ok)"
```

- [ ] **Step 3: 写一致性门禁 `tools/check_vendor.sh`**

**先说清楚本任务最容易写错的地方：**

`shellkit vendor <dir> --check` 的实现是拿**运行中的 CLI 所在目录**（`SELF_DIR`）当源去比对目标：

```bash
if bash "$VENDOR_DIR/shellkit" vendor "$ROOT" --check; then   # ← 恒绿
```

`SELF_DIR` 就是副本目录自己 ⇒ 它在拿**副本比副本** ⇒ 永远一致 ⇒ 门禁永远绿。
要真比对，**必须用上游的 CLI** 去查副本。

所以门禁分两层：

- **L1 副本自洽（CI 里能跑，不需要上游）**：副本内容 vs 入库的 `vendor/shellkit.sha256` 清单。
  抓「副本被手改」与「副本夹带清单外的文件」。
- **L2 副本 == 上游（本机有上游时跑）**：用上游 CLI 跑 `vendor --check`。

清单 `vendor/shellkit.sha256` 由 `tools/check_vendor.sh --update` 生成（只在本机生成，生成物随提交入库）。
清单缺失 ⇒ 硬失败（exit 2），**不许在检查模式里自动生成**：自动生成等于「删了清单就等于重新认可当前内容」，
那是假绿。（与 Task 0 的 `.approved` 登记同一思路。）

实现：

```bash
#!/usr/bin/env bash
#
# 门禁：vendor/shellkit/ 这份副本必须与入库清单一致，且（有上游时）与上游一致。
#
# 为什么要这道门：vendor 出去的是**副本**，副本会被手改、被忘记同步。
# 一旦 unix_script 里的 shellkit 与上游分叉，两边的行为差异就没有第二处真相源可查。
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
  (cd "$VENDOR_DIR" && find . -type f ! -name '.DS_Store' | sed 's|^\\./||' | LC_ALL=C sort)
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
__tmp="$(mktemp -d)"
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
__upstream="${SHELLKIT_UPSTREAM:-}"
if [ -z "$__upstream" ] && [ -x "$ROOT/../shellkit/shellkit" ]; then
  __upstream="$ROOT/../shellkit"
fi
if [ -n "$__upstream" ] && [ -x "$__upstream/shellkit" ]; then
  if ! bash "$__upstream/shellkit" vendor "$ROOT" --check; then
    printf 'check_vendor: 副本与上游不一致 —— 用上游 CLI 重新 vendor 一份\n' >&2
    __drift=1
  fi
fi

# --- L3：副本自检（副本要能装、能跑） ---
if [ ! -r "$VENDOR_DIR/tests/run.sh" ]; then
  printf 'check_vendor: 副本缺 tests/run.sh，无法自检\n' >&2
  exit 2
fi
if ! bash "$VENDOR_DIR/tests/run.sh"; then
  printf 'check_vendor: 副本自检未通过\n' >&2
  __drift=1
fi

if [ "$__drift" -ne 0 ]; then
  exit 1
fi
printf 'check_vendor: ok（副本与清单一致）\n'
exit 0
```

- [ ] **Step 4: 验证门禁能抓漂移（三条路都要堵）**

```bash
cd /Users/zhangyi/unix_script

echo '=== 正常：exit 0 ==='
bash tools/check_vendor.sh; echo "exit=$?"

echo '=== 漂移 1：手改副本里的文件 → exit 1 且点名该文件 ==='
cp vendor/shellkit/VERSION /tmp/vendor-version.bak
printf '\n# drift\n' >>vendor/shellkit/VERSION
bash tools/check_vendor.sh; echo "exit=$?"
cp /tmp/vendor-version.bak vendor/shellkit/VERSION

echo '=== 漂移 2：夹带清单外的文件 → exit 1 且点名 ==='
printf 'x\n' >vendor/shellkit/STRAY.txt
bash tools/check_vendor.sh; echo "exit=$?"
rm -f vendor/shellkit/STRAY.txt

echo '=== 漂移 3：删掉清单 → exit 2（不许自动重新生成） ==='
mv vendor/shellkit.sha256 /tmp/vendor-manifest.bak
bash tools/check_vendor.sh; echo "exit=$?"
mv /tmp/vendor-manifest.bak vendor/shellkit.sha256

echo '=== 复原：exit 0 ==='
bash tools/check_vendor.sh; echo "exit=$?"
```

- [ ] **Step 5: 提交**

```bash
cd /Users/zhangyi/unix_script
git add vendor tools/check_vendor.sh
git commit -m "build(vendor): 引入 shellkit 副本与副本一致性门禁"
```

---

## Task 14: unix_script `lib/uxs_i18n.sh` —— i18n 域配置

**Files:**
- Create: `lib/uxs_i18n.sh`
- Modify: `install.sh`（加载它）

**Interfaces:**
- Produces: `uxs_i18n_init ROOT` —— 设置 `SHELLKIT_I18N_DOMAIN=unix_script`、
  `SHELLKIT_I18N_DIRS="<ROOT>/locale:<shellkit locale>"`、`SHELLKIT_LANG=zh_CN`

- [ ] **Step 1: 写 `lib/uxs_i18n.sh`**

```bash
#!/usr/bin/env bash
#
# unix_script 的 i18n 配置。
#
# shellkit 的 _t 默认查 shellkit 域；unix_script 自己的文案走 unix_script 域。
# 两个域共用一套查找目录：先 unix_script 自己的 locale，再 shellkit 的 locale。
#
# SHELLKIT_LANG 默认 zh_CN：unix_script 的用户是中文优先，
# 没有 gettext 的机器靠 shellkit 的纯 bash 兜底表出中文。

# 幂等保护
if [[ -n "${_UXS_I18N_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_UXS_I18N_LOADED=1

# uxs_i18n_init ROOT —— 配置 i18n 域与查找目录
# ROOT 是 unix_script 仓库根（用来定位 locale/）。
uxs_i18n_init() {
    local root="${1:-${SCRIPT_DIR:-.}}"
    local sk_locale="$SHELLKIT_HOME/locale"

    export SHELLKIT_I18N_DOMAIN="unix_script"
    export SHELLKIT_I18N_DIRS="$root/locale:$sk_locale"
    export SHELLKIT_LANG="${SHELLKIT_LANG:-zh_CN}"
    export TEXTDOMAINDIR="$root/locale"

    # 设置域与目录发生在 bootstrap 之后，这里重新载入一次兜底表
    if declare -f _sk_i18n_load_tables >/dev/null 2>&1; then
        _SK_I18N_TABLES=""
        _sk_i18n_load_tables || true
    fi
    return 0
}
```

- [ ] **Step 2: 在 `install.sh` 里加载并调用**

在 `source "$SCRIPT_DIR/lib/common.sh"` **之前**加：

```bash
# shellkit 是唯一的基础库入口：先加载它，再加载 unix_script 自己的 lib。
source "$SCRIPT_DIR/vendor/shellkit/lib/bootstrap.sh"
```

在加载完 `lib/common.sh` 之后加：

```bash
source "$SCRIPT_DIR/lib/uxs_i18n.sh"
uxs_i18n_init "$SCRIPT_DIR"
```

- [ ] **Step 3: 验证**

```bash
cd /Users/zhangyi/unix_script
bash -n install.sh
./install.sh --list | head -3
bash tools/check_snapshot.sh; echo "exit=$?"
```
期望：快照 exit=0（i18n 改动不影响模块清单输出）。

- [ ] **Step 4: 提交**

```bash
cd /Users/zhangyi/unix_script
git add lib/uxs_i18n.sh install.sh
git commit -m "feat(i18n): 接上 shellkit 的 i18n 域与兜底表"
```

---

## Task 15: unix_script `lib/uxs_compat.sh` —— 能力函数转发门面

**Files:**
- Create: `lib/uxs_compat.sh`
- Modify: `lib/common.sh`（删掉被转发的那批能力函数，改为 source uxs_compat.sh）

**Interfaces:**
- Produces: 与既有 `lib/common.sh` **同名同义**的一组能力函数（见下表）

**必须逐字等价的映射（输出与退出码都要一致）：**

| 旧名 | 转发到 | 等价要求 |
|---|---|---|
| `detect_os` | `os_name` | 仍设置 `OS_TYPE`、`OS_KERNEL` |
| `detect_arch` | `os_arch` | 仍设置 `ARCH_TYPE`、`ARCH_TYPE_LOWER` |
| `detect_distro` | `os_distro_*` | 仍设置 `DISTRO_ID`、`DISTRO_VERSION_ID`、`DISTRO_NAME`、`DISTRO_FAMILY` |
| `detect_desktop` | `os_desktop_env` | 仍设置 `DESKTOP_ENV`、`IS_DESKTOP` |
| `detect_pkg_manager` | `os_pkg_manager` | 仍设置 `PKG_MANAGER`；brew 也要认 |
| `pkg_install` | `os_pkg_install_root` | 包管理器参数逐字一致 |
| `pkg_remove` | `os_pkg_remove_root` | 同上 |
| `pkg_installed` | `os_pkg_installed` | 同上 |
| `pkg_update` | `os_pkg_update_root` | 同上 |
| `command_exists` | `os_has_cmd` | 单参数包装 |
| `check_commands` | `require_cmd` | 缺命令时仍 `exit 1` 且报同样的中文 |
| `verify_sha256` | `net_verify` | 返回 0/非 0 即可（调用方都用 `if !`） |
| `version_gt` | `ver_gt` | 非法版本串保守判否 |
| `github_latest_tag` | `http_github_latest_tag` | 输出不带 v 前缀 |
| `github_release_asset_url` | `http_github_release_asset` | 输出 URL |
| `uxs_with_timeout` | `run_timeout` | 超时 rc=124 |
| `uxs_func_with_timeout` | `run_func_timeout` | 超时 rc=143 |
| `uxs_svc` | `svc_*` | action 语义逐条对应 |
| `install_systemd_unit` | `svc_install_unit` | 写 unit + daemon-reload |
| `emit_status/emit_version/emit_extra` | `status_*` | 输出形状逐字一致 |
| `uxs_is_machine_mode` | `status_is_machine` | 返回值语义一致 |

**不在本任务范围（Stage 1 不动）**：`info`、`success`、`warn`、`error`、`header`、`menu`、
`ensure_epel`、`require_sudo`、`dry_run_exec`、`dry_run_sudo`、`uxs_install_sudo_shim`、`get_local_ip`。

- [ ] **Step 1: 写 `lib/uxs_compat.sh`**

```bash
#!/usr/bin/env bash
#
# 能力函数转发门面（Stage 1 过渡层）。
#
# 为什么有这一层：Stage 1 不动 78 个模块脚本，它们调用的是 lib/common.sh 里的
# 旧函数名。直接删掉旧名会让全部模块崩，所以这里保留同名函数，转发到 shellkit。
#
# Stage 3 把 78 个模块逐个迁到 shellkit API 之后，这一层整体删除。
#
# 转发要求：**输出与退出码逐字等价**。unix_script 的行为快照门禁
# （tools/check_snapshot.sh）负责证明这一点。

# 幂等保护
if [[ -n "${_UXS_COMPAT_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_UXS_COMPAT_LOADED=1

# ---------- 平台 / 架构 ----------

# detect_os —— 设置 OS_TYPE / OS_KERNEL（兼容既有全局变量口径）
detect_os() {
    OS_KERNEL="$(uname -s)"
    OS_TYPE="$(os_name)"
    case "$OS_TYPE" in
        linux|darwin) return 0 ;;
        *)
            error "不支持的操作系统：$OS_KERNEL"
            exit 1
            ;;
    esac
}

# detect_arch —— 设置 ARCH_TYPE / ARCH_TYPE_LOWER
detect_arch() {
    ARCH_TYPE="$(os_arch)"
    case "$ARCH_TYPE" in
        aarch64) ARCH_TYPE="ARM64" ;;
        x86_64)  ARCH_TYPE="x86_64" ;;
    esac
    ARCH_TYPE_LOWER="$(printf '%s' "$ARCH_TYPE" | tr '[:upper:]' '[:lower:]')"
}

# detect_distro —— 设置 DISTRO_ID / DISTRO_VERSION_ID / DISTRO_NAME / DISTRO_FAMILY
detect_distro() {
    DISTRO_ID="$(os_distro_id "${1:-}")"
    DISTRO_VERSION_ID="$(os_release_field VERSION_ID "${1:-}")"
    DISTRO_NAME="$(os_distro_name "${1:-}")"
    DISTRO_FAMILY="$(os_distro_family "${1:-}")"
    return 0
}

# detect_desktop —— 设置 DESKTOP_ENV / IS_DESKTOP
detect_desktop() {
    DESKTOP_ENV="$(os_desktop_env)"
    if [[ "$DESKTOP_ENV" != "none" ]]; then IS_DESKTOP=1; else IS_DESKTOP=0; fi
    return 0
}

# ---------- 包管理 ----------

# detect_pkg_manager —— 设置 PKG_MANAGER
detect_pkg_manager() {
    PKG_MANAGER="$(os_pkg_manager 2>/dev/null)" || {
        # shellkit 不认 brew（brew 不是系统包管理器），这里补上
        if command -v brew >/dev/null 2>&1; then
            PKG_MANAGER="brew"
            return 0
        fi
        return 1
    }
    return 0
}

pkg_install()   { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_install_root "$@"; }
pkg_remove()    { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_remove_root "$@"; }
pkg_update()    { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_update_root; }
pkg_installed() { detect_pkg_manager || { error "无法识别包管理器"; return 1; }; os_pkg_installed "$@"; }

# ---------- 命令存在性 ----------

command_exists() { os_has_cmd "$@"; }

check_commands() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done
    if ((${#missing[@]} > 0)); then
        error "缺少必要命令：${missing[*]}"
        error "请先安装后再运行本脚本。"
        exit 1
    fi
}

# ---------- 校验 / 版本 ----------

verify_sha256() { net_verify "$@"; }
version_gt()    { ver_gt "$@"; }

# ---------- GitHub ----------

github_latest_tag()        { http_github_latest_tag "$@"; }
github_release_asset_url() { http_github_release_asset "$@"; }

# ---------- 超时 ----------

uxs_with_timeout()      { run_timeout "$@"; }
uxs_func_with_timeout() { run_func_timeout "$@"; }

# ---------- 服务管理 ----------

uxs_svc() {
    local action="$1"; shift
    if [[ "$action" != "daemon-reload" ]] && [[ $# -lt 1 ]]; then
        error "uxs_svc: 缺少 unit 参数" >&2
        return 1
    fi
    case "$action" in
        is-active)       svc_is_active "$@" ;;
        is-enabled)      svc_is_enabled "$@" ;;
        list-unit-files) systemctl list-unit-files "$@" ;;
        daemon-reload)   svc_daemon_reload ;;
        start)           svc_start "$@" ;;
        stop)            svc_stop "$@" ;;
        restart)         svc_restart "$@" ;;
        reload)          svc_reload "$@" ;;
        enable)          svc_enable "$@" ;;
        disable)         svc_disable "$@" ;;
        enable-now)      svc_enable_now "$@" ;;
        disable-now)     svc_disable_now "$@" ;;
        *)
            error "uxs_svc: 未知 action：$action" >&2
            return 1
            ;;
    esac
}

install_systemd_unit() { svc_install_unit "$@"; }

# ---------- 状态契约 ----------

emit_status()  { status_emit "$@"; }
emit_version() { status_version "$@"; }
emit_extra()   { status_extra "$@"; }
uxs_is_machine_mode() { status_is_machine; }
```

- [ ] **Step 2: 从 `lib/common.sh` 删掉被转发的函数，改 source 门面**

在 `lib/common.sh` 里删掉这些函数：`detect_os`、`detect_arch`、`detect_distro`、`detect_desktop`、
`detect_pkg_manager`、`pkg_install`、`pkg_remove`、`pkg_installed`、`pkg_update`、
`command_exists`、`check_commands`、`verify_sha256`、`version_gt`、
`github_latest_tag`、`github_release_asset_url`、`uxs_with_timeout`、`uxs_func_with_timeout`、
`uxs_svc`、`install_systemd_unit`、`emit_status`、`emit_version`、`emit_extra`、`uxs_is_machine_mode`。

在 `lib/common.sh` 顶部（幂等保护之后）加：

```bash
# shellkit 是唯一的基础库入口。
# 用自定位而不是 $SCRIPT_DIR：模块脚本 source 本文件时 $SCRIPT_DIR 是模块目录。
_UXS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
_UXS_ROOT="$(cd "$_UXS_COMMON_DIR/.." &>/dev/null && pwd)"
if [ -z "${SK_VERSION:-}" ]; then
    source "$_UXS_ROOT/vendor/shellkit/lib/bootstrap.sh"
fi

# 能力函数转发到 shellkit（Stage 1 过渡层，Stage 3 后删除）
source "$_UXS_COMMON_DIR/uxs_compat.sh"
```

- [ ] **Step 3: 验证**

```bash
cd /Users/zhangyi/unix_script
bash -n lib/common.sh lib/uxs_compat.sh
bash tools/check_snapshot.sh; echo "exit=$?"
bash tests/ci_run.sh --phase static; echo "exit=$?"
./dev-tools/bun/install.sh status; echo "exit=$?"
```
期望：快照 exit=0；static 相位全绿；模块 status 正常。

- [ ] **Step 4: 提交**

```bash
cd /Users/zhangyi/unix_script
git add lib/common.sh lib/uxs_compat.sh
git commit -m "refactor(lib): 能力函数转发到 shellkit —— 输出与退出码逐字等价"
```

---

## Task 16: unix_script 的 registry / deps / status / profile 改调 shellkit

**Files:**
- Modify: `lib/registry.sh`
- Modify: `lib/deps.sh`
- Modify: `lib/status.sh`
- Modify: `lib/profile.sh`
- Create: `tools/check_status_shape.sh`（状态输出的结构判据）

**Interfaces:**
- Consumes: `registry_scan`、`registry_get`、`registry_visible`、`registry_deps`、`registry_topo`、
  `status_*`、`profile_*`
- Produces: `tools/check_status_shape.sh` —— 校验 `--status-json` 的输出形状（每行 `key:value`，
  状态码在有限集里）；退出码 0 通过 / 1 不通过

- [ ] **Step 1: 写结构门禁 `tools/check_status_shape.sh`**

```bash
#!/usr/bin/env bash
#
# 状态输出的结构判据。
#
# 为什么不做逐字基线：--status-json 与各模块 status 的内容依赖**本机实际安装状态**，
# 同一份代码在两台机器上必然不同。逐字基线会变成永远的红。
# 能固定的是**形状**：每行 key:value、状态码在有限集里。
#
# 退出码：0 通过；1 不通过
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
VALID_STATES="not_installed installed installed:running installed:stopped configured not_configured n/a"

cd "$ROOT"
OUT="$(./install.sh --status-json 2>/dev/null)" || {
    printf 'check_status_shape: --status-json 执行失败\n' >&2
    exit 1
}

# 前 3 行是框架元数据（os/arch/version），跳过
BODY="$(printf '%s\n' "$OUT" | sed -n '4,$p')"

bad=0
while IFS= read -r __line; do
    [ -n "$__line" ] || continue
    case "$__line" in
        *:*) ;;
        *)
            printf 'check_status_shape: 不是 key:value 形态：%s\n' "$__line" >&2
            bad=1
            continue
            ;;
    esac
    __key="${__line%%:*}"
    __val="${__line#*:}"
    if [ -n "$__val" ]; then
        case " $VALID_STATES " in
            *" $__val "*) ;;
            *)
                printf 'check_status_shape: %s 的状态码不在有限集里：%s\n' "$__key" "$__val" >&2
                bad=1
                ;;
        esac
    fi
done <<< "$BODY"

if [ "$bad" -ne 0 ]; then
    printf 'check_status_shape: 状态输出形状不对\n' >&2
    exit 1
fi
printf 'check_status_shape: ok\n'
exit 0
```

- [ ] **Step 2: `lib/registry.sh` 改调 shellkit**

保留字段语义与查询 API（`registry_label`、`registry_desc`、`registry_category`、`registry_aliases`、
`registry_next_steps`、`registry_default_action`、`registry_has_submenu`、`registry_entry_script`、
`registry_requires`、`registry_exportable`、`registry_platforms`、`registry_search`、
`uxs_module_supported`），把「扫描 + 取值」换成 shellkit 的 `registry_*`：

```bash
# registry_scan —— 扫描各分类子目录下的 .manifest
registry_scan() {
    local category_dir dir mod manifest
    _REGISTRY_MODULES=""
    for category_dir in $_CATEGORY_DIRS; do
        [[ -d "$SCRIPT_DIR/$category_dir" ]] || continue
        for dir in "$SCRIPT_DIR/$category_dir"/*/; do
            [[ -d "$dir" ]] || continue
            mod="$(basename "$dir")"
            manifest="$dir/.manifest"
            [[ -f "$manifest" ]] || continue
            _reg_set "$mod" PHYSICAL_PATH "$category_dir/$mod"
            if _parse_manifest "$mod" "$manifest"; then
                _REGISTRY_MODULES="$_REGISTRY_MODULES $mod"
            fi
        done
    done
    _REGISTRY_MODULES="${_REGISTRY_MODULES# }"
    # shellkit 注册表：字段名由这里给出，shellkit 侧不认识这些名字
    registry_scan "$SCRIPT_DIR" '.manifest'
}
```

查询 API 改成读 shellkit 注册表（保持函数签名不变）：

```bash
registry_label()   { registry_get "$1" LABEL; }
registry_desc()    { registry_get "$1" DESC; }
registry_category(){ registry_get "$1" CATEGORY; }
registry_aliases() { registry_get "$1" ALIASES; }
registry_next_steps() { registry_get "$1" NEXT_STEPS; }
registry_default_action()  { local v; v="$(registry_get "$1" DEFAULT_ACTION)"; echo "${v:-install}"; }
registry_has_submenu()     { registry_get "$1" HAS_SUBMENU; }
registry_entry_script()    { local v; v="$(registry_get "$1" ENTRY_SCRIPT)"; echo "${v:-install.sh}"; }
registry_requires()        { local v; v="$(registry_get "$1" REQUIRES)"; echo "${v//,/ }"; }
registry_exportable()      { local v; v="$(registry_get "$1" EXPORTABLE)"; echo "${v//,/ }"; }
registry_platforms()       { local v; v="$(registry_get "$1" PLATFORMS)"; echo "${v//,/ }"; }

# uxs_module_supported <模块名> —— 当前 OS 是否适用（rc 0=适用/未声明，1=不适用）
uxs_module_supported() {
    registry_visible "$1" PLATFORMS
}
```

> ⚠️ `uxs_module_supported` 原来会调 `detect_os` 兜底（单测直接 source registry 时用）。
> 转发到 `registry_visible` 后由 `os_name` 负责判定，**行为等价**（两者都基于 uname）。

- [ ] **Step 3: `lib/deps.sh` 改调 shellkit 的拓扑**

保留既有函数名（`resolve_deps`、`topo_sort_all`）与环检测文案，改为：

```bash
# resolve_deps <mod> —— 传递依赖（拓扑序、不含自身）
resolve_deps() {
    registry_deps "$1" REQUIRES || {
        error "检测到循环依赖，请检查对应模块 .manifest 的 REQUIRES 字段"
        exit 1
    }
}

# topo_sort_all —— 全部模块的安全安装序
topo_sort_all() {
    registry_topo REQUIRES || {
        error "检测到循环依赖，请检查对应模块 .manifest 的 REQUIRES 字段"
        exit 1
    }
}
```

- [ ] **Step 4: `lib/status.sh` 与 `lib/profile.sh` 改调 shellkit**

`lib/status.sh` 里把 `UXS_STATUS_MODE=machine` 的判定统一到 `status_is_machine`
（`emit_*` 已由门面转发，函数体可保持原样）。

`lib/profile.sh` 里把读写 profile 的部分改成用 `profile_write`/`profile_append`/`profile_parse`，
「导哪些模块、哪些键」「apply 时怎么装」的领域逻辑留在 unix_script。

- [ ] **Step 5: 框架层退出码统一到 shellkit 口径**

规格 §7.6 要求 Stage 1 只在**框架层**统一退出码（模块脚本留到 Stage 3 随迁移一起改）：

| 失败场景 | 旧 | 新 |
|---|---|---|
| 用法错（参数不对、未知子命令） | 1 | 2 |
| 前置不满足（模块不存在、平台不适用、缺命令） | 1 | 3 |
| 网络失败（版本检查、GitHub 查询） | 1 | 4 |
| 校验失败（sha256 对不上） | 1 | 5 |
| 一般错误 | 1 | 1 |

改 `install.sh` 的分发层与 `lib/doctor.sh`、`lib/profile.sh`（export/apply）的失败路径。
**状态类子命令恒 0 的纪律不变**（`--status`/`--status-json`/`status` 子命令）。

改完必须跑一次人工核对：

```bash
cd /Users/zhangyi/unix_script
./install.sh --bogus-flag; echo "期望 2，实际 $?"
./install.sh definitely-not-a-module; echo "期望 3，实际 $?"
./install.sh --status-json >/dev/null; echo "期望 0，实际 $?"
```

- [ ] **Step 5b: status 契约健壮性 —— 修掉「export 整体中止」这个既有缺陷**

**实测到的现象**（与本次重构无关，base commit `e7d1ff4` 同样复现）：

```
$ ./install.sh export /tmp/p.txt > /tmp/p.out 2> /tmp/p.err; echo "exit=$?"
exit=1
$ cat /tmp/p.out /tmp/p.err      # 两边都是空的
$ cat /tmp/p.txt                 # 只剩 5 行头注，一个模块行都没有
```

**根因是两处缺陷叠加**：

1. `lib/status.sh` 的 `module_status_machine` 用管道
   `bash script status | sed -n 's/^STATE=//p' | head -1`
   —— 调用方（`install.sh`）开了 `set -o pipefail`，上游的退出码会被管道带出来；
   而 `head -1` 命中即退还会给上游 SIGPIPE（AGENTS.md 明令禁止的写法）。
   实测：`dev-mirror` 的 `status` 退出 1 ⇒ 该管道退出 1。
2. `dev-mirror/install.sh` 的 `status` 分支**退出 1**，违反 AGENTS.md 写明的
   「状态子命令始终退出 0（用于探测）」契约。
3. `lib/profile.sh` 的 `export_profile` 里 `state=$(module_status_machine "$mod")`
   在 `set -e` 下**整体中止** ⇒ export 只剩头注、无任何提示、退出 1。

**本任务要做的（lib 层是本任务范围，模块脚本只改这一个已知违规的）**：

- `module_status_machine` 改成**不依赖管道退出码**的写法：整条管道包在 `|| true` 兜底里，
  或改用不提前关闭管道的写法（例如 `sed -n 's/^STATE=//p'` 后用参数展开取首行）。
  契约：**函数自身恒返回 0**，模块 status 非 0 时仍返回状态值（取不到就返回 `not_installed`）。
- `export_profile` 里对单模块查询失败**不得**中止整批（同样加兜底），
  一个模块查不到只跳过该模块，其余照常导出。
- `dev-tools/dev-mirror/install.sh` 的 `status` 分支改为**退出 0**
  （这是契约违规的修复，单独成一个提交，提交信息写明「修复既有缺陷，与 Stage 1 重构无关」）。

**验收（必须实测，命令与输出写进报告）**：

```bash
cd /Users/zhangyi/unix_script
./install.sh export /tmp/uxs-export-fix.txt; echo "exit=$?"    # 期望 0
grep -c . /tmp/uxs-export-fix.txt                                # 期望 > 5（有模块行）
grep -q '^# unix_script profile' /tmp/uxs-export-fix.txt && echo "头注在"
bash dev-tools/dev-mirror/install.sh status; echo "dev-mirror exit=$?"  # 期望 0
```

- [ ] **Step 6: 验证**

```bash
cd /Users/zhangyi/unix_script
bash tools/check_snapshot.sh; echo "exit=$?"
bash tools/check_status_shape.sh; echo "exit=$?"
bash tests/ci_run.sh --phase static; echo "exit=$?"
bash tests/ci_run.sh --phase routing; echo "exit=$?"
```

- [ ] **Step 7: 提交**

```bash
cd /Users/zhangyi/unix_script
git add lib/registry.sh lib/deps.sh lib/status.sh lib/profile.sh tools/check_status_shape.sh install.sh
git commit -m "refactor(lib): 注册表/依赖/状态/profile 改调 shellkit；框架层退出码统一"
```

`dev-mirror` 的契约修复单独提交：

```bash
cd /Users/zhangyi/unix_script
git add dev-tools/dev-mirror/install.sh
git commit -m "fix(dev-mirror): status 退出码回到 0 —— 状态子命令恒 0 是既有契约"
```

---

## Task 17: 端到端验收

**Files:**
- 无代码改动（只跑门禁）

- [ ] **Step 1: 两仓门禁全绿**

```bash
cd /Users/zhangyi/shellkit && make check; echo "shellkit exit=$?"
cd /Users/zhangyi/unix_script
bash tests/ci_run.sh --phase static; echo "static exit=$?"
bash tests/ci_run.sh --phase routing; echo "routing exit=$?"
bash tools/check_snapshot.sh; echo "snapshot exit=$?"
bash tools/check_status_shape.sh; echo "shape exit=$?"
bash tools/check_vendor.sh; echo "vendor exit=$?"
```
全部期望 exit=0。

- [ ] **Step 2: bash 3.2 基线**

```bash
cd /Users/zhangyi/shellkit
/bin/bash tests/run.sh; echo "exit=$?"
```
期望：exit=0（这是 macOS 自带 bash 3.2 的真实结果；`bash tests/run.sh` 走 PATH 上的 5.3）。

- [ ] **Step 3: 抽样人工验收**

```bash
cd /Users/zhangyi/unix_script
./install.sh --list | head -5
./install.sh --list-modules | head -3
./install.sh --status-json | head -6
./install.sh doctor 2>&1 | tail -10
./install.sh --dry-run bun 2>&1 | head -10
```
逐条看过输出，确认没有异常、没有空输出、没有报错。

- [ ] **Step 4: 收口**

```bash
cd /Users/zhangyi/unix_script
git status --short
git log --oneline refactor/shellkit-stage1 -12
```
把本阶段的提交列表与验证结果写进 PR 描述（**不推送**，推送由用户决定）。

---

## 附录 A：Stage 1 之后的待办（不在本计划内）

- **Stage 2**：CLI v2（新分组子命令面 + 旧 flag 一次性删除 + AGENTS.md/README/docs/bootstrap/CI 同步）
- **Stage 3**：78 个模块分 5 批迁移到 shellkit API + 全量 msgid 化（1500~2500 条 msgid）
- **Stage 4**：删 `lib/uxs_compat.sh`、终稿文档、两仓发版

## 附录 B：风险与对策

| 风险 | 对策 |
|---|---|
| `os_pkg_install_root` 与既有 `pkg_install` 参数不一致，导致安装行为变化 | Task 3 明确「参数逐字一致」，Task 15 的等价表逐条对照 unix_script 原参数 |
| `registry_get` 的取值口径与既有 `_reg_get` 不同（引号/空白） | `registry_get` 沿用 unix_script 的去空白口径；Task 16 的验证覆盖 |
| shellkit 副本与上游分叉 | `tools/check_vendor.sh` 门禁 |
| 快照门禁误报（模块清单随仓库变化） | 快照只覆盖清单类输出；模块增删时显式重新生成基线并写进提交说明 |
| 纯 bash 兜底表在 bash 3.2 上解析慢（大 case） | 表按域分文件；实测 2500 条的启动耗时，超阈值则改为惰性载入 |
| `_t` 多域改动破坏既有 shellkit 行为 | 默认路径（不设新环境变量）逐字不变；Task 1 的测试覆盖新旧两条路径 |





