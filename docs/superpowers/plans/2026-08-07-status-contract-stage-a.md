# Stage A: status 输出契约统一 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 52 个模块的 `status` 子命令在 `UXS_STATUS_MODE=machine` 下输出规范 `STATE=` 行，人类模式输出逐字不变，`--status-json` 不再靠正则猜测。

**Architecture:** 在 `lib/common.sh` 增加 3 个 helper（`emit_status/emit_version/emit_extra`），由环境变量 `UXS_STATUS_MODE` 切换人类/机器输出；`lib/status.sh` 新增 `module_status_machine()`/`module_status_raw()`；`lib/menu.sh` 的 `show_status_json()` 改为读 `STATE=`；52 个模块的 status 函数按 pattern 分批迁移；CI 增加契约校验。

**Tech Stack:** Bash 3.2 兼容（macOS 默认），shellcheck， bats/纯 bash 测试。

## Global Constraints

- **bash 3.2 兼容**：禁用关联数组、`declare -A`、`mapfile`、`readarray`、`echo -e` 在子 shell 的 portability 假设。用空格分隔字符串模拟集合。
- **人类模式向后兼容**：默认 `UXS_STATUS_MODE=human` 时，输出与改造前**逐字一致**（含 emoji、颜色码、中文文案、额外信息行）。
- **规范状态码有限集**（来自 spec A.2）：`not_installed` / `installed:running` / `installed:stopped` / `installed` / `configured` / `not_configured` / `n/a`。机器模式首行必须是 `STATE=<上述之一>`。
- **模块函数命名不强制统一**：本次不重命名 `do_status()`/`show_status()`，只在函数体内部改用 helper。重命名留给后续清理。
- **shellcheck clean**：所有新代码需通过 `.shellcheckrc` 的规则。
- **每个 commit 一个逻辑单元**：lib 改造一个 commit，每个分类目录的模块迁移各一个 commit。

## 模块 status 形状分类（迁移批次依据）

调研结果（52 模块）：
- **P1 simple-two-state (11)**：brew, nvm, bun, deno, go, pnpm, rust, opencode, pi, restic, upftp — 输出 未安装/已安装，多数带版本。
- **P2 service-three-state (14)**：caddy, ddns-go, docker, gitea, grafana, nginx, node_exporter, openlist, postgres, prometheus, redis, tailscale, wireguard, ollama — 未安装/已安装并运行/已安装但未运行。
- **P3 config-two-state (4)**：bbr, swap, dev-enhance, multi-net — 已配置/未配置（多数带平台 guard 输出 n/a）。
- **P5 special (2)**：shutdown_timer, process_manager_tool — status 逻辑在 `lib/status.sh` 的 `check_*_status()`，不在模块 install.sh。
- **P6 other (21)**：certbot, cockpit, fail2ban, uptime-kuma, essential-pkgs, sys-setup, code-lint, dev-mirror, dev-tui, minikube, modern-cli, zsh_setup, clash, deskflow, disk-usage, docker-image, k7s, nat, safe-rm, sys-cmd, ufw — 多状态/多行/仪表盘/聚合，逐个定制。

---

## File Structure

| 文件 | 责任 | 本计划改动 |
|------|------|-----------|
| `lib/common.sh` | 共享函数库 | **新增** emit_status/emit_version/emit_extra（交互工具区之后，约 line 452） |
| `lib/status.sh` | 注册表驱动的状态查询 | **新增** module_status_machine/module_status_raw；**改造** check_shutdown_timer_status/check_process_manager_status 用 helper；module_status 注释更新 |
| `lib/menu.sh` | 机器可读输出 | **重写** show_status_json（删 if-grep，读 STATE=） |
| `tests/ci_run.sh` | CI 驱动 | **新增** status 契约校验函数，挂到 routing 阶段 |
| `services/*/install.sh` (17) | 服务模块 | status 函数迁移到 helper |
| `essentials/*/install.sh` (6) | 装机必备模块 | status 函数迁移 |
| `dev-tools/*/install.sh` (12) | 开发环境模块 | status 函数迁移 |
| `ai-tools/*/install.sh` (3) | AI 工具模块 | status 函数迁移 |
| `sys-tools/*/install.sh` (12，排除 P5 的 2 个) | 系统工具模块 | status 函数迁移 |
| `AGENTS.md` / `README.md` | 文档 | 更新 status-json 说明 |

---

## Task 1: 在 lib/common.sh 增加 emit_* helper

**Files:**
- Modify: `lib/common.sh:451`（在 `yes_no()` 函数之后追加）

**Interfaces:**
- Produces:
  - `emit_status <state> <human_msg>` — 人类模式 `echo -e "$human_msg"`；机器模式 `printf 'STATE=%s\n' "$state"`
  - `emit_version <version>` — 仅机器模式输出 `VERSION=<version>`；人类模式无输出（版本已在人类消息里）
  - `emit_extra <key=value>` — 仅机器模式输出 `EXTRA=<key=value>`；人类模式无输出

- [ ] **Step 1: 在 yes_no() 之后追加 helper 函数区**

在 `lib/common.sh` 末尾（`yes_no()` 函数的闭合 `}` 之后）追加：

```bash

# ---------------- status 输出契约 helper（UXS_STATUS_MODE 双轨）----------------
# 详见 docs/superpowers/specs/2026-08-07-status-contract-deps-profile-design.md 阶段 A。
# 人类模式（默认）：输出带颜色/emoji 的中文，向后兼容。
# 机器模式（UXS_STATUS_MODE=machine）：输出规范字段行，无颜色无 emoji。
#
# 规范状态码有限集：not_installed / installed:running / installed:stopped /
#                   installed / configured / not_configured / n/a

# emit_status <state> <human_msg>
# 人类模式：echo -e "$human_msg"（含颜色/emoji）
# 机器模式：printf 'STATE=%s\n' "$state"
emit_status() {
    local state="$1" human_msg="$2"
    if [[ "${UXS_STATUS_MODE:-human}" == "machine" ]]; then
        printf 'STATE=%s\n' "$state"
    else
        echo -e "$human_msg"
    fi
}

# emit_version <version>
# 仅机器模式输出 VERSION= 行（人类模式版本已在状态消息里，不重复）
emit_version() {
    [[ "${UXS_STATUS_MODE:-human}" == "machine" ]] && printf 'VERSION=%s\n' "$1"
}

# emit_extra <key=value>
# 仅机器模式输出 EXTRA= 行（人类模式的额外信息由模块自己 echo，并用 human 守卫包裹）
emit_extra() {
    [[ "${UXS_STATUS_MODE:-human}" == "machine" ]] && printf 'EXTRA=%s\n' "$1"
}

# uxs_is_machine_mode — 供模块判断是否需用 human 守卫包裹纯人类辅助输出
uxs_is_machine_mode() {
    [[ "${UXS_STATUS_MODE:-human}" == "machine" ]]
}
```

- [ ] **Step 2: 验证 helper 在两种模式下行为正确**

Run:
```bash
bash -c 'source lib/common.sh; emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"; emit_version "1.2.3"; emit_extra "registry=cn"'
```
Expected: 三行人类输出（绿字 ✅ 行 + 无 VERSION/EXTRA 行，因为默认 human 模式）。

Run:
```bash
UXS_STATUS_MODE=machine bash -c 'source lib/common.sh; emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC}"; emit_version "1.2.3"; emit_extra "registry=cn"'
```
Expected:
```
STATE=installed:running
VERSION=1.2.3
EXTRA=registry=cn
```
（无颜色码、无 emoji）

- [ ] **Step 3: shellcheck 通过**

Run: `shellcheck lib/common.sh`
Expected: 无新增错误（既有的 SC2034 豁免保持）。

- [ ] **Step 4: Commit**

```bash
git add lib/common.sh
git commit -m "feat(common): add emit_status/emit_version/emit_extra helpers (UXS_STATUS_MODE)

阶段 A 基础设施：双轨 status 输出契约。人类模式默认，向后兼容；
机器模式输出 STATE=/VERSION=/EXTRA= 规范字段，供 status-json/health/profile 复用。"
```

---

## Task 2: lib/status.sh 新增 machine 模式查询函数 + 改造 P5 特殊模块

**Files:**
- Modify: `lib/status.sh`（新增 `module_status_machine`/`module_status_raw`；改造 `check_shutdown_timer_status`/`check_process_manager_status`）

**Interfaces:**
- Consumes: `emit_status`/`emit_extra` from Task 1
- Produces:
  - `module_status_machine <mod>` — 输出某模块的 STATE 值（单一状态码字符串）
  - `module_status_raw <mod>` — 输出某模块 machine 模式完整原始输出（含 STATE=/VERSION=/EXTRA= 多行）

- [ ] **Step 1: 在 module_status() 之后新增 machine 模式查询函数**

在 `lib/status.sh` 的 `module_status()` 函数闭合 `}` 之后（约 line 27）追加：

```bash

# --- 机器模式查询（供 status-json / export / health 复用）---
# module_status_machine <模块名> -> 输出 STATE 值（单一状态码）
module_status_machine() {
    local mod="$1"
    local entry_script mod_path script
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>/dev/null \
        | sed -n 's/^STATE=//p' | head -1
}

# module_status_raw <模块名> -> 输出完整机器模式原始输出（STATE=/VERSION=/EXTRA=）
module_status_raw() {
    local mod="$1"
    local entry_script mod_path script
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo "STATE=not_installed"; return; }
    UXS_STATUS_MODE=machine bash "$script" status 2>/dev/null
}
```

- [ ] **Step 2: 改造 check_shutdown_timer_status 用 helper**

将 `lib/status.sh` 的 `check_shutdown_timer_status()`（约 line 30-44）替换为：

```bash
check_shutdown_timer_status() {
    local is_configured=false state human
    if [[ "$OS_TYPE" == "darwin" ]]; then
        [ -f "/Library/LaunchDaemons/com.user.dailyshutdown.plist" ] && is_configured=true
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if crontab -l 2>/dev/null | grep -q "# AUTO_SHUTDOWN_SCRIPT"; then
            is_configured=true
        fi
    fi
    if $is_configured; then
        state="configured"
        human="${GREEN}✅ 已配置每日定时关机${NC}"
    else
        state="not_configured"
        human="${RED}❌ 未配置${NC}"
    fi
    emit_status "$state" "$human"
}
```

- [ ] **Step 3: 改造 check_process_manager_status 用 helper**

将 `check_process_manager_status()`（约 line 46-60）替换为：

```bash
check_process_manager_status() {
    local is_installed=false state human
    if [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ]; then
        is_installed=true
    fi
    if $is_installed; then
        if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
            state="installed"
            human="${GREEN}✅ 已安装并配置${NC}"
        else
            state="installed"   # 已装但 PATH 未配，仍算 installed（用 EXTRA 标注）
            human="${YELLOW}⚠️  已安装但 PATH 未配置${NC}"
        fi
    else
        state="not_installed"
        human="${RED}❌ 未安装${NC}"
    fi
    emit_status "$state" "$human"
}
```

- [ ] **Step 4: 验证 machine 模式查询**

Run（在仓库根，已 `detect_os` 上下文由 lib 注入）:
```bash
bash -c 'source lib/common.sh; source lib/core.sh; source lib/registry.sh; source lib/status.sh; detect_os; registry_scan; echo "--- shutdown_timer machine ---"; module_status_machine shutdown_timer; echo "--- raw ---"; module_status_raw shutdown_timer'
```
Expected: `module_status_machine` 输出 `configured` 或 `not_configured`（单一状态码）；`module_status_raw` 输出 `STATE=...` 一行。

- [ ] **Step 5: shellcheck 通过**

Run: `shellcheck lib/status.sh`
Expected: 无错误。

- [ ] **Step 6: Commit**

```bash
git add lib/status.sh
git commit -m "feat(status): add module_status_machine/raw + migrate P5 special modules

新增 machine 模式查询 API；shutdown_timer/process_manager_tool 改用 emit_status。
为 show_status_json 重写和模块迁移做准备。"
```

---

## Task 3: 重写 lib/menu.sh 的 show_status_json()

**Files:**
- Modify: `lib/menu.sh:215-246`（`show_status_json()` 函数体）

**Interfaces:**
- Consumes: `module_status_raw` from Task 2
- Produces: `show_status_json()` 输出与现状格式一致（`module:state[:version]`），但实现从 7 层 if-grep 改为读 STATE=。

- [ ] **Step 1: 替换 show_status_json 函数体**

将 `lib/menu.sh` 的 `show_status_json()`（line 215-246）整个替换为：

```bash
show_status_json() {
    detect_os
    detect_arch
    echo "os:$OS_TYPE"
    echo "arch:$ARCH_TYPE"
    echo "version:$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"

    local mod raw state version line
    for mod in $_REGISTRY_MODULES; do
        raw=$(module_status_raw "$mod")
        state=$(echo "$raw" | sed -n 's/^STATE=//p' | head -1)
        version=$(echo "$raw" | sed -n 's/^VERSION=//p' | head -1)
        [[ -z "$state" ]] && state="unknown"
        line="$mod:$state"
        [[ -n "$version" ]] && line="$line:$version"
        printf '%s\n' "$line"
    done
}
```

- [ ] **Step 2: 验证 status-json 在迁移前仍工作（靠 legacy 兜底）**

注意：此时尚未迁移模块，模块的 status 函数还没输出 STATE=，所以 `module_status_raw` 会返回空（sed 提取不到 STATE=），`state` 会是 `unknown`。这是**预期**的中间状态——本 Task 只改菜单层。下一个 Task 起开始迁移模块后 state 才会变准。

Run: `./install.sh --status-json 2>/dev/null | head -10`
Expected: 每个模块行形如 `docker:unknown`（因为模块还没迁移）。os/arch/version 三行正常。

- [ ] **Step 3: shellcheck 通过**

Run: `shellcheck lib/menu.sh`
Expected: 无错误。

- [ ] **Step 4: Commit**

```bash
git add lib/menu.sh
git commit -m "refactor(menu): rewrite show_status_json to read STATE= (no more if-grep)

删掉 7 层中文关键词猜测，改为读 module_status_raw 的规范字段。
模块迁移完成后状态码将精确。过渡期未迁移模块显示 unknown（后续 Task 修复）。"
```

---

## Task 4: 迁移 services/ 模块（17 个，P2 为主）

**Files:**
- Modify: 17 个 `services/*/install.sh` 的 status 函数

**Interfaces:**
- Consumes: `emit_status`/`emit_version`/`emit_extra`/`uxs_is_machine_mode` from Task 1

**迁移模式参考（P2 service-three-state，以 docker 为例）：**

改造前：
```bash
status_docker() {
    if ! command_exists docker; then
        echo -e "${RED}❌ 未安装${NC}"
        return
    fi
    local ver; ver=$(docker --version 2>/dev/null || echo "")
    if [[ "$OS_TYPE" == "linux" ]]; then
        if systemctl is-active --quiet docker 2>/dev/null; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($ver)"
        else
            echo -e "${YELLOW}⚠️  已安装但服务未运行${NC} ($ver)"
        fi
    else
        if docker info >/dev/null 2>&1; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($ver)"
        else
            echo -e "${YELLOW}⚠️  已安装，但 Docker 守护进程未运行（请启动 Docker Desktop）${NC}"
        fi
    fi
}
```

改造后：
```bash
status_docker() {
    if ! command_exists docker; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
        return
    fi
    local ver; ver=$(docker --version 2>/dev/null || echo "")
    emit_version "$ver"
    if [[ "$OS_TYPE" == "linux" ]]; then
        if systemctl is-active --quiet docker 2>/dev/null; then
            emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC} ($ver)"
        else
            emit_status "installed:stopped" "${YELLOW}⚠️  已安装但服务未运行${NC} ($ver)"
        fi
    else
        if docker info >/dev/null 2>&1; then
            emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC} ($ver)"
        else
            emit_status "installed:stopped" "${YELLOW}⚠️  已安装，但 Docker 守护进程未运行（请启动 Docker Desktop）${NC}"
        fi
    fi
}
```

**关键规则（适用于所有模块）：**
1. 每个原本 `echo -e "..."` 的状态行 → 替换为 `emit_status "<码>" "原消息"`（原消息含颜色/emoji 原样保留）
2. 版本信息：原本内联在状态行的版本，额外调用 `emit_version "$ver"`（人类模式不重复输出，因为状态行已含版本；机器模式输出独立 VERSION= 行）
3. 额外信息行（如 bun 的 `registry:`、brew 的 `prefix:`）：用 `if ! uxs_is_machine_mode; then echo "..."; fi` 守卫包裹（人类模式保留，机器模式抑制以防污染 STATE= 解析），同时调用 `emit_extra "key=value"` 输出机器可读版本
4. 状态码映射：
   - 未安装 → `not_installed`
   - 已安装并运行 / 已安装且正在运行 → `installed:running`
   - 已安装但服务未运行 / 已安装但未运行 / 守护进程未运行 → `installed:stopped`
   - 已安装（无服务概念）→ `installed`
   - 不适用（仅 Linux/仅 macOS）→ `n/a`
5. **平台 guard**：原本输出 `不适用（仅 Linux）` 的分支 → `emit_status "n/a" "${YELLOW}⚠️  不适用（仅 Linux）${NC}"`

- [ ] **Step 1: 迁移所有 P2 services 模块（13 个）**

逐个改造（按字母序）：caddy, ddns-go, docker, gitea, grafana, nginx, node_exporter, openlist, postgres, prometheus, redis, tailscale, wireguard。

每个模块：打开 `services/<mod>/install.sh`，找到 status 函数（多数是 `status_<mod>`，nginx 是 `do_status`），按上述 P2 模式改造。注意 postgres/redis 的状态行内联了端口信息——端口作为 `emit_extra "port=$PORT"` 输出，人类行保留 `, 端口 $PORT`。wireguard 的 `(接口: wg0)` 同理用 extra。

- [ ] **Step 2: 迁移 P6 services 模块（4 个：certbot, cockpit, fail2ban, uptime-kuma）**

这 4 个有平台 guard 或非标准三态，逐个定制：

**certbot**（`do_status`）：未安装→not_installed；已安装→installed（certbot 无服务概念）。`自动续期`/`已申请证书` 额外行用 human 守卫包裹，续期状态用 `emit_extra "autorenew=enabled/disabled"`，证书数用 `emit_extra "certs=N"`。

**cockpit**（`status_cockpit`）：平台 guard（仅 Linux）→n/a；未安装→not_installed；`已安装并运行`→installed:running；`已安装（socket 模式，访问时激活）`→installed:stopped（语义最接近，socket 激活视为未持续运行）。

**fail2ban**（`status_fail2ban`）：平台 guard（仅 Linux）→n/a；未安装→not_installed；运行→installed:running；未运行→installed:stopped。

**uptime-kuma**（`status_uptime_kuma`）：`未安装（需 Docker）`→not_installed；`已安装并运行`→installed:running；`容器已创建但未运行`→installed:stopped。

- [ ] **Step 3: 逐个验证 machine 模式输出合法**

Run（对每个 services 模块）:
```bash
for mod in caddy certbot cockpit ddns-go docker fail2ban gitea grafana nginx node_exporter openlist postgres prometheus redis tailscale uptime-kuma wireguard; do
    path=$(find services -maxdepth 2 -name "$mod" -type d | head -1)
    echo "=== $mod ==="
    UXS_STATUS_MODE=machine bash "$path/install.sh" status 2>/dev/null | head -5
done
```
Expected: 每个模块首行为 `STATE=<合法码>`，合法码在有限集内。VERSION=/EXTRA= 行可选。

- [ ] **Step 4: 验证人类模式输出与改造前一致**

对 docker、nginx、redis 抽样：先 `git stash`（保存迁移改动），跑 `bash services/docker/install.sh status` 记录输出；`git stash pop` 恢复，再跑一次，diff 应为空。

Run:
```bash
# 记录改造前
git stash
bash services/docker/install.sh status > /tmp/docker_before.txt 2>/dev/null
git stash pop
# 记录改造后
bash services/docker/install.sh status > /tmp/docker_after.txt 2>/dev/null
diff /tmp/docker_before.txt /tmp/docker_after.txt && echo "IDENTICAL" || echo "DIFF FOUND"
```
Expected: `IDENTICAL`（人类模式零变化）。

对 nginx、redis 重复同样验证。

- [ ] **Step 5: shellcheck 通过（抽样）**

Run: `shellcheck services/docker/install.sh services/nginx/install.sh services/redis/install.sh`
Expected: 无错误（既有豁免保持）。

- [ ] **Step 6: Commit**

```bash
git add services/
git commit -m "feat(services): migrate 17 modules to emit_status contract (P2+P6)

所有 services/ 模块 status 函数改用 emit_status/emit_version/emit_extra。
人类模式输出逐字不变；机器模式输出规范 STATE= 行。
含 docker/nginx/redis 等 13 个 P2 服务模块 + certbot/cockpit/fail2ban/uptime-kuma 4 个 P6。"
```

---

## Task 5: 迁移 essentials/ 模块（6 个，P1/P3/P6 混合）

**Files:**
- Modify: 6 个 `essentials/*/install.sh` 的 status 函数

**迁移要点：**

**P1 模块（brew, nvm）：**
- brew（`status_brew`）：未安装→not_installed；已安装→installed。`prefix:`/`source:` 额外行用 human 守卫包裹，`emit_extra "prefix=..."`/`emit_extra "source=..."`。`emit_version "$ver"`。
- nvm（`status_nvm`）：未安装→not_installed；`已安装 nvm v<ver>`→installed。`emit_version "$ver"`。

**P3 模块（bbr, swap）：**
- bbr（`status_bbr`）：平台 guard（仅 Linux）→n/a；`BBR 已开启`→configured；`未开启 BBR`→not_configured。qdisc/算法用 extra。
- swap（`status_swap`）：平台 guard（仅 Linux）→n/a；`已启用 swap`→configured；`未启用 swap`→not_configured。`swapon --show` 表用 human 守卫包裹（机器模式不输出多行表格）。

**P6 模块（essential-pkgs, sys-setup）：**
- essential-pkgs（`status_pkgs`）：`必备工具已安装齐全`→installed；`缺少：...`→not_installed（缺工具视为未完成安装）。缺少的工具名用 `emit_extra "missing=a,b,c"`。
- sys-setup（`status_sys_setup`）：平台 guard（仅 Linux）→n/a；多行配置概览。主状态：若所有子项都 ✅→configured；任一为默认/未配→not_configured。子项详情（镜像源/时区/NTP/ulimit/SSH）用 human 守卫包裹 + `emit_extra` 各一个。

- [ ] **Step 1: 逐个迁移 6 个模块**

按上述要点改造 bbr, brew, essential-pkgs, nvm, swap, sys-setup。

- [ ] **Step 2: 验证 machine 模式**

Run:
```bash
for mod in bbr brew essential-pkgs nvm swap sys-setup; do
    echo "=== $mod ==="
    UXS_STATUS_MODE=machine bash "essentials/$mod/install.sh" status 2>/dev/null | head -8
done
```
Expected: 每个首行 `STATE=<合法码>`。bbr/swap/sys-setup 在 macOS 上应输出 `STATE=n/a`。

- [ ] **Step 3: 人类模式抽样比对（brew, swap）**

Run（brew）:
```bash
git stash
bash essentials/brew/install.sh status > /tmp/brew_before.txt 2>/dev/null
git stash pop
bash essentials/brew/install.sh status > /tmp/brew_after.txt 2>/dev/null
diff /tmp/brew_before.txt /tmp/brew_after.txt && echo "IDENTICAL"
```
Expected: `IDENTICAL`。

- [ ] **Step 4: shellcheck 抽样**

Run: `shellcheck essentials/brew/install.sh essentials/swap/install.sh`
Expected: 无错误。

- [ ] **Step 5: Commit**

```bash
git add essentials/
git commit -m "feat(essentials): migrate 6 modules to emit_status contract (P1+P3+P6)

brew/nvm (P1), bbr/swap (P3), essential-pkgs/sys-setup (P6)。
平台 guard 输出 n/a；config 类用 configured/not_configured。"
```

---

## Task 6: 迁移 dev-tools/ 模块（12 个，P1/P3/P6 混合）

**Files:**
- Modify: 12 个 `dev-tools/*/install.sh` 的 status 函数

**迁移要点：**

**P1 模块（bun, deno, go, pnpm, rust）：**
- bun（`status_bun`）：未安装→not_installed；已安装→installed。`registry:` 额外行用 human 守卫 + `emit_extra "registry=..."`。`emit_version`。
- deno/go/pnpm/rust：未安装→not_installed；已安装→installed。`emit_version`。

**P3 模块（dev-enhance）：**
- dev-enhance（`status_dev_enhance`）：`已配置`→configured；`未配置`→not_configured。`$parts` 用 `emit_extra "configured_parts=..."`。

**P6 模块（code-lint, dev-mirror, dev-tui, minikube, modern-cli, zsh_setup）：**
- code-lint（`status_code_lint`）：`全部已安装`→installed；`部分已安装`→installed（部分也算装了，用 extra 标注缺失）；`未安装任何工具`→not_installed。`emit_extra "installed=N/total"`、`emit_extra "missing=..."`。逐工具 ✅/❌ 清单用 human 守卫。
- dev-mirror（`do_status` 聚合）：每个语言的 registry 状态。主状态：若所有已装语言的镜像都已换→configured；否则 not_configured（或部分）。子项每语言用 `emit_extra "npm=..."` 等 + human 守卫。
- dev-tui（`status_dev_tui`）：`lazydocker + lazygit 已安装`→installed；`部分已安装`→installed（extra 标注）；`未安装`→not_installed。
- minikube（`do_status`）：`已安装并配置`→installed；`已安装但 PATH 未配置`→installed（emit_extra "path=unconfigured"）；`未安装`→not_installed。
- modern-cli（`status_modern_cli`）：bundle 检查，同 code-lint 模式。
- zsh_setup（`show_status`，支持 --json）：未安装→not_installed；已安装→installed。framework/theme/backup 用 extra + human 守卫。注意 zsh_setup 已有 --json 支持，本次只加 STATE= 头部，不破坏 --json。

- [ ] **Step 1: 逐个迁移 12 个模块**

按上述要点改造。

- [ ] **Step 2: 验证 machine 模式**

Run:
```bash
for mod in bun code-lint deno dev-enhance dev-mirror dev-tui go minikube modern-cli pnpm rust zsh_setup; do
    echo "=== $mod ==="
    UXS_STATUS_MODE=machine bash "dev-tools/$mod/install.sh" status 2>/dev/null | head -8
done
```
Expected: 每个首行 `STATE=<合法码>`。

- [ ] **Step 3: 人类模式抽样比对（bun, go）**

Run（bun，含 registry 额外行）:
```bash
git stash
bash dev-tools/bun/install.sh status > /tmp/bun_before.txt 2>/dev/null
git stash pop
bash dev-tools/bun/install.sh status > /tmp/bun_after.txt 2>/dev/null
diff /tmp/bun_before.txt /tmp/bun_after.txt && echo "IDENTICAL"
```
Expected: `IDENTICAL`。

- [ ] **Step 4: shellcheck 抽样**

Run: `shellcheck dev-tools/bun/install.sh dev-tools/zsh_setup/install.sh`
Expected: 无错误。

- [ ] **Step 5: Commit**

```bash
git add dev-tools/
git commit -m "feat(dev-tools): migrate 12 modules to emit_status contract (P1+P3+P6)

bun/deno/go/pnpm/rust (P1), dev-enhance (P3),
code-lint/dev-mirror/dev-tui/minikube/modern-cli/zsh_setup (P6)。
zsh_setup 保留既有 --json 支持，新增 STATE= 头部。"
```

---

## Task 7: 迁移 ai-tools/ 模块（3 个，P1/P2 混合）

**Files:**
- Modify: 3 个 `ai-tools/*/install.sh` 的 status 函数

**迁移要点：**
- ollama（`do_status`，P2）：未安装→not_installed；运行→installed:running；未运行→installed:stopped。
- opencode（`status_opencode`，P1）：未安装→not_installed；已安装→installed。`emit_version`。
- pi（`status_pi`，P1）：未安装→not_installed；已安装→installed。`emit_version`。

- [ ] **Step 1: 迁移 3 个模块**

- [ ] **Step 2: 验证 machine 模式**

Run:
```bash
for mod in ollama opencode pi; do
    echo "=== $mod ==="
    UXS_STATUS_MODE=machine bash "ai-tools/$mod/install.sh" status 2>/dev/null | head -5
done
```
Expected: 每个首行 `STATE=<合法码>`。

- [ ] **Step 3: 人类模式抽样比对（opencode）**

Run:
```bash
git stash
bash ai-tools/opencode/install.sh status > /tmp/opencode_before.txt 2>/dev/null
git stash pop
bash ai-tools/opencode/install.sh status > /tmp/opencode_after.txt 2>/dev/null
diff /tmp/opencode_before.txt /tmp/opencode_after.txt && echo "IDENTICAL"
```
Expected: `IDENTICAL`。

- [ ] **Step 4: Commit**

```bash
git add ai-tools/
git commit -m "feat(ai-tools): migrate 3 modules to emit_status contract

ollama (P2), opencode/pi (P1)。"
```

---

## Task 8: 迁移 sys-tools/ 模块（12 个非 P5，P1/P3/P6 混合）

**Files:**
- Modify: 12 个 `sys-tools/*/install.sh` 的 status 函数（排除 shutdown_timer 和 process_manager_tool，它们在 Task 2 已处理）

**迁移要点：**

**P1 模块（restic, upftp）：** 未安装→not_installed；已安装→installed。`emit_version`。

**P3 模块（multi-net）：** `status_multinet`。平台 guard（仅 Linux）→n/a；`已配置`→configured；`未配置`→not_configured。规则数用 extra。

**P6 模块（clash, deskflow, disk-usage, docker-image, k7s, nat, safe-rm, sys-cmd, ufw）：**
- clash（`status_clash`）：平台 guard→n/a；服务三态→installed:running/installed:stopped/not_installed。
- deskflow（`status_deskflow`）：平台 guard→n/a；未安装→not_installed；`已安装（Flatpak）`→installed。
- disk-usage（`status_disk`）：**特殊**——这不是安装状态，是仪表盘。主状态固定 `installed`（纯命令封装，始终可用）；emit_extra "dashboard=yes"。仪表盘表格用 human 守卫（机器模式不输出多行 df 表）。sys-cmd 同理。
- docker-image（`do_status`）：检查 docker 本身。`Docker 已安装且正在运行`→installed:running；`已安装但守护进程未运行`→installed:stopped；`未安装`→not_installed。
- k7s（`status_k7s`）：多源检测，已安装→installed（emit_extra "source=path" + emit_version）；未安装→not_installed。
- nat（`do_status`）：平台 guard→n/a；多行 NAT 概览。主状态：转发规则数>0→configured；否则 not_configured。子项用 extra + human 守卫。
- safe-rm（`status_safe_rm`）：`已安装 (未启用)`→installed（emit_extra "enabled=no"）；`已安装 (已启用 rm 保护)`→installed（emit_extra "enabled=yes"）；`未安装`→not_installed。回收站大小用 human 守卫。
- sys-cmd（`status_sys_cmd`）：固定 `可用（纯命令封装，无需安装）`→installed。emit_extra "type=builtin"。
- ufw（`status_ufw`）：平台 guard（macOS 输出不适用 + 配置路径）→n/a；未安装→not_installed；`已安装并启用`→configured（启用态）；`已安装但未启用`→not_configured。verbose dump 用 human 守卫。

- [ ] **Step 1: 逐个迁移 12 个模块**

按上述要点改造。

- [ ] **Step 2: 验证 machine 模式**

Run:
```bash
for mod in clash deskflow disk-usage docker-image k7s multi-net nat restic safe-rm sys-cmd ufw upftp; do
    echo "=== $mod ==="
    UXS_STATUS_MODE=machine bash "sys-tools/$mod/install.sh" status 2>/dev/null | head -8
done
```
Expected: 每个首行 `STATE=<合法码>`。clash/deskflow/multi-net/nat 在 macOS 上输出 `STATE=n/a`。

- [ ] **Step 3: 人类模式抽样比对（k7s, ufw）**

Run（k7s）:
```bash
git stash
bash sys-tools/k7s/install.sh status > /tmp/k7s_before.txt 2>/dev/null
git stash pop
bash sys-tools/k7s/install.sh status > /tmp/k7s_after.txt 2>/dev/null
diff /tmp/k7s_before.txt /tmp/k7s_after.txt && echo "IDENTICAL"
```
Expected: `IDENTICAL`。ufw 同样验证。

- [ ] **Step 4: shellcheck 抽样**

Run: `shellcheck sys-tools/disk-usage/install.sh sys-tools/ufw/install.sh`
Expected: 无错误。

- [ ] **Step 5: Commit**

```bash
git add sys-tools/
git commit -m "feat(sys-tools): migrate 12 modules to emit_status contract (excl P5)

restic/upftp (P1), multi-net (P3),
clash/deskflow/disk-usage/docker-image/k7s/nat/safe-rm/sys-cmd/ufw (P6)。
shutdown_timer/process_manager_tool 在 Task 2 已于 lib/status.sh 改造。"
```

---

## Task 9: 全量验证 status-json + 人类模式无回归

**Files:**
- 无文件改动，纯验证 Task

- [ ] **Step 1: 全量 status-json 检查（无 unknown）**

Run: `./install.sh --status-json 2>/dev/null`
Expected: 所有模块行的 state 字段在有限集内（`not_installed`/`installed:running`/`installed:stopped`/`installed`/`configured`/`not_configured`/`n/a`），**无 `unknown`**。

若发现 unknown：定位该模块，检查 status 函数是否漏了 emit_status 调用，回到对应 Task 修复。

- [ ] **Step 2: 全量人类模式抽样（每类至少 2 个）**

对每类至少 2 个模块，确认人类模式输出非空且含中文文案：
```bash
for mod in services/docker services/nginx essentials/brew essentials/swap dev-tools/bun dev-tools/zsh_setup ai-tools/ollama sys-tools/k7s sys-tools/ufw; do
    echo "=== $mod ==="
    bash "$mod/install.sh" status 2>/dev/null | head -3
done
```
Expected: 每个都有正常的人类输出（emoji/中文/颜色），无 `STATE=` 字样泄漏到人类模式。

- [ ] **Step 3: 确认 status 子命令退出码为 0**

Run:
```bash
for mod in docker bun brew; do
    bash "$(find . -maxdepth 3 -name install.sh -path "*/$mod/*" | head -1)" status >/dev/null 2>&1
    echo "$mod status exit: $?"
done
```
Expected: 全部退出 0（status 子命令用于探测，始终退出 0）。

- [ ] **Step 4: 如有问题，回到对应 Task 修复后重新验证**

本步骤不产生 commit（纯验证）。若全绿，进入 Task 10。

---

## Task 10: CI 增加 status 契约校验

**Files:**
- Modify: `tests/ci_run.sh`（新增 `check_status_contract` 函数，挂到 routing 阶段）

**Interfaces:**
- Consumes: 所有迁移完成的模块（Task 4-8）

- [ ] **Step 1: 在 ci_run.sh 新增 check_status_contract 函数**

在 `tests/ci_run.sh` 的合适位置（其他 check_* 函数附近）新增：

```bash
# ---------------- status 契约校验 ----------------
# 每个模块在 UXS_STATUS_MODE=machine 下首行必须是 STATE= 且值在有限集内。
# 复用 ci_run.sh 既有的报告 helper：report_row <name> <pass|fail|skip> [short]
check_status_contract() {
    local valid=" not_installed installed:running installed:stopped installed configured not_configured n/a "
    local cat_dirs="services essentials dev-tools ai-tools sys-tools"
    local cat_dir mod_dir mod first state
    for cat_dir in $cat_dirs; do
        [[ -d "$REPO_DIR/$cat_dir" ]] || continue
        for mod_dir in "$REPO_DIR/$cat_dir"/*/; do
            [[ -d "$mod_dir" ]] || continue
            mod=$(basename "$mod_dir")
            [[ -f "$mod_dir/install.sh" ]] || continue   # P5 模块无 install.sh，跳过
            first=$(UXS_STATUS_MODE=machine bash "$mod_dir/install.sh" status 2>/dev/null | head -1)
            if [[ "$first" != STATE=* ]]; then
                report_row "status 契约: $mod" fail "首行非 STATE=（实际: '$first'）"
                continue
            fi
            state="${first#STATE=}"
            if [[ " $valid " != *" $state "* ]]; then
                report_row "status 契约: $mod" fail "状态码 '$state' 不在有限集"
                continue
            fi
            report_row "status 契约: $mod" pass
        done
    done
}
```

注：`report_row` 是 ci_run.sh 既有的报告 helper（签名见 ci_run.sh line 54：`report_row <name> <pass|fail|skip> [short_msg]`）。`report_header`/`report_footer` 在 phase 函数开头/结尾成对调用。本函数只做逐模块断言，pass/fail 计入由 report_row 机制处理。

- [ ] **Step 2: 把 check_status_contract 挂到 routing 阶段**

在 `tests/ci_run.sh` 的 `phase_routing()` 函数内（line 142 起），在合适位置（其他逐模块检查旁边，`report_footer` 之前）插入对 `check_status_contract` 的调用。check_status_contract 内部用 `report_row` 逐模块报告，故直接调用即可，由 phase_routing 的 `report_header`/`report_footer` 包裹。

- [ ] **Step 3: 本地运行 routing 阶段验证**

Run: `./tests/ci_run.sh --phase routing`
Expected: 全部模块通过契约校验，退出码 0。若失败，报告会列出问题模块。

- [ ] **Step 4: shellcheck ci_run.sh**

Run: `shellcheck tests/ci_run.sh`
Expected: 无错误。

- [ ] **Step 5: Commit**

```bash
git add tests/ci_run.sh
git commit -m "test(ci): add status contract check (STATE= validity for all modules)

routing 阶段新增 check_status_contract：每个模块 machine 模式首行必须
是合法 STATE=。防止 status 函数回归破坏契约。"
```

---

## Task 11: 更新文档（AGENTS.md / README.md）

**Files:**
- Modify: `AGENTS.md`（更新 `--status-json` 输出说明，新增状态码表）
- Modify: `README.md`（如涉及 status 说明）

- [ ] **Step 1: 在 AGENTS.md 的"机器可读状态"章节补充状态码说明**

找到 `### 机器可读状态` 章节，在 `--status-json` 示例之后追加状态码表：

```markdown
状态码含义（state 字段）：

| 状态码 | 含义 |
|--------|------|
| `not_installed` | 未安装 |
| `installed` | 已安装（无服务概念，如 CLI 工具） |
| `installed:running` | 已安装且服务运行中 |
| `installed:stopped` | 已安装但服务未运行 |
| `configured` | 已配置（配置类模块） |
| `not_configured` | 未配置 |
| `n/a` | 当前平台不适用 |
```

- [ ] **Step 2: 在 AGENTS.md"模块子命令约定"补充 machine 模式说明**

在"模块子命令约定"表格后追加一段：

```markdown
### 机器可读 status（模块内部）

模块的 `status` 子命令支持环境变量 `UXS_STATUS_MODE=machine`，输出规范字段（无颜色无 emoji）：

```
STATE=<状态码>           # 必填，见上表
VERSION=<版本>           # 可选
EXTRA=<key=value>        # 可选，附加信息
```

模块作者使用 `lib/common.sh` 的 `emit_status`/`emit_version`/`emit_extra` helper 输出，人类模式默认向后兼容。详见 `docs/superpowers/specs/2026-08-07-status-contract-deps-profile-design.md`。
```

- [ ] **Step 3: 检查 README.md 是否需要同步**

Run: `grep -n "status-json\|status_json\|UXS_STATUS" README.md`
若有相关描述，同步更新；若无，跳过。

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md README.md
git commit -m "docs: document status contract (STATE codes + UXS_STATUS_MODE)

AGENTS.md 新增状态码表和 machine 模式协议说明，便于 AI agent 和模块作者使用。"
```

---

## Stage A 完成验收

全部 Task 完成后，确认：

- [ ] `./install.sh --status-json` 输出所有模块合法状态码，无 `unknown`
- [ ] `UXS_STATUS_MODE=machine <module>/install.sh status` 对全部 52 模块首行均为 `STATE=<合法码>`
- [ ] 人类模式（默认）抽样比对：docker/bun/brew/k7s/ufw/swap 输出与改造前逐字一致
- [ ] `./tests/ci_run.sh --phase static` 通过（shellcheck + bash -n）
- [ ] `./tests/ci_run.sh --phase routing` 通过（含新增 status 契约校验）
- [ ] AGENTS.md 文档更新

完成后，Stage A 闭环。可开始 Stage E（依赖图）的新一轮 brainstorm→plan。
