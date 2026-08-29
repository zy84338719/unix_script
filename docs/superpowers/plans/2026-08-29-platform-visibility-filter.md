# 平台可见性过滤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 模块用 `.manifest` 的 `PLATFORMS` 键声明适用 OS，框架在所有模块枚举出口隐藏当前系统不适用的模块，`UNIX_SCRIPT_SHOW_ALL=1` 恢复全量。

**Architecture:** registry 层新增纯判定 API（`uxs_module_supported` / `uxs_module_visible` / `registry_visible_modules`），所有出口（CLI 列表/搜索/状态、交互菜单、dispatch、profile）改为消费可见列表；`_REGISTRY_MODULES` 本体不变，dispatch/别名/依赖仍基于全量。规格：`docs/superpowers/specs/2026-08-29-platform-visibility-filter-design.md`。

**Tech Stack:** 纯 bash（bash 3.2 兼容），测试为仓库自有 t_eq/t_rc/t_true 断言脚本 + `tests/ci_run.sh --phase routing`。

## Global Constraints

- bash 3.2 兼容：无关联数组、无 `${var,,}`、无 `wait -n`（沿用 registry 的 eval 动态变量模式）
- 模块名连字符转下划线的 `_reg_varname` 约定不变；`_REGISTRY_MODULES` 本体不被过滤改动
- escape hatch 环境变量名精确为 `UNIX_SCRIPT_SHOW_ALL`（值 `1` 生效）；manifest 键名精确为 `PLATFORMS`，取值 `linux` / `darwin` 逗号分隔
- 过滤函数在 `set -euo pipefail` 下 rc 安全（失败分支不得触发 set -e 误杀，参照 `emit_version 始终返回 0` 惯例）
- `--status-json` 头 3 行框架元数据（os/arch/version）不动；模块 `status` 子命令始终退出 0 的约定不动
- 16 个受限模块的声明以 2026-08-29 macOS 实测为准：15 个 `PLATFORMS=linux`（1panel btpanel casaos cockpit fail2ban webmin bbr swap sys-setup clash disk multi-net nat ops-kit ufw）+ 1 个 `PLATFORMS=darwin`（brew）
- 模块内部 OS 运行时检查全部保留（纵深防御）
- 输出中文、子命令英文；不引入新命令行 flag
- 每个 Task 结束跑 `bash tests/unit_platform_filter.sh` 退出 0 后才 commit

---

### Task 1: registry 平台 API + 16 模块补声明

**Files:**
- Modify: `lib/registry.sh`（头注格式块 + `_parse_manifest` + 查询 API 区）
- Modify: 16 个 `.manifest`（15 个追加 `PLATFORMS=linux`，`essentials/brew/.manifest` 追加 `PLATFORMS=darwin`）
- Create: `tests/unit_platform_filter.sh`
- Modify: `tests/ci_run.sh`（routing 阶段注册新单测，紧随 usability 断言行之后，约 :516）

**Interfaces:**
- Consumes: `_reg_get`/`_reg_set`（registry 内部既有）、`detect_os`（common.sh，设 `OS_TYPE`）
- Produces（后续所有 Task 依赖，签名精确）:
  - `registry_platforms <mod>` → stdout：空格分隔平台串；无声明输出空行
  - `uxs_module_supported <mod>` → rc：0=适用（含未声明），1=不适用
  - `uxs_module_visible <mod>` → rc：0=可见（SHOW_ALL=1 恒 0，否则同 supported）
  - `registry_visible_modules` → stdout：单个空格分隔的可见模块名串（注册序）

- [ ] **Step 1: 16 个 manifest 追加声明**

```bash
cd /Users/zhangyi/my_project/unix_script
for m in services/1panel services/btpanel services/casaos services/cockpit \
         services/fail2ban services/webmin essentials/bbr essentials/swap \
         essentials/sys-setup sys-tools/clash sys-tools/disk sys-tools/multi-net \
         sys-tools/nat sys-tools/ops-kit sys-tools/ufw; do
    printf 'PLATFORMS=linux\n' >> "$m/.manifest"
done
printf 'PLATFORMS=darwin\n' >> essentials/brew/.manifest
grep -c '^PLATFORMS=' services/*/.manifest essentials/*/.manifest sys-tools/*/.manifest 2>/dev/null | grep -v ':0' | wc -l   # 期望 16
```

- [ ] **Step 2: registry.sh 头注格式块（`NEXT_STEPS` 行后）加一行**

```bash
#   PLATFORMS=linux[,darwin] （可选，声明适用 OS；缺省=全平台，不适用当前系统的模块在各出口隐藏）
```

- [ ] **Step 3: `_parse_manifest` 初始化与解析分支**

初始化默认值块（`_reg_set "$mod" EXPORTABLE ""` 之后）加：

```bash
    _reg_set "$mod" PLATFORMS ""
```

case 分支（`EXPORTABLE)` 行之后）加：

```bash
            PLATFORMS)        _reg_set "$mod" PLATFORMS "$value" ;;  # 平台可见性：适用 OS（逗号分隔）
```

- [ ] **Step 4: 查询 API（`registry_exportable` 定义之后追加）**

```bash
# 平台可见性：模块声明的适用 OS（空格分隔；空=全平台适用）
registry_platforms()        { local v; v=$(_reg_get "$1" PLATFORMS); echo "${v//,/ }"; }

# uxs_module_supported <模块名> — 当前 OS 是否适用（rc 0=适用/未声明，1=不适用）。
# OS_TYPE 未初始化时兜底 detect_os（单测等直接 source registry 的场景）。
uxs_module_supported() {
    local mod="$1" plats p
    [[ -n "${OS_TYPE:-}" ]] || detect_os >/dev/null 2>&1 || true
    plats=$(registry_platforms "$mod")
    [[ -z "$plats" ]] && return 0
    for p in $plats; do
        [[ "$p" == "${OS_TYPE:-}" ]] && return 0
    done
    return 1
}

# uxs_module_visible <模块名> — escape hatch：UNIX_SCRIPT_SHOW_ALL=1 恒可见
uxs_module_visible() {
    [[ "${UNIX_SCRIPT_SHOW_ALL:-0}" == "1" ]] && return 0
    uxs_module_supported "$1"
}

# registry_visible_modules — 当前系统可见的模块名（单个空格分隔串，注册序）。
# 仅呈现层使用；dispatch/别名/依赖解析继续用全量 $_REGISTRY_MODULES。
registry_visible_modules() {
    local mod out=""
    for mod in $_REGISTRY_MODULES; do
        uxs_module_visible "$mod" && out="$out $mod"
    done
    echo "${out# }"
}
```

- [ ] **Step 5: 写测试 `tests/unit_platform_filter.sh`（首批：registry 层）**

```bash
#!/usr/bin/env bash
#
# tests/unit_platform_filter.sh — 平台可见性过滤单测
# 覆盖：PLATFORMS 解析 / uxs_module_supported / registry_visible_modules /
#       CLI 出口过滤 + SHOW_ALL / dispatch 护栏 / apply 跳过（随任务分批追加）
# 独立运行：bash tests/unit_platform_filter.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望> <实际>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}
t_rc() {  # t_rc <名称> <期望rc> <实际rc>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1  期望rc=$2 实际rc=$3"
    fi
}
t_true() {  # t_true <名称> <条件命令>
    if eval "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL: $1"
    fi
}

SCRIPT_DIR="$REPO_DIR"
# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=../lib/registry.sh
source "$REPO_DIR/lib/registry.sh"
set +e +o pipefail
detect_os >/dev/null 2>&1 || true
registry_scan

# ---------- PLATFORMS 解析 ----------
t_eq "registry_platforms(ufw)=linux" "linux" "$(registry_platforms ufw)"
t_eq "registry_platforms(sys-setup)=linux" "linux" "$(registry_platforms sys-setup)"
t_eq "registry_platforms(brew)=darwin" "darwin" "$(registry_platforms brew)"
t_eq "registry_platforms(docker)=空（全平台）" "" "$(registry_platforms docker)"

# ---------- uxs_module_supported 真值表（按宿主分支断言）----------
case "$OS_TYPE" in
    darwin)
        uxs_module_supported docker;  t_rc "supported(darwin): docker→0" 0 $?
        uxs_module_supported brew;    t_rc "supported(darwin): brew→0" 0 $?
        uxs_module_supported ufw;     t_rc "supported(darwin): ufw→1" 1 $?
        uxs_module_supported sys-setup; t_rc "supported(darwin): sys-setup→1" 1 $?
        ;;
    linux)
        uxs_module_supported docker;  t_rc "supported(linux): docker→0" 0 $?
        uxs_module_supported ufw;     t_rc "supported(linux): ufw→0" 0 $?
        uxs_module_supported brew;    t_rc "supported(linux): brew→1" 1 $?
        ;;
esac

# ---------- registry_visible_modules ----------
VIS=$(registry_visible_modules)
case "$OS_TYPE" in
    darwin)
        t_true "visible(darwin): 含 docker" 'case " $VIS " in *" docker "*) true;; *) false;; esac'
        t_true "visible(darwin): 不含 ufw" 'case " $VIS " in *" ufw "*) false;; *) true;; esac'
        t_true "visible(darwin): 含 brew" 'case " $VIS " in *" brew "*) true;; *) false;; esac'
        ;;
    linux)
        t_true "visible(linux): 含 ufw" 'case " $VIS " in *" ufw "*) true;; *) false;; esac'
        t_true "visible(linux): 不含 brew" 'case " $VIS " in *" brew "*) false;; *) true;; esac'
        ;;
esac
UNIX_SCRIPT_SHOW_ALL=1
VIS_ALL=$(registry_visible_modules)
unset UNIX_SCRIPT_SHOW_ALL
t_eq "visible: SHOW_ALL=1 输出全量注册表" "$_REGISTRY_MODULES" "$VIS_ALL"

echo "unit_platform_filter: 通过 $PASS / 失败 $FAIL"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 6: 跑测试验证通过**

Run: `bash tests/unit_platform_filter.sh`
Expected: `通过 12 / 失败 0`（darwin 宿主；linux 宿主条数不同），退出码 0

- [ ] **Step 7: 注册进 ci_run.sh（`assert "usability: 批次① 单测全过"` 行之后）**

```bash
    assert "platform-filter: 平台可见性单测全过" bash "$REPO_DIR/tests/unit_platform_filter.sh"
```

- [ ] **Step 8: Commit**

```bash
git add lib/registry.sh tests/unit_platform_filter.sh tests/ci_run.sh \
        services/1panel/.manifest services/btpanel/.manifest services/casaos/.manifest \
        services/cockpit/.manifest services/fail2ban/.manifest services/webmin/.manifest \
        essentials/bbr/.manifest essentials/swap/.manifest essentials/sys-setup/.manifest \
        essentials/brew/.manifest sys-tools/clash/.manifest sys-tools/disk/.manifest \
        sys-tools/multi-net/.manifest sys-tools/nat/.manifest sys-tools/ops-kit/.manifest \
        sys-tools/ufw/.manifest
git commit -m "feat(registry): PLATFORMS 平台声明——manifest 解析 + supported/visible API + 16 个受限模块补声明"
```

---

### Task 2: CLI 出口过滤（--list* / search / --status / --status-json / usage）

**Files:**
- Modify: `lib/menu.sh`（`show_list_modules` :345 / `show_list_categories` :364 / `show_status_json` :388 / `show_installed_services` 在 lib/status.sh :56 / `show_search_results` :495 / `show_usage` 模块段 :586）
- Modify: `lib/status.sh`（`show_installed_services` :56）
- Modify: `install.sh`（`--list` :191-196）
- Modify: `tests/unit_platform_filter.sh`（追加 CLI 段）

**Interfaces:**
- Consumes: Task 1 的 `registry_visible_modules` / `uxs_module_visible`
- Produces: 无新接口；`--status-json` 默认行数=可见模块数、头 3 行不变

- [ ] **Step 1: 追加失败测试（文件末尾 `echo` 汇总行之前插入）**

```bash
# ---------- CLI 出口过滤（子进程级，覆盖接线）----------
run_install() { bash "$REPO_DIR/install.sh" "$@"; }
LST=$(run_install --list)
LST_ALL=$(UNIX_SCRIPT_SHOW_ALL=1 run_install --list)
case "$OS_TYPE" in
    darwin)
        t_true "--list: 不含 ufw" 'case " $LST " in *" ufw "*) false;; *) true;; esac'
        t_true "--list: 含 docker" 'case " $LST " in *" docker "*) true;; *) false;; esac'
        t_true "SHOW_ALL --list: 含 ufw" 'case " $LST_ALL " in *" ufw "*) true;; *) false;; esac'
        ;;
    linux)
        t_true "--list: 不含 brew" 'case " $LST " in *" brew "*) false;; *) true;; esac'
        t_true "SHOW_ALL --list: 含 brew" 'case " $LST_ALL " in *" brew "*) true;; *) false;; esac'
        ;;
esac
N_ALL=$(printf '%s' "$LST_ALL" | wc -w | tr -d ' ')
N_VIS=$(printf '%s' "$LST" | wc -w | tr -d ' ')
t_true "--list: 可见数 ≤ 全量数（${N_VIS}/${N_ALL}）" "(( $N_VIS <= $N_ALL ))"

# --status-json 关键不变量：默认零 n/a 行；SHOW_ALL 行数=全量模块数；头 3 行元数据不动
J=$(run_install --status-json | tail -n +4)
J_ALL=$(UNIX_SCRIPT_SHOW_ALL=1 run_install --status-json)
t_eq "status-json: 默认零 n/a 行" "0" "$(printf '%s\n' "$J" | grep -c ':n/a' || true)"
t_eq "status-json: 默认行数=可见模块数" "$N_VIS" "$(printf '%s\n' "$J" | grep -c . || true)"
t_eq "status-json: SHOW_ALL 行数=全量模块数" "$N_ALL" "$(printf '%s\n' "$J_ALL" | tail -n +4 | grep -c . || true)"
t_eq "status-json: 头 3 行元数据仍在" "3" "$(printf '%s\n' "$J_ALL" | head -3 | grep -cE '^(os|arch|version):' || true)"

# search：隐藏模块无匹配 rc=1；SHOW_ALL 命中 rc=0
if [[ "$OS_TYPE" == "darwin" ]]; then
    run_install search ufw >/dev/null 2>&1; t_rc "search: darwin 搜 ufw 无匹配 rc=1" 1 $?
    UNIX_SCRIPT_SHOW_ALL=1 run_install search ufw >/dev/null 2>&1; t_rc "search: SHOW_ALL 搜 ufw rc=0" 0 $?
    run_install search 容器 >/dev/null 2>&1; t_rc "search: 通用关键字 rc=0" 0 $?
fi

# --list-categories 不含隐藏模块行
LC=$(run_install --list-categories)
case "$OS_TYPE" in
    darwin) t_true "--list-categories: 无 ufw 行" '! printf "%s" "$LC" | grep -q "^  ufw"' ;;
    linux)  t_true "--list-categories: 无 brew 行" '! printf "%s" "$LC" | grep -q "^  brew"' ;;
esac
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_platform_filter.sh`
Expected: FAIL（`--list: 不含 ufw` 等——出口尚未过滤）

- [ ] **Step 3: 改 lib/menu.sh 六处**

`show_list_modules` 首行循环改源：

```bash
    for mod in $(registry_visible_modules); do
```

`show_list_categories` 开头取一次可见列表，两个内层循环 `for mod in $_REGISTRY_MODULES` 均改为 `for mod in $vis`，函数体前加 `vis=$(registry_visible_modules)`：

```bash
show_list_categories() {
    local cat mod label vis
    vis=$(registry_visible_modules)
```

`show_status_json` 局部变量行与两处迭代源改可见列表：

```bash
    local mod state version line vis
    vis=$(registry_visible_modules)
    # shellcheck disable=SC2086  # $vis 为受控模块名列表，需要分词
    status_batch_query $vis
    for mod in $vis; do
```

`show_search_results` 的收集循环加可见性过滤：

```bash
    while IFS= read -r mod; do
        [[ -n "$mod" ]] || continue
        uxs_module_visible "$mod" || continue
        hits+=("$mod")
    done < <(registry_search "$@")
```

`show_usage` 模块段取模块改用 `category_items`（其 Task 3 会加可见性；本任务先接上，语义经由 Task 3 生效，不影响本任务测试）：

```bash
    for cat in $CATEGORY_ORDER; do
        mods=$(category_items "$cat" "")
        if [[ -z "$mods" ]]; then continue; fi
```

`show_usage` 帮助文本 `--list-categories` 行后加一行说明：

```
                      （--list* 与 search 默认仅显示本机适用模块；UNIX_SCRIPT_SHOW_ALL=1 显示全量）
```

- [ ] **Step 4: 改 lib/status.sh `show_installed_services`**

函数体开头取 `vis=$(registry_visible_modules)`，两个 `for mod in $_REGISTRY_MODULES` 改 `for mod in $vis`。

- [ ] **Step 5: 改 install.sh `--list`**

```bash
        --list)
            # 动态列出所有有 manifest 的模块（按平台可见性过滤）
            for mod in $(registry_visible_modules); do printf '%s ' "$mod"; done
            echo
            exit 0
            ;;
```

- [ ] **Step 6: 跑测试确认全过**

Run: `bash tests/unit_platform_filter.sh && bash tests/unit_usability.sh`
Expected: 两个脚本退出码 0（usability 的 N_JSON==N_LIST 断言两侧同源收缩，不破）

- [ ] **Step 7: Commit**

```bash
git add lib/menu.sh lib/status.sh install.sh tests/unit_platform_filter.sh
git commit -m "feat(ux): CLI 出口（--list*/search/status/status-json/usage）按平台过滤，SHOW_ALL=1 恢复全量"
```

---

### Task 3: 交互菜单过滤（bash 菜单 / fzf / 卸载菜单）

**Files:**
- Modify: `lib/menu.sh`（`category_items` :103 / `render_main_page` :72-86 / `uninstall_menu_loop` :411-487 两处）
- Modify: `lib/menu_fzf.sh`（`menu_fzf_main` :32）
- Modify: `tests/unit_platform_filter.sh`（追加菜单段）

**Interfaces:**
- Consumes: Task 1 的 `uxs_module_visible`
- Produces: `category_items` 语义升级（返回分类内**可见**模块；签名不变）

- [ ] **Step 1: 追加失败测试（CLI 段之后）**

文件头 source 区加 `source "$REPO_DIR/lib/menu.sh"`（menu.sh 有幂等保护，可安全重复 source）：

```bash
# ---------- category_items / 菜单可见性 ----------
case "$OS_TYPE" in
    darwin)
        t_true "category_items: 系统工具不含 ufw" 'case " $(category_items 系统工具 "") " in *" ufw "*) false;; *) true;; esac'
        t_true "category_items: 系统工具含 disk-usage" 'case " $(category_items 系统工具 "") " in *" disk-usage "*) true;; *) false;; esac'
        ;;
    linux)
        t_true "category_items: 装机必备不含 brew" 'case " $(category_items 装机必备 "") " in *" brew "*) false;; *) true;; esac'
        ;;
esac
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_platform_filter.sh`
Expected: FAIL（category_items 尚未过滤）

- [ ] **Step 3: `category_items` 加可见性过滤（for 循环体首行）**

```bash
    for mod in $(registry_modules_in_category "$cat"); do
        uxs_module_visible "$mod" || continue
        if [[ -n "$lf" ]]; then
```

- [ ] **Step 4: `render_main_page` 分类计数改用可见列表**

原 `local n=1 cat mods installed=0 total=0 mod state` 与分类循环替换为：

```bash
    local n=1 cat mod state vis installed=0 total=0
    for cat in $CATEGORY_ORDER; do
        vis=$(category_items "$cat" "")
        if [[ -z "$vis" ]]; then continue; fi
        total=0; installed=0
        for mod in $vis; do
            total=$((total + 1))
            state=$(status_state_get "$mod")
            case "$state" in
                installed*|configured) installed=$((installed + 1)) ;;
            esac
        done
        printf "  %d) %s（%d/%d 已装）\n" "$n" "$cat" "$installed" "$total"
        n=$((n + 1))
    done
```

- [ ] **Step 5: `uninstall_menu_loop` 两处枚举改 `category_items`**

主页面两处 `if [[ -n "$(registry_modules_in_category "$c")" ]]` 均改为：

```bash
            if [[ -n "$(category_items "$c" "")" ]]; then
```

分类页条目 `items=$(registry_modules_in_category "$cur_cat")` 改为：

```bash
            items=$(category_items "$cur_cat" "")
```

- [ ] **Step 6: `menu_fzf_main` 行构建改可见列表**

```bash
    for mod in $(registry_visible_modules); do
```

- [ ] **Step 7: 跑测试 + 手验菜单**

Run: `bash tests/unit_platform_filter.sh`
Expected: 退出码 0
手验（darwin 宿主）: `printf 'q\n' | bash install.sh 2>/dev/null | grep -c ufw` 无输出命中；`UXS_MENU=bash bash install.sh` 进入后选系统工具分类目视无 ufw（人工步骤，不进 commit 门槛）

- [ ] **Step 8: Commit**

```bash
git add lib/menu.sh lib/menu_fzf.sh tests/unit_platform_filter.sh
git commit -m "feat(ux): 交互菜单（bash/fzf/卸载）按平台过滤，空分类整类隐藏"
```

---

### Task 4: dispatch 平台护栏 + 依赖护栏

**Files:**
- Modify: `install.sh`（新增 `platform_gate_or_die`；`dispatch_module` :53-68 后、`dispatch_module_or_passthrough` :118-126 内、`ensure_module_deps` :101-110 循环首）
- Modify: `tests/unit_platform_filter.sh`（追加护栏段）

**Interfaces:**
- Consumes: Task 1 的 `uxs_module_visible` / `registry_platforms`
- Produces: `platform_gate_or_die <resolved名> <用户输入名>`（install.sh 内部函数；rc 恒不返回——放行或 exit 1）

- [ ] **Step 1: 追加失败测试（菜单段之后）**

```bash
# ---------- dispatch 平台护栏 ----------
if [[ "$OS_TYPE" == "darwin" ]]; then
    OUT=$(run_install ufw </dev/null 2>&1); t_rc "gate: darwin 分发 ufw rc=1" 1 $?
    t_true "gate: 报错含「不支持当前系统」" 'printf "%s" "$OUT" | grep -q "不支持当前系统"'
    t_true "gate: 提示 SHOW_ALL 逃生口" 'printf "%s" "$OUT" | grep -q "UNIX_SCRIPT_SHOW_ALL=1"'
    OUT=$(UNIX_SCRIPT_SHOW_ALL=1 run_install ufw status </dev/null 2>&1); t_rc "gate: SHOW_ALL 放行透传 status rc=0" 0 $?
fi
if [[ "$OS_TYPE" == "linux" ]]; then
    OUT=$(run_install brew </dev/null 2>&1); t_rc "gate: linux 分发 brew rc=1" 1 $?
    t_true "gate: 报错含「不支持当前系统」" 'printf "%s" "$OUT" | grep -q "不支持当前系统"'
fi
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_platform_filter.sh`
Expected: FAIL（gate 未实现——darwin 上 `install.sh ufw` 走到模块内部报错或安装路径，rc/文案不符）

- [ ] **Step 3: install.sh 加护栏函数（`dispatch_module` 定义之前）**

```bash
# 平台可见性护栏：模块不适用当前系统时拦截并给指引（UNIX_SCRIPT_SHOW_ALL=1 放行）。
# 放行路径 return 0；拦截路径 error + exit 1。
platform_gate_or_die() {
    local resolved="$1" input="${2:-$1}"
    uxs_module_visible "$resolved" && return 0
    local sup
    sup=$(registry_platforms "$resolved")
    error "模块 ${input} 不支持当前系统（${OS_TYPE:-未知}，仅支持：${sup:-无}）"
    info "查看适用模块: $0 --list-categories ｜ 强制显示全量: UNIX_SCRIPT_SHOW_ALL=1 $0 ${input}"
    exit 1
}
```

- [ ] **Step 4: 两个分发路径接护栏**

`dispatch_module` 内，未知模块检查块之后、`default_action=` 之前加：

```bash
    # 平台护栏：不适用模块在分发层拦截（模块内部检查保留为纵深防御）
    platform_gate_or_die "$resolved" "$name"
```

`dispatch_module_or_passthrough` 内，路径存在性 if 块首行加：

```bash
        if [[ -d "$SCRIPT_DIR/$mod_path" ]] && [[ -f "$SCRIPT_DIR/$mod_path/$entry_script" ]]; then
            platform_gate_or_die "$resolved" "$1"
            local mod="$1"; shift
```

- [ ] **Step 5: `ensure_module_deps` 依赖护栏（for 循环体首）**

```bash
    for dep in $deps; do
        # 依赖不适用当前系统时明确报错，而非装到一半失败
        if ! uxs_module_visible "$dep"; then
            error "模块 $mod 依赖 $dep，但 $dep 不支持当前系统（仅支持：$(registry_platforms "$dep")）"
            exit 1
        fi
        dep_state=$(module_status_machine "$dep")
```

- [ ] **Step 6: 跑测试确认全过 + dry-run 冒烟**

Run: `bash tests/unit_platform_filter.sh && bash install.sh --dry-run docker && bash tests/unit_usability.sh`
Expected: 全部退出码 0（dry-run 冒烟确认正常安装路径未被误拦）

- [ ] **Step 7: Commit**

```bash
git add install.sh tests/unit_platform_filter.sh
git commit -m "feat(ux): dispatch 平台护栏 + 依赖不适用护栏，UNIX_SCRIPT_SHOW_ALL=1 放行"
```

---

### Task 5: profile 出口（export 过滤 / apply 跳过）

**Files:**
- Modify: `lib/profile.sh`（`export_profile` :47 拓扑循环首 / `apply_profile` :155 label 赋值后）
- Modify: `tests/unit_platform_filter.sh`（追加 profile 段）

**Interfaces:**
- Consumes: Task 1 的 `uxs_module_visible` / `registry_platforms`
- Produces: 无新接口；apply 遇不适用行 warn+skipped 计数，不中断、不影响 rc

- [ ] **Step 1: 追加失败测试（护栏段之后）**

```bash
# ---------- profile：export 过滤 / apply 跳过 ----------
if [[ "$OS_TYPE" == "darwin" ]]; then HIDDEN_MOD=ufw; else HIDDEN_MOD=brew; fi

PFILE=$(mktemp)
run_install export "$PFILE" >/dev/null 2>&1; t_rc "export: rc=0" 0 $?
t_true "export: 文件含头注" 'grep -q "^# unix_script profile" "$PFILE"'
t_true "export: 不导出不适用模块 $HIDDEN_MOD" "! grep -q \"^${HIDDEN_MOD}\" \"\$PFILE\""
rm -f "$PFILE"

PROF=$(mktemp)
printf '%s   # 测试不适用行\n' "$HIDDEN_MOD" > "$PROF"
OUT=$(run_install apply "$PROF" --dry-run </dev/null 2>&1); t_rc "apply: 仅不适用行 rc=0（跳过不报错）" 0 $?
t_true "apply: 输出跳过原因（不支持当前系统）" 'printf "%s" "$OUT" | grep -q "不支持当前系统"'
t_true "apply: 汇总计跳过 1" 'printf "%s" "$OUT" | grep -q "跳过 1"'
rm -f "$PROF"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/unit_platform_filter.sh`
Expected: FAIL（export 会导出隐藏模块行 / apply 不跳过）

- [ ] **Step 3: `export_profile` 拓扑循环首加过滤**

```bash
        for mod in $order; do
            uxs_module_visible "$mod" || continue   # 只导出本机适用模块（不适用模块在本机无 profile 意义）
            local state
            state=$(module_status_machine "$mod")
```

（原循环体首的 `local state` 与取 state 两行保留，仅在其前插入过滤行）

- [ ] **Step 4: `apply_profile` 应用循环加跳过分支**

在 `label=$(registry_label "$mod")` 行之后、已就绪跳过判断之前插入：

```bash
        # 平台可见性：profile 可跨机器携带，目标机器不适用的行跳过（不报错、不中断）
        if ! uxs_module_visible "$mod"; then
            warn "跳过 ${label}（不支持当前系统 ${OS_TYPE:-?}，仅：$(registry_platforms "$mod")）"
            skipped=$((skipped + 1))
            continue
        fi
```

- [ ] **Step 5: 跑测试确认全过**

Run: `bash tests/unit_platform_filter.sh`
Expected: 退出码 0

- [ ] **Step 6: Commit**

```bash
git add lib/profile.sh tests/unit_platform_filter.sh
git commit -m "feat(profile): export 仅导本机适用模块；apply 跳过不适用行（profile 跨机携带）"
```

---

### Task 6: 文档 + 全量验证

**Files:**
- Modify: `AGENTS.md`（--status-json 段、新增平台可见性小节、注意事项 bullet）
- Modify: `docs/superpowers/specs/2026-08-29-platform-visibility-filter-design.md`（状态行改「已实现」）

**Interfaces:**
- Consumes: 前 5 个 Task 的全部行为
- Produces: 文档契约（AI agent 阅读面）

- [ ] **Step 1: AGENTS.md `--status-json` 段（状态码表之后）加一段**

```markdown
自 v1.15.0 起，`--status-json` 默认仅输出**本机适用**的模块（平台不适用的模块被隐藏，不再出现 `n/a` 行）。需要全量清单（含不适用模块）时：

```bash
UNIX_SCRIPT_SHOW_ALL=1 ./install.sh --status-json
```
```

- [ ] **Step 2: AGENTS.md「配置复现 / profile（阶段 D）」小节之后新增小节**

```markdown
### 平台可见性（PLATFORMS 声明 + SHOW_ALL）

模块可在 `.manifest` 中声明适用 OS：`PLATFORMS=linux[,darwin]`（缺省 = 全平台适用）。
不适用当前系统的模块默认从**所有出口**隐藏：`--list` / `--list-modules` / `--list-categories` /
`search` / 交互菜单（bash 与 fzf）/ 卸载菜单 / `--status` / `--status-json` / `export`。

- 直接安装不适用模块（如 macOS 上 `./install.sh ufw`）被框架拦截，给出解释性报错与恢复指引
- `apply` profile 时跳过本机不适用行（profile 可跨机器携带）
- `UNIX_SCRIPT_SHOW_ALL=1` 恢复全量显示（对上述所有出口生效）
- 绕过 install.sh 直接调用模块路径时，模块内部平台检查仍生效（输出 n/a / 报错，纵深防御）
```

- [ ] **Step 3: AGENTS.md 注意事项 bullet 替换**

原 `- 某些模块仅 Linux（macOS 会输出"不适用"并退出 0）` 替换为：

```markdown
- 平台不适用的模块默认从列表/菜单隐藏（manifest `PLATFORMS` 声明）；`UNIX_SCRIPT_SHOW_ALL=1` 显示全量；绕过入口直接调模块时仍输出「不适用」并退出 0
```

- [ ] **Step 4: 规格文档状态行**

`docs/superpowers/specs/2026-08-29-platform-visibility-filter-design.md` 头部 `状态：待评审` 改 `状态：已实现（2026-08-29）`。

- [ ] **Step 5: 全量验证**

```bash
bash tests/unit_platform_filter.sh \
  && bash tests/unit_usability.sh \
  && bash tests/unit_suggest.sh \
  && bash tests/ci_run.sh --phase static \
  && bash tests/ci_run.sh --phase routing
```

Expected: 全部退出码 0。routing 阶段包含既有 `search 面板` 断言（1panel/btpanel/webmin 为 `PLATFORMS=linux`，宿主为 Linux CI 容器时可见，不受影响；本地 darwin 上该断言属 routing 的容器腿/分支逻辑，若本地跑请确认其在 darwin 下的分支行为——panel 断言在 darwin 会被过滤，若该断言不分宿主直接 grep，需给断言加 `[[ $(uname) == Linux ]]` 守卫，此为唯一允许的 ci_run.sh 存量断言修正）。

- [ ] **Step 6: 手验矩阵（darwin 本机，人工确认不阻塞）**

```bash
./install.sh --list | grep -c ufw                      # 期望 0
UNIX_SCRIPT_SHOW_ALL=1 ./install.sh --status-json | grep -c ':n/a'   # 期望 15
./install.sh ufw 2>&1 | grep 不支持                     # 期望命中
./install.sh search swap; echo $?                       # 期望无匹配 rc=1
```

- [ ] **Step 7: Commit**

```bash
git add AGENTS.md docs/superpowers/specs/2026-08-29-platform-visibility-filter-design.md tests/ci_run.sh
git commit -m "docs: AGENTS.md 平台可见性契约（PLATFORMS/SHOW_ALL）+ 规格标记已实现"
```

---

## Self-Review 记录

- 规格覆盖：§声明格式→Task 1；§registry API→Task 1；§过滤出口→Task 2（CLI/status）+ Task 3（菜单）+ Task 5（profile）；§拦截与报错→Task 4；§escape hatch→Task 1（API）+ Task 2（CLI 文档行）+ Task 6（AGENTS.md）；§测试 1-6 项→Task 1/2/4/5 + Task 2 的零 n/a 不变量；§文档→Task 6。规格 §6 第 4 项「apply 跳过后续行继续处理」由 Task 5 测试的 `跳过 1` 计数 + rc=0 覆盖
- 类型一致性：`uxs_module_visible`/`uxs_module_supported`/`registry_platforms`/`registry_visible_modules` 各 Task 引用签名与 Task 1 定义一致；`platform_gate_or_die` 双参在两处调用一致
- 占位符扫描：无 TBD/TODO；所有代码步骤含完整代码
- 已知留白（有意）：dep 护栏（Task 4 Step 5）无自动化测试——仓库无「可见模块依赖隐藏模块」的自然夹具，人工 review 覆盖；scaffold 模板不感知 PLATFORMS（规格非目标）
