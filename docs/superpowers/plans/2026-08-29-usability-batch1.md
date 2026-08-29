# 易用性快修包批次① Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `--status-json` 从 2m16s 降到秒级且永不被单模块截断；doctor/ufw 无 TTY 误报清零；dry-run 压制 brew auto-update；机器可读输出文档补齐。

**Architecture:** 框架层复用 `status_batch_query` 并行批查（扩展为捕获 STATE+VERSION）；新增可移植 `uxs_with_timeout` 超时护栏；ufw/doctor 改降级与跳过逻辑。输出格式零变化。

**Tech Stack:** 纯 bash（3.2 兼容）+ perl（超时护栏，近universal）；测试为本仓库自带 unit 脚本 + `tests/ci_run.sh` assert。

**Spec:** `docs/superpowers/specs/2026-08-29-usability-batch1-design.md`

## Global Constraints

- 执行前用 `git worktree` 隔离工作分支（本仓库有并行 agent 会话共用工作区，禁止直接在共享 main 上改）；基础分支 `main`
- bash 3.2 兼容：不用关联数组、`wait -n`、`mapfile`
- shellcheck 干净：以 `shellcheck -e SC2164,SC1091,SC2317,SC2329 -x <file>` 为准（与 `tests/ci_run.sh:127` 一致）
- `--status-json` 输出格式不变：头 3 行 `os:/arch:/version:` + 每模块一行 `模块:状态[:版本]`；54 模块时恒为 57 行
- 状态子命令（status）永远退出 0；安装类失败退出非 0
- 面向人的输出为中文，风格与现有 `info/warn/success/error` 一致；管道下无颜色（沿用现有函数即可）
- 每个任务收尾跑 `bash tests/unit_usability.sh` 必须全过

---

### Task 1: `uxs_with_timeout` 超时护栏（lib/common.sh）

**Files:**
- Modify: `lib/common.sh`（追加在 `uxs_install_sudo_shim` 函数之后）
- Create: `tests/unit_usability.sh`
- Modify: `tests/ci_run.sh`（注册单测，见 Step 5）

**Interfaces:**
- Consumes: `command_exists`（common.sh 已有）
- Produces: `uxs_with_timeout <秒> <命令...>`——超时 rc=124（GNU timeout 对齐）；子命令被信号终止 rc=128+信号；其余透传命令退出码；perl 缺失时不套超时直接执行
- Produces: 测试文件 harness `t_eq`（沿用 unit_platform.sh 模式）、`t_true <名称> <条件命令>`

- [ ] **Step 1: 写失败测试（tests/unit_usability.sh 新建）**

```bash
#!/usr/bin/env bash
#
# tests/unit_usability.sh — 易用性快修包批次① 单测
# 覆盖：uxs_with_timeout / status 批查容错 / --status-json 防截断 / doctor 无 TTY / ufw 降级链 / dry-run 副作用
# 独立运行：bash tests/unit_usability.sh（退出码 0=全过）
# 也被 tests/ci_run.sh 调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望> <实际>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}

t_true() {  # t_true <名称> <条件命令>
    if eval "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1"
    fi
}

# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
set +e +o pipefail

# ---------- uxs_with_timeout ----------
rc=$(uxs_with_timeout 2 true; echo $?)
t_eq "timeout: 快命令透传 rc=0" "0" "$rc"

rc=$(uxs_with_timeout 2 false; echo $?)
t_eq "timeout: 失败命令透传 rc=1" "1" "$rc"

S=$SECONDS
rc=$(uxs_with_timeout 1 sleep 5 >/dev/null 2>&1; echo $?)
ELAPSED=$((SECONDS - S))
t_eq "timeout: 超时 rc=124" "124" "$rc"
t_true "timeout: 超时及时返回（实测 ${ELAPSED}s ≤ 2s）" "(( ELAPSED <= 2 ))"

# ---------- 汇总 ----------
echo "通过 $PASS / 失败 $FAIL"
[[ "$FAIL" -eq 0 ]]
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_usability.sh`
Expected: FAIL（`uxs_with_timeout: command not found` 类错误）

- [ ] **Step 3: 实现（lib/common.sh，追加在 `uxs_install_sudo_shim` 的 `fi` 之后）**

```bash
# ---------------- 超时护栏 ----------------
# uxs_with_timeout <秒> <命令...> — 带超时执行命令（macOS/Linux 通用，无 GNU timeout 依赖）。
# 契约：超时 rc=124（与 GNU timeout 对齐）；子命令被信号终止 rc=128+信号；其余透传退出码。
# perl 缺失（极简容器）时不套超时直接执行，行为退化为无护栏。
# 实现：perl fork + alarm + kill。不能 exec——exec 后 alarm 虽存活但无法返回 124。
uxs_with_timeout() {
    local secs="$1"
    shift
    if ! command_exists perl; then
        "$@"
        return
    fi
    perl -e '
        my $secs = shift @ARGV;
        my @cmd  = @ARGV;
        my $pid = fork();
        if (!defined $pid) { exit 125; }
        if ($pid == 0) { exec(@cmd) or exit 127; }
        $SIG{ALRM} = sub {
            kill "TERM", $pid;
            sleep 1;
            kill "KILL", $pid;
            exit 124;
        };
        alarm $secs;
        waitpid $pid, 0;
        alarm 0;
        my $st = $?;
        if ($st & 127) { exit(128 + ($st & 127)); }
        exit($st >> 8);
    ' "$secs" "$@"
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/unit_usability.sh`
Expected: `通过 4 / 失败 0`，退出 0

- [ ] **Step 5: 注册到 tests/ci_run.sh（routing 阶段）**

在 `check_status_contract` 调用行（`grep -n "check_status_contract" tests/ci_run.sh` 定位）之后加一行：

```bash
    assert "usability: 批次① 单测全过" bash "$REPO_DIR/tests/unit_usability.sh"
```

Run: `bash tests/ci_run.sh --phase routing 2>&1 | grep usability`
Expected: 该 assert 出现且状态 ✅（若整阶段有其他环境性失败，只看本行）

- [ ] **Step 6: shellcheck + 提交**

```bash
shellcheck -e SC2164,SC1091,SC2317,SC2329 -x lib/common.sh tests/unit_usability.sh
git add lib/common.sh tests/unit_usability.sh tests/ci_run.sh
git commit -m "feat(lib): uxs_with_timeout 可移植超时护栏（perl fork+alarm，rc=124 对齐 GNU）"
```

---

### Task 2: ufw status 三级降级链（sys-tools/ufw/install.sh）

**Files:**
- Modify: `sys-tools/ufw/install.sh:129-141`（`status_ufw` 内 `local ufw_status` 起的判断块）
- Modify: `tests/unit_usability.sh`（追加 ufw 测试段）

**Interfaces:**
- Consumes: `emit_status` / `uxs_is_machine_mode` / `command_exists`（common.sh 已有）
- Produces: `status_ufw` 在任何路径都输出一行 `STATE=`（机器模式），退出 0；降级映射：`sudo -n ufw status` 成功→configured/not_configured（原语义），失败→`systemctl is-active ufw` active→installed:running 否则 installed，systemctl 也没有→installed

- [ ] **Step 1: 追加失败测试（tests/unit_usability.sh 末尾汇总段之前）**

注意：本测试段整体包在 `if [[ "$(uname)" == "Linux" ]]; then ... fi` 里（macOS 走 n/a 分支测不了链路）。

```bash
# ---------- ufw 三级降级链（仅 Linux；macOS 上 ufw status=n/a）----------
if [[ "$(uname)" == "Linux" ]]; then
    UFW_SH="$REPO_DIR/sys-tools/ufw/install.sh"
    FAKE=$(mktemp -d)

    # 降级1：sudo -n 成功（原语义保留）
    printf '#!/bin/sh\necho "Status: active"\n' > "$FAKE/sudo"
    chmod +x "$FAKE/sudo"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 可用 active→configured" "configured" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    printf '#!/bin/sh\necho "Status: inactive"\n' > "$FAKE/sudo"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 可用 inactive→not_configured" "not_configured" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    # 降级2：sudo -n 失败（无凭据/无 TTY），systemctl 兜底
    printf '#!/bin/sh\nexit 1\n' > "$FAKE/sudo"
    printf '#!/bin/sh\necho active\n' > "$FAKE/systemctl"
    chmod +x "$FAKE/sudo" "$FAKE/systemctl"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 失败 systemctl active→installed:running" "installed:running" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    printf '#!/bin/sh\nexit 3\n' > "$FAKE/systemctl"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 失败 systemctl inactive→installed" "installed" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    # 降级3：sudo 与 systemctl 全失败 → 兜底 installed，且必有输出
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_true "ufw: 全失败兜底仍有 STATE= 输出" "printf '%s' \"\$out\" | grep -q '^STATE='"
    rm -rf "$FAKE"
fi
```

（若测试机没装 ufw，`command_exists ufw` 先行返回 not_installed——测试前需保证 ufw 在 PATH；CI Ubuntu 容器自带。若本地无 ufw，用 `printf '#!/bin/sh\nexit 0\n' > "$FAKE/ufw"` 一并注入 FAKE PATH，**推荐直接注入**，不依赖测试机装没装：）

```bash
    printf '#!/bin/sh\nexit 0\n' > "$FAKE/ufw"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_usability.sh`
Expected: Linux 上 ufw 各用例 FAIL（现实现 `sudo ufw status` 被假 sudo 返回空 → not_configured，与 installed:running 期望不符；且无输出用例可能过——以实际为准，至少降级2的两条 FAIL）

- [ ] **Step 3: 实现（替换 status_ufw 中 `local ufw_status` 到函数尾的判断块）**

```bash
    # 三级降级：sudo -n ufw status → systemctl is-active ufw → 兜底 installed。
    # 防 set -e/pipefail 中止：所有命令替换带 || true，任何路径必须落到一个 emit_status。
    local ufw_status sysd
    ufw_status=""
    if ufw_status=$(sudo -n ufw status 2>/dev/null | head -1 || true) && [[ -n "$ufw_status" ]]; then
        if [[ "$ufw_status" == *"active"* ]]; then
            emit_status "configured" "${GREEN}已安装并启用${NC}"
            if ! uxs_is_machine_mode; then
                echo
                sudo -n ufw status verbose 2>/dev/null || sudo ufw status verbose
            fi
        else
            emit_status "not_configured" "${YELLOW}已安装但未启用${NC}"
        fi
        return
    fi
    # sudo 不可用（无凭据/无 TTY）：降级 systemd 单元状态
    if command_exists systemctl && sysd=$(systemctl is-active ufw 2>/dev/null || true); then
        if [[ "$sysd" == "active" ]]; then
            emit_status "installed:running" "${GREEN}已安装且服务运行中（降级检测）${NC}"
        else
            emit_status "installed" "${YELLOW}已安装（sudo 不可用，降级检测）${NC}"
        fi
        return
    fi
    # systemctl 也没有：命令存在即视为已装
    emit_status "installed" "${YELLOW}已安装（无法读取详细状态）${NC}"
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/unit_usability.sh`
Expected: 全过（含 Task 1 的 4 条）

- [ ] **Step 5: shellcheck + 提交**

```bash
shellcheck -e SC2164,SC1091,SC2317,SC2329 -x sys-tools/ufw/install.sh
git add sys-tools/ufw/install.sh tests/unit_usability.sh
git commit -m "fix(ufw): status 三级降级链——sudo -n 探测 + systemctl 兜底，杜绝无 TTY 静默中止"
```

---

### Task 3: doctor 无 TTY 误报修复（lib/doctor.sh）

**Files:**
- Modify: `lib/doctor.sh`（发行版检测段 + sudo 检测段）
- Modify: `tests/unit_usability.sh`（追加 doctor 测试段）

**Interfaces:**
- Consumes: `detect_distro`/`detect_os`（common.sh 已有）；`OS_TYPE`
- Produces: 无 TTY（`[[ ! -t 0 ]]`）时 sudo 检查输出「无法检测 sudo（非交互环境），已跳过」且不计入问题数；macOS 发行版缺失输出 INFO「macOS 不适用发行版检测（已跳过）」不计问题数；Linux 缺 os-release 仍 WARNING 计数

- [ ] **Step 1: 追加失败测试（ufw 测试段之后）**

```bash
# ---------- doctor 无 TTY（管道即无 TTY，测试天然满足）----------
DOC_OUT=$(bash "$REPO_DIR/install.sh" doctor </dev/null 2>&1)
t_true "doctor: 无 TTY 时 sudo 项跳过不误报" "printf '%s' \"\$DOC_OUT\" | grep -q '无法检测 sudo'"
t_true "doctor: 无 TTY 时无 sudo 不可用误报" "! printf '%s' \"\$DOC_OUT\" | grep -q 'sudo 不可用'"
if [[ "$(uname)" == "Darwin" ]]; then
    t_true "doctor: macOS 不再把缺 os-release 计为 WARNING" "! printf '%s' \"\$DOC_OUT\" | grep -q '未能识别发行版'"
    t_true "doctor: macOS 显示已跳过" "printf '%s' \"\$DOC_OUT\" | grep -q '不适用发行版检测'"
fi
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_usability.sh`
Expected: doctor 各用例 FAIL（现实现输出「sudo 不可用」，macOS 输出「未能识别发行版」）

- [ ] **Step 3: 实现**

发行版段（`detect_distro` 调用后的 if/else）改为：

```bash
    detect_distro
    if [[ -n "$DISTRO_ID" ]]; then
        success "发行版：$DISTRO_NAME（ID=$DISTRO_ID 版本=${DISTRO_VERSION_ID:-未知}，${DISTRO_FAMILY} 系）"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "macOS 不适用发行版检测（已跳过）"
    else
        warn "未能识别发行版（缺少 /etc/os-release，包系族按包管理器判定）"
    fi
```

sudo 段（`# Sudo` 注释下的 if/elif 链）改为：

```bash
    if [[ $EUID -eq 0 ]]; then
        success "当前以 root 运行 ✓"
    elif [[ ! -t 0 ]]; then
        # 无 TTY 时 sudo -v 无法交互输密码，检测必然失败——按跳过处理，不计问题
        info "无法检测 sudo（非交互环境），已跳过"
    elif sudo -n true 2>/dev/null; then
        success "sudo 可用（免密） ✓"
    elif sudo -v 2>/dev/null; then
        success "sudo 可用 ✓"
    else
        warn "sudo 不可用（部分安装操作可能失败）"
        ((issues++))
    fi
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/unit_usability.sh`
Expected: 全过

- [ ] **Step 5: shellcheck + 提交**

```bash
shellcheck -e SC2164,SC1091,SC2317,SC2329 -x lib/doctor.sh
git add lib/doctor.sh tests/unit_usability.sh
git commit -m "fix(doctor): 无 TTY 时 sudo 检测按跳过处理；macOS 缺 os-release 降为 INFO"
```

---

### Task 4: `--status-json` 并行化 + 防截断（lib/status.sh + lib/menu.sh）

**Files:**
- Modify: `lib/status.sh`（`status_batch_query` + 新增 version 缓存 helper）
- Modify: `lib/menu.sh:387-405`（`show_status_json`）
- Modify: `tests/unit_usability.sh`（追加防截断测试段）
- Modify: 慢模块 `install.sh`（Step 4 确认的阻塞点，详见该步决策规则）

**Interfaces:**
- Consumes: `module_status_raw`（status.sh 已有，输出 STATE=/VERSION=/EXTRA= 原始行）
- Produces: `status_batch_query <mods...>`——批查后同时填充 STATE 与 VERSION 两级内存缓存（原 STATE 契约不变，菜单零感知）
- Produces: `_uxs_version_set <mod> <ver>` / `_uxs_version_get <mod>`（镜像 `_uxs_state_set`/`status_state_get` 的 eval 模式）

- [ ] **Step 1: 追加失败测试（doctor 测试段之后）**

```bash
# ---------- --status-json 防截断 + 批查容错 ----------
status_batch_query __no_such_mod__ 2>/dev/null
t_eq "批查: 不存在模块兜底 unknown" "unknown" "$(status_state_get __no_such_mod__)"

cd "$REPO_DIR"
N_LIST=$(./install.sh --list | tr ' ' '\n' | grep -c .)
N_JSON=$(./install.sh --status-json | tail -n +4 | grep -c .)
t_eq "status-json: 模块行数完整（防 ufw 式截断）" "$N_LIST" "$N_JSON"
N_META=$(./install.sh --status-json | head -3 | grep -cE '^(os|arch|version):')
t_eq "status-json: 头 3 行元数据仍在" "3" "$N_META"
cd - >/dev/null
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_usability.sh`
Expected: 「批查: 不存在模块兜底 unknown」可能过（现有实现已容错）；「模块行数完整」在无故障环境也会过（它防的是回归）——本步允许这两条现状即过，**真正失败的是 version 列缺失**：补充一条带版本模块的断言（本机 bun 已装时）：

```bash
# 已装 bun 时：status-json 必须保留版本列（批查改造不丢 VERSION）
t_eq "status-json: 版本列保留（bun）" "$(./install.sh --status-json | sed -n 's/^bun:installed://p')" "$(bun --version 2>/dev/null || echo __bun_absent__)"
```

（bun 未装时期望为 `__bun_absent__`、实际行为空行不匹配——先本地确认 bun 已装；未装环境跳过本条：用 `if command -v bun >/dev/null; then ... fi` 包裹。）

- [ ] **Step 3: 实现 status.sh（version helper + 批查改造）**

在 `status_state_get` 之后新增：

```bash
# --- 版本内存态（--status-json 的版本列用；镜像 _uxs_state_* 模式）---
_uxs_version_varname() {
    local safe_mod="${1//-/_}"
    echo "_UXS_VERSION_${safe_mod}"
}

_uxs_version_set() {
    local varname
    varname=$(_uxs_version_varname "$1")
    eval "${varname}=\$2"
}

_uxs_version_get() {
    local varname
    varname=$(_uxs_version_varname "$1")
    eval "echo \"\${${varname}:-}\""
}
```

`status_batch_query` 整体替换为（任务子进程改抓 raw，回填解析 STATE+VERSION）：

```bash
# --- 并行批查：固定并发跑 module_status_raw，解析 STATE+VERSION 进内存 ---
status_batch_query() {
    local jobs="${UXS_STATUS_JOBS:-8}"
    if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then jobs=8; fi
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/uxs-status.XXXXXX")
    local mod running=0
    for mod in "$@"; do
        (
            local raw
            raw=$(module_status_raw "$mod" 2>/dev/null || true)
            printf '%s' "$raw" > "$tmpdir/$mod"
        ) &
        running=$((running + 1))
        if (( running >= jobs )); then
            wait
            running=0
        fi
    done
    wait
    local state version
    for mod in "$@"; do
        state=""; version=""
        if [[ -f "$tmpdir/$mod" ]]; then
            state=$(sed -n 's/^STATE=//p' "$tmpdir/$mod" | head -1)
            version=$(sed -n 's/^VERSION=//p' "$tmpdir/$mod" | head -1)
        fi
        [[ -z "$state" ]] && state="unknown"
        _uxs_state_set "$mod" "$state"
        _uxs_version_set "$mod" "$version"
    done
    rm -rf "$tmpdir"
}
```

- [ ] **Step 4: 实现 menu.sh（show_status_json 整体替换）**

```bash
show_status_json() {
    detect_os
    detect_arch
    echo "os:$OS_TYPE"
    echo "arch:$ARCH_TYPE"
    echo "version:$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"

    local mod state version line
    status_batch_query $_REGISTRY_MODULES
    for mod in $_REGISTRY_MODULES; do
        state=$(status_state_get "$mod")
        [[ -z "$state" ]] && state="unknown"
        version=$(_uxs_version_get "$mod")
        line="$mod:$state"
        [[ -n "$version" ]] && line="$line:$version"
        printf '%s\n' "$line"
    done
}
```

- [ ] **Step 5: 慢模块阻塞点定位与加护栏（决策规则明确，逐模块执行）**

对 spec 点名的 4 个模块逐一定位（在 macOS 与 Linux 各跑一次，取慢的那次的结果）：

```bash
# 例（tailscale）：读 status 函数里每个对外命令，逐个计时
grep -n "status" services/tailscale/install.sh
time tailscale version; time tailscale status; time tailscale ip -4 2>/dev/null
# clash/docker/k7s 同法：先 grep 出 status 路径上调用的外部命令，再逐个 time
```

决策规则：**实测 >1s 的命令才加护栏**，写法统一为 `结果=$(uxs_with_timeout 5 <命令> ...)`（超时 5 秒）。若某模块慢因是 macOS 本机特有（如 tailscale GUI 守护），而 CI/服务器 Linux 上 <1s，则不加护栏、在本任务 commit message 里记录实测数据。预期候选（以实测为准，不盲加）：tailscale 的 `tailscale status`、docker 的 `docker info`/`docker version`、k7s 的 `kubectl version` 类网络探测。

- [ ] **Step 6: 跑测试 + 计时验证**

```bash
bash tests/unit_usability.sh
time ./install.sh --status-json > /dev/null
```
Expected: 全过；耗时从 2m16s 级降到 ≲15s（macOS，受未加护栏模块残余影响）/ 容器内秒级

- [ ] **Step 7: shellcheck + 提交**

```bash
shellcheck -e SC2164,SC1091,SC2317,SC2329 -x lib/status.sh lib/menu.sh services/tailscale/install.sh sys-tools/clash/install.sh services/docker/install.sh sys-tools/k7s/install.sh
git add lib/status.sh lib/menu.sh tests/unit_usability.sh services/tailscale/install.sh sys-tools/clash/install.sh services/docker/install.sh sys-tools/k7s/install.sh
git commit -m "feat(status): --status-json 并行批查（STATE+VERSION 双缓存）+ 单模块故障恒定输出 unknown"
```

（git add 按实际改动的模块文件增删；未改的模块不要 add。）

---

### Task 5: dry-run 压制 brew auto-update（lib/common.sh）

**Files:**
- Modify: `lib/common.sh`（`uxs_install_sudo_shim` 函数体首行）
- Modify: `tests/unit_usability.sh`（追加 dry-run 测试段）

**Interfaces:**
- Consumes: `uxs_install_sudo_shim`（dry-run 统一入口，install.sh 与菜单共用）
- Produces: dry-run 启用后环境变量 `HOMEBREW_NO_AUTO_UPDATE=1`（尊重调用方已有值）

- [ ] **Step 1: 追加失败测试（防截断测试段之后）**

```bash
# ---------- dry-run：brew auto-update 副作用压制 ----------
unset HOMEBREW_NO_AUTO_UPDATE
uxs_install_sudo_shim
t_eq "dry-run: shim 注入 HOMEBREW_NO_AUTO_UPDATE=1" "1" "${HOMEBREW_NO_AUTO_UPDATE:-}"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_usability.sh`
Expected: 该条 FAIL（实际为空）

- [ ] **Step 3: 实现（uxs_install_sudo_shim 函数体首行加 export）**

```bash
uxs_install_sudo_shim() {
    # dry-run 顺带压制 brew auto-update：纯网络副作用（更新 tap）违背预览语义且拖慢执行
    export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
    sudo() {
        info "[dry-run] sudo $*"
        return 0
    }
}
```

- [ ] **Step 4: 跑测试确认通过 + 实测 dry-run 不再 auto-update**

```bash
bash tests/unit_usability.sh
./install.sh --dry-run essential-pkgs 2>&1 | head -8
```
Expected: 全过；dry-run 输出不再出现 `Auto-updating Homebrew`

- [ ] **Step 5: shellcheck + 提交**

```bash
shellcheck -e SC2164,SC1091,SC2317,SC2329 -x lib/common.sh
git add lib/common.sh tests/unit_usability.sh
git commit -m "fix(dry-run): 压制 Homebrew auto-update 网络副作用（HOMEBREW_NO_AUTO_UPDATE=1）"
```

---

### Task 6: 文档补齐 + 全量回归（AGENTS.md / README.md / CHANGELOG.md）

**Files:**
- Modify: `AGENTS.md`（`--status-json` 状态码表格之前）
- Modify: `README.md`（「机器可读输出」节示例）
- Modify: `CHANGELOG.md`（`[Unreleased]` 节，无则新建）

**Interfaces:**
- Consumes: 无
- Produces: 文档与实现一致

- [ ] **Step 1: AGENTS.md 补元数据行说明**

在 AGENTS.md `### 机器可读状态` 一节的 `--status-json` 代码示例后追加：

```markdown
输出首部固定 3 行框架元数据（AI 解析时跳过前 3 行，或按 key 是否为模块名判断）：

```
os:darwin       # 宿主 OS（darwin/linux）
arch:ARM64      # CPU 架构
version:1.13.0  # unix_script 自身版本
```
```

- [ ] **Step 2: README.md 示例同步**

「🤖 机器可读输出」节第 2 个示例块改为带头 3 行：

```bash
# 2) 当前安装状态（key:value，无颜色无 emoji；首 3 行为框架元数据 os/arch/version）
$ ./install.sh --status-json
os:darwin
arch:ARM64
version:1.13.0
node_exporter:not_installed
docker:installed:running
bun:installed:v1.3.14
```

- [ ] **Step 3: CHANGELOG.md `[Unreleased]` 记录**

在 `[Unreleased]` 下 Added/Fixed/Changed 记录本批 5 项（标题原文引用各 commit message 主题）：

```markdown
### Added
- `uxs_with_timeout` 可移植超时护栏（lib 层动词，perl fork+alarm，rc=124 对齐 GNU timeout）

### Fixed
- `--status-json` 并行批查提速（串行 2 分钟级 → 秒级），单模块故障恒定输出 `:unknown`，不再截断
- ufw status 三级降级链，无 TTY/无 sudo 凭据不再静默中止
- doctor 无 TTY 时 sudo 检测按跳过处理；macOS 缺 os-release 降为 INFO
- dry-run 模式压制 Homebrew auto-update 网络副作用
```

（version 号以合入时 VERSION 为准，不入本段。）

- [ ] **Step 4: 全量回归**

```bash
./tests/ci_run.sh --phase static
./tests/ci_run.sh --phase routing
```
Expected: static 全绿（bash -n + shellcheck 211+ 项）；routing 全绿（含新 usability assert）

- [ ] **Step 5: 提交**

```bash
git add AGENTS.md README.md CHANGELOG.md
git commit -m "docs: 补 --status-json 头部元数据说明；CHANGELOG 记录易用性快修包批次①"
```

---

## 任务依赖与顺序

Task 1 → Task 2 → Task 3 互相独立可并行（仅共享测试文件，注意追加段落时按任务序放）；Task 4 依赖 Task 1（uxs_with_timeout）；Task 5、6 依赖前置任务在分支上。推荐严格按 1→2→3→4→5→6 串行。

## 完成定义（DoD）

- [ ] `bash tests/unit_usability.sh` 全过
- [ ] `./tests/ci_run.sh --phase static` 与 `--phase routing` 全绿
- [ ] macOS 实测 `time ./install.sh --status-json` 耗时 ≤ 15s 且输出行数 = 模块数 + 3
- [ ] `./install.sh --dry-run essential-pkgs` 输出无 `Auto-updating Homebrew`
- [ ] 管道跑 `./install.sh doctor` 无「sudo 不可用」误报
- [ ] CHANGELOG/AGENTS/README 与实现一致
