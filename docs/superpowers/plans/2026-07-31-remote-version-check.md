# 远端版本监测与更新提示 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `install.sh` 在启动时自动检查 GitHub 远端是否发布新版本并提示用户，同时提供 `check-update`（主动检查）与 `update`（安全检查 + 确认后 `git pull`）两个子命令。

**Architecture:** 公共能力（版本读取 / 语义比较 / 远端比对 / 安全 git pull）放进 `lib/common.sh`，紧邻现有 `github_latest_tag()`；`install.sh` 只负责调用时机（启动钩子）与子命令分发。所有网络与 git 操作全程容错，绝不影响主流程退出码。

**Tech Stack:** Bash 3.2+（macOS 兼容，禁用 `mapfile`/关联数组等 Bash 4 特性）、`curl`、`git`、`sort -V`、ShellCheck。

## Global Constraints

- **macOS Bash 3.2 兼容**：禁用 `mapfile`、关联数组 `declare -A`、`read -N`、`echo -e` 在 dash 下的差异等。版本比较必须用 `sort -V`（BSD sort 支持）而非 Bash 4 数组。
- **容错优先**：`check_for_update`、自动检查钩子、`do_self_update` 的所有失败路径都不得让 `install.sh` 非零退出或打印错误打断主流程（用 `2>/dev/null` + `|| true` + `return`）。
- **不破坏现有子命令**：`--help` / `--version` / `--status` / `--list` / 模块名路由保持原样，仅新增 `check-update` / `update`。
- **仅提示不自动改**：自动检查只打印提示；`update` 必须经 `yes_no` 确认且通过全部安全检查后才 `git pull`。
- **CI 强制静态检查**：所有新增/修改脚本必须过 `bash -n` 与 `shellcheck -e SC2164,SC1091 -x`（与 CI 一致）。
- **常量**：`UPDATE_REPO="zy84338719/unix_script"`。
- **开关环境变量**：`UNIX_SCRIPT_NO_UPDATE_CHECK=1` 关闭自动检查。
- **自动检查跳过条件**：`CI=true` 或非 TTY 时跳过自动检查（`check-update` 子命令不受影响）。
- **curl 超时**：`--max-time 5`。
- **本计划不改 `VERSION` 文件**（发布动作，留给人工 bump）。

**关键既有函数（已存在于 `lib/common.sh`，本计划复用，勿重复定义）：**
- `github_latest_tag() <repo>` — 取 GitHub 最新 release tag（去前导 `v`），失败返回空。已支持 `GH_TOKEN`/`GITHUB_TOKEN` 认证。
- `yes_no() <prompt>` — `y/Y` 返回 0，否则 1。
- `info()` / `success()` / `warn()` / `error()` — 统一彩色打印。

---

## File Structure

| 文件 | 责任 | 动作 |
|------|------|------|
| `lib/common.sh` | 新增版本监测公共能力：`get_local_version` / `version_gt` / `check_for_update` / `print_update_hint` / `do_self_update` + 常量 `UPDATE_REPO` | 修改（在第 242 行 `github_latest_tag()` 函数块之后、第 243 行 `# ---------------- 服务管理封装` 注释之前插入新区段） |
| `install.sh` | 启动自动检查钩子 + `check-update` / `update` 子命令分发 + usage 文本 | 修改（`main()` 与 `show_usage()`） |
| `tests/ci_run.sh` | routing 阶段新增 check-update / update / 关闭开关测试 | 修改（`phase_routing()`） |
| `README.md` | 文档：自动更新检查说明 + 子命令列表 | 修改 |
| `CHANGELOG.md` | 记录新功能 | 修改 |

---

### Task 1: 在 `lib/common.sh` 新增版本读取与比较函数

**Files:**
- Modify: `lib/common.sh`（在第 242 行 `github_latest_tag() { ... }` 函数闭合 `}` 之后、第 243 行 `# ---------------- 服务管理封装` 之前插入）

**Interfaces:**
- Consumes: `$SCRIPT_DIR`（调用方脚本已定义的全局变量，指向仓库根）。
- Produces:
  - `get_local_version()` → stdout 输出本地版本号字符串（如 `1.2.0`），读不到返回 `unknown`。
  - `version_gt() <a> <b>` → 退出码 0 表示 `a > b`（语义化版本，去前导 `v`），1 表示否。对空值或非版本串保守返回 1。

- [ ] **Step 1: 在 `github_latest_tag()` 之后插入新区段**

定位锚点：`lib/common.sh` 中 `github_latest_tag()` 的闭合 `}`（约第 242 行）与下一行注释 `# ---------------- 服务管理封装（systemd / launchd 双平台） ----------------`（约第 243 行）之间。

插入以下内容（含区段注释 + 常量 + 两个函数）：

```bash

# ---------------- 版本更新检查 ----------------
# 本仓库在 GitHub 的标识（owner/repo），用于查询远端最新 release。
UPDATE_REPO="zy84338719/unix_script"

# 读取本地 VERSION 文件内容（去首尾空白）；读不到返回 "unknown"。
# 依赖调用方已定义的全局变量 SCRIPT_DIR（仓库根）。
get_local_version() {
    local ver_file="${SCRIPT_DIR:-.}/VERSION"
    local ver
    ver=$(cat "$ver_file" 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$ver" ]]; then
        ver="unknown"
    fi
    echo "$ver"
}

# 语义化版本比较：当且仅当 a > b 返回 0，否则返回 1。
# 自动去除前导 'v'；对空值或非法版本串保守返回 1（不误报有更新）。
# 实现：用 sort -V 对 "a\nb" 排序，若最小者 == b 且 a != b，则 a > b。
# 兼容 macOS BSD sort（支持 -V）。
version_gt() {
    local a="$1"
    local b="$2"
    # 去前导 v/V
    a="${a#v}"; a="${a#V}"
    b="${b#v}"; b="${b#V}"
    # 空值或含明显非版本字符（仅允许数字与点）则保守判否
    [[ -z "$a" || -z "$b" ]] && return 1
    [[ "$a" =~ ^[0-9][0-9.]*$ ]] || return 1
    [[ "$b" =~ ^[0-9][0-9.]*$ ]] || return 1
    [[ "$a" == "$b" ]] && return 1
    local lowest
    lowest=$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)
    [[ "$lowest" == "$b" ]]
}
```

- [ ] **Step 2: 验证语法**

Run: `bash -n lib/common.sh && shellcheck -e SC2164,SC1091 -x lib/common.sh`
Expected: 两条命令都无输出、退出码 0。

- [ ] **Step 3: 手工验证函数行为**

Run:
```bash
bash -c '
SCRIPT_DIR="."; source ./lib/common.sh
version_gt 1.2.1 1.2.0 && echo "1.2.1>1.2.0 OK" || echo "1.2.1>1.2.0 FAIL"
version_gt 1.2.0 1.2.0 && echo "eq WRONG" || echo "eq OK"
version_gt 1.2.0 1.2.1 && echo "less WRONG" || echo "less OK"
version_gt 2.0 1.9 && echo "major OK" || echo "major FAIL"
version_gt "" 1.0 && echo "empty WRONG" || echo "empty OK"
version_gt v1.2.3 1.2.2 && echo "vprefix OK" || echo "vprefix FAIL"
echo "local_ver=$(get_local_version)"
'
```
Expected: 输出 `1.2.1>1.2.0 OK`、`eq OK`、`less OK`、`major OK`、`empty OK`、`vprefix OK`、`local_ver=1.2.0`（即当前 VERSION 文件内容）。

- [ ] **Step 4: Commit**

```bash
git add lib/common.sh
git commit -m "feat(common): 新增 get_local_version 与 version_gt 版本比较函数"
```

---

### Task 2: 在 `lib/common.sh` 新增 `check_for_update` 与 `print_update_hint`

**Files:**
- Modify: `lib/common.sh`（紧接 Task 1 插入的区段末尾，即 `version_gt()` 闭合 `}` 之后继续追加）

**Interfaces:**
- Consumes: `get_local_version()`（Task 1）、`github_latest_tag()`（既有）、`UPDATE_REPO`（Task 1 常量）、`version_gt()`（Task 1）、`warn()`（既有）。
- Produces:
  - `check_for_update()` → 设全局 `REMOTE_LATEST`（远端版本或空）与 `UPDATE_AVAILABLE`（`true`/`false`）；返回 0=有更新，1=无更新或出错。网络失败静默。
  - `print_update_hint()` → 读 `UPDATE_AVAILABLE`，为 `true` 时用 `warn` 打印两行提示；无全局则先调用 `check_for_update`。

- [ ] **Step 1: 在 `version_gt()` 之后追加两个函数**

在 Task 1 插入的 `version_gt()` 闭合 `}` 之后、`# ---------------- 服务管理封装` 注释之前，追加：

```bash

# 比对本地与远端版本，设置全局：
#   REMOTE_LATEST      远端最新 tag（去前导 v）；取不到则为空
#   UPDATE_AVAILABLE   true / false
# 返回码：0=有新版本，1=无新版本或检查过程出错（网络失败等，静默不报错）。
check_for_update() {
    REMOTE_LATEST=""
    UPDATE_AVAILABLE=false
    local local_ver remote_ver
    local_ver=$(get_local_version)
    # 复用既有 github_latest_tag：带超时与认证；失败返回空。
    remote_ver=$(curl -fsSL --max-time 5 \
        "${GH_TOKEN:+-H Authorization:}" "${GH_TOKEN:+Bearer $GH_TOKEN}" \
        "${GITHUB_TOKEN:+-H Authorization:}" "${GITHUB_TOKEN:+Bearer $GITHUB_TOKEN}" \
        "https://api.github.com/repos/${UPDATE_REPO}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
    # 上面拼接 GH_TOKEN 头的方式在某些 curl 版本下可能产生空参数，回退到 github_latest_tag
    if [[ -z "$remote_ver" ]]; then
        remote_ver=$(github_latest_tag "$UPDATE_REPO")
    fi
    REMOTE_LATEST="$remote_ver"
    if [[ -n "$remote_ver" ]] && version_gt "$remote_ver" "$local_ver"; then
        UPDATE_AVAILABLE=true
        return 0
    fi
    return 1
}

# 若有更新则打印一行醒目提示（仅提示，不自动改）。
# 若 UPDATE_AVAILABLE 未设置，先调用 check_for_update（容错：失败不打印）。
print_update_hint() {
    if [[ -z "${UPDATE_AVAILABLE:-}" ]]; then
        check_for_update 2>/dev/null || true
    fi
    if [[ "${UPDATE_AVAILABLE:-}" == "true" ]]; then
        warn "[更新提示] 检测到新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST}"
        warn "    运行 ./install.sh update 一键更新（会先确认，不会静默改动）"
    fi
}
```

> 注意：`check_for_update` 里手写 curl 拼接 GH_TOKEN 头较脆弱（空 token 时会产生空 `-H` 参数被 curl 警告），因此紧跟一个回退到既有的 `github_latest_tag`（它内部正确处理了空 token）。如果手写 curl 行在任何环境报警告，可整段替换为直接调用 `remote_ver=$(github_latest_tag "$UPDATE_REPO")`。实现时优先采用更简洁的「直接调用 `github_latest_tag`」版本（见 Step 1b）。

- [ ] **Step 2（采用更简洁实现，替代 Step 1 的 curl 手写段）:**

为避免脆弱的 token 头拼接，实际实现采用直接复用 `github_latest_tag` 的简洁版本。将 Step 1 中 `check_for_update` 的取 remote_ver 段简化为：

```bash
    remote_ver=$(github_latest_tag "$UPDATE_REPO")
```

即整个 `check_for_update` 最终实现为：

```bash
check_for_update() {
    REMOTE_LATEST=""
    UPDATE_AVAILABLE=false
    local local_ver remote_ver
    local_ver=$(get_local_version)
    remote_ver=$(github_latest_tag "$UPDATE_REPO")
    REMOTE_LATEST="$remote_ver"
    if [[ -n "$remote_ver" ]] && version_gt "$remote_ver" "$local_ver"; then
        UPDATE_AVAILABLE=true
        return 0
    fi
    return 1
}
```

- [ ] **Step 3: 验证语法与静态检查**

Run: `bash -n lib/common.sh && shellcheck -e SC2164,SC1091 -x lib/common.sh`
Expected: 无输出、退出码 0。

- [ ] **Step 4: 手工验证（离线容错）**

Run:
```bash
bash -c '
SCRIPT_DIR="."; source ./lib/common.sh
# 模拟离线：check_for_update 不应崩溃，UPDATE_AVAILABLE 应为 false
if check_for_update 2>/dev/null; then echo "有更新: $REMOTE_LATEST"; else echo "无更新或离线(预期)"; fi
echo "UPDATE_AVAILABLE=$UPDATE_AVAILABLE REMOTE_LATEST=${REMOTE_LATEST:-<空>}"
# print_update_hint 在无更新时不应打印任何 warn 行
print_update_hint 2>/dev/null
echo "---hint 结束---"
'
```
Expected: 即便无网络也正常退出，`UPDATE_AVAILABLE=false`，`print_update_hint` 不打印 warn 行（除非远端确实有更新）。

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh
git commit -m "feat(common): 新增 check_for_update 与 print_update_hint 远端版本检查"
```

---

### Task 3: 在 `lib/common.sh` 新增 `do_self_update`（安全检查 + git pull）

**Files:**
- Modify: `lib/common.sh`（紧接 Task 2 的 `print_update_hint()` 闭合 `}` 之后追加，仍在 `# ---------------- 服务管理封装` 注释之前）

**Interfaces:**
- Consumes: `check_for_update()`（Task 2，用于取 `REMOTE_LATEST`）、`get_local_version()`（Task 1）、`yes_no()`（既有）、`info()`/`success()`/`warn()`/`error()`（既有）、`$SCRIPT_DIR`。
- Produces: `do_self_update()` → 安全检查（git 仓库 / origin / 干净工作区 / 非 detached）全部通过 + `yes_no` 确认后执行 `git pull`；返回 0=成功，1=用户拒绝或不安全。

- [ ] **Step 1: 在 `print_update_hint()` 之后追加 `do_self_update`**

```bash

# 安全自更新：检查前置条件 → yes_no 确认 → git pull。
# 任何不安全条件都拒绝执行并提示，绝不静默改动本地仓库。
# 返回码：0=更新成功（或已是最新），1=用户拒绝或不满足安全条件。
do_self_update() {
    cd "${SCRIPT_DIR:-.}" 2>/dev/null || { error "无法进入仓库目录"; return 1; }

    # 1) 必须是 git 仓库
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        error "当前目录不是 git 仓库（可能是直接下载的压缩包）。"
        info "请重新克隆：git clone git@github.com:${UPDATE_REPO}.git"
        return 1
    fi

    # 2) 必须有 origin 远端
    if ! git remote get-url origin >/dev/null 2>&1; then
        error "未配置 origin 远端，无法执行 git pull。"
        info "请手动添加远端或从 ${UPDATE_REPO} 重新克隆。"
        return 1
    fi

    # 3) 工作区必须干净（无未提交改动），避免 pull 覆盖本地修改
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        error "工作区有未提交改动，为安全起见拒绝自动 pull。"
        info "请先 commit 或 stash 本地改动后重试：./install.sh update"
        return 1
    fi

    # 4) detached HEAD 警告（main 分支才适合 pull）
    if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
        warn "当前处于 detached HEAD 状态，git pull 可能无意义。"
        if ! yes_no "仍要尝试更新？"; then
            info "已取消。请切到 main 分支：git checkout main && git pull"
            return 1
        fi
    fi

    # 先查询是否有新版本（取 REMOTE_LATEST 用于提示）
    check_for_update 2>/dev/null || true
    local target="${REMOTE_LATEST:-最新}"
    info "将执行 git pull 更新到 ${target}（origin: $(git remote get-url origin)）"
    if ! yes_no "确认执行 git pull 更新？"; then
        info "已取消更新。"
        return 1
    fi

    info "正在拉取更新..."
    if git pull --ff-only origin 2>/dev/null; then
        local new_ver
        new_ver=$(get_local_version)
        success "更新完成，当前版本：${new_ver}"
        return 0
    else
        error "git pull 失败（可能是冲突或网络问题）。"
        info "请手动执行：git pull --ff-only origin"
        return 1
    fi
}
```

- [ ] **Step 2: 验证语法与静态检查**

Run: `bash -n lib/common.sh && shellcheck -e SC2164,SC1091 -x lib/common.sh`
Expected: 无输出、退出码 0。

- [ ] **Step 3: 手工验证拒绝路径（不破坏当前仓库）**

Run:
```bash
bash -c '
SCRIPT_DIR="."; source ./lib/common.sh
# 制造一个脏工作区文件以触发拒绝路径
touch /tmp/__dirty_marker 2>/dev/null
echo "test" > ./__dirty_test_file 2>/dev/null
# 因有未提交改动，应被拒绝（输出 error 并 return 1）
do_self_update <<< "n"
rc=$?
echo "do_self_update rc=$rc"
rm -f ./__dirty_test_file
'
```
Expected: 打印「工作区有未提交改动…拒绝自动 pull」并 `rc=1`，且**未执行任何 git pull**（`git log` 头部不变）。验证后脏文件已清理。

- [ ] **Step 4: Commit**

```bash
git add lib/common.sh
git commit -m "feat(common): 新增 do_self_update 安全自更新（git 安全检查 + 确认 pull）"
```

---

### Task 4: 在 `install.sh` 接入启动自动检查钩子 + `check-update` / `update` 子命令

**Files:**
- Modify: `install.sh`
  - `main()`（约第 817-841 行）：在 `detect_os` / `detect_arch` 之后、参数 `case` 之前插入自动检查钩子；在 `case` 内新增两个分支。
  - `show_usage()`（约第 786-810 行）：新增两条子命令说明。
  - `dispatch_module()` 兜底 `*)`（约第 782 行）：错误提示纳入新子命令。

**Interfaces:**
- Consumes: `print_update_hint()`（Task 2）、`check_for_update()`（Task 2）、`do_self_update()`（Task 3），均来自 `lib/common.sh`（install.sh 顶部已 `source`）。
- Produces: 两个新子命令 `check-update`、`update`；启动时的非阻塞更新提示。

- [ ] **Step 1: 新增「是否应在启动时自动检查」辅助函数**

在 `install.sh` 的 `main()` 函数**之前**（即 `# ---------------- 主函数 ----------------` 注释之前），新增一个辅助函数：

```bash

# 判断是否应在启动时自动检查更新。
# 跳过条件：UNIX_SCRIPT_NO_UPDATE_CHECK=1、或 CI=true、或非交互（非 TTY）。
should_auto_check_update() {
    [[ "${UNIX_SCRIPT_NO_UPDATE_CHECK:-0}" == "1" ]] && return 1
    [[ "${CI:-false}" == "true" ]] && return 1
    [[ -t 1 ]] || return 1   # 非 TTY（管道/重定向）不自动检查
    return 0
}
```

- [ ] **Step 2: 在 `main()` 插入自动检查钩子**

`main()` 当前结构（约第 817 行起）：

```bash
main() {
    detect_os
    detect_arch

    # 无参数 -> 交互式
    if [[ $# -eq 0 ]]; then
        interactive_main
        return
    fi
    ...
```

在 `detect_arch` 之后、`# 无参数 -> 交互式` 注释之前插入钩子。修改后：

```bash
main() {
    detect_os
    detect_arch

    # 启动时自动检查远端新版本（仅提示，不阻塞、不影响退出码）
    if should_auto_check_update; then
        print_update_hint 2>/dev/null || true
    fi

    # 无参数 -> 交互式
    if [[ $# -eq 0 ]]; then
        interactive_main
        return
    fi
```

- [ ] **Step 3: 在 `main()` 的 `case` 新增 `check-update` / `update` 分支**

当前 `case "$1" in`（约第 828 行）：

```bash
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        -v|--version) echo "unix_script $(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
        -s|--status)  INTERACTIVE=false; show_installed_services; exit 0 ;;
        --list)
            echo "node_exporter ddns-go wireguard tailscale docker fail2ban openlist uptime-kuma cockpit essential-pkgs sys-setup swap bbr nvm zsh minikube dev-tui opencode ollama deskflow shutdown_timer process_manager safe-rm clash multi-net"
            exit 0
            ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)  dispatch_module "$1" ;;
    esac
```

在 `--list)` 分支之后、`-*)` 之前插入两个新分支：

```bash
        check-update)
            info "检查远端最新版本..."
            if check_for_update 2>/dev/null; then
                warn "有新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST}"
                info "运行 ./install.sh update 一键更新"
            else
                if [[ -n "${REMOTE_LATEST:-}" ]]; then
                    success "已是最新版本：$(get_local_version)（远端 ${REMOTE_LATEST}）"
                else
                    warn "无法获取远端版本（网络问题或未发布 release），当前版本 $(get_local_version)"
                fi
            fi
            exit 0
            ;;
        update)
            do_self_update
            exit $?
            ;;
```

- [ ] **Step 4: 更新 `show_usage()` 文本**

在 `show_usage()` 的「选项」区（`--list` 行之后）新增两行；并在「示例」区追加示例。当前（约第 786-810 行）：

```bash
选项:
  -h, --help        显示本帮助
  -v, --version     显示版本
  -s, --status      查看所有模块的安装状态后退出（非交互）
  --list            列出可用模块名后退出

模块名（用于非交互安装）:
  ...
```

在 `--list` 那行之后新增：

```bash
  check-update      检查远端是否有新版本（不修改本地）
  update            安全检查 + 确认后执行 git pull 更新本地仓库
```

在「示例」区追加：

```bash
  $0 check-update          # 检查是否有新版本
  $0 update                # 更新到最新版本（需确认）
```

- [ ] **Step 5: 验证语法与静态检查**

Run: `bash -n install.sh && shellcheck -e SC2164,SC1091 -x install.sh`
Expected: 无输出、退出码 0。

- [ ] **Step 6: 手工验证三个入口**

Run（自动检查在 CI/管道下应跳过，故用 `script` 伪 TTY 或直接验证子命令）：

```bash
# 1) check-update 应正常退出（不管有无网络）
./install.sh check-update; echo "check-update rc=$?"
# 2) update 在当前干净 git 仓库应进入确认流程（输入 n 取消）
echo "n" | ./install.sh update; echo "update rc=$? (期望非0，因管道非TTY可能直接拒绝)"
# 3) UNIX_SCRIPT_NO_UPDATE_CHECK=1 时 --help 不触发网络
UNIX_SCRIPT_NO_UPDATE_CHECK=1 ./install.sh --help >/dev/null; echo "help rc=$?"
# 4) 向后兼容：原有命令仍可用
./install.sh --version; ./install.sh --list | head -c 40; echo
```
Expected: `check-update rc=0`；`update` 不破坏仓库（`git status` 仍 clean）；`help rc=0`；`--version`/`--list` 输出不变。

- [ ] **Step 7: Commit**

```bash
git add install.sh
git commit -m "feat(install): 启动自动检查更新 + check-update/update 子命令"
```

---

### Task 5: 在 `tests/ci_run.sh` 的 routing 阶段新增测试

**Files:**
- Modify: `tests/ci_run.sh`（`phase_routing()` 函数内，在第 143 行 `assert "install.sh 未知模块报错 (exit 1)" ...` 之后追加新断言）

**Interfaces:**
- Consumes: `install.sh` 的 `check-update` / `update` 子命令（Task 4）、`UNIX_SCRIPT_NO_UPDATE_CHECK` 开关（Task 4）。
- Produces: routing 报告新增 4 行断言。

- [ ] **Step 1: 在 routing 阶段追加断言**

定位锚点：`phase_routing()` 内这一行（约第 143 行）之后：

```bash
    assert "install.sh 未知模块报错 (exit 1)" bash -c "! \"$REPO_DIR/install.sh\" __nope__ >/dev/null 2>&1"
```

在其后追加：

```bash

    # 2b. 版本更新检查子命令
    # check-update 即使无网络/无 release 也必须正常退出（容错）
    assert "install.sh check-update (exit 0)" bash "$REPO_DIR/install.sh" check-update
    # update 在 CI（非交互、detached 或受控）不应破坏仓库：用 n 取消 / 或被安全检查拦截
    assert "install.sh update (不破坏仓库)" bash -c "echo n | \"$REPO_DIR/install.sh\" update >/dev/null 2>&1; git -C \"$REPO_DIR\" diff --quiet HEAD"
    # UNIX_SCRIPT_NO_UPDATE_CHECK=1 关闭自动检查，且 --help 不受影响
    assert "关闭自动检查开关后 --help 正常" bash -c "UNIX_SCRIPT_NO_UPDATE_CHECK=1 \"$REPO_DIR/install.sh\" --help >/dev/null"
    # common.sh 新函数存在
    assert "common.sh 含更新检查函数" bash -c "source \"$REPO_DIR/lib/common.sh\" && type get_local_version >/dev/null && type version_gt >/dev/null && type check_for_update >/dev/null && type do_self_update >/dev/null"
```

- [ ] **Step 2: 验证静态检查（ci_run.sh 自身也要过）**

Run: `bash -n tests/ci_run.sh && shellcheck -e SC2164,SC1091 -x tests/ci_run.sh`
Expected: 无输出、退出码 0。

- [ ] **Step 3: 本地运行 routing 阶段验证全绿**

Run: `./tests/ci_run.sh --phase routing --out /tmp/routing-report.md; echo "rc=$?"`
Expected: `rc=0`，报告末尾 `❌ 失败 0`。

- [ ] **Step 4: Commit**

```bash
git add tests/ci_run.sh
git commit -m "test(ci): routing 新增 check-update/update/关闭开关断言"
```

---

### Task 6: 更新 README.md 与 CHANGELOG.md

**Files:**
- Modify: `README.md`（快速开始区 + 非交互命令列表）
- Modify: `CHANGELOG.md`（顶部新增条目）

**Interfaces:**
- 无代码接口；纯文档同步，与 Task 4 的子命令行为一致。

- [ ] **Step 1: 在 README.md 非交互命令示例区追加子命令**

定位 README.md 中「非交互式安装」代码块（含 `./install.sh --help`、`./install.sh --version` 等示例）。在 `--version` 行之后新增：

```bash
./install.sh check-update   # 检查远端是否有新版本
./install.sh update         # 安全检查 + 确认后 git pull 更新
```

- [ ] **Step 2: 在 README.md 新增「自动更新检查」小节**

在「快速开始」大节内、「单独安装某模块」小节之后，新增一小节：

```markdown
### 🔄 自动更新检查

运行 `install.sh` 时会自动（仅提示，不自动改动）检查 GitHub 是否发布了新版本，有更新会在顶部提示。也可手动检查或更新：

```bash
./install.sh check-update   # 检查是否有新版本
./install.sh update         # 安全检查 + 确认后 git pull 更新（需 git clone 来源）
```

> 环境变量 `UNIX_SCRIPT_NO_UPDATE_CHECK=1` 可关闭启动时的自动检查（CI / 离线场景适用）。
```

- [ ] **Step 3: 在 CHANGELOG.md 顶部新增条目**

在 `## [1.2.0] - 2026-07-31` 之上新增（版本号留待发布时定，这里用 `[Unreleased]`）：

```markdown
## [Unreleased]

### 新增
- **远端版本监测与更新提示**：
  - `install.sh` 启动时自动检查 GitHub 最新 release，有新版本在顶部提示（仅提示，不自动改动）。
  - 新增 `check-update` 子命令：主动检查远端版本。
  - 新增 `update` 子命令：安全检查（git 仓库 / origin / 干净工作区 / 非 detached）+ 确认后 `git pull`。
  - 新增 `lib/common.sh` 公共函数：`get_local_version` / `version_gt` / `check_for_update` / `print_update_hint` / `do_self_update`。
  - 环境变量 `UNIX_SCRIPT_NO_UPDATE_CHECK=1` 可关闭启动自动检查。
```

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: 记录远端版本检查与 update 子命令"
```

---

### Task 7: 全量验证与最终自检

**Files:** 无（只读验证）

- [ ] **Step 1: 全量静态检查（与 CI 一致）**

Run: `./tests/ci_run.sh --phase static --out /tmp/static-report.md; echo "rc=$?"`
Expected: `rc=0`，所有 `bash -n` 与 `shellcheck` 行为 pass（shellcheck 未安装则 skip）。

- [ ] **Step 2: 全量路由测试**

Run: `./tests/ci_run.sh --phase routing --out /tmp/routing-report.md; echo "rc=$?"`
Expected: `rc=0`，含本计划新增的 4 条断言全 pass。

- [ ] **Step 3: 端到端手工冒烟**

Run:
```bash
./install.sh --version                    # 向后兼容
./install.sh check-update                 # 正常退出
echo n | ./install.sh update              # 取消，不破坏仓库
git status --porcelain                    # 应为空（未引入脏改动）
git log --oneline -1                      # 头部 commit 为本特性最后一条
```
Expected: 全部符合预期，工作区 clean。

- [ ] **Step 4: 验证 macOS Bash 3.2 兼容性要点**

人工复核（或运行）确认未使用 Bash 4 特性：
- 无 `mapfile` / `readarray`
- 无关联数组 `declare -A`
- `version_gt` 用 `sort -V` 而非数组比较
- `printf '%s\n%s\n'` 而非 here-string `<<<` 数组

Run: `grep -nE 'mapfile|readarray|declare -A' lib/common.sh install.sh; echo "grep rc=$?"`
Expected: 无匹配（grep rc=1）。

---

## Self-Review（计划作者已完成）

**1. Spec 覆盖：**
- 启动自动检查 → Task 4 Step 2 ✓
- `check-update` 子命令 → Task 4 Step 3 ✓
- `update` 子命令 + 安全检查 → Task 3 + Task 4 Step 3 ✓
- 版本比较 → Task 1 ✓
- 开关 / CI 跳过 / 超时 → Task 4 Step 1 + Task 2（github_latest_tag 已含超时概念，本计划复用）✓
- 测试 → Task 5 ✓
- 文档 → Task 6 ✓

**2. 占位符扫描：** 无 TBD/TODO；每步含可执行代码或命令。

**3. 类型/命名一致：** `get_local_version`、`version_gt`、`check_for_update`、`print_update_hint`、`do_self_update`、`UPDATE_REPO`、`REMOTE_LATEST`、`UPDATE_AVAILABLE` 在所有 Task 中拼写一致。

（注：Task 2 给出了「手写 curl」与「直接复用 github_latest_tag」两版，实现时统一采用后者简洁版，避免脆弱的 token 头拼接。）
