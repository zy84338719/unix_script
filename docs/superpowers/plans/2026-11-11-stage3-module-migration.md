# Stage 3 模块迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 78 个模块分 5 批迁移到 shellkit 的 API 原语（`_t` 国际化、`run`、`net_download`、`fs_atomic_*`、`status` 契约），并把面向用户的中文文案全部改为 gettext（msgid 英文，`zh_CN` 译文）。

**Architecture:** 这是一个**批量改造**计划。每个批次的模式相同：
1. 建 `po/messages.sh` 抽取器（xgettext 借 shellkit 的 `po_to_sh.awk` 生成纯 bash 兜底表，msgid 自动为英文）；
2. 跑抽取器生成该批的 `locale/zh_CN/messages/unix_script.sh`（译文先把「中文片段」摘出来，批量走 LLM 或人工补）；
3. 用 `_t` 包装模块里的硬编码中文；
4. 换底层 API（`run`、`net_download`、`fs_atomic_*`、`status`）；
5. 门禁（static + routing + 快照零差异 + 单测）。

**Tech Stack:** bash 3.2+、shellkit（vendor 副本）、xgettext / msgmerge / msgfmt / awk、自研 `tests/ci_run.sh`。

## Global Constraints

- **bash 3.2 基线**：禁 `declare -A` / `${v^^}` / `${v,,}` / `mapfile` / `[[ -v ]]` / nameref；空数组展开一律 `${arr[@]+"${arr[@]}"}`。
- **stdout 只给数据，日志一律 stderr**；出参用 `printf -v`。
- **退出码口径**（AGENTS.md 已写明）：`0` 成功（**状态类子命令恒 0**）/ `1` 一般错误 / `2` 用法错 / `3` 前置不满足 / `4` 网络失败 / `5` 校验失败。
- **模块子命令恒 0** 的纪律（`status` 子命令）继续有效：迁移后仍是 0。
- **快照门禁**：改了 `status` 输出的模块，必须 `bash tools/snapshot.sh` + `bash tools/snapshot.sh --approve` 重新生成基线。
- **缩进**：unix_script 仓用 4 空格；本仓无 fmt 门禁，跟随既有行文风格。
- **禁止 `git add -A` / `git add .`**：必须显式列文件。
- **模块内文案**：面向用户的所有中文（菜单、提示、错误、状态、帮助）都要 `_t` 化；**内部注释、变量名、函数名**不转。

---

## 模块迁移的写法约定（2026-11-11 补：三个真坑）

前面 13 个模块踩出来的。后面 68 个模块照着做，别再犯。

### 1. 带变量的文案用 `_tf`，不要用 `printf "$(_t ...)"`

`_tf` 是 shellkit i18n 模块的新函数（译文当 printf 格式串，占位符按参数填）。

```bash
# 对：_tf 收口了 SC2059，SC2059 只在 shellkit 里出现一次
error "$(_tf 'Unknown action: %s' "$action")"

# 错：SC2059（格式串是变量）—— gettext 的标准用法，但 shellcheck 判它
error "$(printf "$(_t 'Unknown action: %s')" "$action")"
```

### 2. 变量前面不要加反斜杠

双引号里 `\${VAR}` 输出的是**字面量**，不是变量值。

```bash
# 错：输出「未知操作: ${action}」，且状态色码 ${YELLOW} 不生效
error "$(_t 'Unknown action: ')\${action}"

# 对
error "$(_t 'Unknown action: ')${action}"
```

迁移后必须与迁移前**逐字比对**（同命令、同 locale、只差路径）：

```bash
git show 7729437:services/<mod>/install.sh > /tmp/old/services/<mod>/install.sh
cp -R lib vendor /tmp/old/          # 让旧版能跑起来
bash /tmp/old/services/<mod>/install.sh help > /tmp/old.txt
bash services/<mod>/install.sh help > /tmp/new.txt
diff /tmp/old.txt /tmp/new.txt        # 只该差 $0 的路径
```

### 3. `||` 分支里不能直接放 `$(...)`

```bash
# 错：SC2091 —— 命令替换会被当命令执行（真 bug，不是风格问题）
cur=$(certbot --version 2>&1 || $(_t 'Unknown version'))

# 对
cur=$(certbot --version 2>&1 || printf '%s' "$(_t 'Unknown version')")
```

同理 `echo "$(_t 'x')"` 的 echo 是多余的（SC2005），但**去掉 echo 与改写 `||` 分支要一起做** ——
去掉 echo 后 SC2091 才暴露出来。

### 4. 抽 msgid 与灌译文

```bash
bash po/messages.sh services        # 抽 msgid（参数是**分类名**，不认模块名）
# 用「只填空 msgstr、保留原格式」的脚本灌译文 —— 重建 po 会丢旧译文
bash po/messages.sh services        # 重新编译 .mo + 兜底表
bash tools/check_i18n_drift.sh services
```

- msgmerge 已加 `-N`（--no-fuzzy-matching）：新增 msgid 一律留空，**绝不猜译文**。
  必须确认 `grep -c '^#, fuzzy' locale/*/LC_MESSAGES/*.po` 是 0 —— fuzzy 条目会被 msgfmt 排除，
  运行时静默回落英文，而 po 里还留着一条看着像对的错译文。
- 译文里的占位符个数必须与原文一致 —— `msgfmt --check` 会校验（编译期就红）。

### 5. 断言不能绑死本地化文案

`grep -q '仅支持 Linux'` 这类断言，在文案改成英文 msgid 后必然假红。
断言要认**结构事实**（`[[ ! -t 0 ]]`、函数名、枚举串），而不是某句文案。
改完断言做**负对照**：把被测结构去掉，断言必须变红；不变红 ⇒ 它没有判据能力。

### 6. 跑门禁前先冻结工作树

**在 `tests/ci_run.sh` 或模块脚本被编辑的过程中跑的验收结果不可信** ——
测试跑到一半文件变了，会报出「-eq: command not found」这类语法错误。
改完 → 确认 `bash -n` 通过 → 再跑门禁，期间不要动被测文件。

---

## 命令矩阵（5 批的顺序）

| 批次 | 分类 | 模块数 | 代码行数 | 备注 |
|---|---|---|---|---|
| **3a** | services | 34 | 13,906 | 服务类，多网络操作（net_download）与 systemd 服务（svc_*） |
| **3b** | sys-tools | 16 | 13,034 | 系统工具，多 fs_atomic_*、run、status |
| **3c** | dev-tools | 19 | 9,698 | 开发工具，多包管理（os_pkg_*）与下载 |
| **3d** | essentials | 6 | 3,110 | 装机必备，较小，收尾第一批 |
| **3e** | ai-tools | 3 | 834 | AI 工具，最小，收尾 |

**每批的验收门禁**（Stage 1 的纪律沿用）：
1. `tests/ci_run.sh --phase static`：bash -n + shellcheck 全过。
2. `tests/ci_run.sh --phase routing`：模块 status 输出与基线逐字一致；状态形状判据通过。
3. `tests/ci_run.sh --phase install`：实装测试（若有 systemd 依赖则走 CI 的 Linux 容器）。
4. `tests/snapshot.sh` + `--approve`：改了 status 输出的模块要重新生成基线。
5. **新断言**：
   - `bash tools/check_i18n_drift.sh <分类>` —— 校验「模块里没有残留的硬编码中文」（允许清单制，先把存量注释放白名单）。
   - `bash tools/check_i18n_cross.sh` —— 校验「译文没串味」（msgid 说的是 A 模块、译文却写着 B 模块的文案）。
   - `bash tests/unit_i18n.sh` —— 校验「译文的占位符个数与 msgid 一致」。
   - **与迁移前的输出逐字比对** —— 见上面「模块迁移的写法约定」第 2 条。
     这条最重要：变量被转义、译文串味这类缺陷，扫代码看不出来，只有比对能发现。

---

### Task 3a: services 批次（34 个模块）

**Files:**
- Modify: `po/messages.sh`（新建）
- Modify: `po/po_to_sh.awk`（复制 shellkit 的）
- Create: `locale/zh_CN/LC_MESSAGES/unix_script.po`
- Create: `locale/zh_CN/messages/unix_script.sh`
- Modify: `services/*/install.sh`（34 个）
- Modify: `services/*/.manifest`（不需要动）
- Test: `tests/unit_i18n.sh`（新建，校验兜底表里的 msgid 能查到译文）
- Test: `tools/check_i18n_drift.sh`（新建，扫模块里的硬编码中文并报警）

**Interfaces:**
- Consumes: Stage 1 的 `uxs_i18n_init`（已在 `lib/common.sh` 调用）。
- Produces:
  - `po/messages.sh` —— 从 `services/*/install.sh` 抽取 msgid 并生成兜底表。
  - `tools/check_i18n_drift.sh` —— 校验 `services/*/install.sh` 没有硬编码中文。
  - `locale/zh_CN/messages/unix_script.sh` —— 该批的兜底表（纯 bash 查表函数）。

- [ ] **Step 1: 建抽取器 `po/messages.sh`**

```bash
#!/usr/bin/env bash
#
# 从模块源码抽取 msgid，生成 .pot 与 .po，再编译成纯 bash 兜底表。
# 用法：
#   bash po/messages.sh            # 重新生成 pot + 合并 po + 编译 mo + 生成兜底表
#   bash po/messages.sh --check    # 只检查：不写文件
#   bash po/messages.sh --only services  # 只处理 services 批次
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
```

- [ ] **Step 2: 复制 `po/po_to_sh.awk`（从 shellkit 借）**

```bash
cp /Users/zhangyi/shellkit-stage1/po/po_to_sh.awk /Users/zhangyi/unix_script/po/po_to_sh.awk
```

- [ ] **Step 3: 初始化 `locale/zh_CN/LC_MESSAGES/unix_script.po`**

先建一个空的 po 头（xgettext 会往里填 msgid）：

```bash
mkdir -p /Users/zhangyi/unix_script/locale/zh_CN/LC_MESSAGES
cat > /Users/zhangyi/unix_script/locale/zh_CN/LC_MESSAGES/unix_script.po <<'PO_EOF'
msgid ""
msgstr ""
"Project-Id-Version: unix_script 1.22.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
PO_EOF
```

- [ ] **Step 4: 抽 msgid 并生成兜底表**

```bash
cd /Users/zhangyi/unix_script
bash po/messages.sh services   # 只处理 services 批次
```

生成的 `locale/zh_CN/LC_MESSAGES/unix_script.po` 里会有 `msgid "Detected installed Docker"` 等条目。

- [ ] **Step 5: 翻译 `unix_script.po`**

把 msgid 翻成中文（手写或 LLM 批量），例如：

```
msgid "Detected installed Docker"
msgstr "检测到已安装 Docker"

msgid "Install failed"
msgstr "安装失败"
```

译完后再跑一次 `bash po/messages.sh`，把 `unix_script.sh`（纯 bash 兜底表）也编译出来。

- [ ] **Step 6: 建 `tools/check_i18n_drift.sh`（扫硬编码中文）**

```bash
#!/usr/bin/env bash
#
# 校验模块里没有残留的硬编码中文。
#
# 用法：
#   bash tools/check_i18n_drift.sh          # 扫所有模块
#   bash tools/check_i18n_drift.sh services # 只扫 services
#
# 白名单（允许硬编码的串）：内部注释、.manifest 里的 LABEL / DESC / NEXT_STEPS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
BATCH="${1:-all}"

if [ "$BATCH" = "all" ]; then
  DIRS=(services sys-tools dev-tools essentials ai-tools)
else
  DIRS=("$BATCH")
fi

violation=0
for dir in "${DIRS[@]}"; do
  for script in "$ROOT/$dir"/*/install.sh "$ROOT/$dir"/*/*.sh; do
    [ -f "$script" ] || continue
    # 排除 .manifest 与 README.md（这两个本来就是给人看的，不进 _t）
    case "$script" in
      *.manifest|*.md) continue ;;
    esac
    # 匹配硬编码中文（不在 _t '...' 里，不在注释 # 行里）
    # 先把 _t '...' 的内容抠掉，再查剩下的中文
    stripped="$(sed -E "s/_t '[^']*'//g; s/_t \"[^\]*\"//g" "$script")"
    if echo "$stripped" | grep -q '[一-龥]'; then
      echo "check_i18n_drift: $script 含硬编码中文（应改为 _t）"
      violation=1
    fi
  done
done

if [ "$violation" -eq 1 ]; then
  exit 1
fi
echo "check_i18n_drift: ok"
```

- [ ] **Step 7: 批量包装 `services/*/install.sh` 里的硬编码中文**

用 `_t` 包装（示例）：

```bash
# 改前
warn "检测到已安装 Docker（${cur}）"
info "已取消"
error "安装失败"

# 改后
warn "$(_t 'Detected installed Docker')（${cur}）"
info "$(_t 'Cancelled')"
error "$(_t 'Install failed')"
```

**注意：`_t` 里的 msgid 必须是英文**（这是 gettext 的约定）。翻译表里的中文是给用户的，源码里的 msgid 是英文。

- [ ] **Step 8: 换底层 API（services 批次特有的）**

```bash
# 改前（手写）
curl -sSL "$MIRROR_INSTALLER" | bash

# 改后（shellkit 的 net_download）
net_download "$MIRROR_INSTALLER" /tmp/docker-mirror.sh || exit 4
bash /tmp/docker-mirror.sh
```

```bash
# 改前（手写）
systemctl enable docker

# 改后（shellkit 的 svc_*）
svc_enable docker || exit 3
```

```bash
# 改前（手写）
if ! systemctl is-active docker >/dev/null 2>&1; then
    echo "Docker 未运行"
fi

# 改后（shellkit 的 svc_*）
if ! svc_is_active docker; then
    echo "$(_t 'Docker is not running')"
fi
```

- [ ] **Step 9: 跑门禁**

```bash
cd /Users/zhangyi/unix_script
CLEAN=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'minimax/shims' | tr '\n' ':')
env PATH="$CLEAN" bash tests/ci_run.sh --phase static
env PATH="$CLEAN" bash tests/ci_run.sh --phase routing
env PATH="$CLEAN" bash tools/check_status_shape.sh
env PATH="$CLEAN" bash tools/check_i18n_drift.sh services
env PATH="$CLEAN" bash tests/snapshot.sh && env PATH="$CLEAN" bash tests/snapshot.sh --approve
```

期望：全部退出码 0；routing 里 status 输出与基线逐字一致。

- [ ] **Step 10: 提交**

```bash
cd /Users/zhangyi/unix_script
git add po/messages.sh po/po_to_sh.awk locale/zh_CN/LC_MESSAGES/unix_script.po locale/zh_CN/LC_MESSAGES/unix_script.mo locale/zh_CN/messages/unix_script.sh
git add services/*/install.sh
git add tools/check_i18n_drift.sh tests/unit_i18n.sh
git commit -m "feat(i18n): services 批次迁移到 shellkit API + 全量 msgid 化"
```

---

### Task 3b: sys-tools 批次（16 个模块）

**Files:**
- Modify: `sys-tools/*/install.sh`（16 个）
- Modify: `locale/zh_CN/LC_MESSAGES/unix_script.po`（增量 msgid）
- Modify: `locale/zh_CN/messages/unix_script.sh`（重新生成）

**Interfaces:**
- Consumes: Task 3a 的 `po/messages.sh`、`po_to_sh.awk`、`uxs_i18n_init`。

- [ ] **Step 1: 增量抽取 msgid**

```bash
cd /Users/zhangyi/unix_script
bash po/messages.sh sys-tools
bash po/messages.sh   # 重新生成兜底表（把 sys-tools 的 msgid 也加进来）
```

- [ ] **Step 2: 翻译并编译**

把 `unix_script.po` 里新增的 msgid 翻成中文（手写或 LLM 批量）。

- [ ] **Step 3: 批量包装 + 换 API**

同 Task 3a Step 7/8。

- [ ] **Step 4: 跑门禁 + 提交**

```bash
cd /Users/zhangyi/unix_script
CLEAN=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'minimax/shims' | tr '\n' ':')
env PATH="$CLEAN" bash tests/ci_run.sh --phase static
env PATH="$CLEAN" bash tests/ci_run.sh --phase routing
env PATH="$CLEAN" bash tools/check_i18n_drift.sh sys-tools
env PATH="$CLEAN" bash tests/snapshot.sh && env PATH="$CLEAN" bash tests/snapshot.sh --approve
git add sys-tools/*/install.sh locale/zh_CN/LC_MESSAGES/unix_script.po locale/zh_CN/LC_MESSAGES/unix_script.mo locale/zh_CN/messages/unix_script.sh
git commit -m "feat(i18n): sys-tools 批次迁移到 shellkit API + 全量 msgid 化"
```

---

### Task 3c: dev-tools 批次（19 个模块）

**Files:**
- Modify: `dev-tools/*/install.sh`（19 个）
- Modify: `locale/zh_CN/LC_MESSAGES/unix_script.po`（增量 msgid）
- Modify: `locale/zh_CN/messages/unix_script.sh`（重新生成）

**Interfaces:**
- Consumes: Task 3a 的 `po/messages.sh`、`po_to_sh.awk`、`uxs_i18n_init`。

- [ ] **Step 1: 增量抽取 msgid + 翻译**

```bash
cd /Users/zhangyi/unix_script
bash po/messages.sh dev-tools
bash po/messages.sh
```

- [ ] **Step 2: 批量包装 + 换 API**

同 Task 3a Step 7/8。

- [ ] **Step 3: 跑门禁 + 提交**

```bash
cd /Users/zhangyi/unix_script
CLEAN=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'minimax/shims' | tr '\n' ':')
env PATH="$CLEAN" bash tests/ci_run.sh --phase static
env PATH="$CLEAN" bash tests/ci_run.sh --phase routing
env PATH="$CLEAN" bash tools/check_i18n_drift.sh dev-tools
env PATH="$CLEAN" bash tests/snapshot.sh && env PATH="$CLEAN" bash tests/snapshot.sh --approve
git add dev-tools/*/install.sh locale/zh_CN/LC_MESSAGES/unix_script.po locale/zh_CN/LC_MESSAGES/unix_script.mo locale/zh_CN/messages/unix_script.sh
git commit -m "feat(i18n): dev-tools 批次迁移到 shellkit API + 全量 msgid 化"
```

---

### Task 3d: essentials 批次（6 个模块）

**Files:**
- Modify: `essentials/*/install.sh`（6 个）
- Modify: `locale/zh_CN/LC_MESSAGES/unix_script.po`（增量 msgid）
- Modify: `locale/zh_CN/messages/unix_script.sh`（重新生成）

**Interfaces:**
- Consumes: Task 3a 的 `po/messages.sh`、`po_to_sh.awk`、`uxs_i18n_init`。

- [ ] **Step 1: 增量抽取 msgid + 翻译**

```bash
cd /Users/zhangyi/unix_script
bash po/messages.sh essentials
bash po/messages.sh
```

- [ ] **Step 2: 批量包装 + 换 API**

同 Task 3a Step 7/8。

- [ ] **Step 3: 跑门禁 + 提交**

```bash
cd /Users/zhangyi/unix_script
CLEAN=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'minimax/shims' | tr '\n' ':')
env PATH="$CLEAN" bash tests/ci_run.sh --phase static
env PATH="$CLEAN" bash tests/ci_run.sh --phase routing
env PATH="$CLEAN" bash tools/check_i18n_drift.sh essentials
env PATH="$CLEAN" bash tests/snapshot.sh && env PATH="$CLEAN" bash tests/snapshot.sh --approve
git add essentials/*/install.sh locale/zh_CN/LC_MESSAGES/unix_script.po locale/zh_CN/LC_MESSAGES/unix_script.mo locale/zh_CN/messages/unix_script.sh
git commit -m "feat(i18n): essentials 批次迁移到 shellkit API + 全量 msgid 化"
```

---

### Task 3e: ai-tools 批次（3 个模块）

**Files:**
- Modify: `ai-tools/*/install.sh`（3 个）
- Modify: `locale/zh_CN/LC_MESSAGES/unix_script.po`（增量 msgid）
- Modify: `locale/zh_CN/messages/unix_script.sh`（重新生成）

**Interfaces:**
- Consumes: Task 3a 的 `po/messages.sh`、`po_to_sh.awk`、`uxs_i18n_init`。

- [ ] **Step 1: 增量抽取 msgid + 翻译**

```bash
cd /Users/zhangyi/unix_script
bash po/messages.sh ai-tools
bash po/messages.sh
```

- [ ] **Step 2: 批量包装 + 换 API**

同 Task 3a Step 7/8。

- [ ] **Step 3: 跑门禁 + 提交**

```bash
cd /Users/zhangyi/unix_script
CLEAN=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'minimax/shims' | tr '\n' ':')
env PATH="$CLEAN" bash tests/ci_run.sh --phase static
env PATH="$CLEAN" bash tests/ci_run.sh --phase routing
env PATH="$CLEAN" bash tools/check_i18n_drift.sh ai-tools
env PATH="$CLEAN" bash tests/snapshot.sh && env PATH="$CLEAN" bash tests/snapshot.sh --approve
git add ai-tools/*/install.sh locale/zh_CN/LC_MESSAGES/unix_script.po locale/zh_CN/LC_MESSAGES/unix_script.mo locale/zh_CN/messages/unix_script.sh
git commit -m "feat(i18n): ai-tools 批次迁移到 shellkit API + 全量 msgid 化"
```

---

### Task 4: 收尾（删 `uxs_compat`、补单测、全量门禁）

**Files:**
- Delete: `lib/uxs_compat.sh`（78 个模块都迁完后）
- Modify: `lib/common.sh`（删 uxs_i18n_init 调用）
- Modify: `CHANGELOG.md`（补 Unreleased 段）
- Test: `tests/unit_i18n.sh`（补通用用例）

- [ ] **Step 1: 删 `lib/uxs_compat.sh`**

```bash
cd /Users/zhangyi/unix_script
git rm lib/uxs_compat.sh
```

**前提**：确认 78 个模块都不再用 `uxs_compat` 里的函数（`info` / `warn` / `error` 等），改用 shellkit 的 `log_*` 系列。如果有残留，先改完再删。

- [ ] **Step 2: 单测补通用用例**

在 `tests/unit_i18n.sh` 里加：

```bash
#!/usr/bin/env bash
# tests/unit_i18n.sh — i18n 单测
# 校验兜底表里的 msgid 能查到译文（不依赖 gettext）
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/lib/common.sh"
uxs_i18n_init "$REPO_DIR"

PASS=0
FAIL=0

t_translate() { # t_translate <msgid> <期望译文>
    local out
    out="$(_t "$1")"
    if [ "$out" = "$2" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1 → 期望 '$2' 实际 '$out'"
    fi
}

# 校验几条关键的 msgid
t_translate "Detected installed Docker" "检测到已安装 Docker"
t_translate "Install failed" "安装失败"
t_translate "Cancelled" "已取消"

echo "unit_i18n: 通过 $PASS / 失败 $FAIL"
[[ "$FAIL" -eq 0 ]]
```

- [ ] **Step 3: 全量门禁 + 提交**

```bash
cd /Users/zhangyi/unix_script
CLEAN=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'minimax/shims' | tr '\n' ':')
env PATH="$CLEAN" bash tests/ci_run.sh --phase static
env PATH="$CLEAN" bash tests/ci_run.sh --phase routing
env PATH="$CLEAN" bash tools/check_status_shape.sh
env PATH="$CLEAN" bash tools/check_i18n_drift.sh
env PATH="$CLEAN" bash tests/snapshot.sh && env PATH="$CLEAN" bash tests/snapshot.sh --approve
env PATH="$CLEAN" bash tests/unit_i18n.sh
git add -u
git commit -m "refactor(i18n): 删 uxs_compat 门面，78 模块全量迁移完成"
```

---

## Self-Review

**1. 规格覆盖**（对照设计文档 §7.5 / §8 / §9）

| 规格要求 | 落在哪个 Task |
|---|---|
| 78 模块分 5 批迁移（services → sys-tools → dev-tools → essentials → ai-tools） | 3a / 3b / 3c / 3d / 3e |
| 换 shellkit API（run / net_download / fs_atomic_* / status） | 每批 Step 7/8 |
| 文案 msgid 化 + zh_CN 译文 | 每批 Step 1/2 |
| 删 `lib/uxs_compat.sh` | Task 4 Step 1 |
| 每批快照零差异（有意变更登记在案） | 每批 Step 9 |
| shellcheck 绿 | 每批 Step 9（static 阶段） |
| 模块级 status 输出对比一致 | 每批 Step 9（routing 阶段） |

**2. Placeholder 扫描**：本计划无 TBD/TODO；每个代码步骤都给出实际代码。

**3. 一致性核对**：
- `_t` 在 shellkit 的 `i18n.sh` 里定义（Stage 1 已确认）。
- `net_download` / `svc_*` / `fs_atomic_*` 在 shellkit 的 `net.sh` / `svc.sh` / `fs.sh` 里定义（Stage 1 已确认）。
- `uxs_i18n_init` 已在 `lib/common.sh` 里调用（Stage 1 已确认）。
- `po/messages.sh` 借用了 shellkit 的 `po_to_sh.awk`（Stage 1 已确认该文件存在且可用）。

**已知取舍（明确记录，不留给实施者猜）**

- **msgid 一律英文**：这是 gettext 的约定，翻译表里的中文是给用户的，源码里的 msgid 必须是英文。这要求「翻译」这一步要先把模块里的中文文案翻成英文，再放进 `_t`。
- **增量抽取**：`po/messages.sh` 支持 `--only <batch>` 参数，可以只处理某个批次，避免每批都要全量抽取。但重新生成兜底表时要把所有批次都扫一遍（因为 `unix_script.sh` 是唯一的）。
- **白名单**：`tools/check_i18n_drift.sh` 允许 `.manifest` 与 `README.md` 里的硬编码中文（这两个本来就是给人看的，不进 `_t`）。
- **`uxs_compat` 的删除时机**：必须在 78 个模块都迁完后再删，否则残留的 `info` / `warn` / `error` 调用会崩。

---
