# unix_script 易用性改造（UX Overhaul）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落实 `docs/superpowers/specs/2026-08-15-ux-overhaul-design.md`——菜单双轨（fzf 优先/bash 降级）、DESC 单一数据源、did-you-mean、补全动态化、状态并行缓存、网络超时、文档同步。

**Architecture:** 以 `.manifest` 新增 `DESC=` 为唯一描述数据源；`lib/suggest.sh`（纯函数）提供编辑距离/多选解析；`lib/status.sh` 增加并行批查 + TTL 跨进程缓存；`lib/menu.sh` 重构为两级分类菜单并暴露 `menu_exec_actions` 等共享动作执行器；`lib/menu_fzf.sh` 消费同一批执行器实现 fzf 模式；补全文件改为运行时从 `.manifest` 动态生成。

**Tech Stack:** 纯 Bash（bash 3.2 兼容，macOS 系统自带版本）；fzf 为可选运行时依赖；测试驱动 `tests/ci_run.sh`（static/routing/install 三阶段）+ 新增 `tests/unit_suggest.sh` 独立单测 runner。

## Global Constraints

- 从 `main` 切出分支 `feat/ux-overhaul`，所有提交落在该分支。
- **bash 3.2 兼容**：禁用关联数组、`${var,,}`/`${var^^}`、`wait -n`、`mapfile`/`readarray`。小写化用 `tr '[:upper:]' '[:lower:]'`。
- **set -euo pipefail 安全**：条件副作用一律用 `if` 结构，不写 `A && B` 尾式表达式（仓库既定风格，见 commit bd2542d 的 SC2015 修复）。
- **机器接口只追加不修改**：`--list-modules` 前两列、`--status-json` 每行语义不变（描述作为第 3 列追加在末尾）。
- 新建 `lib/*.sh` 遵循仓库惯例：文件头注释块 + 幂等保护（`if [[ -n "${_XXX_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi`）。
- 输出中文，模块名/子命令名/环境变量名英文。
- 静态门禁：`shellcheck -e SC2164,SC1091,SC2317,SC2329 -x` 与 `bash -n` 全部通过。
- fzf 为零强制依赖：所有 fzf 代码路径在无 fzf 环境必须可降级到 bash 菜单。
- 每个任务完成后运行对应测试并提交一次（ conventional commit 中文描述风格，与仓库历史一致）。

---

### Task 0: 分支准备与基线验证

**Files:** 无改动。

**Interfaces:** 无。

- [ ] **Step 1: 切分支**

```bash
cd /Users/zhangyi/my_project/unix_script
git checkout main && git pull --ff-only 2>/dev/null; git checkout -b feat/ux-overhaul
```

- [ ] **Step 2: 基线测试全绿**

Run: `./tests/ci_run.sh --phase static && ./tests/ci_run.sh --phase routing`
Expected: 两阶段汇总 `失败 0`（macOS 上部分 install 项会 skip，属正常；本机跑不了的场景以 routing/static 为准）。

---

### Task 1: DESC 数据层（registry 解析 + 52 个 manifest + scaffold 模板 + `--list-modules` 第 3 列）

**Files:**
- Modify: `lib/registry.sh`（`_parse_manifest` 初始化与 case 分支、`registry_desc()`、头注释）
- Modify: 52 个 `<分类>/<模块>/.manifest`（追加 `DESC=` 行）
- Modify: `lib/scaffold.sh:47-51`（manifest 模板加 DESC 占位）
- Modify: `lib/menu.sh:169-194`（`show_list_modules` 追加第 3 列）
- Modify: `tests/ci_run.sh`（routing 阶段新增数据完整性断言）

**Interfaces:**
- Produces: `registry_desc <mod>` → echo 该模块 DESC（无则空串）；`.manifest` 支持 `DESC=<值>`（可选字段）；`--list-modules` 输出 `模块名\t子命令[  requires:...]\t描述` 三列 TSV。

- [ ] **Step 1: 写失败测试**（加到 `tests/ci_run.sh` 的 `phase_routing` 内、`# 12. 行为测试：别名解析…` 块之后）：

```bash
    # 13. DESC 数据完整性：--list-modules 三列且第 3 列（描述）非空
    local desc_bad
    desc_bad=$("$REPO_DIR/install.sh" --list-modules 2>/dev/null | awk -F'\t' 'NF<3 || $3==""')
    if [[ -z "$desc_bad" ]]; then
        report_row "DESC: --list-modules 三列非空" pass
    else
        report_row "DESC: --list-modules 三列非空" fail "缺描述: $(printf '%s' "$desc_bad" | head -3 | tr '\n' ' ')"
    fi
    # shellcheck disable=SC2016
    assert "DESC: registry_desc(docker) 非空" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh
         registry_scan; [ -n "$(registry_desc docker)" ]' _ "$REPO_DIR"
    assert "DESC: scaffold 模板含 DESC 占位" bash -c "grep -q 'DESC=' '$REPO_DIR/lib/scaffold.sh'"
```

- [ ] **Step 2: 运行验证失败**

Run: `./tests/ci_run.sh --phase routing`
Expected: `DESC: --list-modules 三列非空` 与 `registry_desc(docker)` 两条 FAIL（scaffold 断言因模板尚无 DESC 也 FAIL）。

- [ ] **Step 3: registry.sh 支持 DESC**

3a. 头注释 Manifest 格式清单中 `LABEL=显示名称` 行后加一行：

```
#   DESC=一句话中文描述    （可选，≤20 字，菜单/补全/--list-modules 展示用）
```

3b. `_parse_manifest` 初始化块（现 `lib/registry.sh:71-78`）在 `_reg_set "$mod" LABEL ""` 后加：

```bash
    _reg_set "$mod" DESC ""
```

3c. 解析 case（现 `lib/registry.sh:85-94`）的 `LABEL)` 分支后加：

```bash
            DESC)             _reg_set "$mod" DESC "$value" ;;
```

3d. 查询 API 区（现 `lib/registry.sh:136` 附近）加：

```bash
registry_desc()            { _reg_get "$1" DESC; }
```

- [ ] **Step 4: 批量写入 52 个 DESC**（一次性脚本，内容以 README 表格为底稿；在仓库根执行）：

```bash
cd /Users/zhangyi/my_project/unix_script
add_desc() {
    local mod="$1" desc="$2" cat_dir mf
    for cat_dir in services essentials dev-tools ai-tools sys-tools; do
        mf="$cat_dir/$mod/.manifest"
        if [[ -f "$mf" ]]; then
            if grep -q '^DESC=' "$mf"; then
                sed -i.bak "s|^DESC=.*|DESC=$desc|" "$mf"
            else
                printf 'DESC=%s\n' "$desc" >> "$mf"
            fi
            rm -f "$mf.bak"
            return 0
        fi
    done
    echo "未找到模块: $mod" >&2; return 1
}
while read -r mod desc; do
    [[ -z "$mod" ]] && continue
    add_desc "$mod" "$desc" || exit 1
done <<'EOF'
docker 容器引擎（Engine / Desktop）
nginx Web 服务器 / 反向代理
caddy 现代 Web 服务器（自动 HTTPS）
redis 内存数据库 / 缓存
postgres PostgreSQL 数据库
prometheus 监控系统（时间序列数据库）
grafana 监控可视化面板
node_exporter Prometheus 系统指标收集器
uptime-kuma 服务可用性监控面板（Docker）
gitea 自托管 Git 服务
openlist 文件列表 / 网盘聚合（原 Alist）
ddns-go 动态域名解析服务
certbot Let's Encrypt 免费 SSL 证书
fail2ban SSH 暴力破解防护
cockpit Linux Web 管理面板
tailscale 免公网 IP 的组网 VPN
wireguard 现代、快速、安全的 VPN
essential-pkgs curl/git/vim/htop/tmux/jq 等一键装齐
sys-setup 换源/时区/NTP/优化/SSH 加固/自动更新
nvm Node.js 多版本管理
brew Homebrew 包管理器
swap 创建 / 调整 swap 虚拟内存
bbr TCP BBR 拥塞控制加速
bun Bun 运行时（含国内镜像加速）
deno Deno 运行时
go Go 语言环境
rust Rust 语言环境
pnpm Node.js 包管理器
dev-mirror 开发换源加速（npm/Go/Rust/pip）
dev-enhance Neovim+LazyVim / git delta / tmux 配置
dev-tui lazydocker + lazygit
modern-cli bat/eza/ripgrep/fd/fzf/zoxide/starship
zsh_setup Zsh + Oh My Zsh + 插件配置
code-lint 代码分析工具集
minikube 本地 Kubernetes 开发环境
ollama 本地大模型运行时
opencode 终端 AI 编程助手
pi Pi AI 编程代理框架
clash 代理核心 + TUN 透明代理（mihomo）
sys-cmd 系统诊断命令集（cpu/mem/port/disk/net）
disk-usage 磁盘空间管理
docker-image 镜像导出为 .tar.gz（离线分发）
process_manager_tool 智能搜索和管理系统进程
shutdown_timer 定时 / 倒计时关机管理
safe-rm 安全删除替代 rm，防误删
nat NAT 端口转发
multi-net 多网卡策略路由
ufw UFW 防火墙管理
restic 增量加密备份工具
deskflow 键鼠共享（Flatpak / Homebrew）
k7s Kubernetes 桌面监控
upftp 轻量级 FTP 文件分享工具
EOF
echo "done: $(grep -rl '^DESC=' services essentials dev-tools ai-tools sys-tools --include='.manifest' | wc -l) 个 manifest 已含 DESC"
```

Expected: `done: 52 个 manifest 已含 DESC`。

- [ ] **Step 5: scaffold 模板加 DESC**

`lib/scaffold.sh` 的 manifest heredoc（现 47-51 行）改为：

```bash
    # .manifest
    cat > "$dir/.manifest" <<EOF
LABEL=$label
CATEGORY=$category
DESC=一句话中文描述（请替换）
DEFAULT_ACTION=install
EOF
```

同文件「下一步」提示（现 158-161 行）首条前插入：

```bash
    echo "  0. 编辑 $cat_dir/$name/.manifest 的 DESC 为一句话中文描述"
```

- [ ] **Step 6: show_list_modules 追加第 3 列**

`lib/menu.sh` 的 `show_list_modules`（现 169-194 行）改为：

```bash
show_list_modules() {
    local mod subs line reqs desc
    for mod in $_REGISTRY_MODULES; do
        local entry_script mod_path
        entry_script=$(registry_entry_script "$mod")
        mod_path=$(registry_path "$mod")
        local script="$SCRIPT_DIR/$mod_path/$entry_script"
        [[ -f "$script" ]] || continue
        subs=""
        local usage_line
        usage_line=$(grep -m1 '用法:' "$script" 2>/dev/null || true)
        if [[ "$usage_line" == *"{"*"}"* ]]; then
            subs=$(echo "$usage_line" | sed 's/.*{//;s/}.*//' | tr '|' ' ')
        fi
        if [[ -z "$subs" ]]; then
            subs=$(grep -oE '^\s+(install|uninstall|status|help|mirror|unmirror|start|stop|restart|enable|disable|pull|all|config|example|tun-on|tun-off|clear|list|setup|route-user|route-port|save)\)' "$script" 2>/dev/null | tr -d ' )' | sort -u | tr '\n' ' ' || true)
        fi
        [[ -z "$subs" ]] && subs="install"
        line="$subs"
        # 阶段 E：有 REQUIRES 时追加 requires: 列（逗号分隔），便于 AI/人类识别前置依赖
        reqs=$(registry_requires "$mod")
        if [[ -n "$reqs" ]]; then
            line="$line  requires:${reqs// /,}"
        fi
        # UX：末尾追加描述列（第 3 列，供人类/AI 识别模块用途；前两列语义不变）
        desc=$(registry_desc "$mod")
        printf '%s\t%s\t%s\n' "$mod" "$line" "$desc"
    done
}
```

（保持 `[[ -z "$subs" ]] && subs="install"` 原样即可——它是赋值不是尾式副作用，仓库现状如此。）

- [ ] **Step 7: 运行测试通过**

Run: `./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: DESC 三条断言 PASS；static 全绿。抽查：`./install.sh --list-modules | head -3` 输出三列。

- [ ] **Step 8: 提交**

```bash
git add -A && git commit -m "feat(ux): .manifest 增加 DESC 单一数据源，--list-modules 追加描述列"
```

---

### Task 2: `lib/suggest.sh` 纯函数库 + 单测 runner

**Files:**
- Create: `lib/suggest.sh`
- Create: `tests/unit_suggest.sh`
- Modify: `install.sh`（source 列表加 `lib/suggest.sh`，加在 `lib/registry.sh` 之后）
- Modify: `lib/menu.sh`（把 `show_list_modules` 里的子命令提取启发式重构为 `module_subcommands()`）

**Interfaces:**
- Consumes: `$_REGISTRY_MODULES`（registry 已加载后调用）。
- Produces（后续任务依赖的精确签名）:
  - `levenshtein <a> <b>` → echo 编辑距离（非负整数），rc 0
  - `suggest_module <输入>` → echo 至多 3 个模块名（空格分隔，按 前缀→子串→编辑距离≤2 优先级）；无候选输出空串，rc 0
  - `parse_multiselect <输入> <最大序号>` → echo `n n n`（升序去重）；非法输入（格式错/越界/逆序区间）rc 1 且无输出
  - `module_subcommands <mod>`（定义在 menu.sh）→ echo 空格分隔子命令，至少 `install`

- [ ] **Step 1: 写失败测试** `tests/unit_suggest.sh`（新建，可独立运行）：

```bash
#!/usr/bin/env bash
#
# tests/unit_suggest.sh — lib/suggest.sh 纯函数单测
# 独立运行：bash tests/unit_suggest.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
#
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望输出> <实际输出>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}

t_rc() {  # t_rc <名称> <期望rc:0|1> <实际rc>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望rc=$2 实际rc=$3"
    fi
}

SCRIPT_DIR="$REPO_DIR"
# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
# shellcheck source=../lib/registry.sh
source "$REPO_DIR/lib/registry.sh"
# shellcheck source=../lib/suggest.sh
source "$REPO_DIR/lib/suggest.sh"
# shellcheck source=../lib/menu.sh
source "$REPO_DIR/lib/menu.sh"
detect_os >/dev/null 2>&1 || true
registry_scan

# ---- levenshtein ----
t_eq "lev(docker,docker)=0"   0 "$(levenshtein docker docker)"
t_eq "lev(doker,docker)=1"    1 "$(levenshtein doker docker)"
t_eq "lev(,abc)=3"            3 "$(levenshtein '' abc)"
t_eq "lev(cat,)=3"            3 "$(levenshtein cat '')"
t_eq "lev(kitten,sitting)=3"  3 "$(levenshtein kitten sitting)"
t_eq "lev(flaw,lawn)=2"       2 "$(levenshtein flaw lawn)"

# ---- suggest_module ----
t_eq "suggest(doker)=docker"      "docker"  "$(suggest_module doker)"
t_eq "suggest(post)=postgres"     "postgres" "$(suggest_module post)"
t_eq "suggest(zzzqqq) 为空"       ""        "$(suggest_module zzzqqq)"

# ---- parse_multiselect ----
t_eq "parse(1)"            "1"           "$(parse_multiselect 1 10)"
t_eq "parse(1,3)"          "1 3"         "$(parse_multiselect 1,3 10)"
t_eq "parse(2-5)"          "2 3 4 5"     "$(parse_multiselect 2-5 10)"
t_eq "parse(1,3,5-8)"      "1 3 5 6 7 8" "$(parse_multiselect 1,3,5-8 10)"
t_eq "parse(3,1) 排序"     "1 3"         "$(parse_multiselect 3,1 10)"
t_eq "parse(1,1) 去重"     "1"           "$(parse_multiselect 1,1 10)"
parse_multiselect 0 10 >/dev/null 2>&1;      t_rc "parse(0) 越界 rc1"     1 "$?"
parse_multiselect 11 10 >/dev/null 2>&1;     t_rc "parse(11) 越界 rc1"    1 "$?"
parse_multiselect 8-2 10 >/dev/null 2>&1;    t_rc "parse(8-2) 逆序 rc1"   1 "$?"
parse_multiselect "a,1" 10 >/dev/null 2>&1;  t_rc "parse(a,1) 非法 rc1"   1 "$?"

# ---- module_subcommands（menu.sh 重构产物）----
case " $(module_subcommands docker) " in
    *" mirror "*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL: module_subcommands(docker) 含 mirror，实际: $(module_subcommands docker)" ;;
esac
case " $(module_subcommands bun) " in
    *" uninstall "*) PASS=$((PASS + 1)) ;;
    *) FAIL=$((FAIL + 1)); echo "FAIL: module_subcommands(bun) 含 uninstall" ;;
esac

echo "unit_suggest: 通过 $PASS / 失败 $FAIL"
[[ $FAIL -eq 0 ]]
```

```bash
chmod +x tests/unit_suggest.sh
```

- [ ] **Step 2: 运行验证失败**

Run: `bash tests/unit_suggest.sh`
Expected: FAIL（`levenshtein: command not found` 等导致多个 FAIL，退出码 1）。

- [ ] **Step 3: 实现 `lib/suggest.sh`**（新建）：

```bash
#!/usr/bin/env bash
#
# lib/suggest.sh
#
# 纯函数工具库：编辑距离、未知模块建议、多选输入解析。
# 依赖：调用方已 source lib/registry.sh 且完成 registry_scan（仅 suggest_module 需要）。
# bash 3.2 兼容：仅用索引数组与算术展开，无关联数组/${var,,}/wait -n。
#

# 幂等保护
if [[ -n "${_SUGGEST_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_SUGGEST_SH_LOADED=1

# 两字符串的 Levenshtein 编辑距离（纯 bash DP，两行滚动数组）
levenshtein() {
    local a="$1" b="$2"
    local alen=${#a} blen=${#b}
    if [[ "$a" == "$b" ]]; then echo 0; return 0; fi
    if (( alen == 0 )); then echo "$blen"; return 0; fi
    if (( blen == 0 )); then echo "$alen"; return 0; fi
    local i j cost above left diag best
    local prev=() cur=()
    for ((j = 0; j <= blen; j++)); do prev[j]=$j; done
    for ((i = 1; i <= alen; i++)); do
        cur[0]=$i
        for ((j = 1; j <= blen; j++)); do
            if [[ "${a:i-1:1}" == "${b:j-1:1}" ]]; then cost=0; else cost=1; fi
            above=$(( prev[j] + 1 ))
            left=$(( cur[j-1] + 1 ))
            diag=$(( prev[j-1] + cost ))
            best=$above
            if (( left < best )); then best=$left; fi
            if (( diag < best )); then best=$diag; fi
            cur[j]=$best
        done
        prev=("${cur[@]}")
    done
    echo "${prev[blen]}"
}

# 未知模块名建议：前缀匹配 → 子串匹配 → 编辑距离 ≤ 2，至多 3 个
suggest_module() {
    local input="$1"
    local lower
    lower=$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')
    local mod lmod hits="" n
    # 1) 前缀（输入至少 2 字符，避免单字符噪声）
    if (( ${#lower} >= 2 )); then
        for mod in $_REGISTRY_MODULES; do
            lmod=$(printf '%s' "$mod" | tr '[:upper:]' '[:lower:]')
            if [[ "$lmod" == "$lower"* ]]; then
                hits="$hits $mod"
            fi
        done
    fi
    # 2) 子串
    for mod in $_REGISTRY_MODULES; do
        case " $hits " in *" $mod "*) continue ;; esac
        lmod=$(printf '%s' "$mod" | tr '[:upper:]' '[:lower:]')
        if [[ "$lmod" == *"$lower"* ]]; then
            hits="$hits $mod"
        fi
    done
    # 3) 编辑距离 ≤ 2
    for mod in $_REGISTRY_MODULES; do
        n=$(printf '%s' "$hits" | wc -w)
        if (( n >= 3 )); then break; fi
        case " $hits " in *" $mod "*) continue ;; esac
        if (( $(levenshtein "$lower" "$mod") <= 2 )); then
            hits="$hits $mod"
        fi
    done
    # 截取前 3 个
    local out="" cnt=0
    for mod in $hits; do
        cnt=$((cnt + 1))
        if (( cnt > 3 )); then break; fi
        out="$out $mod"
    done
    echo "${out# }"
}

# 多选输入解析：parse_multiselect <输入> <最大序号>
#   输入形如 1 / 1,3 / 2-5 / 1,3,5-8（可混合、乱序、重复）
#   成功：输出去重升序的编号列表（空格分隔），rc 0
#   失败：无输出，rc 1（非法字符 / 越界 / 逆序区间）
parse_multiselect() {
    local input="$1" max="$2"
    [[ "$input" =~ ^[0-9] ]] || return 1
    local out="" item lo hi n
    local IFS=','
    local -a tokens
    read -ra tokens <<< "$input"
    unset IFS
    for item in "${tokens[@]}"; do
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            lo=$item; hi=$item
        elif [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            lo=${BASH_REMATCH[1]}; hi=${BASH_REMATCH[2]}
            if (( lo > hi )); then return 1; fi
        else
            return 1
        fi
        if (( lo < 1 || hi > max )); then return 1; fi
        for ((n = lo; n <= hi; n++)); do
            case " $out " in
                *" $n "*) ;;
                *) out="$out $n" ;;
            esac
        done
    done
    [[ -z "$out" ]] && return 1
    printf '%s\n' $out | sort -n | tr '\n' ' ' | sed 's/ $//'
}
```

- [ ] **Step 4: menu.sh 抽取 `module_subcommands` 并让 `show_list_modules` 复用**

在 `lib/menu.sh` 的 `show_list_modules` 上方新增：

```bash
# 模块支持的子命令（空格分隔）：先解析入口脚本 usage 行的 {a|b|c} 枚举，
# 回退扫描 case 分支的已知子命令词表；最终兜底 "install"。
module_subcommands() {
    local mod="$1"
    local entry_script mod_path script subs usage_line
    entry_script=$(registry_entry_script "$mod")
    mod_path=$(registry_path "$mod")
    script="$SCRIPT_DIR/$mod_path/$entry_script"
    [[ -f "$script" ]] || { echo ""; return 0; }
    subs=""
    usage_line=$(grep -m1 '用法:' "$script" 2>/dev/null || true)
    if [[ "$usage_line" == *"{"*"}"* ]]; then
        subs=$(echo "$usage_line" | sed 's/.*{//;s/}.*//' | tr '|' ' ')
    fi
    if [[ -z "$subs" ]]; then
        subs=$(grep -oE '^\s+(install|uninstall|status|help|mirror|unmirror|start|stop|restart|enable|disable|pull|all|config|example|tun-on|tun-off|clear|list|setup|route-user|route-port|save)\)' "$script" 2>/dev/null | tr -d ' )' | sort -u | tr '\n' ' ' || true)
    fi
    [[ -z "$subs" ]] && subs="install"
    echo "$subs"
}
```

并把 `show_list_modules` 内提取 `subs` 的整段（Task 1 Step 6 版本中的 `subs=""` 到 `[[ -z "$subs" ]] && subs="install"`）替换为一行：

```bash
        subs=$(module_subcommands "$mod")
```

（`[[ -f "$script" ]] || continue` 的存在性检查保留在 show_list_modules 内。）

- [ ] **Step 5: install.sh source 列表接入**

`install.sh:24`（`source "$SCRIPT_DIR/lib/registry.sh"`）之后加：

```bash
source "$SCRIPT_DIR/lib/suggest.sh"
```

- [ ] **Step 6: 运行测试通过**

Run: `bash tests/unit_suggest.sh && ./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: 单测 `失败 0`；routing/static 全绿（含 Task 1 的 DESC 断言不回归）。

- [ ] **Step 7: 提交**

```bash
git add lib/suggest.sh tests/unit_suggest.sh install.sh lib/menu.sh
git commit -m "feat(ux): lib/suggest.sh 编辑距离/模块建议/多选解析 + 独立单测 runner"
```

---

### Task 3: did-you-mean 接入 + usage 分组

**Files:**
- Modify: `install.sh:46-55`（`dispatch_module` 未知模块分支）
- Modify: `lib/menu.sh:301-343`（`show_usage` 模块清单分组）
- Modify: `tests/ci_run.sh`（routing 断言）

**Interfaces:**
- Consumes: `suggest_module <输入>`（Task 2）、`registry_modules_in_category`/`registry_desc`（Task 1）、`$CATEGORY_ORDER`（registry）。

- [ ] **Step 1: 写失败测试**（routing 阶段，Task 1 的 DESC 块后）：

```bash
    # 14. did-you-mean：未知模块给出建议且不再倾倒 usage
    # shellcheck disable=SC2016
    assert "容错: doker → 建议 docker (exit 1)" bash -c \
        'out=$("$1/install.sh" doker 2>&1); rc=$?; [ "$rc" -eq 1 ] && printf "%s" "$out" | grep -q "docker"' _ "$REPO_DIR"
    # shellcheck disable=SC2016
    assert "容错: 无相近候选时不倾倒 usage" bash -c \
        'out=$("$1/install.sh" zzzqqq 2>&1); rc=$?; [ "$rc" -eq 1 ] && printf "%s" "$out" | grep -q "list-categories" && ! printf "%s" "$out" | grep -q "^用法:"' _ "$REPO_DIR"
    assert "容错: usage 按分类分组（含描述）" bash -c \
        '"$1/install.sh" --help | grep -q "\[服务\]" && "$1/install.sh" --help | grep -q "容器引擎"' _ "$REPO_DIR"
```

- [ ] **Step 2: 运行验证失败**

Run: `./tests/ci_run.sh --phase routing`
Expected: 三条 `容错:` FAIL。

- [ ] **Step 3: 改 `dispatch_module` 未知分支**（`install.sh:51-55` 替换为）：

```bash
    if [[ "$resolved" == "$name" ]] && ! echo "$_REGISTRY_MODULES" | grep -qw "$name"; then
        error "未知模块: $name"
        local suggestions first extra
        suggestions=$(suggest_module "$name")
        if [[ -n "$suggestions" ]]; then
            first=$(printf '%s' "$suggestions" | awk '{print $1}')
            echo "  你是想输入 ${first} 吗？（$0 ${first}）"
            extra=$(printf '%s' "$suggestions" | cut -d' ' -f2-)
            if [[ -n "$extra" ]]; then
                echo "  其他候选: ${extra}"
            fi
        fi
        info "查看全部模块: $0 --list-categories"
        exit 1
    fi
```

- [ ] **Step 4: `show_usage` 模块清单分组**（`lib/menu.sh` 的 `show_usage` 整体替换；`$mod_list` 变量与单行清单删除）：

```bash
show_usage() {
    cat <<EOF
用法: $0 [选项] [模块名]

选项:
  -h, --help        显示本帮助
  -v, --version     显示版本
  -s, --status      查看所有模块的安装状态后退出（非交互）
  --dry-run         预览模式：仅打印将执行的操作，不实际执行
  --list            列出可用模块名后退出
  --list-modules    机器可读：模块名 + 支持子命令 + 描述（TSV，供 AI/脚本）
  --list-categories 按分类列出所有模块
  --status-json     机器可读：模块状态 key:value（无颜色，供 AI/脚本）
  check-update      检查远端是否有新版本（不修改本地）
  update            安全检查 + 确认后执行 git pull 更新本地仓库
  scaffold <名称>   生成新模块脚手架（--category <分类> --label <标签>）
  doctor            环境诊断：检查运行 unix_script 所需的前提条件
  cli               安装全局命令 uxs 到 ~/.tools/bin（之后可在任意目录 uxs <子命令>）
  uninstall-cli     卸载全局命令 uxs
  completions       安装 Tab 自动补全到当前 shell 配置

模块（按分类；别名与平台支持详见 --list-categories / README）:
EOF
    local cat mod label desc
    for cat in $CATEGORY_ORDER; do
        local mods
        mods=$(registry_modules_in_category "$cat")
        if [[ -z "$mods" ]]; then continue; fi
        echo "  [$cat]"
        for mod in $mods; do
            label=$(_reg_get "$mod" LABEL)
            desc=$(registry_desc "$mod")
            printf '    %-22s %s\n' "$mod" "${desc:-$label}"
        done
    done
    cat <<EOF

示例:
  $0                       # 进入交互式主菜单（fzf 模糊搜索/多选；无 fzf 自动用分类菜单）
  $0 --status              # 直接打印安装状态
  $0 docker                # 直接安装 docker
  $0 tailscale             # 直接安装 tailscale
  $0 check-update          # 检查是否有新版本
  $0 update                # 更新到最新版本（需确认）
  $0 scaffold my-tool      # 生成名为 my-tool 的新模块脚手架
  $0 doctor                # 环境诊断
  $0 --dry-run docker      # 预览安装 docker 的操作（不实际执行）
  $0 cli                   # 安装全局命令 uxs（之后可 uxs docker-image 等）
EOF
}
```

- [ ] **Step 5: 运行测试通过**

Run: `./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: 全绿（原有 `install.sh --help`、非 TTY 用法断言不回归——新 usage 仍含「显示本帮助」字样）。

- [ ] **Step 6: 提交**

```bash
git add install.sh lib/menu.sh tests/ci_run.sh
git commit -m "feat(ux): 未知模块 did-you-mean 建议 + usage 按分类分组展示"
```

---

### Task 4: 网络请求超时

**Files:**
- Modify: `lib/common.sh`（curl 调用 4 处 + 顶部超时参数数组）
- Modify: `tests/ci_run.sh`（routing 断言）

**Interfaces:**
- Produces: 全局数组 `UXS_CURL_TIMEOUT_ARGS`（source common.sh 即可用）；环境变量 `UXS_CURL_TIMEOUT`（max-time 秒，默认 10）、`UXS_CURL_CONNECT_TIMEOUT`（connect-timeout 秒，默认 5）。**细化 spec**：spec 原文「单值覆盖 connect/max」细化为上述两个独立变量，语义更明确。

- [ ] **Step 1: 写失败测试**（routing 阶段追加）：

```bash
    # 15. 网络超时：common.sh 所有 curl 均带超时参数
    # shellcheck disable=SC2016
    assert "超时: common.sh 定义 UXS_CURL_TIMEOUT_ARGS" bash -c \
        'source "$1/lib/common.sh" && [ "${#UXS_CURL_TIMEOUT_ARGS[@]}" -eq 4 ]' _ "$REPO_DIR"
    local bare_curls
    bare_curls=$(grep -n 'curl ' "$REPO_DIR/lib/common.sh" | grep -v 'UXS_CURL_TIMEOUT_ARGS' | grep -v '^\s*#' || true)
    if [[ -z "$bare_curls" ]]; then
        report_row "超时: 全部 curl 带超时参数" pass
    else
        report_row "超时: 全部 curl 带超时参数" fail "$(printf '%s' "$bare_curls" | head -2 | tr '\n' ' ')"
    fi
```

- [ ] **Step 2: 运行验证失败**

Run: `./tests/ci_run.sh --phase routing`
Expected: 两条 FAIL。

- [ ] **Step 3: 实现**

3a. `lib/common.sh` 颜色定义之后（`NC` 行后）加：

```bash
# ---------------- 网络超时 ----------------
# 所有对外 curl 统一带超时，弱网下不阻塞菜单启动。
# 可用环境变量覆盖：UXS_CURL_TIMEOUT（max-time 秒）、UXS_CURL_CONNECT_TIMEOUT（connect 秒）。
UXS_CURL_TIMEOUT_ARGS=(
    "--connect-timeout" "${UXS_CURL_CONNECT_TIMEOUT:-5}"
    "--max-time" "${UXS_CURL_TIMEOUT:-10}"
)
```

3b. `github_latest_tag` 内两处 `curl -fsSL ${auth[@]+"${auth[@]}"} "$api_url"` 改为：

```bash
curl -fsSL "${UXS_CURL_TIMEOUT_ARGS[@]}" ${auth[@]+"${auth[@]}"} "$api_url"
```

3c. `github_release_asset_url` 内两处同样在 `curl -fsSL` 后插入 `"${UXS_CURL_TIMEOUT_ARGS[@]}"`。

3d. `grep -n 'curl ' lib/common.sh` 确认无遗漏（`check_for_update` 走 `github_latest_tag`，无直接 curl）。

- [ ] **Step 4: 运行测试通过**

Run: `./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add lib/common.sh tests/ci_run.sh
git commit -m "fix(ux): 全部 curl 加 connect/max 超时（UXS_CURL_TIMEOUT 可覆盖），弱网不卡菜单"
```

---

### Task 5: 状态并行批查 + TTL 跨进程缓存 + 图标映射

**Files:**
- Modify: `lib/status.sh`（文件末尾追加新 section）
- Modify: `tests/ci_run.sh`（routing 断言）

**Interfaces:**
- Consumes: `module_status_machine <mod>`（既有）。
- Produces（Task 6/7 依赖）:
  - `status_batch_query <mods...>` → 并行查询并写入内存；无输出
  - `_uxs_state_set <mod> <state>` / `status_state_get <mod>` → 内存读写
  - `status_state_refresh <mod>` → 单模块即时刷新（动作执行后调用）
  - `status_icon <state>` → echo `✓`（installed*/configured）/ 空格（not_*）/ `·`（n/a）/ `?`（其他）
  - `status_cache_load`（命中 rc 0 并填充内存；未命中/禁用 rc 1）、`status_cache_save`、`status_cache_update <mod> <state>`
  - `menu_status_ensure` → 缓存命中或全量并行批查 + 落盘（菜单入口调用）
  - 环境变量：`UXS_STATUS_JOBS`（默认 8）、`UXS_STATUS_CACHE_TTL`（秒，默认 300，0=禁用）、`UXS_STATUS_CACHE_DIR`（默认 `/tmp/uxs-status-$(id -u)`，测试可覆盖）

- [ ] **Step 1: 写失败测试**（routing 阶段追加）：

```bash
    # 16. 状态缓存与图标（lib/status.sh）
    # shellcheck disable=SC2016
    assert "状态: status_icon 映射" bash -c \
        'source "$1/lib/common.sh" && source "$1/lib/registry.sh" && source "$1/lib/status.sh"
         [ "$(status_icon installed)" = "✓" ] && [ "$(status_icon installed:running)" = "✓" ] && \
         [ "$(status_icon configured)" = "✓" ] && [ "$(status_icon not_installed)" = " " ] && \
         [ "$(status_icon n/a)" = "·" ] && [ "$(status_icon unknown)" = "?" ]' _ "$REPO_DIR"
    local sc_dir
    sc_dir=$(mktemp -d)
    # shellcheck disable=SC2016
    assert "状态: 并行批查 + 缓存写入 + 命中" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/status.sh
         registry_scan
         UXS_STATUS_CACHE_DIR="$2" UXS_STATUS_CACHE_TTL=60 status_batch_query docker redis
         [ -n "$(UXS_STATUS_CACHE_DIR="$2" status_state_get docker)" ] && \
         [ -n "$(UXS_STATUS_CACHE_DIR="$2" status_state_get redis)" ]
         UXS_STATUS_CACHE_DIR="$2" status_cache_save
         UXS_STATUS_CACHE_DIR="$2" status_cache_load' _ "$REPO_DIR" "$sc_dir"
    # shellcheck disable=SC2016
    assert "状态: TTL=0 禁用缓存（load 必 miss）" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/status.sh
         if UXS_STATUS_CACHE_DIR="$2" UXS_STATUS_CACHE_TTL=0 status_cache_load; then exit 1; else exit 0; fi' _ "$REPO_DIR" "$sc_dir"
    rm -rf "$sc_dir"
```

- [ ] **Step 2: 运行验证失败**

Run: `./tests/ci_run.sh --phase routing`
Expected: 三条 FAIL（函数未定义）。

- [ ] **Step 3: 实现**（追加到 `lib/status.sh` 末尾）：

```bash
# ============================================================
# 菜单状态层：内存态 + 并行批查 + TTL 跨进程缓存（UX 改造）
#
# 实测串行全量 status 查询 ~5.4s（52 模块），菜单重画不可接受。
# 三层：并行批查（UXS_STATUS_JOBS，默认 8）→ 内存变量 →
#       /tmp TTL 缓存（UXS_STATUS_CACHE_TTL 秒，默认 300，0=禁用；
#       UXS_STATUS_CACHE_DIR 可覆盖，测试用）。
# bash 3.2 兼容：动态变量名沿用 registry 的 eval 模式；并发用 jobs/wait（无 wait -n）。
# ============================================================

# --- 内存态（模块名连字符转下划线，同 _reg_varname 约定）---
_uxs_state_varname() {
    local safe_mod="${1//-/_}"
    echo "_UXS_STATE_${safe_mod}"
}

_uxs_state_set() {
    local varname
    varname=$(_uxs_state_varname "$1")
    eval "${varname}=\$2"
    # 已知模块清单（去重追加），供 cache_save 遍历
    case " ${_UXS_STATE_KNOWN:-} " in
        *" $1 "*) ;;
        *) _UXS_STATE_KNOWN="${_UXS_STATE_KNOWN:-} $1" ;;
    esac
}

status_state_get() {
    local varname
    varname=$(_uxs_state_varname "$1")
    eval "echo \"\${${varname}:-}\""
}

# --- TTL 缓存目录：按仓库路径区分（多 clone 不互相污染）---
_uxs_cache_dir() {
    local base key
    base="${UXS_STATUS_CACHE_DIR:-/tmp/uxs-status-$(id -u)}"
    key=$(printf '%s' "${SCRIPT_DIR:-.}" | cksum | cut -d' ' -f1)
    echo "$base/$key"
}

_uxs_cache_file() {
    echo "$(_uxs_cache_dir)/cache"
}

# 命中：填充内存态返回 0；未命中/禁用/损坏：返回 1
status_cache_load() {
    local ttl="${UXS_STATUS_CACHE_TTL:-300}"
    if [[ "$ttl" == "0" ]]; then return 1; fi
    local file
    file=$(_uxs_cache_file)
    [[ -f "$file" ]] || return 1
    local ts now
    ts=$(sed -n 's/^#ts=//p' "$file" | head -1)
    now=$(date +%s)
    [[ "$ts" =~ ^[0-9]+$ ]] || return 1
    if (( now - ts > ttl )); then return 1; fi
    local mod state
    while IFS=$'\t' read -r mod state; do
        if [[ -z "$mod" || "$mod" == \#* ]]; then continue; fi
        _uxs_state_set "$mod" "$state"
    done < "$file"
    return 0
}

status_cache_save() {
    local ttl="${UXS_STATUS_CACHE_TTL:-300}"
    if [[ "$ttl" == "0" ]]; then return 0; fi
    local dir file mod
    dir=$(_uxs_cache_dir)
    mkdir -p "$dir" 2>/dev/null || return 0
    file="$dir/cache"
    {
        echo "#ts=$(date +%s)"
        for mod in ${_UXS_STATE_KNOWN:-}; do
            printf '%s\t%s\n' "$mod" "$(status_state_get "$mod")"
        done
    } > "$file" 2>/dev/null || true
}

# 单模块状态变更后更新缓存行（缓存不存在则不做任何事）
status_cache_update() {
    local mod="$1" state="$2" file
    file=$(_uxs_cache_file)
    [[ -f "$file" ]] || return 0
    if grep -q "^${mod}$(printf '\t')" "$file"; then
        grep -v "^${mod}$(printf '\t')" "$file" > "${file}.tmp" 2>/dev/null || true
        printf '%s\t%s\n' "$mod" "$state" >> "${file}.tmp"
        mv "${file}.tmp" "$file"
    else
        printf '%s\t%s\n' "$mod" "$state" >> "$file"
    fi
}

# --- 并行批查：固定并发跑 module_status_machine，结果进内存 ---
status_batch_query() {
    local jobs="${UXS_STATUS_JOBS:-8}"
    if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then jobs=8; fi
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/uxs-status.XXXXXX")
    local mod running=0
    for mod in "$@"; do
        (
            local st
            st=$(module_status_machine "$mod" 2>/dev/null || echo unknown)
            [[ -z "$st" ]] && st=unknown
            printf '%s' "$st" > "$tmpdir/$mod"
        ) &
        running=$((running + 1))
        if (( running >= jobs )); then
            wait
            running=0
        fi
    done
    wait
    for mod in "$@"; do
        if [[ -f "$tmpdir/$mod" ]]; then
            _uxs_state_set "$mod" "$(cat "$tmpdir/$mod")"
        else
            _uxs_state_set "$mod" unknown
        fi
    done
    rm -rf "$tmpdir"
}

# 单模块即时刷新（动作执行成功后调用）
status_state_refresh() {
    local mod="$1" st
    st=$(module_status_machine "$mod" 2>/dev/null || echo unknown)
    [[ -z "$st" ]] && st=unknown
    _uxs_state_set "$mod" "$st"
    status_cache_update "$mod" "$st"
}

# 人类菜单状态图标
status_icon() {
    case "$1" in
        installed*|configured) echo "✓" ;;
        not_installed|not_configured) echo " " ;;
        "n/a") echo "·" ;;
        *) echo "?" ;;
    esac
}

# 菜单入口：优先吃缓存，否则并行批查全量并落盘
menu_status_ensure() {
    if status_cache_load; then
        return 0
    fi
    info "正在检查各模块安装状态（首次约数秒；UXS_STATUS_CACHE_TTL=0 可关闭缓存）..."
    # shellcheck disable=SC2086  # $_REGISTRY_MODULES 为受控模块名列表，需要分词
    status_batch_query $_REGISTRY_MODULES
    status_cache_save
}
```

- [ ] **Step 4: 运行测试通过**

Run: `./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add lib/status.sh tests/ci_run.sh
git commit -m "feat(ux): 状态并行批查(8并发)+TTL跨进程缓存+菜单状态图标"
```

---

### Task 6: bash 两级分类菜单重构（menu.sh）

**Files:**
- Modify: `lib/menu.sh`（重写交互区：`show_main_menu`/`interactive_main`/`show_uninstall_menu`/`do_uninstall` 替换为新实现；`show_system_info`/`show_list_modules`/`show_list_categories`/`show_status_json`/`show_usage` 保留）
- Modify: `install.sh`（无签名变化；`interactive_main` 仍是入口）

**Interfaces:**
- Consumes: Task 2 `parse_multiselect`；Task 5 `menu_status_ensure`/`status_state_get`/`status_icon`/`status_state_refresh`/`status_batch_query`/`status_cache_save`；既有 `_reg_get`/`registry_*`/`run_in_dir`/`ensure_module_deps`/`manage_*`。
- Produces（Task 7 依赖）:
  - `resolve_menu_mode` → echo `fzf|bash`（`UXS_MENU=fzf|bash` 强制；auto = 有 fzf 用 fzf；强制 fzf 缺 fzf 时 warn 并回退 bash）
  - `interactive_main` → 按 resolve_menu_mode 分派（`menu_fzf_main` 未定义时兜底 bash）
  - `menu_exec_actions <mods...>` → 依次执行默认动作；install 先 `ensure_module_deps`；HAS_SUBMENU 模块仅允许单选进入 `manage_<name>`；每个动作后 `status_state_refresh`
  - `menu_error <msg>` → 红色错误行（不 sleep、不 clear）
  - 渲染纯函数：`render_main_page`、`render_category_page <cat> <filter>`、`category_items <cat> <filter>`（序号即 category_items 顺序，二者必须同序）

- [ ] **Step 1: 写失败测试**（routing 阶段追加；菜单交互循环不可自动化，覆盖模式解析与渲染纯函数）：

```bash
    # 17. 菜单：模式解析与渲染纯函数（交互循环不自动化）
    # shellcheck disable=SC2016
    assert "菜单: UXS_MENU=bash 强制 bash 模式" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh
         registry_scan
         [ "$(UXS_MENU=bash resolve_menu_mode)" = "bash" ]' _ "$REPO_DIR"
    # shellcheck disable=SC2016
    assert "菜单: category_items 过滤（vpn → tailscale+wireguard）" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh
         registry_scan
         items=$(category_items 服务 vpn)
         echo "$items" | grep -q tailscale && echo "$items" | grep -q wireguard && \
         [ "$(echo "$items" | wc -w)" -eq 2 ]' _ "$REPO_DIR"
    # shellcheck disable=SC2016
    assert "菜单: render_category_page 含状态列与描述" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh
         registry_scan
         render_category_page 服务 "" 2>/dev/null | grep -q "容器引擎" && \
         render_category_page 服务 "" 2>/dev/null | grep -q "docker"' _ "$REPO_DIR"
```

- [ ] **Step 2: 运行验证失败**

Run: `./tests/ci_run.sh --phase routing`
Expected: 三条 FAIL。

- [ ] **Step 3: 重写 menu.sh 交互区**

将 `lib/menu.sh` 中 `show_main_menu`、`interactive_main`、`show_uninstall_menu`、`do_uninstall` 四个函数整体删除，替换为下述实现（`show_system_info` 保留不动，被 `render_main_page` 复用）：

```bash
# ============================================================
# 交互菜单（UX 改造）：两级分类导航 + 多选 + 过滤 + 状态图标
# fzf 可用时由 menu_fzf.sh 的 menu_fzf_main 接管（见 interactive_main 分派）。
# ============================================================

# 菜单模式解析：UXS_MENU=fzf|bash 强制；auto=有 fzf 用 fzf；强制 fzf 缺失时回退 bash
resolve_menu_mode() {
    local mode="${UXS_MENU:-auto}"
    case "$mode" in
        fzf)
            if command -v fzf >/dev/null 2>&1; then
                echo "fzf"
            else
                warn "UXS_MENU=fzf 但未检测到 fzf，回退 bash 菜单（安装：brew install fzf / apt install fzf）"
                echo "bash"
            fi
            ;;
        bash) echo "bash" ;;
        *)
            if command -v fzf >/dev/null 2>&1; then echo "fzf"; else echo "bash"; fi
            ;;
    esac
}

# 错误提示：不清屏、不 sleep（保留现场，用户看得到错在哪）
menu_error() {
    error "$1"
}

# ---------------- 首页与分类页渲染（纯函数，可测） ----------------

render_main_page() {
    clear 2>/dev/null || true
    header "🚀 一键安装脚本 - 服务与环境管理工具"
    echo "========================================"
    show_system_info
    local current_ver
    current_ver=$(get_local_version 2>/dev/null || echo unknown)
    echo "脚本版本:      v${current_ver}"
    if [[ "${UPDATE_AVAILABLE:-}" == "true" ]]; then
        echo -e "最新版本:      ${YELLOW}v${REMOTE_LATEST:-?}${NC} ${YELLOW}(有更新！输入 c 检查/更新)${NC}"
    else
        echo "最新版本:      v${current_ver}（已是最新）"
    fi
    echo "───────────────────────────────"
    menu "请选择分类："
    echo
    local n=1 cat mods installed=0 total=0 mod state
    for cat in $CATEGORY_ORDER; do
        mods=$(registry_modules_in_category "$cat")
        if [[ -z "$mods" ]]; then continue; fi
        total=0; installed=0
        for mod in $mods; do
            total=$((total + 1))
            state=$(status_state_get "$mod")
            case "$state" in
                installed*|configured) installed=$((installed + 1)) ;;
            esac
        done
        printf "  %d) %s（%d/%d 已装）\n" "$n" "$cat" "$installed" "$total"
        n=$((n + 1))
    done
    echo
    echo "  --- 管理 ---"
    echo "  s) 查看已安装状态"
    echo "  u) 卸载服务/环境"
    echo "  c) 检查更新"
    echo "  f) 刷新状态缓存"
    echo "  q) 退出"
    echo
    echo "========================================"
}

# 分类页条目（空格分隔模块名）；filter 非空时按 模块名/LABEL/DESC 子串过滤（大小写不敏感）
category_items() {
    local cat="$1" filter="$2" mod label desc hay out=""
    local lf
    lf=$(printf '%s' "$filter" | tr '[:upper:]' '[:lower:]')
    for mod in $(registry_modules_in_category "$cat"); do
        if [[ -n "$lf" ]]; then
            label=$(_reg_get "$mod" LABEL)
            desc=$(registry_desc "$mod")
            hay=$(printf '%s %s %s' "$mod" "$label" "$desc" | tr '[:upper:]' '[:lower:]')
            if [[ "$hay" != *"$lf"* ]]; then continue; fi
        fi
        out="$out $mod"
    done
    echo "${out# }"
}

render_category_page() {
    local cat="$1" filter="$2"
    clear 2>/dev/null || true
    header "📁 ${cat}"
    echo "========================================"
    if [[ -n "$filter" ]]; then
        echo "过滤: /${filter}（输入 / 清空过滤）"
        echo "───────────────────────────────"
    fi
    local mods n=1 mod label desc state icon marker
    mods=$(category_items "$cat" "$filter")
    if [[ -z "$mods" ]]; then
        warn "无匹配模块"
    fi
    for mod in $mods; do
        label=$(_reg_get "$mod" LABEL)
        desc=$(registry_desc "$mod")
        state=$(status_state_get "$mod")
        icon=$(status_icon "$state")
        marker=""
        if [[ -n "$(_reg_get "$mod" HAS_SUBMENU)" ]]; then
            marker="（子菜单）"
        fi
        printf "  %2d) %s %-18s %-22s %s%s\n" "$n" "$icon" "$mod" "$label" "$desc" "$marker"
        n=$((n + 1))
    done
    echo
    echo "───────────────────────────────"
    echo "  b) 返回上级    （多选示例: 1,3,5-8；过滤示例: /vpn）"
    echo "========================================"
}

# ---------------- 动作执行（bash 菜单与 fzf 菜单共用） ----------------

menu_exec_actions() {
    local mods=("$@") mod submenu path entry default_action
    if [[ ${#mods[@]} -eq 0 ]]; then return 0; fi
    for mod in "${mods[@]}"; do
        submenu=$(_reg_get "$mod" HAS_SUBMENU)
        if [[ -n "$submenu" ]]; then
            if [[ ${#mods[@]} -gt 1 ]]; then
                warn "${mod} 需进入子菜单操作，已跳过（请单独选择）"
                continue
            fi
            "manage_${submenu}"
            break
        fi
        default_action=$(registry_default_action "$mod")
        local -a action_args
        read -ra action_args <<< "$default_action"
        if [[ "${action_args[0]:-}" == "install" ]]; then
            ensure_module_deps "$mod"
        fi
        path=$(registry_path "$mod")
        entry=$(registry_entry_script "$mod")
        run_in_dir "$path" "$entry" "${action_args[@]}"
        status_state_refresh "$mod"
    done
    echo
    read -r -p "按回车键返回..."
}

# ---------------- 主循环（bash 模式） ----------------

menu_check_update() {
    clear 2>/dev/null || true
    header "🔄 检查更新"
    echo "========================================"
    info "当前版本：v$(get_local_version)"
    if check_for_update 2>/dev/null; then
        warn "检测到新版本：v$(get_local_version) → v${REMOTE_LATEST:-?}"
        if yes_no "是否立即更新？"; then
            do_self_update
        fi
    else
        if [[ -n "${REMOTE_LATEST:-}" ]]; then
            success "已是最新版本：v$(get_local_version)"
        else
            warn "无法获取远端版本（网络问题或未发布 release）"
        fi
    fi
    echo
    read -r -p "按回车键返回主菜单..."
}

interactive_main() {
    local mode
    mode=$(resolve_menu_mode)
    if [[ "$mode" == "fzf" ]] && type menu_fzf_main >/dev/null 2>&1; then
        menu_fzf_main
        return $?
    fi
    interactive_main_bash
}

interactive_main_bash() {
    menu_status_ensure
    local page="main" cur_cat="" choice cats c n found
    while true; do
        if [[ "$page" == "main" ]]; then
            render_main_page
            # 内层读循环：错误输入不重绘，保留现场
            while true; do
                read -r -p "请输入选项: " choice
                case "$choice" in
                    s|S) show_installed_services; break ;;
                    u|U) uninstall_menu_loop; break ;;
                    c|C) menu_check_update; break ;;
                    f|F)
                        info "刷新安装状态..."
                        # shellcheck disable=SC2086
                        status_batch_query $_REGISTRY_MODULES
                        status_cache_save
                        success "状态缓存已刷新"
                        break
                        ;;
                    q|Q|0) info "感谢使用！再见！"; exit 0 ;;
                    ''|*[!0-9]*) menu_error "无效选项: ${choice:-（空）}"; continue ;;
                    *)
                        cats=$(registry_categories)
                        n=1; found=""
                        for c in $cats; do
                            if [[ $n -eq "$choice" ]]; then found="$c"; break; fi
                            n=$((n + 1))
                        done
                        if [[ -n "$found" ]]; then
                            cur_cat="$found"; page="cat"
                            break
                        fi
                        menu_error "无效选项: $choice（共 ${n} 个分类）"
                        continue
                        ;;
                esac
            done
        else
            category_page_loop "$cur_cat"
            page="main"
        fi
    done
}

category_page_loop() {
    local cat="$1" filter="" input items max nums
    while true; do
        render_category_page "$cat" "$filter"
        while true; do
            read -r -p "请输入编号（支持 1,3,5-8，/关键字 过滤，b 返回）: " input
            case "$input" in
                b|B|0) return 0 ;;
                /*)
                    filter="${input#/}"
                    break   # 变更过滤 → 重绘
                    ;;
                "")
                    continue   # 空输入忽略，不重绘
                    ;;
                *[!0-9,-]*)
                    menu_error "无效输入: $input"
                    continue
                    ;;
                *)
                    items=$(category_items "$cat" "$filter")
                    max=$(printf '%s' "$items" | wc -w)
                    if [[ "$max" -eq 0 ]]; then
                        menu_error "当前列表为空"
                        continue
                    fi
                    if ! nums=$(parse_multiselect "$input" "$max"); then
                        menu_error "无效编号: $input（范围 1-${max}）"
                        continue
                    fi
                    local -a sel mods
                    read -ra sel <<< "$nums"
                    mods=()
                    local idx m i=1
                    for m in $items; do
                        for idx in "${sel[@]}"; do
                            if [[ "$idx" -eq "$i" ]]; then
                                mods+=("$m")
                            fi
                        done
                        i=$((i + 1))
                    done
                    menu_exec_actions "${mods[@]}"
                    break   # 执行完毕 → 重绘
                    ;;
            esac
        done
    done
}

# ---------------- 卸载菜单（两级导航 + 状态图标） ----------------

uninstall_menu_loop() {
    menu_status_ensure
    local page="main" cur_cat="" choice cats c n found input items max m i mod
    while true; do
        if [[ "$page" == "main" ]]; then
            clear 2>/dev/null || true
            header "🗑️  卸载服务与环境"
            echo "========================================"
            warn "注意：卸载操作将完全移除服务及其配置文件！"
            echo
            menu "请选择分类："
            echo
            n=1
            cats=$(registry_categories)
            for c in $cats; do
                if [[ -n "$(registry_modules_in_category "$c")" ]]; then
                    printf "  %d) %s\n" "$n" "$c"
                    n=$((n + 1))
                fi
            done
            echo "  0) 返回主菜单"
            echo
            echo "========================================"
            read -r -p "请输入选项: " choice
            if [[ "$choice" == "0" ]]; then return 0; fi
            if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
                menu_error "无效选项: $choice"
                continue
            fi
            n=1; found=""
            for c in $cats; do
                if [[ -n "$(registry_modules_in_category "$c")" ]]; then
                    if [[ $n -eq "$choice" ]]; then found="$c"; break; fi
                    n=$((n + 1))
                fi
            done
            if [[ -z "$found" ]]; then
                menu_error "无效选项: $choice"
                continue
            fi
            cur_cat="$found"; page="cat"
        else
            clear 2>/dev/null || true
            header "🗑️  卸载 · ${cur_cat}"
            echo "========================================"
            items=$(registry_modules_in_category "$cur_cat")
            max=$(printf '%s' "$items" | wc -w)
            i=1
            for m in $items; do
                printf "  %2d) %s %-18s %s\n" "$i" "$(status_icon "$(status_state_get "$m")")" "$m" "$(_reg_get "$m" LABEL)"
                i=$((i + 1))
            done
            echo "  0) 返回上级"
            echo "========================================"
            read -r -p "请输入要卸载的编号: " input
            if [[ "$input" == "0" ]]; then page="main"; continue; fi
            if ! [[ "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 || "$input" -gt "$max" ]]; then
                menu_error "无效编号: $input"
                continue
            fi
            i=1; mod=""
            for m in $items; do
                if [[ $i -eq "$input" ]]; then mod="$m"; break; fi
                i=$((i + 1))
            done
            local entry
            entry=$(registry_entry_script "$mod")
            if yes_no "确认卸载 $(_reg_get "$mod" LABEL)？"; then
                info "开始卸载..."
                run_in_dir "$(registry_path "$mod")" "$entry" uninstall
                status_state_refresh "$mod"
            fi
            echo
            read -r -p "按回车键继续..."
        fi
    done
}
```

- [ ] **Step 4: 运行测试通过**

Run: `./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: 全绿（含既有非 TTY 断言：`install.sh </dev/null` 仍打印「检测到非交互环境」+「显示本帮助」——该路径不进 `interactive_main`，不受影响）。

- [ ] **Step 5: 手工冒烟（有 TTY 的终端）**

Run: `UXS_MENU=bash ./install.sh`
Expected: 首页 5 个分类带「x/y 已装」；进「服务」分类看到 `✓ docker … 容器引擎…`；输入 `/vpn` 过滤出 tailscale+wireguard；输入 `b` 返回；`q` 退出。错误输入（如 `99`）打印错误行且不闪屏。

- [ ] **Step 6: 提交**

```bash
git add lib/menu.sh
git commit -m "feat(ux): bash 菜单两级分类导航+状态图标+描述+多选(1,3,5-8)+/过滤"
```

---

### Task 7: fzf 菜单（`lib/menu_fzf.sh`）

**Files:**
- Create: `lib/menu_fzf.sh`
- Modify: `install.sh`（source 列表加 `lib/menu_fzf.sh`，加在 `lib/menu.sh` 之后）
- Modify: `tests/ci_run.sh`（routing 断言）

**Interfaces:**
- Consumes: Task 6 `menu_exec_actions`/`menu_status_ensure`；Task 5 `status_state_get`/`status_icon`；registry API。
- Produces: `menu_fzf_main`（fzf 多选界面，ESC/取消静默返回 rc 0）；`_fzf_preview_supported`（fzf ≥ 0.20.0 判定）。

- [ ] **Step 1: 写失败测试**（routing 阶段追加；CI 容器无 fzf，主要验证降级与源码结构）：

```bash
    # 18. fzf 菜单：源码结构与降级
    assert "fzf 菜单: lib/menu_fzf.sh 存在" bash -c "test -f '$REPO_DIR/lib/menu_fzf.sh'"
    assert "fzf 菜单: install.sh 已 source menu_fzf.sh" bash -c "grep -q 'lib/menu_fzf.sh' '$REPO_DIR/install.sh'"
    # shellcheck disable=SC2016
    assert "fzf 菜单: 无 fzf 时 resolve_menu_mode=auto → bash" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh && source ./lib/menu_fzf.sh
         registry_scan
         if command -v fzf >/dev/null 2>&1; then
            [ "$(UXS_MENU=bash resolve_menu_mode)" = "bash" ]
         else
            [ "$(resolve_menu_mode)" = "bash" ]
         fi' _ "$REPO_DIR"
```

- [ ] **Step 2: 运行验证失败**

Run: `./tests/ci_run.sh --phase routing`
Expected: 前两条 FAIL。

- [ ] **Step 3: 实现 `lib/menu_fzf.sh`**（新建）：

```bash
#!/usr/bin/env bash
#
# lib/menu_fzf.sh
#
# fzf 交互菜单：模糊搜索 + TAB 多选 + 右侧 README 预览。
# 依赖 fzf（可选）：由 lib/menu.sh 的 resolve_menu_mode 保证仅在 fzf 存在时进入。
# 行格式（TAB 分隔）：图标\t模块名\tLABEL\tDESC\t物理路径
#

# 幂等保护
if [[ -n "${_MENU_FZF_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_MENU_FZF_SH_LOADED=1

# fzf ≥ 0.20.0 才有 --preview；1.x 及以上恒真
_fzf_preview_supported() {
    command -v fzf >/dev/null 2>&1 || return 1
    local v maj min
    v=$(fzf --version 2>/dev/null | awk '{print $1}')
    maj=${v%%.*}
    min=${v#*.}; min=${min%%.*}
    [[ "$maj" =~ ^[0-9]+$ ]] || return 1
    if (( maj > 0 )); then return 0; fi
    [[ "$min" =~ ^[0-9]+$ ]] && (( min >= 20 ))
}

menu_fzf_main() {
    menu_status_ensure
    # preview 子 shell 需要仓库绝对路径
    export UXS_REPO_DIR="$SCRIPT_DIR"

    local lines="" mod state icon label desc path
    for mod in $_REGISTRY_MODULES; do
        state=$(status_state_get "$mod")
        icon=$(status_icon "$state")
        label=$(_reg_get "$mod" LABEL)
        desc=$(registry_desc "$mod")
        path=$(registry_path "$mod")
        lines+="${icon}	${mod}	${label}	${desc}	${path}"$'\n'
    done

    local -a fzf_args=(--multi --header="TAB 多选 · 回车执行默认动作 · ESC 退出" --delimiter=$'\t')
    if _fzf_preview_supported; then
        fzf_args+=(
            --preview 'head -30 "$UXS_REPO_DIR/{5}/README.md" 2>/dev/null || echo "（无模块 README）"'
            --preview-window "right:40%:wrap"
        )
    fi

    local selected
    if ! selected=$(printf '%s' "$lines" | fzf "${fzf_args[@]}"); then
        # ESC / Ctrl-C / 无选择：静默返回
        return 0
    fi
    local -a mods
    read -ra mods <<< "$(printf '%s\n' "$selected" | awk -F'\t' '{print $2}' | tr '\n' ' ')"
    if [[ ${#mods[@]} -eq 0 ]]; then return 0; fi
    menu_exec_actions "${mods[@]}"
}
```

- [ ] **Step 4: install.sh source 接入**（`source "$SCRIPT_DIR/lib/menu.sh"` 之后）：

```bash
source "$SCRIPT_DIR/lib/menu_fzf.sh"
```

- [ ] **Step 5: 运行测试通过**

Run: `./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: 全绿。

- [ ] **Step 6: 手工冒烟**（本机若装了 fzf）

Run: `./install.sh`（不设 UXS_MENU，应直接进 fzf 界面）
Expected: 列表行含 `✓` 图标与中文描述；输入 `vpn` 模糊过滤；TAB 勾选 2 个回车批量执行；ESC 退出回 shell。

- [ ] **Step 7: 提交**

```bash
git add lib/menu_fzf.sh install.sh tests/ci_run.sh
git commit -m "feat(ux): fzf 菜单（模糊搜索+TAB多选+README预览），无 fzf 自动降级"
```

---

### Task 8: 补全注册表驱动动态化

**Files:**
- Rewrite: `completions/uxs.bash`
- Rewrite: `completions/uxs.zsh`
- Modify: `tests/ci_run.sh`（routing 断言）
- Modify: `docs/superpowers/specs/2026-08-15-ux-overhaul-design.md`（⑤ 节按实施细化修订，见 Step 6）

**Interfaces:**
- Consumes: 仓库目录布局（`services|essentials|dev-tools|ai-tools|sys-tools/<mod>/.manifest`）、模块 usage 行 `{a|b|c}` 枚举启发式（与 `module_subcommands` 相同）。
- Produces: bash/zsh 补全运行时从 `.manifest` 动态生成模块清单（新增模块自动进补全，永不脱节）；bash 对未知模块回退 `install uninstall status help`。

**实施细化（对 spec ⑤ 的偏离说明）**：spec 原文「DESC 不进补全」。实施保留 zsh 的描述显示（zsh 现状即有描述，去掉是回归），来源改为与模块清单同一次 `.manifest` 扫描读取 `LABEL=`/`DESC=`，无额外 IO 开销；bash 的 compgen 机制本身无描述展示，维持纯名称。Task 8 Step 6 会把此细化写回 spec。

- [ ] **Step 1: 写失败测试**（routing 阶段追加）：

```bash
    # 19. 补全：注册表驱动（与 --list 同源）
    # shellcheck disable=SC2016
    assert "补全: bash 模块清单与注册表一致" bash -c '
        COMP_WORDS=(uxs ""); COMP_CWORD=1
        source "$1/completions/uxs.bash"
        _uxs_completions
        printf "%s\n" "${COMPREPLY[@]}" | sort > /tmp/uxs_comp.$$.txt
        "$1/install.sh" --list | tr " " "\n" | grep -v "^$" | sort > /tmp/uxs_reg.$$.txt
        diff -q /tmp/uxs_comp.$$.txt /tmp/uxs_reg.$$.txt
        rc=$?; rm -f /tmp/uxs_comp.$$.txt /tmp/uxs_reg.$$.txt; exit $rc' _ "$REPO_DIR"
    if command -v zsh >/dev/null 2>&1; then
        assert "补全: uxs.zsh 语法正确" zsh -n "$REPO_DIR/completions/uxs.zsh"
    else
        report_row "补全: uxs.zsh 语法" skip "zsh 未安装"
    fi
    assert "补全: uxs.zsh manifest 驱动（无硬编码清单）" bash -c \
        "! grep -q 'bbr:BBR' '$REPO_DIR/completions/uxs.zsh' && grep -q 'manifest' '$REPO_DIR/completions/uxs.zsh'"
    assert "补全: uxs.bash manifest 驱动" bash -c \
        "! grep -q 'bbr brew bun clash' '$REPO_DIR/completions/uxs.bash' && grep -q 'manifest' '$REPO_DIR/completions/uxs.bash'"
```

- [ ] **Step 2: 运行验证失败**

Run: `./tests/ci_run.sh --phase routing`
Expected: bash 一致性断言 FAIL（旧清单缺 certbot/code-lint/disk-usage/nat）；zsh 硬编码断言 FAIL。

- [ ] **Step 3: 重写 `completions/uxs.bash`**（整文件替换）：

```bash
#!/usr/bin/env bash
# unix_script / uxs Bash 自动补全（注册表驱动）
# 模块清单运行时从仓库 .manifest 动态生成，新增模块自动进补全。
# 用法：source completions/uxs.bash

_uxs_completions() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local comp_dir repo_root cat_dir d
    comp_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_root="$(cd "$comp_dir/.." && pwd)"

    # 第一个参数：模块名 + 全局选项
    if [[ $COMP_CWORD -eq 1 ]]; then
        local modules="" globals
        for cat_dir in services essentials dev-tools ai-tools sys-tools; do
            [[ -d "$repo_root/$cat_dir" ]] || continue
            for d in "$repo_root/$cat_dir"/*/; do
                if [[ -f "$d/.manifest" ]]; then
                    modules="$modules $(basename "$d")"
                fi
            done
        done
        globals="--status --status-json --list --list-modules --list-categories --dry-run --no-deps --version --help update check-update cli uninstall-cli doctor scaffold export apply completions"
        COMPREPLY=( $(compgen -W "$modules $globals" -- "$cur") )
        return 0
    fi

    # 第二个参数：子命令（解析模块 usage 行 {a|b|c} 枚举；无枚举回退默认四件套）
    if [[ $COMP_CWORD -eq 2 ]]; then
        local mod="${COMP_WORDS[1]}" script="" subcmds="" usage_line
        for cat_dir in services essentials dev-tools ai-tools sys-tools; do
            if [[ -f "$repo_root/$cat_dir/$mod/install.sh" ]]; then
                script="$repo_root/$cat_dir/$mod/install.sh"
                break
            fi
        done
        if [[ -n "$script" ]]; then
            usage_line=$(grep -m1 '用法:' "$script" 2>/dev/null || true)
            if [[ "$usage_line" == *"{"*"}"* ]]; then
                subcmds=$(echo "$usage_line" | sed 's/.*{//;s/}.*//' | tr '|' ' ')
            fi
        fi
        [[ -z "$subcmds" ]] && subcmds="install uninstall status help"
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi

    return 0
}

complete -F _uxs_completions uxs
complete -F _uxs_completions install.sh
```

- [ ] **Step 4: 重写 `completions/uxs.zsh`**（整文件替换）：

```zsh
#compdef uxs

# unix_script / uxs Zsh 自动补全（注册表驱动）
# 模块清单与描述运行时从仓库 .manifest 动态生成，新增模块自动进补全。
# 用法：source completions/uxs.zsh

_uxs() {
    local -a modules globals subcmds
    local comp_file repo_root mf mod label desc line script
    comp_file=${(%):-%x}
    repo_root=${comp_file:A:h}/..

    # 模块清单：扫描各分类目录 .manifest（与 install.sh --list 同源）
    modules=()
    for mf in "$repo_root"/services/*/.manifest(N) \
              "$repo_root"/essentials/*/.manifest(N) \
              "$repo_root"/dev-tools/*/.manifest(N) \
              "$repo_root"/ai-tools/*/.manifest(N) \
              "$repo_root"/sys-tools/*/.manifest(N); do
        mod=${mf:h:t}
        desc=$(grep -m1 '^DESC=' "$mf" 2>/dev/null | cut -d= -f2-)
        label=$(grep -m1 '^LABEL=' "$mf" 2>/dev/null | cut -d= -f2-)
        modules+=("${mod}:${desc:-$label}")
    done

    globals=(
        '--status:查看所有模块状态'
        '--status-json:机器可读状态'
        '--list:列出模块名'
        '--list-modules:列出模块及子命令'
        '--list-categories:列出模块分类'
        '--dry-run:预览模式'
        '--no-deps:跳过依赖自动安装'
        '--version:查看版本'
        '--help:帮助信息'
        'update:更新到最新版'
        'check-update:检查新版本'
        'cli:安装全局命令 uxs'
        'uninstall-cli:卸载全局命令 uxs'
        'completions:安装 Tab 补全'
        'doctor:环境诊断'
        'scaffold:创建新模块模板'
        'export:导出已装模块为 profile'
        'apply:从 profile 应用配置'
    )

    _arguments -C \
        '1: :->first_arg' \
        '2: :->second_arg' \
        '*:: :->rest'

    case $state in
        first_arg)
            _describe -t modules '模块' modules
            _describe -t globals '全局选项' globals
            ;;
        second_arg)
            local m=$words[2]
            script=$(print -r -- "$repo_root"/*/"$m"/install.sh(N) | head -1)
            subcmds=()
            if [[ -n $script ]]; then
                line=$(grep -m1 '用法:' "$script" 2>/dev/null)
                if [[ $line == *\{*}* ]]; then
                    subcmds=( ${(s:|:)${${line##*\{}%%\}*}} )
                fi
            fi
            (( $#subcmds )) || subcmds=(install uninstall status help)
            _describe -t subcmds '子命令' subcmds
            ;;
    esac
}

_uxs "$@"
```

- [ ] **Step 5: 运行测试通过**

Run: `./tests/ci_run.sh --phase routing && ./tests/ci_run.sh --phase static`
Expected: 全绿（macOS 本机有 zsh，`zsh -n` 也应 PASS）。
手工冒烟：`bash -c 'source completions/uxs.bash; COMP_WORDS=(uxs ""); COMP_CWORD=1; _uxs_completions; echo "${COMPREPLY[*]}"'` 应输出全部 52 个模块（含 certbot/code-lint/disk-usage/nat）。

- [ ] **Step 6: 修订 spec ⑤**

`docs/superpowers/specs/2026-08-15-ux-overhaul-design.md` ⑤ 节的「DESC 不进补全…」条目替换为：

```markdown
  - 描述展示：zsh 补全保留描述显示（现状即有，去掉属回归），来源改为与模块清单同一次 `.manifest` 扫描读取 `LABEL=`/`DESC=`，无额外 IO；bash compgen 无描述机制，维持纯名称
```

- [ ] **Step 7: 提交**

```bash
git add completions/uxs.bash completions/uxs.zsh tests/ci_run.sh docs/superpowers/specs/2026-08-15-ux-overhaul-design.md
git commit -m "feat(ux): bash/zsh 补全注册表驱动动态生成（修复脱节 4 模块，新增自动同步）"
```

---

### Task 9: 文档同步（README / AGENTS.md / CHANGELOG）

**Files:**
- Modify: `README.md`（新增「交互式菜单」一节 + `--list-modules` 示例三列 + 别名/补全小节措辞）
- Modify: `AGENTS.md`（`--list-modules` 输出示例与说明）
- Modify: `CHANGELOG.md`（`[Unreleased]`）

**Interfaces:** 无代码接口；文案必须与实现一致（环境变量名、多选语法、图标含义以本计划 Global Constraints 与 Task 5/6/7 的实现为准）。

- [ ] **Step 1: README 增补**

1a. 在「统一子命令接口」章节之前插入：

```markdown
## 🖥️ 交互式菜单

无参数运行 `./install.sh` 进入交互菜单。根据环境自动选择模式（`UXS_MENU=fzf|bash` 强制指定）：

**fzf 模式**（检测到 [fzf](https://github.com/junegunn/fzf) 时自动启用）
- 输入关键字模糊搜索模块（模块名 / 名称 / 中文描述）
- `TAB` 勾选多个模块，回车批量执行默认动作（install 依赖自动先装）
- 右侧预览窗格显示模块 README（fzf ≥ 0.20）

**bash 分类菜单**（无 fzf 时自动降级）
- 首页选分类（服务 / 装机必备 / 开发环境 / AI工具 / 系统工具，附「已装/总数」），再进模块列表
- 每行含状态图标与中文描述：`✓` 已安装 · 空白 未安装 · `·` 本平台不适用
- 支持一次多选：输入 `1,3,5-8`（逗号/区间可混合）
- 输入 `/关键字` 过滤当前分类（匹配模块名/名称/描述），单独输入 `/` 清空过滤
- `b` 返回上级；首页：`s` 状态总览 · `u` 卸载 · `c` 检查更新 · `f` 刷新状态缓存 · `q` 退出

菜单内的安装状态来自并行查询的跨进程缓存：默认缓存 300 秒（`UXS_STATUS_CACHE_TTL` 调整，`0` 禁用），并发度 `UXS_STATUS_JOBS`（默认 8）。
```

1b. README 中既有 `--list-modules` 示例输出更新为三列形态（保持原有行，追加描述列示例），并在该表格/段落注明「第 3 列为模块描述（DESC）」。

- [ ] **Step 2: AGENTS.md 更新**

「机器可读的模块清单」小节的示例与说明改为：

```markdown
### 机器可读的模块清单（含子命令）

```bash
./install.sh --list-modules
# 输出 TSV：模块名\t支持子命令[  requires:...]\t描述
# node_exporter	install uninstall status help	Prometheus 系统指标收集器
# bun	install mirror unmirror uninstall status help	Bun 运行时（含国内镜像加速）
# minikube	install uninstall status help  requires:docker	本地 Kubernetes 开发环境
```

第 3 列为 `.manifest` 的 `DESC`（一句话中文描述；无描述的模块该列为空）。前两列语义与历史版本一致。
```

- [ ] **Step 3: CHANGELOG**

`CHANGELOG.md` 顶部 `[Unreleased]` 段合并为：

```markdown
## [Unreleased]

### Added
- 交互菜单双轨重构：fzf 模糊搜索/TAB 多选/README 预览（`UXS_MENU=fzf|bash` 强制切换，无 fzf 自动降级）
- bash 分类两级菜单：状态图标、模块描述、`1,3,5-8` 多选、`/关键字` 过滤
- did-you-mean：未知模块名给出编辑距离建议，不再倾倒模块清单
- `.manifest` 新增 `DESC` 字段（描述单一数据源），`--list-modules` 追加描述列
- 安装状态并行批查 + TTL 跨进程缓存（`UXS_STATUS_CACHE_TTL` / `UXS_STATUS_JOBS`）
- bash/zsh 补全改为注册表驱动动态生成（新增模块自动进补全）

### Fixed
- 弱网环境启动菜单长时间卡顿（GitHub API 请求无超时；现默认 connect 5s / max 10s，`UXS_CURL_TIMEOUT` 可覆盖）
```

- [ ] **Step 4: 校验文档与实现一致**

Run: `grep -rn 'UXS_STATUS_CACHE_TTL\|UXS_MENU\|UXS_CURL_TIMEOUT' README.md AGENTS.md CHANGELOG.md && ./tests/ci_run.sh --phase static`
Expected: 文档中的环境变量名与 lib 实现逐一对应；static 全绿。

- [ ] **Step 5: 提交**

```bash
git add README.md AGENTS.md CHANGELOG.md
git commit -m "docs: 同步交互菜单/状态缓存/超时/补全文档（README/AGENTS/CHANGELOG）"
```

---

### Task 10: 收尾全量验证与 spec 状态更新

**Files:**
- Modify: `docs/superpowers/specs/2026-08-15-ux-overhaul-design.md`（头部状态改已实施）
- Modify: `tests/static-report.md`、`tests/routing-report.md`（CI 运行产物）

**Interfaces:** 无。

- [ ] **Step 1: 全量本地验证**

Run: `./tests/ci_run.sh --phase static && ./tests/ci_run.sh --phase routing && bash tests/unit_suggest.sh`
Expected: 三者全绿（`失败 0`；本机 macOS 上 install 阶段大量 skip，不作为门禁）。

- [ ] **Step 2: 交互冒烟双模式**

Run: `UXS_MENU=bash ./install.sh` 与（若本机有 fzf）`./install.sh`
Expected: Task 6 Step 5 / Task 7 Step 6 的预期行为全部成立；`UXS_MENU=fzf`（临时改 PATH 隐藏 fzf 时）出现回退 warn 而非报错退出。

- [ ] **Step 3: spec 状态更新**

`docs/superpowers/specs/2026-08-15-ux-overhaul-design.md` 头部：

```markdown
**状态**: 已实施（2026-08-15，feat/ux-overhaul）
```

- [ ] **Step 4: 提交收尾**

```bash
git add docs/superpowers/specs/2026-08-15-ux-overhaul-design.md tests/static-report.md tests/routing-report.md
git commit -m "test(ux): 全量验证报告 + spec 标记已实施"
```

---

## Self-Review 记录（计划完成后自检，已修正）

1. **Spec 覆盖**：spec ①→Task 1；②→Task 6/7；③→Task 5；④→Task 3（模块级子命令建议按 spec「本次不强制改 52 个模块」精神整体延后，未建无调用方的死代码）；⑤→Task 8（含偏离说明并回写 spec）；⑥→Task 4（单值覆盖细化为两个变量，已在 Interfaces 注明）；⑦→Task 9；⑧→各任务 Step 1 的 TDD 断言 + Task 10 汇总。无遗漏。
2. **占位符扫描**：无 TBD/TODO/「稍后实现」；所有代码步骤含完整代码。
3. **命名一致性**：`menu_exec_actions`/`menu_status_ensure`/`status_state_get`/`status_icon`/`category_items`/`resolve_menu_mode`/`parse_multiselect`/`suggest_module`/`module_subcommands`/`UXS_CURL_TIMEOUT_ARGS` 在定义任务与消费任务间签名一致；Task 6 测试的 source 清单与 install.sh 实际加载顺序一致（suggest/status 在 menu 前）。
