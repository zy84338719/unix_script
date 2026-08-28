# disk 健康诊断升级（smart 判定 + scan 坏块扫描）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `sys-tools/disk` 的 `smart` 从"原样输出 smartctl"升级为"逐项判读 + 分级结论"，并新增 `scan` 子命令用 badblocks 做只读坏块扫描。

**Architecture:** 全部改动集中在 `sys-tools/disk/install.sh`（判定逻辑抽为纯函数 `_smart_verdict` 及其解析 helper，供单测直接 source；运行时 glue 薄封装）。配套改 `lib/submenus.sh` 菜单、`tests/ci_run.sh` 断言、模块 README、CHANGELOG。spec 见 `docs/superpowers/specs/2026-08-28-disk-health-scan-design.md`。

**Tech Stack:** Bash（`set -euo pipefail`）、smartctl（smartmontools）、badblocks（e2fsprogs）、shellcheck、bash 单测（t_eq 断言风格，同 `tests/unit_suggest.sh`）。

## Global Constraints

- 只读原则：scan 严禁出现 badblocks `-w` / `-n` 写模式（CI 有负向断言）。
- 平台：模块仅 Linux；macOS 走 `_linux_require` 报"仅支持 Linux"。
- 避免仓库已知坑：pipefail 下 `cmd | head/-q` 会 SIGPIPE 中止——管道前先捕获到变量再 grep；`lsblk|head` 类加 `|| true`。
- shellcheck：CI 以 `shellcheck -e SC2164,SC1091,SC2317,SC2329 -x` 为门禁，新代码必须干净。
- 机器模式走 `emit_status`/`emit_extra`（`UXS_STATUS_MODE=machine`）；人类模式保持 emoji/颜色。
- 每个 Task 结束时 static + routing 必须恢复全绿再 commit。
- 工作目录：本计划的 worktree 为 `.worktrees/disk-health-scan`（分支 `feat/disk-health-scan`，基于 release/v1.10.0）。下文相对路径均以 worktree 根为基准。

---

### Task 1: 修存量 shellcheck（SC2128/SC2178）

**Files:**
- Modify: `sys-tools/disk/install.sh:403-410`

**Interfaces:**
- Consumes: 无
- Produces: `cmd_status` 中局部变量改名 `missing` → `miss_tools`；`emit_extra "missing=..."` 的对外 key 不变。消除与 `lib/common.sh:212`（`check_commands` 的数组 `local missing=()`）的同名变量混淆。

- [ ] **Step 1: 确认现状复现**

Run: `shellcheck -x -e SC2164,SC1091,SC2317,SC2329 sys-tools/disk/install.sh`
Expected: 报 SC2178/SC2128，指向 403/405/407/408 行的 `missing`。

- [ ] **Step 2: 改名（精确 diff）**

```bash
# 旧（cmd_status 内，共 6 处 missing → miss_tools）：
    local missing="" t opt_missing="" disks=0
    for t in lsblk parted; do
        command -v "$t" >/dev/null 2>&1 || missing="$missing$t "
    done
    command -v mkfs.ext4 >/dev/null 2>&1 || missing="$missing mkfs.ext4"
    if [[ -n "$missing" ]]; then
        emit_status "not_installed" "⚠️  磁盘工具箱依赖缺失:${missing}（运行 ./install.sh disk install 补齐）"
        emit_extra "missing=${missing// /,}"

# 新：
    local miss_tools="" t opt_missing="" disks=0
    for t in lsblk parted; do
        command -v "$t" >/dev/null 2>&1 || miss_tools="$miss_tools$t "
    done
    command -v mkfs.ext4 >/dev/null 2>&1 || miss_tools="$miss_tools mkfs.ext4"
    if [[ -n "$miss_tools" ]]; then
        emit_status "not_installed" "⚠️  磁盘工具箱依赖缺失:${miss_tools}（运行 ./install.sh disk install 补齐）"
        emit_extra "missing=${miss_tools// /,}"
```

- [ ] **Step 3: 验证**

Run: `shellcheck -x -e SC2164,SC1091,SC2317,SC2329 sys-tools/disk/install.sh && bash tests/ci_run.sh --phase static; echo "exit=$?"`
Expected: shellcheck 零输出；static 报告"失败 0"（基线 193 过 + 1 修复 = 194 过）。

- [ ] **Step 4: Commit**

```bash
git add sys-tools/disk/install.sh
git commit -m "fix(disk): cmd_status 局部变量 missing 与 common.sh 数组同名触发 shellcheck SC2178/SC2128，改名 miss_tools"
```

---

### Task 2: source-guard + SMART 判定纯函数（TDD）

**Files:**
- Modify: `sys-tools/disk/install.sh`（末尾 main 调用加 source-guard；`cmd_smart` 之前插入纯函数段）
- Create: `tests/unit_disk_smart.sh`

**Interfaces:**
- Produces（后续 Task 3/4 依赖，签名精确如下）:
  - `_smart_ata_raw <A输出> <属性ID>` → stdout: RAW 值数字前缀（无则空）
  - `_smart_nvme_val <A输出> <标签>` → stdout: 标签后的值字符串（无则空）
  - `_smart_pct <值串>` → stdout: 数字前缀（"95%"→95；"0x00"→0）
  - `_smart_health_word <H输出>` → stdout: `PASSED`|`FAILED`|空
  - `_smart_num_gt <a> <b>` → rc0 当 a>b（空/非数字按 0）
  - `_smart_verdict <H输出> <A输出> <nvme|ata>` → stdout: `<verdict>|<原因1;原因2>`，verdict ∈ `healthy|warning|critical|unknown`；原因用 `;` 连接，healthy 时为空
  - `_smart_verdict_emoji <verdict>` / `_smart_verdict_cn <verdict>` → stdout: ✅🟡🔴 / 健康·注意·危险·未知
  - install.sh 可被 source（只定义函数不执行 main）
  - `tests/unit_disk_smart.sh` 退出码 0=全过

- [ ] **Step 1: 先写失败的单测 `tests/unit_disk_smart.sh`**

```bash
#!/usr/bin/env bash
#
# tests/unit_disk_smart.sh — sys-tools/disk SMART 判定纯函数单测
# 独立运行：bash tests/unit_disk_smart.sh（退出码 0=全过）
# 也被 tests/ci_run.sh routing 阶段调用。
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

# source 模块脚本取纯函数（source 后关闭 -e/-o pipefail，保留 -u，避免被测函数的预期非零返回中止测试）
# shellcheck source=../sys-tools/disk/install.sh
source "$REPO_DIR/sys-tools/disk/install.sh"
set +e +o pipefail

# ---------- fixtures ----------
ATA_H_PASSED='SMART overall-health self-assessment test result: PASSED'
ATA_H_FAILED='SMART overall-health self-assessment test result: FAILED!'
ATA_A_HEADER='ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE'
ATA_A_HEALTHY=$(printf '%s\n  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always   -           0\n187 Reported_Uncorrect      0x0032   100   100   000    Old_age   Always   -           0\n196 Reallocated_Event_Count 0x0032   100   100   000    Old_age   Always   -           0\n197 Current_Pending_Sector  0x0022   100   100   000    Old_age   Always   -           0\n198 Offline_Uncorrectable   0x0008   100   100   000    Old_age   Offline  -           0\n' "$ATA_A_HEADER")
ATA_A_PENDING=$(printf '%s\n197 Current_Pending_Sector  0x0022   088   088   000    Old_age   Always   -           8\n' "$ATA_A_HEADER")
ATA_A_REALLOC=$(printf '%s\n  5 Reallocated_Sector_Ct   0x0033   092   092   010    Pre-fail  Always   -           24\n' "$ATA_A_HEADER")
NVME_A_HEALTHY='Critical Warning:                   0x00
Available Spare:                    100%
Available Spare Threshold:          10%
Percentage Used:                    2%
Media and Data Integrity Errors:    0'
NVME_A_MEDIA='Critical Warning:                   0x00
Percentage Used:                    88%
Media and Data Integrity Errors:    24'
NVME_A_WORN='Critical Warning:                   0x00
Percentage Used:                    95%
Media and Data Integrity Errors:    0'
NVME_A_SPARE='Critical Warning:                   0x00
Available Spare:                    5%
Available Spare Threshold:          10%
Percentage Used:                    40%
Media and Data Integrity Errors:    0'

# ---------- 解析 helper ----------
t_eq "ata_raw: 5 号属性取 RAW" "24" "$(_smart_ata_raw "$ATA_A_REALLOC" 5)"
t_eq "ata_raw: 缺失属性为空" "" "$(_smart_ata_raw "$ATA_A_HEALTHY" 12)"
t_eq "ata_raw: 健康 0" "0" "$(_smart_ata_raw "$ATA_A_HEALTHY" 197)"
t_eq "nvme_val: Percentage Used" "95%" "$(_smart_nvme_val "$NVME_A_WORN" "Percentage Used:")"
t_eq "nvme_val: 不误配 Threshold 前缀" "10%" "$(_smart_nvme_val "$NVME_A_SPARE" "Available Spare Threshold:")"
t_eq "health_word: FAILED!→FAILED" "FAILED" "$(_smart_health_word "$ATA_H_FAILED")"
t_eq "pct: 去百分号" "95" "$(_smart_pct "95%")"
t_eq "num_gt: 空=0 不大于 0" rc1 "$(_smart_num_gt "" 0 && echo rc0 || echo rc1)"

# ---------- verdict：ATA ----------
t_eq "ATA 全 0 → healthy" "healthy|" "$(_smart_verdict "$ATA_H_PASSED" "$ATA_A_HEALTHY" ata)"
t_eq "ATA pending>0 → critical" "critical|待定扇区(Current_Pending)=8" "$(_smart_verdict "$ATA_H_PASSED" "$ATA_A_PENDING" ata)"
t_eq "ATA 重映射>0 → warning" "warning|重映射扇区(Reallocated_Sector)=24" "$(_smart_verdict "$ATA_H_PASSED" "$ATA_A_REALLOC" ata)"
t_eq "ATA 总评 FAILED → critical" "critical|SMART 总评 FAILED" "$(_smart_verdict "$ATA_H_FAILED" "$ATA_A_HEALTHY" ata)"
t_eq "ATA 读不到 → unknown" "unknown|读不到 SMART 数据（USB 桥/RAID 背板不支持或权限不足）" "$(_smart_verdict "" "" ata)"

# ---------- verdict：NVMe ----------
t_eq "NVMe 干净 → healthy" "healthy|" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_HEALTHY" nvme)"
t_eq "NVMe media>0 → critical" "critical|介质错误(Media Errors)=24" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_MEDIA" nvme)"
t_eq "NVMe 寿命≥90 → warning" "warning|寿命已耗 95%" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_WORN" nvme)"
t_eq "NVMe 备用空间低于阈值 → critical" "critical|备用空间 5% 低于阈值 10%" "$(_smart_verdict "$ATA_H_PASSED" "$NVME_A_SPARE" nvme)"

# ---------- 结论 ----------
echo "unit_disk_smart: 通过 $PASS / 失败 $FAIL"
(( FAIL == 0 ))
```

- [ ] **Step 2: 运行确认失败**

Run: `bash tests/unit_disk_smart.sh; echo "exit=$?"`
Expected: 大量 `FAIL: ... 函数未找到`/command not found，退出码非 0。

- [ ] **Step 3: install.sh 加 source-guard + 实现纯函数**

(a) 文件末尾：

```bash
# 旧：
main "$@"

# 新：
# 允许单测 source 本文件只取纯函数；直接执行时照常入口
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
```

(b) 在 `# 子命令实现` 分隔注释之前插入：

```bash
# ============================================================
# SMART 健康判定（纯函数：只解析传入文本，不碰设备，可单测）
# ============================================================

# ATA 属性表：取指定 ID 的 RAW 值数字前缀；属性不存在输出空
_smart_ata_raw() {
    local raw
    raw=$(awk -v id="$2" '$1 == id { print $10; exit }' <<<"$1")
    raw=${raw%%[^0-9]*}
    echo "$raw"
}

# NVMe 属性：按标签取冒号后的值（trim 首尾空白）
_smart_nvme_val() {
    awk -v lbl="$2" 'index($0, lbl) { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' <<<"$1"
}

# 取数字前缀："95%"→95，"0x00"→0，空→空
_smart_pct() {
    local v=${1:-}
    v=${v%%[^0-9]*}
    echo "$v"
}

# -H 输出的总评词：PASSED / FAILED / 空（读不到）
_smart_health_word() {
    local w
    w=$(awk '/overall-health self-assessment test result:/ { print $NF; exit }' <<<"$1")
    w=${w//[^A-Za-z]/}
    echo "$w"
}

# 非负整数比较：$1 > $2 时返回 0（空/非数字按 0；10# 强制十进制防八进制）
_smart_num_gt() {
    local a=${1:-0} b=${2:-0}
    [[ "$a" =~ ^[0-9]+$ ]] || a=0
    [[ "$b" =~ ^[0-9]+$ ]] || b=0
    (( 10#$a > 10#$b ))
}

# 判定核心：入参 =(-H 输出, -A 输出, 总线 nvme|ata)
# 输出 "<verdict>|<原因;...>"；verdict ∈ healthy|warning|critical|unknown
_smart_verdict() {
    local h_out="$1" a_out="$2" bus="$3"
    local verdict="healthy" reasons="" health id raw
    health=$(_smart_health_word "$h_out")
    if [[ "$health" == "FAILED" ]]; then
        verdict="critical"
        reasons="SMART 总评 FAILED"
    elif [[ -z "$health" ]]; then
        echo "unknown|读不到 SMART 数据（USB 桥/RAID 背板不支持或权限不足）"
        return 0
    fi
    case "$bus" in
        nvme)
            local cw media spare spare_th pct
            cw=$(_smart_nvme_val "$a_out" "Critical Warning:")
            media=$(_smart_nvme_val "$a_out" "Media and Data Integrity Errors:")
            spare=$(_smart_pct "$(_smart_nvme_val "$a_out" "Available Spare:")")
            spare_th=$(_smart_pct "$(_smart_nvme_val "$a_out" "Available Spare Threshold:")")
            pct=$(_smart_pct "$(_smart_nvme_val "$a_out" "Percentage Used:")")
            if [[ -n "$cw" && "$cw" != "0x00" && "$cw" != "0" ]]; then
                verdict="critical"
                reasons="${reasons:+${reasons};}NVMe critical_warning=${cw}"
            fi
            if _smart_num_gt "$media" 0; then
                verdict="critical"
                reasons="${reasons:+${reasons};}介质错误(Media Errors)=${media}"
            fi
            if [[ "$spare" =~ ^[0-9]+$ && "$spare_th" =~ ^[0-9]+$ ]] && (( 10#$spare < 10#$spare_th )); then
                verdict="critical"
                reasons="${reasons:+${reasons};}备用空间 ${spare}% 低于阈值 ${spare_th}%"
            fi
            if _smart_num_gt "$pct" 89; then
                [[ "$verdict" == "healthy" ]] && verdict="warning"
                reasons="${reasons:+${reasons};}寿命已耗 ${pct}%"
            fi
            ;;
        *)
            for id in 197 198 187; do   # 待定/不可修复/不可纠正 → 危险
                raw=$(_smart_ata_raw "$a_out" "$id")
                if _smart_num_gt "$raw" 0; then
                    verdict="critical"
                    case "$id" in
                        197) reasons="${reasons:+${reasons};}待定扇区(Current_Pending)=${raw}" ;;
                        198) reasons="${reasons:+${reasons};}不可修复扇区(Offline_Uncorrectable)=${raw}" ;;
                        187) reasons="${reasons:+${reasons};}不可纠正(Reported_Uncorrect)=${raw}" ;;
                    esac
                fi
            done
            for id in 5 196; do         # 重映射扇区/事件 → 注意（盘在自愈）
                raw=$(_smart_ata_raw "$a_out" "$id")
                if _smart_num_gt "$raw" 0; then
                    [[ "$verdict" == "healthy" ]] && verdict="warning"
                    case "$id" in
                        5)   reasons="${reasons:+${reasons};}重映射扇区(Reallocated_Sector)=${raw}" ;;
                        196) reasons="${reasons:+${reasons};}重映射事件(Reallocation_Event)=${raw}" ;;
                    esac
                fi
            done
            ;;
    esac
    echo "${verdict}|${reasons}"
}

_smart_verdict_emoji() {
    case "$1" in
        healthy)  echo "✅" ;;
        warning)  echo "🟡" ;;
        critical) echo "🔴" ;;
        *)        echo "🟡" ;;
    esac
}

_smart_verdict_cn() {
    case "$1" in
        healthy)  echo "健康" ;;
        warning)  echo "注意" ;;
        critical) echo "危险" ;;
        *)        echo "未知" ;;
    esac
}
```

- [ ] **Step 4: 单测转绿**

Run: `bash tests/unit_disk_smart.sh; echo "exit=$?"`
Expected: `unit_disk_smart: 通过 17 / 失败 0`，退出码 0。

- [ ] **Step 5: 静态检查**

Run: `bash -n sys-tools/disk/install.sh && bash -n tests/unit_disk_smart.sh && shellcheck -x -e SC2164,SC1091,SC2317,SC2329 sys-tools/disk/install.sh tests/unit_disk_smart.sh; echo "exit=$?"`
Expected: exit=0。

- [ ] **Step 6: Commit**

```bash
git add sys-tools/disk/install.sh tests/unit_disk_smart.sh
git commit -m "feat(disk): SMART 判定纯函数（_smart_verdict：ATA/NVMe 关键指标分级）+ 单测；入口支持 source"
```

---

### Task 3: cmd_smart 重写 + usage/dispatch + CI 断言

**Files:**
- Modify: `sys-tools/disk/install.sh`（`cmd_smart` 整体替换；`usage()` 两处；`main` dispatch 不变已有 smart 分支）
- Modify: `tests/ci_run.sh:332`（枚举断言更新）+ 其后新增 2 条断言

**Interfaces:**
- Consumes: Task 2 全部纯函数。
- Produces: `cmd_smart`（无参=全整盘概览；单盘=详情）；`_smart_bus <dev>`、`_smart_report_one <dev>`、`_smart_report_detail <dev>`（Task 4 不依赖，但 README 引用行为）。

- [ ] **Step 1: 替换 cmd_smart 并新增运行时 glue**

```bash
# 总线类型：NVMe 走 NVMe 判读，其余按 ATA（SAS 仅总评可判）
_smart_bus() {
    local info
    info=$(sudo smartctl -i "$1" 2>/dev/null || true)
    if grep -qi 'NVMe Version' <<<"$info"; then
        echo nvme
    else
        echo ata
    fi
}

# 单盘一行结论（概览用；机器模式输出 STATE/EXTRA）
_smart_report_one() {
    local dev="$1" h a vout verdict reasons model size emoji cn
    h=$(sudo smartctl -H "$dev" 2>/dev/null || true)
    a=$(sudo smartctl -A "$dev" 2>/dev/null || true)
    vout=$(_smart_verdict "$h" "$a" "$(_smart_bus "$dev")")
    verdict=${vout%%|*}
    reasons=${vout#*|}
    model=$(lsblk -dno MODEL "$dev" 2>/dev/null | head -1 || true)
    size=$(lsblk -dno SIZE "$dev" 2>/dev/null | head -1 || true)
    if uxs_is_machine_mode; then
        emit_status "$verdict" "${dev} $(_smart_verdict_cn "$verdict")"
        emit_extra "dev=${dev##*/} model=${model} reasons=${reasons}"
    else
        emoji=$(_smart_verdict_emoji "$verdict")
        cn=$(_smart_verdict_cn "$verdict")
        emit_status "$verdict" "${emoji} ${dev##*/}  ${model:-?}  ${size:-?}  ${cn}${reasons:+（${reasons}）}"
    fi
}

# 单盘详情：设备信息 + 总评 + 关键指标 + 属性表 + 结论
_smart_report_detail() {
    local dev="$1" h a vout verdict reasons temp hours
    h=$(sudo smartctl -H "$dev" 2>/dev/null || true)
    a=$(sudo smartctl -A "$dev" 2>/dev/null || true)
    vout=$(_smart_verdict "$h" "$a" "$(_smart_bus "$dev")")
    verdict=${vout%%|*}
    reasons=${vout#*|}
    if uxs_is_machine_mode; then
        emit_status "$verdict" "${dev}"
        emit_extra "dev=${dev##*/} reasons=${reasons}"
        return 0
    fi
    header "═══ SMART 健康体检：${dev} ═══"
    echo "—— 设备信息 ——"
    sudo smartctl -i "$dev" 2>/dev/null | sed -n '1,20p' || true
    echo
    echo "—— SMART 总评 ——"
    sudo smartctl -H "$dev" 2>/dev/null || true   # 健康异常时 smartctl 退出非零是正常语义，以输出为准
    echo
    echo "—— 关键指标 ——"
    temp=$(_smart_ata_raw "$a" 194)
    [[ -n "$temp" ]] || temp=$(_smart_pct "$(_smart_nvme_val "$a" "Temperature:")")
    hours=$(_smart_ata_raw "$a" 9)
    [[ -n "$hours" ]] || hours=$(_smart_nvme_val "$a" "Power On Hours:")
    [[ -n "$temp" ]] && echo "温度: ${temp}°C"
    [[ -n "$hours" ]] && echo "通电时长: ${hours} 小时"
    echo
    echo "—— 属性表 ——"
    sudo smartctl -A "$dev" 2>/dev/null || true
    echo
    case "$verdict" in
        healthy)  success "$(_smart_verdict_emoji healthy) 结论：健康——未发现异常指标" ;;
        warning)  warn "$(_smart_verdict_emoji warning) 结论：注意——${reasons}（盘正在自愈，关注趋势，保持备份）" ;;
        critical) error "$(_smart_verdict_emoji critical) 结论：危险——${reasons}（建议立即备份数据，评估换盘）" ;;
        *)        warn "$(_smart_verdict_emoji unknown) 结论：未知——${reasons}" ;;
    esac
    [[ "$verdict" == "critical" ]] && return 1
    return 0
}

cmd_smart() {
    _linux_require || return 1
    if ! command -v smartctl >/dev/null 2>&1; then
        info "未安装 smartmontools，正在补装..."
        pkg_install smartmontools
    fi
    require_sudo
    if [[ $# -eq 0 ]]; then
        header "SMART 健康概览（全部整盘）："
        local d any=false
        while IFS= read -r d; do
            any=true
            _smart_report_one "/dev/$d"
        done < <(lsblk -drno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')
        $any || warn "未发现整盘设备"
        return 0
    fi
    local dev_s="$1" dev
    dev=$(_disk_resolve "$dev_s") || return 1
    dev=$(_disk_base_disk "$dev")
    _smart_report_detail "$dev"
}
```

- [ ] **Step 2: 更新 usage()**

```bash
# 旧：
#   smart <整盘>                  SMART 健康检查（缺 smartmontools 自动补装）
# 新（另在枚举行加 scan 由 Task 4 一并处理，此处只改 smart 说明行）：
  smart [整盘]                  SMART 健康体检（无参=全部整盘概览；单盘=详情+判读）
```

并在 usage 末尾"安全护栏"清单追加一行：

```
  · smart/scan 为只读体检：不写盘，scan 对使用中设备仅警告不拒绝
```

- [ ] **Step 3: tests/ci_run.sh 新增 smart 断言（不动枚举行，枚举行由 Task 4 一并更新为含 scan 的最终形态）**

在 9d disk 断言段（原 332 行枚举断言之后）追加：

```bash
    assert "disk: smart 判定纯函数存在（可单测）" bash -c "grep -q '_smart_verdict()' \"$REPO_DIR/$disk_path/install.sh\""
    assert "disk: smart 判定单测全过" bash "$REPO_DIR/tests/unit_disk_smart.sh"
```

说明：本 Task 收尾时 usage 枚举暂未含 scan、dispatch 暂无 scan 分支，故枚举断言保持旧值即可全绿。

- [ ] **Step 4: 验证**

Run: `bash tests/unit_disk_smart.sh && bash tests/ci_run.sh --phase routing; echo "exit=$?"`
Expected: 单测 17/17；routing 失败 0（基线 393 过 → 约 395 过）。

- [ ] **Step 5: Commit**

```bash
git add sys-tools/disk/install.sh tests/ci_run.sh
git commit -m "feat(disk): smart 升级为健康体检——无参全盘概览/单盘判读详情/机器模式 STATE+EXTRA"
```

---

### Task 4: cmd_scan + 菜单入口 + 枚举/scan 断言

**Files:**
- Modify: `sys-tools/disk/install.sh`（新增 `cmd_scan`；usage 枚举行与 scan 说明行；dispatch 加 scan）
- Modify: `lib/submenus.sh`（`_disk_menu_display` 加第 10 项；`_disk_menu_action` 加 case 10）
- Modify: `tests/ci_run.sh`（枚举断言更新为含 scan + scan 只读断言）

**Interfaces:**
- Consumes: `_disk_resolve`/`_disk_base_disk`/`_disk_in_use`/`_disk_is_protected`/`_disk_show_detail`/`_linux_require`/`require_sudo`/`pkg_install`。
- Produces: `cmd_scan <整盘|分区>`：0 坏块 exit 0；发现坏块 exit 1；badblocks 异常退出 exit 1。

- [ ] **Step 1: 实现 cmd_scan（插在 cmd_smart 之后）**

```bash
cmd_scan() {
    local dev_s="${1:-}" dev base size est_min bb_out badn rc
    [[ -n "$dev_s" ]] || { error "用法: scan <整盘|分区>（如 sdb 或 sdb1）"; return 1; }
    _linux_require || return 1
    dev=$(_disk_resolve "$dev_s") || return 1
    if ! command -v badblocks >/dev/null 2>&1; then
        info "未安装 badblocks（e2fsprogs），正在补装..."
        pkg_install e2fsprogs
    fi
    require_sudo
    base=$(_disk_base_disk "$dev")
    _disk_show_detail "$dev"
    # 只读扫描不走破坏性护栏：使用中/系统盘仅警告 IO 竞争，不拒绝（不写盘，数据零风险）
    if _disk_in_use "$dev" || _disk_is_protected "$base"; then
        warn "扫描为只读（不写盘），但 ${dev} 正在使用中/属系统盘：扫描会显著变慢且拖累系统 IO"
    fi
    size=$(lsblk -bno SIZE "$dev" 2>/dev/null | head -1 || true)
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        est_min=$(( size / 1048576 / 150 / 60 ))
        (( est_min < 1 )) && est_min=1
        info "预计耗时约 $(( est_min / 60 )) 小时 $(( est_min % 60 )) 分钟（按 ~150MB/s 估算，SSD 通常更快）"
    fi
    header "开始只读盘面扫描（badblocks，不写盘）。长时间扫描建议放 tmux/screen；Ctrl-C 可中断，已扫部分无结论可直接重跑。"
    bb_out=$(mktemp "${TMPDIR:-/tmp}/uxs-badblocks.XXXXXX")
    rc=0
    sudo badblocks -sv -b 4096 -o "$bb_out" "$dev" || rc=$?
    badn=$(wc -l < "$bb_out" 2>/dev/null || true)
    badn=$(printf '%s' "${badn:-0}" | tr -d '[:space:]')
    if (( badn > 0 )); then
        error "🔴 发现 ${badn} 个坏块！建议：① 立即备份重要数据 ② ./install.sh disk smart ${base##*/} 查看重映射趋势 ③ 评估更换硬盘"
        echo "坏块 LBA 清单（前 20 行；完整清单: ${bb_out}）:"
        head -20 "$bb_out" || true
        return 1
    elif (( rc != 0 )); then
        error "扫描异常退出（rc=${rc}；退出码 bit2=被中断）。已扫描部分无结论，可直接重跑"
        return 1
    fi
    rm -f "$bb_out"
    success "✅ 盘面完好：${dev} 全盘只读扫描未发现坏块"
}
```

- [ ] **Step 2: usage 枚举行 + scan 说明行 + dispatch**

```bash
# 枚举行（新）：
用法: install.sh {list|wizard|partition|format|mount|umount|fstab|smart|scan|wipe|install|uninstall|status|help}
# 说明行（smart 行之后插入）：
  scan <整盘|分区>              盘面坏块只读扫描（badblocks 不写盘，耗时可能数小时）
# dispatch（smart 分支后加）：
        scan)      cmd_scan "$@" ;;
```

- [ ] **Step 3: 菜单（lib/submenus.sh）**

`_disk_menu_display` 末尾追加一行；`_disk_menu_action` 在 `9)` 分支后加 `10)`：

```bash
# display 追加：
    echo " 10) 坏块只读扫描（badblocks，不写盘）"
# action 追加：
        10)
            read -r -p "整盘或分区 (如 sdb / sdb1): " dk
            run_in_dir sys-tools/disk install.sh scan "$dk"
            ;;
```

并把 `8)` 的提示语改为支持回车看概览：

```bash
# 旧：
        8)
            read -r -p "整盘 (如 sda): " dk
            run_in_dir sys-tools/disk install.sh smart "$dk"
            ;;
# 新：
        8)
            read -r -p "整盘 (如 sda，回车=全部整盘概览): " dk
            run_in_dir sys-tools/disk install.sh smart ${dk:+"$dk"}
            ;;
```

`_disk_menu_display` 第 8 行同步改为 `echo "  8) SMART 健康体检（回车=全部整盘概览）"`。

- [ ] **Step 4: tests/ci_run.sh 更新枚举断言 + scan 只读断言**

```bash
# 枚举行替换为：
    assert "disk: usage 子命令枚举完整（供 --list-modules/补全解析）" bash -c "grep -qF '{list|wizard|partition|format|mount|umount|fstab|smart|scan|wipe|install|uninstall|status|help}' \"$REPO_DIR/$disk_path/install.sh\""
# 追加：
    assert "disk: scan 子命令存在且只读（禁 badblocks 写模式 -w/-n）" bash -c "grep -q 'cmd_scan()' \"$REPO_DIR/$disk_path/install.sh\" && ! grep -Eq 'badblocks .*( -w| -n)' \"$REPO_DIR/$disk_path/install.sh\""
```

- [ ] **Step 5: 验证**

Run: `bash -n sys-tools/disk/install.sh && bash -n lib/submenus.sh && shellcheck -x -e SC2164,SC1091,SC2317,SC2329 sys-tools/disk/install.sh lib/submenus.sh && bash tests/unit_disk_smart.sh && bash tests/ci_run.sh --phase routing; echo "exit=$?"`
Expected: 全绿（routing 基线 393 → 约 397 过 0 败）。

- [ ] **Step 6: Commit**

```bash
git add sys-tools/disk/install.sh lib/submenus.sh tests/ci_run.sh
git commit -m "feat(disk): 新增 scan 盘面坏块只读扫描（badblocks -sv，耗时预估+坏块清单+建议）；菜单与枚举同步"
```

---

### Task 5: README + CHANGELOG

**Files:**
- Modify: `sys-tools/disk/README.md`
- Modify: `CHANGELOG.md`（`[Unreleased]` 节）

**Interfaces:** 纯文档，无代码接口。

- [ ] **Step 1: README**

在功能/用法清单中与 SMART 相关小节改写并新增 scan 说明（保持该 README 现有小节风格，插入以下条目）：

```markdown
- `smart [整盘]`：SMART 健康体检。无参数=遍历全部整盘输出一行式概览（✅健康/🟡注意/🔴危险/未知 + 原因）；
  指定整盘=详情（设备信息、总评、温度/通电时长、属性表 + 判读结论）。
  判读规则：ATA 看 5/196 重映射（→注意）、187/197/198 不可纠正与待定扇区（→危险）；
  NVMe 看 critical_warning、介质错误、备用空间低于阈值（→危险）、寿命耗用 ≥90%（→注意）。
  `UXS_STATUS_MODE=machine` 下输出 `STATE=<verdict>` + `EXTRA=dev=... model=... reasons=...`。
- `scan <整盘|分区>`：盘面坏块只读扫描（badblocks -sv，不写盘，数据零风险）。
  扫描前展示设备详情与按容量的耗时预估（~150MB/s 折算）；使用中/系统盘仅警告 IO 竞争不拒绝。
  发现坏块时列出 LBA 清单并给出备份/查 SMART/换盘建议，退出码非 0；0 坏块退出 0。
  TB 级机械盘可能耗时数小时，建议放 tmux/screen。`smart` 判读支持 ATA/NVMe；SAS 仅总评可判。
```

- [ ] **Step 2: CHANGELOG [Unreleased]**

```markdown
## [Unreleased]

### 新增
- **磁盘健康诊断升级（sys-tools/disk）**：`disk smart` 从原样输出 smartctl 升级为逐项判读——无参数全盘概览与单盘详情均给出分级结论（✅健康/🟡注意/🔴危险/未知），ATA 判读重映射/待定/不可纠正扇区、NVMe 判读介质错误/备用空间/寿命耗用，机器模式输出 `STATE`/`EXTRA`；新增 `disk scan` 盘面坏块只读扫描（badblocks 不写盘，实时进度、耗时预估、坏块 LBA 清单与备份/换盘建议）

### 修复
- disk `cmd_status` 局部变量与 lib/common.sh 数组同名触发 shellcheck SC2178/SC2128（改名 miss_tools）
```

- [ ] **Step 3: Commit**

```bash
git add sys-tools/disk/README.md CHANGELOG.md
git commit -m "docs(disk): smart 体检与 scan 坏块扫描用法说明；CHANGELOG [Unreleased]"
```

---

### Task 6: 本地全量回归

**Files:** 无新改动（验证任务）

- [ ] **Step 1:** `bash tests/ci_run.sh --phase static` → 失败 0
- [ ] **Step 2:** `bash tests/ci_run.sh --phase routing` → 失败 0（unit_disk_smart 由 routing 内断言执行）
- [ ] **Step 3:** `bash tests/unit_suggest.sh`（确认未碰坏既有单测）→ 通过
- [ ] **Step 4:** `bash sys-tools/disk/install.sh smart`（macOS 上）→ 输出"仅支持 Linux"且退出 1（平台契约）
- [ ] **Step 5:** `git log --oneline origin/release/v1.10.0..HEAD` 复核提交序列干净

---

### Task 7: 远程真机验证（murphy-server 192.168.108.66）

**Files:** 无（验证任务；目标机免密 SSH：`zhangyi@192.168.108.66`，Ubuntu，有 sda/sdb 与免密 sudo）

- [ ] **Step 1: 同步 worktree 到远程**

```bash
rsync -a --delete --exclude .git \
  .worktrees/disk-health-scan/ zhangyi@192.168.108.66:/tmp/uxs-disk-health/
```

- [ ] **Step 2: 远程跑单测与静态（Linux 侧复核）**

```bash
ssh zhangyi@192.168.108.66 'bash /tmp/uxs-disk-health/tests/unit_disk_smart.sh && bash /tmp/uxs-disk-health/tests/ci_run.sh --phase static'
```
Expected: 单测 17/17；static 失败 0。

- [ ] **Step 3: smart 真盘验证**

```bash
ssh zhangyi@192.168.108.66 'bash /tmp/uxs-disk-health/sys-tools/disk/install.sh smart; echo "rc=$?"'
ssh zhangyi@192.168.108.66 'bash /tmp/uxs-disk-health/sys-tools/disk/install.sh smart sda >/dev/null; echo "rc=$?"'
```
Expected: 概览每盘一行结论（sda/sdb 均健康或给出真实原因）；单盘详情正常、rc 0（健康盘）。核对机器模式：
```bash
ssh zhangyi@192.168.108.66 'UXS_STATUS_MODE=machine bash /tmp/uxs-disk-health/sys-tools/disk/install.sh smart'
```
Expected: 每盘 `STATE=` + `EXTRA=dev=... model=... reasons=...` 两行、无颜色无 emoji。

- [ ] **Step 4: scan loopback 全链路（不碰真盘数据）**

```bash
ssh zhangyi@192.168.108.66 'truncate -s 512M /tmp/uxs-scan-test.img && sudo losetup -f --show /tmp/uxs-scan-test.img'
# 记下输出的 loop 设备（如 /dev/loop0），然后：
ssh zhangyi@192.168.108.66 'bash /tmp/uxs-disk-health/sys-tools/disk/install.sh scan loop0; echo "rc=$?"'
```
Expected: 显示详情 + 耗时预估（512MB → ~1 分钟内）+ badblocks 进度 + "✅ 盘面完好"，rc=0。

- [ ] **Step 5: 清理远程临时资源**

```bash
ssh zhangyi@192.168.108.66 'sudo losetup -d /dev/loop0 2>/dev/null; rm -f /tmp/uxs-scan-test.img; rm -rf /tmp/uxs-disk-health'
```

- [ ] **Step 6: 结果记录**

真机若暴露 bug：修复 + 补单测 + 追加提交（历史先例：disk 模块真机抓出 3 个真 bug）。验证通过后汇报，等待用户「提交发布」授权再推送/PR。
