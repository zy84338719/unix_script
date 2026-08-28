# disk-usage top 深度下钻 + 交互模式 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增强 `sys-tools/disk-usage` 的 `top` 子命令：`--depth` 参数下钻、智能 TTY 交互式逐层下钻、`--min-size` 过滤、修空格路径/漏隐藏目录/sort -h 兼容三个 bug。

**Architecture:** 单文件模块内重构 `top_disk`：扫描内核统一为 `du -k -d`（tab 分隔纯数字 KB）→ awk 过滤（min-size/根自身）→ 数字排序 → 纯函数 `_fmt_kb` 渲染；交互层用路径栈数组 + `read` 循环，`[ -t 0 ] && [ -t 1 ]` 检测自动退化为纯输出。

**Tech Stack:** 纯 bash（**3.2 兼容**：macOS 自带 bash 3.2，禁用 `${arr[-1]}`/关联数组/`&>>`）、POSIX awk、BSD/GNU du·find·sort 公共子集。

**Spec:** `docs/superpowers/specs/2026-08-28-disk-usage-top-drill-design.md`

## Global Constraints

- 工作目录：git worktree `/Users/zhangyi/my_project/unix_script-top`，分支 `feat/disk-usage-top-drill`。**不要**在 `/Users/zhangyi/my_project/unix_script` 主工作区改任何东西（那边有另一批未提交改动）。
- bash 3.2 兼容：数组末元素用 `${arr[$(( ${#arr[@]} - 1 ))]}`；空数组不得在 `set -u` 下展开 `"${arr[@]}"`（先判 `${#arr[@]}`）；`unset` 数组元素用双quotes让 `$(( ))` 先求值。
- `set -euo pipefail` 禁忌：管道截断一律用 `awk -v n=N 'NR<=n'` 而非 `head`（SIGPIPE→141 中止，仓库已知坑）；`[[ cond ]] && action` 若为函数最后一条会污染返回值，用 if/fi。
- 输出全部中文；颜色/emoji 走 `lib/common.sh` 的 `header/info/warn/error/success` helper（NO_COLOR 由其处理），纯数据行用裸 printf。
- top 是只读命令：不引入 `require_sudo`/dry-run 依赖；sudo 仅作为 du/find 前缀（初始路径为 `/` 时）。
- 每个任务收尾：`bash -n` + `shellcheck -e SC2164,SC1091,SC2317,SC2329 -x`（与 CI static 阶段同参数）对改动文件跑干净，然后 commit。
- 测试统一进 `tests/ci_run.sh` routing 阶段（disk 模块 9d 节之后新增 9e 节），开发期用相同的 `bash -c` 片段单跑以快速迭代。

---

### Task 1: 纯函数 `_parse_size_to_kb` + `_fmt_kb`

**Files:**
- Modify: `sys-tools/disk-usage/install.sh`（在 `# top - 大文件/目录排行` 分节注释之后、`top_disk()` 之前插入两个函数）
- Test: `tests/ci_run.sh`（9d 节之后插入 9e 节前两条断言）

**Interfaces:**
- Consumes: 无
- Produces: `_parse_size_to_kb <"100M"|"2G"|"500k">` → stdout 输出 KB 整数，缺单位/含非法字符 → return 1；`_fmt_kb <kb>` → stdout `12.3G|123M|456K`（≥1G 一位小数，≥1M 向下取整整数 M，其余 K）。Task 2/3 直接调用。

- [ ] **Step 1: 写失败测试**

在 `tests/ci_run.sh` 的 `# 9d. disk 模块…` 断言块之后、`# 4b. status 契约…` 之前插入：

```bash
    # 9e. disk-usage top：深度下钻 + 交互守卫
    local dus_path
    dus_path=$(resolve_module_path disk-usage)
    assert "disk-usage: _fmt_kb 单位换算边界" bash -c '
        source "$1/sys-tools/disk-usage/install.sh" >/dev/null 2>&1
        [ "$(_fmt_kb 456)" = "456K" ] || exit 1
        [ "$(_fmt_kb 1024)" = "1M" ] || exit 1
        [ "$(_fmt_kb 1536)" = "1M" ] || exit 1
        [ "$(_fmt_kb 2097152)" = "2.0G" ] || exit 1
        [ "$(_fmt_kb 1610612736)" = "1536.0G" ] || exit 1
        [ "$(_fmt_kb 1572864)" = "1.5G" ] || exit 1' _ "$REPO_DIR"
    assert "disk-usage: _parse_size_to_kb 解析与拒绝" bash -c '
        source "$1/sys-tools/disk-usage/install.sh" >/dev/null 2>&1
        [ "$(_parse_size_to_kb 100M)" = "102400" ] || exit 1
        [ "$(_parse_size_to_kb 2g)" = "2097152" ] || exit 1
        [ "$(_parse_size_to_kb 500K)" = "500" ] || exit 1
        if _parse_size_to_kb 100 >/dev/null 2>&1; then echo "缺单位应拒绝"; exit 1; fi
        if _parse_size_to_kb 100MB >/dev/null 2>&1; then echo "非法后缀应拒绝"; exit 1; fi
        if _parse_size_to_kb abc >/dev/null 2>&1; then echo "非数字应拒绝"; exit 1; fi' _ "$REPO_DIR"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/zhangyi/my_project/unix_script-top && bash -c 'source sys-tools/disk-usage/install.sh >/dev/null 2>&1; _fmt_kb 456' 2>&1 | tail -1`
Expected: `_fmt_kb: command not found`（两条断言同理失败）

- [ ] **Step 3: 最小实现**

在 `sys-tools/disk-usage/install.sh` 的 `# ============` `# top - 大文件/目录排行` 分节注释后插入（`top_disk()` 保持原样，Task 2 再重构）：

```bash
# ---- top: 纯函数（大小解析/格式化） ----

# "100M"/"2g"/"500K" → KB 整数。必须带 K/M/G 单位（防纯数字歧义），非法返回 1
_parse_size_to_kb() {
    local s="${1:-}" num
    case "$s" in
        *[Kk]) num="${s%[Kk]}" ;;
        *[Mm]) num="${s%[Mm]}" ;;
        *[Gg]) num="${s%[Gg]}" ;;
        *) return 1 ;;
    esac
    [[ "$num" =~ ^[0-9]+$ ]] || return 1
    case "$s" in
        *[Kk]) echo $(( num )) ;;
        *[Mm]) echo $(( num * 1024 )) ;;
        *)     echo $(( num * 1048576 )) ;;
    esac
}

# KB → 人类可读：≥1G 一位小数（1.5G），≥1M 向下取整（123M），其余 K（456K）
_fmt_kb() {
    local kb="$1"
    if (( kb >= 1048576 )); then
        printf '%d.%dG\n' $(( kb / 1048576 )) $(( (kb % 1048576) * 10 / 1048576 ))
    elif (( kb >= 1024 )); then
        printf '%dM\n' $(( kb / 1024 ))
    else
        printf '%dK\n' "$kb"
    fi
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/zhangyi/my_project/unix_script-top && bash tests/ci_run.sh --phase routing --out /tmp/r.md 2>&1 | tail -2; grep -E "disk-usage: _(fmt_kb|parse)" /tmp/r.md`
Expected: 汇总 `失败 0`；两条断言 ✅（其余既有断言不受影响）

- [ ] **Step 5: 质量门 + 提交**

Run: `bash -n sys-tools/disk-usage/install.sh && shellcheck -e SC2164,SC1091,SC2317,SC2329 -x sys-tools/disk-usage/install.sh && bash -n tests/ci_run.sh`

```bash
git add sys-tools/disk-usage/install.sh tests/ci_run.sh
git commit -m "feat(disk-usage): top 纯函数层——_parse_size_to_kb/--min-size 解析与 _fmt_kb 人类可读输出"
```

---

### Task 2: 扫描内核 + 渲染 + `top_disk` 装配（非交互全链路）

**Files:**
- Modify: `sys-tools/disk-usage/install.sh`（整段替换 `top_disk()`，新增 `_top_scan_dirs`/`_top_scan_dirs_fallback`/`_top_scan_files`/`_top_print_dirs`/`_top_print_files`/`_norm_path`；`main()` 参数解析加 `--depth/--min-size/--no-interactive`）
- Test: `tests/ci_run.sh`（9e 节追加 fixture 行为断言）

**Interfaces:**
- Consumes: Task 1 的 `_fmt_kb`/`_parse_size_to_kb`；`lib/common.sh` 的 `header/info/warn/error/detect_os`（main 已调用 detect_os，OS_TYPE 可用）
- Produces（Task 3 依赖，签名固定）:
  - 全局 `USE_SUDO`（0/1，初始路径为 `/` 时 1）、`TOP_MIN_SIZE_KB`（空=不过滤）、`_top_last_paths[]`（最近一次榜单的目录路径，序号即下标+1）
  - `_top_print_dirs <path> <depth> <count>`：渲染目录榜（含表头与「正在扫描」提示）
  - `_top_print_files <path> <count>`：渲染文件榜
- `main()` 新增解析：`--depth N → TOP_DEPTH`、`--min-size S → TOP_MIN_SIZE`、`--no-interactive → TOP_NO_INTERACTIVE=1`

- [ ] **Step 1: 写失败测试**

9e 节追加：

```bash
    assert "disk-usage: top fixture（空格路径/隐藏目录/深度/min-size/文件榜/管道无交互）" bash -c '
        FX=$(mktemp -d) || exit 1
        mkdir -p "$FX/big" "$FX/small" "$FX/.hidden" "$FX/dir with space/lvl2" || exit 1
        dd if=/dev/zero of="$FX/big/huge.bin" bs=1048576 count=51 2>/dev/null || exit 1
        dd if=/dev/zero of="$FX/big/f.bin" bs=1048576 count=3 2>/dev/null || exit 1
        dd if=/dev/zero of="$FX/small/f.bin" bs=1048576 count=1 2>/dev/null || exit 1
        dd if=/dev/zero of="$FX/.hidden/f.bin" bs=1048576 count=2 2>/dev/null || exit 1
        dd if=/dev/zero of="$FX/dir with space/lvl2/f.bin" bs=1048576 count=2 2>/dev/null || exit 1
        out=$(bash "$1/sys-tools/disk-usage/install.sh" top "$FX" --count 20 --no-interactive </dev/null 2>&1); rc=$?
        [ "$rc" -eq 0 ] || { echo "rc=$rc"; echo "$out"; rm -rf "$FX"; exit 1; }
        echo "$out" | grep -q "dir with space" || { echo "空格路径缺失"; exit 1; }
        echo "$out" | grep -q ".hidden" || { echo "隐藏目录缺失"; exit 1; }
        echo "$out" | grep -Eq "[0-9]+(\.[0-9]+)?[MG]" || { echo "无 M/G 单位输出"; exit 1; }
        echo "$out" | grep -q "huge.bin" || { echo "文件榜缺 >50M 文件"; exit 1; }
        echo "$out" | grep -q "q=退出" && { echo "管道下不应出现交互提示"; exit 1; }
        out2=$(bash "$1/sys-tools/disk-usage/install.sh" top "$FX" --min-size 3M --no-interactive </dev/null 2>&1)
        echo "$out2" | grep -q "big" || { echo "min-size 误杀大目录"; exit 1; }
        echo "$out2" | grep -q "small" && { echo "min-size 未过滤小目录"; exit 1; }
        echo "$out2" | grep -q ".hidden" && { echo "min-size 未过滤 2M 隐藏目录"; exit 1; }
        out3=$(bash "$1/sys-tools/disk-usage/install.sh" top "$FX" --depth 2 --count 30 --no-interactive </dev/null 2>&1)
        echo "$out3" | grep -q "lvl2" || { echo "--depth 2 未下钻"; exit 1; }
        echo "$out3" | grep -q "dir with space/lvl2" || { echo "空格路径被截断"; exit 1; }
        if bash "$1/sys-tools/disk-usage/install.sh" top "$FX" --min-size 100 --no-interactive </dev/null >/dev/null 2>&1; then echo "缺单位应报错"; rm -rf "$FX"; exit 1; fi
        rm -rf "$FX"' _ "$REPO_DIR"
```

注意 `grep -q "dir with space/lvl2"` 同时覆盖「含空格路径完整显示」与 depth=1 时子目录不出现无关——depth=1 下 `dir with space`（父）出现而 `lvl2` 不出现由 `out3` 对照。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/zhangyi/my_project/unix_script-top && bash -c 'FX=$(mktemp -d); mkdir -p "$FX/a b"; bash sys-tools/disk-usage/install.sh top "$FX" --depth 2 --no-interactive </dev/null >/dev/null 2>&1; echo rc=$?; rm -rf "$FX"'`
Expected: `rc=1`（现实现不认识 --depth/--no-interactive，落入 `-*` 报未知选项）

- [ ] **Step 3: 实现**

3a. `main()` 参数解析（`--count` 行后追加三行 case 分支）：

```bash
            --depth)      TOP_DEPTH="$2"; shift 2 ;;
            --min-size)   TOP_MIN_SIZE="$2"; shift 2 ;;
            --no-interactive) TOP_NO_INTERACTIVE=1; shift ;;
```

3b. 整段替换 `top_disk()`（从 `top_disk() {` 到其配对 `}`，即现 168-234 行）为：

```bash
# ---- top: 扫描内核 ----
USE_SUDO=0

# 规整路径：去掉尾部斜杠（根 / 除外）
_norm_path() {
    local p="$1"
    [[ "$p" != "/" ]] && p="${p%/}"
    printf '%s\n' "$p"
}

# 目录扫描：du -k -d 输出 KB<TAB>路径（tab 分隔天然兼容空格路径，且覆盖隐藏目录）。
# 过滤根自身行与 <min-size 条目，纯数字排序后取前 count（awk 截断避免 head SIGPIPE）。
# du 不支持 -d 时（极老 BusyBox）回退单层 glob（含 .[!.]* 覆盖隐藏目录）。
_top_scan_dirs() {
    local path="$1" depth="$2" count="$3"
    local du_cmd=(du)
    [[ "$USE_SUDO" == "1" ]] && du_cmd=(sudo du)
    local raw rc=0
    raw=$("${du_cmd[@]}" -k -d "$depth" "$path" 2>/dev/null) || rc=1
    if [[ -z "$raw" && "$rc" -ne 0 ]]; then
        warn "当前 du 不支持深度扫描，已回退单层模式" >&2
        raw=$(_top_scan_dirs_fallback "$path")
    fi
    local min_kb="${TOP_MIN_SIZE_KB:-0}"
    printf '%s\n' "$raw" | awk -F'\t' -v root="$path" -v min="$min_kb" '$2 != root && $1+0 >= min+0' \
        | sort -rn | awk -v n="$count" 'NR<=n'
}

# 降级：逐项 du -sk。显式 .[!.]* 覆盖隐藏目录且不会扫到 ..
_top_scan_dirs_fallback() {
    local path="$1" p
    local du_cmd=(du)
    [[ "$USE_SUDO" == "1" ]] && du_cmd=(sudo du)
    for p in "$path"/* "$path"/.[!.]*; do
        if [[ -e "$p" || -L "$p" ]]; then
            "${du_cmd[@]}" -sk "$p" 2>/dev/null || true
        fi
    done
}

# 文件扫描：find -type f -size +50M → du -k，数字排序取前 count
_top_scan_files() {
    local count="$1"; shift
    local raw
    if [[ "$USE_SUDO" == "1" ]]; then
        raw=$(sudo find "$@" -type f -size +50M -exec du -k {} + 2>/dev/null || true)
    else
        raw=$(find "$@" -type f -size +50M -exec du -k {} + 2>/dev/null || true)
    fi
    printf '%s\n' "$raw" | sort -rn | awk -v n="$count" 'NR<=n'
}

# ---- top: 渲染 ----
_top_last_paths=()

_top_print_dirs() {
    local path="$1" depth="$2" count="$3"
    info "正在扫描（深度 ${depth}，大目录可能需要一些时间）..."
    _top_last_paths=()
    local lines
    lines=$(_top_scan_dirs "$path" "$depth" "$count") || true
    header "═══════════════════════════════════════"
    header "  📊 ${path} 下最大的目录（Top ${count} · 深度 ${depth}）"
    header "═══════════════════════════════════════"
    if [[ -z "$lines" ]]; then
        info "  （无匹配的子目录）"
        return 0
    fi
    local kb p
    while IFS=$'\t' read -r kb p; do
        [[ -z "$kb" ]] && continue
        _top_last_paths+=("$p")
        printf "  %3d) %8s  %s\n" "${#_top_last_paths[@]}" "$(_fmt_kb "$kb")" "$p"
    done <<< "$lines"
    return 0
}

_top_print_files() {
    local path="$1" count="$2"
    local search_paths=()
    if [[ "$path" == "/" ]]; then
        # 根目录：只扫常见位置（全盘 find 太慢）
        local cand p
        if [[ "$OS_TYPE" == "darwin" ]]; then
            cand=("/var/log" "/tmp" "$HOME/Library/Logs" "$HOME/Library/Caches")
        else
            cand=("/var/log" "/tmp" "/var/cache")
        fi
        for p in "${cand[@]}"; do
            if [[ -d "$p" ]]; then
                search_paths+=("$p")
            fi
        done
    else
        search_paths=("$path")
    fi
    header "  📄 最大的文件（Top ${count}，仅列 >50M）"
    if [[ ${#search_paths[@]} -eq 0 ]]; then
        info "  （无可扫描的文件路径）"
        return 0
    fi
    local lines kb p
    lines=$(_top_scan_files "$count" "${search_paths[@]}") || true
    if [[ -z "$lines" ]]; then
        info "  （未发现大于 50M 的文件）"
        return 0
    fi
    while IFS=$'\t' read -r kb p; do
        [[ -z "$kb" ]] && continue
        printf "   ‣ %8s  %s\n" "$(_fmt_kb "$kb")" "$p"
    done <<< "$lines"
    return 0
}

# ============================================================
# top - 大文件/目录排行（--depth 下钻 + 智能 TTY 交互，见 Task 3）
# ============================================================
top_disk() {
    local scan_path
    scan_path=$(_norm_path "${1:-/}")

    # 参数校验（count/depth 正整数；min-size 必须带单位）
    case "${TOP_COUNT:-10}" in
        ''|*[!0-9]*|0) error "--count 需为正整数: ${TOP_COUNT:-}"; usage; exit 1 ;;
    esac
    case "${TOP_DEPTH:-1}" in
        ''|*[!0-9]*|0) error "--depth 需为正整数: ${TOP_DEPTH:-}"; usage; exit 1 ;;
    esac
    TOP_MIN_SIZE_KB=""
    if [[ -n "${TOP_MIN_SIZE:-}" ]]; then
        TOP_MIN_SIZE_KB=$(_parse_size_to_kb "$TOP_MIN_SIZE") || {
            error "--min-size 需带 K/M/G 单位，如 100M"; usage; exit 1
        }
    fi

    if [[ ! -d "$scan_path" ]]; then
        error "路径不存在: $scan_path"
        exit 1
    fi

    # 仅初始路径为 / 时整体加 sudo 前缀（一次授权全程有效，交互下钻不重复弹密码）
    if [[ "$scan_path" == "/" ]]; then
        USE_SUDO=1
    else
        USE_SUDO=0
    fi

    echo
    _top_print_dirs "$scan_path" "${TOP_DEPTH:-1}" "${TOP_COUNT:-10}"
    echo
    _top_print_files "$scan_path" "${TOP_COUNT:-10}"
    echo
}
```

3c. 文件顶部子命令注释同步为 `# 子命令：status | top | monitor | clean | help`（不变，无需动；若原文有出入以现状为准只改 top 相关）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/zhangyi/my_project/unix_script-top && bash tests/ci_run.sh --phase routing --out /tmp/r.md 2>&1 | tail -2; grep "disk-usage" /tmp/r.md`
Expected: fixture 断言 ✅，汇总 `失败 0`

- [ ] **Step 5: 质量门 + 提交**

Run: `bash -n sys-tools/disk-usage/install.sh && shellcheck -e SC2164,SC1091,SC2317,SC2329 -x sys-tools/disk-usage/install.sh`

```bash
git add sys-tools/disk-usage/install.sh tests/ci_run.sh
git commit -m "feat(disk-usage): top 扫描内核重构——du -k -d 深度下钻/--min-size 过滤/空格路径与隐藏目录修复"
```

---

### Task 3: 交互模式（智能 TTY + 路径栈）

**Files:**
- Modify: `sys-tools/disk-usage/install.sh`（新增 `_top_interactive`；`top_disk()` 尾部按 TTY 分流）
- Test: `tests/ci_run.sh`（9e 节追加结构断言）

**Interfaces:**
- Consumes: Task 2 的 `_top_print_dirs`/`_top_print_files`/`_top_last_paths[]`/`USE_SUDO`
- Produces: `top_disk` 的交互入口（`[ -t 0 ] && [ -t 1 ]` 且未设 `TOP_NO_INTERACTIVE` 时进入）

- [ ] **Step 1: 写失败测试**

9e 节追加：

```bash
    assert "disk-usage: 交互层结构（TTY 守卫/路径栈/键位）" bash -c '
        grep -q "_top_interactive()" "$1/sys-tools/disk-usage/install.sh" || exit 1
        grep -q "\-t 0" "$1/sys-tools/disk-usage/install.sh" || exit 1
        grep -q "\-t 1" "$1/sys-tools/disk-usage/install.sh" || exit 1
        grep -q "TOP_NO_INTERACTIVE" "$1/sys-tools/disk-usage/install.sh" || exit 1
        grep -q "u=上一层" "$1/sys-tools/disk-usage/install.sh" || exit 1' _ "$REPO_DIR"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `grep -c "_top_interactive()" /Users/zhangyi/my_project/unix_script-top/sys-tools/disk-usage/install.sh`
Expected: `0`

- [ ] **Step 3: 实现**

3a. 在 `top_disk()` 之前插入：

```bash
# ---- top: 交互模式（智能 TTY：stdout+stdin 均为终端且未 --no-interactive 才启用） ----
# 键位：序号=下钻（depth 重置 1）  u=上一层（恢复原 depth）  c=改数量  q/回车=退出
_top_interactive() {
    local start_path="$1" start_depth="$2"
    local count="$3"
    local -a stack_paths=("$start_path") stack_depths=("$start_depth")
    local cur depth ans n new_count idx n_paths

    while true; do
        n=${#stack_paths[@]}
        cur="${stack_paths[$((n - 1))]}"
        depth="${stack_depths[$((n - 1))]}"
        echo
        _top_print_dirs "$cur" "$depth" "$count"
        if [[ "$n" -eq 1 ]]; then
            echo
            _top_print_files "$cur" "$count"
        fi
        echo
        printf "序号=下钻该目录  u=上一层  c=改数量(当前 %s, 如 10/20/30/50)  q=退出\n> " "$count"
        if ! read -r ans; then
            break    # EOF（Ctrl-D）安全退出
        fi
        case "$ans" in
            q|Q|"")
                break
                ;;
            u|U)
                if [[ "$n" -le 1 ]]; then
                    info "已在顶层"
                else
                    unset "stack_paths[$((n - 1))]"
                    unset "stack_depths[$((n - 1))]"
                fi
                ;;
            c|C)
                printf "输入数量（正整数，回车保留 %s）: " "$count"
                if ! read -r new_count; then break; fi
                if [[ -z "$new_count" ]]; then
                    :
                elif [[ "$new_count" =~ ^[0-9]+$ && "$new_count" -ge 1 ]]; then
                    count="$new_count"
                else
                    warn "非法数量，保留 $count"
                fi
                ;;
            *[!0-9]*)
                warn "无效输入: $ans"
                ;;
            *)
                n_paths=${#_top_last_paths[@]}
                if [[ "$n_paths" -eq 0 ]]; then
                    warn "当前榜单为空，无目录可下钻"
                elif [[ "$ans" -ge 1 && "$ans" -le "$n_paths" ]]; then
                    idx=$((ans - 1))
                    stack_paths+=("${_top_last_paths[$idx]}")
                    stack_depths+=(1)
                else
                    warn "序号超出范围（1-${n_paths}）"
                fi
                ;;
        esac
    done
    return 0
}
```

3b. `top_disk()` 尾部（`echo` + `_top_print_dirs`…那段）替换为分流：

```bash
    if [[ -t 0 && -t 1 && -z "${TOP_NO_INTERACTIVE:-}" ]]; then
        _top_interactive "$scan_path" "${TOP_DEPTH:-1}" "${TOP_COUNT:-10}"
    else
        echo
        _top_print_dirs "$scan_path" "${TOP_DEPTH:-1}" "${TOP_COUNT:-10}"
        echo
        _top_print_files "$scan_path" "${TOP_COUNT:-10}"
        echo
    fi
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/zhangyi/my_project/unix_script-top && bash tests/ci_run.sh --phase routing --out /tmp/r.md 2>&1 | tail -2; grep "disk-usage" /tmp/r.md`
Expected: 全部 ✅。且手动验证管道退化：`echo | bash sys-tools/disk-usage/install.sh top /tmp --no-interactive | grep -c "q=退出"` 输出 `0`（`--no-interactive` 与管道双保险）。

- [ ] **Step 5: 质量门 + 提交**

Run: `bash -n sys-tools/disk-usage/install.sh && shellcheck -e SC2164,SC1091,SC2317,SC2329 -x sys-tools/disk-usage/install.sh`

```bash
git add sys-tools/disk-usage/install.sh tests/ci_run.sh
git commit -m "feat(disk-usage): top 交互模式——TTY 检测自动降级、序号下钻/u 上层/c 改数量路径栈"
```

---

### Task 4: 文档 + 全量验证 + 双平台实测

**Files:**
- Modify: `sys-tools/disk-usage/install.sh`（`usage()`）、`sys-tools/disk-usage/README.md`、`CHANGELOG.md`

**Interfaces:**
- Consumes: Task 1-3 全部实现
- Produces: 文档与发布就绪的分支

- [ ] **Step 1: 更新 usage()**

`usage()` 中 top 段替换为：

```
  top [路径] [--count N] [--depth D] [--min-size SIZE] [--no-interactive]
                             大文件/目录排行（路径默认 /，数量默认 10）
    --depth D                目录扫描深度（默认 1）；2 可看第二层子目录
    --min-size SIZE          只显示不小于该大小的条目（需带 K/M/G 单位，如 100M）
    --no-interactive         禁用交互（管道/CI 下自动禁用）
                             交互键位：序号=下钻  u=上一层  c=改数量  q=退出
```

示例段追加：

```
  disk-usage top /var --depth 2   # 二层下钻：/var 与 /var/lib/docker 一屏可见
  disk-usage top ~ --min-size 100M  # 只看 100M 以上的大家伙
```

- [ ] **Step 2: 更新 README.md 的 top 小节**

`## 用法` 中 top 示例替换为：

```bash
# 大文件/目录排行（M/G 人类可读单位）
./disk-usage/install.sh top              # 根目录 Top 10（终端下可交互下钻）
./disk-usage/install.sh top /home        # /home 下 Top 10
./disk-usage/install.sh top --count 20   # Top 20
./disk-usage/install.sh top /var --depth 2       # 二层下钻
./disk-usage/install.sh top ~ --min-size 100M    # 只看 100M+ 的目录/文件
```

`### top` 功能详情替换为：

```
### top
- 扫描指定路径下最大的 N 个目录与文件（M/G 人类可读单位）
- `--depth D` 深度下钻：一条命令看 D 层内的大目录（含隐藏目录）
- 终端下自动进入交互模式：输序号逐层下钻、`u` 上层、`c` 改数量（10/20/30/50）、`q` 退出；管道/CI 自动退化为纯输出（`--no-interactive` 可强制）
- `--min-size 100M` 过滤小条目；大文件榜仅列 >50M，`top <路径>` 时在该路径下找，`top /` 时扫常见位置
- 扫描 `/` 时自动使用 sudo（一次授权全程有效）
```

- [ ] **Step 3: CHANGELOG [Unreleased] 新增条目**

```markdown
### 新增
- **disk-usage top 深度下钻 + 交互模式**：`--depth` 一条命令看多层大目录，终端下智能进入交互（序号下钻/`u` 上层/`c` 改数量/`q` 退出），管道与 CI 自动退化为纯输出；`--min-size` 过滤出 M/G 级大条目。顺带修复：含空格路径显示截断、隐藏目录（`~/.cache` 等）漏统计、`sort -h` 跨平台兼容问题；大文件榜改为跟随 `top <路径>` 参数
```

- [ ] **Step 4: 全量质量门**

Run: `cd /Users/zhangyi/my_project/unix_script-top && bash tests/ci_run.sh --phase static 2>&1 | tail -2 && bash tests/ci_run.sh --phase routing 2>&1 | tail -2`
Expected: 两阶段 `失败 0`

- [ ] **Step 5: macOS 本机交互实测（script pty 喝键）**

```bash
FX=$(mktemp -d); mkdir -p "$FX/l1/l2"
dd if=/dev/zero of="$FX/l1/l2/f.bin" bs=1048576 count=3 2>/dev/null
printf '1\n1\nu\nu\nq\n' | script -q /dev/null bash /Users/zhangyi/my_project/unix_script-top/sys-tools/disk-usage/install.sh top "$FX" --depth 2 | tail -20
rm -rf "$FX"
```
Expected: 依次渲染 3 层目录榜（`--depth 2` 起始 → 序号 1 下钻 → 再下钻 → u → u 回到顶层 → q），无报错、无卡死。

- [ ] **Step 6: murphy-server（Ubuntu 26.04）Linux 实测**

```bash
rsync -a --delete --exclude .git /Users/zhangyi/my_project/unix_script-top/ zhangyi@192.168.108.66:/tmp/uxs-top-test/
ssh zhangyi@192.168.108.66 'cd /tmp/uxs-top-test && bash sys-tools/disk-usage/install.sh top /var --depth 2 --count 15 --no-interactive </dev/null | tail -25'
ssh zhangyi@192.168.108.66 'cd /tmp/uxs-top-test && echo | bash sys-tools/disk-usage/install.sh top /tmp --min-size 1M | grep -c "q=退出"; true'
ssh zhangyi@192.168.108.66 'cd /tmp/uxs-top-test && printf "q\n" | script -qec "bash sys-tools/disk-usage/install.sh top /var/log" /dev/null | tail -8'
ssh zhangyi@192.168.108.66 'rm -rf /tmp/uxs-top-test'
```
Expected: Linux 下 `--depth 2` 列出 /var 二层（/var/lib 等可见、无权限目录不中断）、min-size 管道输出无交互提示、pty 下交互正常渲染退出。

- [ ] **Step 7: 提交**

```bash
git add sys-tools/disk-usage/install.sh sys-tools/disk-usage/README.md CHANGELOG.md
git commit -m "docs(disk-usage): top 深度下钻/交互模式 用法文档与 CHANGELOG"
```

（不推送——等用户「提交发布」授权。）
