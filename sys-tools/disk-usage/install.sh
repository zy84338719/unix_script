#!/usr/bin/env bash
#
# disk-usage/install.sh
#
# 磁盘空间管理工具：查看存储概况、大文件排行、监控告警、一键清理。
# 支持 Linux / macOS。
#
# 子命令：status | top | monitor | clean | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# ---- 全局参数 ----
CRON_ID="unix_script_disk_usage_monitor"
CRON_LOG="/var/log/disk-usage-monitor.log"

# ============================================================
# status - 查看存储概况
# ============================================================
status_disk() {
    detect_os
    # disk-usage 是纯命令封装的仪表盘，无安装态。固定 installed + dashboard=yes。
    uxs_emit_status "installed" "${GREEN}$(_t '✅ Disk dashboard available')${NC}$(_t '(pure command wrapper)')"
    uxs_emit_extra "dashboard=yes"

    # 仪表盘多行表格仅在人类模式输出（机器模式只发 STATE=/EXTRA=）
    if ! uxs_is_machine_mode; then
        _status_disk_dashboard
    fi
}

# 仪表盘实现（人类模式专用）。从 status_disk 抽出，便于人类守卫包裹。
_status_disk_dashboard() {
    header "═══════════════════════════════════════"
    header "       $(_t '💾 Disk space overview')"
    header "═══════════════════════════════════════"
    echo

    # -- 各挂载点使用率 --
    info "$(_t '📁 Mount point usage:')"
    echo
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS: df -h 输出格式略有不同，用 awk 格式化
        df -h | awk -v h_fs="$(_t 'File system')" -v h_cap="$(_t 'Capacity')" -v h_used="$(_t 'Used')" \
            -v h_avail="$(_t 'Available')" -v h_pct="$(_t 'Usage')" -v h_mnt="$(_t 'Mount point')" 'NR==1 {
            printf "%-25s %8s %8s %8s %5s  %s\n", h_fs, h_cap, h_used, h_avail, h_pct, h_mnt
        }
        NR>1 && $1 ~ /^\/dev\// {
            pct = $5; gsub(/%/, "", pct)
            # 红色 / 黄色 / 绿色
            if (pct+0 >= 90) color = "\033[0;31m"
            else if (pct+0 >= 80) color = "\033[0;33m"
            else color = "\033[0;32m"
            nc = "\033[0m"
            if (ENVIRON["NO_COLOR"] != "") { color = ""; nc = "" }
            printf "%s%-25s %8s %8s %8s %5s  %s%s\n", color, $1, $2, $3, $4, $5, $9, nc
        }'
    else
        # Linux: GNU df 支持 --output/-x（过滤伪文件系统）；BusyBox df（Alpine 等）不支持，
        # 降级到 plain df -h。两者列序一致（source,size,used,avail,pcent,target），共用同一 awk。
        local df_data
        df_data=$(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x squashfs 2>/dev/null || true)
        if [[ -z "$df_data" ]]; then
            df_data=$(df -h 2>/dev/null || true)
        fi
        echo "$df_data" | awk -v h_fs="$(_t 'File system')" -v h_cap="$(_t 'Capacity')" -v h_used="$(_t 'Used')" \
            -v h_avail="$(_t 'Available')" -v h_pct="$(_t 'Usage')" -v h_mnt="$(_t 'Mount point')" 'NR==1 {
            printf "%-25s %8s %8s %8s %5s  %s\n", h_fs, h_cap, h_used, h_avail, h_pct, h_mnt
        }
        NR>1 {
            pct = $5; gsub(/%/, "", pct)
            if (pct+0 >= 90) color = "\033[0;31m"
            else if (pct+0 >= 80) color = "\033[0;33m"
            else color = "\033[0;32m"
            nc = "\033[0m"
            if (ENVIRON["NO_COLOR"] != "") { color = ""; nc = "" }
            printf "%s%-25s %8s %8s %8s %5s  %s%s\n", color, $1, $2, $3, $4, $5, $6, nc
        }'
    fi
    echo

    # -- 内存使用 --
    info "$(_t '🧠 Memory usage:')"
    echo
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS 内存信息
        local mem_total mem_used mem_free
        mem_total=$(sysctl -n hw.memsize 2>/dev/null)
        if [[ -n "$mem_total" ]]; then
            local mem_total_gb=$((mem_total / 1024 / 1024 / 1024))
            # 用 vm_stat 获取页面信息。
            # vm_stat 的输出整体收进变量再解析：
            #   - 不用 `| head -1`：head 命中即退会提前关管道，上游 vm_stat 被打成
            #     SIGPIPE(141)，pipefail 下整条管道非 0；
            #   - 原来的 `|| echo 4096` 把「兜底常量」追加到已捕获的输出后面，
            #     page_size 变成 "16384\n4096" 这种多行文本 ⇒ $(( ... * page_size ... ))
            #     直接抛 "syntax error in expression" ⇒ set -e 让 status 子命令中止；
            #     只有管道一条输出都没有时才拿到纯 "4096" ⇒ 页大小被静默写死成 Intel
            #     时代的 4096（Apple Silicon 真值是 16384）⇒ 已用/可用内存算成 1/4。
            # 现在页大小从 vm_stat 表头取真值，取不到再用 getconf PAGESIZE 兜底。
            local page_size free_pages active_pages inactive_pages speculative_pages wired_pages
            local vm_out vm_pages
            vm_out=$(vm_stat 2>/dev/null) || vm_out=""
            page_size=$(printf '%s\n' "$vm_out" | grep -oE 'page size of [0-9]+' | grep -oE '[0-9]+' | sed -n '1p') || page_size=""
            if ! [[ "$page_size" =~ ^[0-9]+$ ]]; then
                page_size=$(getconf PAGESIZE 2>/dev/null) || page_size=""
            fi
            if ! [[ "$page_size" =~ ^[0-9]+$ ]]; then
                page_size=4096
            fi
            # 页面数也从同一份快照里取（原来跑 5 次 vm_stat，计数来自不同时刻）
            vm_pages=$(printf '%s\n' "$vm_out" | awk '
                /Pages free:/     {gsub(/\./,"",$3); f=$3}
                /Pages active:/   {gsub(/\./,"",$3); a=$3}
                /Pages inactive:/ {gsub(/\./,"",$3); i=$3}
                /Pages wired/     {gsub(/\./,"",$4); w=$4}
                END {printf "%d %d %d %d\n", f+0, a+0, i+0, w+0}')
            read -r free_pages active_pages inactive_pages wired_pages <<< "$vm_pages"
            local used_kb=$(( (active_pages + wired_pages) * page_size / 1024 ))
            local free_kb=$(( (free_pages + inactive_pages) * page_size / 1024 ))
            local used_gb=$((used_kb / 1024 / 1024))
            local free_gb=$((free_kb / 1024 / 1024))
            printf '  %s\n' "$(_tf 'Total memory: %dGB | Used: %dGB | Available: %dGB' "$mem_total_gb" "$used_gb" "$free_gb")"
        fi
    else
        # free 属 procps/procps-ng，极简容器（CI routing 阶段，essential-pkgs 未装前）可能缺失；
        # 缺失时降级提示而非中止（status 命令不应因一个可选工具缺失而硬失败）。
        if os_has_cmd free; then
            free -h | awk -v h_total="$(_t 'Total')" -v h_used="$(_t 'Used')" -v h_avail="$(_t 'Available')" \
                -v h_shared="$(_t 'Shared')" -v h_cache="$(_t 'Cache')" 'NR==1 {printf "  %-10s %10s %10s %10s %10s %10s\n", "", h_total, h_used, h_avail, h_shared, h_cache}
                            NR==2 {printf "  %-10s %10s %10s %10s %10s %10s\n", $1, $2, $3, $4, $5, $6}'
        else
            echo "  (free $(_t 'free command unavailable, install procps/procps-ng to view memory details'))"
        fi
    fi
    echo

    # -- Swap 状态 --
    info "$(_t '🔄 Swap status:')"
    echo
    if [[ "$OS_TYPE" == "darwin" ]]; then
        local swap_line
        swap_line=$(sysctl vm.swapusage 2>/dev/null)
        if [[ -n "$swap_line" ]]; then
            # 格式: vm.swapusage: total = 3072.00M  used = 1400.00M  free = 1672.00M  (encrypted)
            local swap_total swap_used swap_free
            swap_total=$(echo "$swap_line" | awk -F' = ' '{print $2}' | awk '{print $1}')
            swap_used=$(echo "$swap_line" | awk -F'used = ' '{print $2}' | awk '{print $1}')
            swap_free=$(echo "$swap_line" | awk -F'free = ' '{print $2}' | awk '{print $1}')
            printf '  %s\n' "$(_tf 'Total: %s | Used: %s | Available: %s' "$swap_total" "$swap_used" "$swap_free")"
        else
            echo "  $(_t 'Cannot get swap information')"
        fi
    else
        if swapon --show 2>/dev/null | grep -q .; then
            swapon --show
        else
            echo "  $(_t 'Swap is not enabled')"
        fi
    fi
    echo

    # -- 告警检查 --
    local has_warning=0
    # Linux 默认挂载点在第 6 列
    local mount_col=6
    # macOS 在第 9 列
    [[ "$OS_TYPE" == "darwin" ]] && mount_col=9
    while IFS= read -r line; do
        local pct
        pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        if [[ "$pct" =~ ^[0-9]+$ ]] && [[ "$pct" -ge 90 ]]; then
            if [[ "$has_warning" -eq 0 ]]; then
                warn "$(_t '⚠️  The following mount points exceed 90% usage:')"
                has_warning=1
            fi
            local mount_point
            mount_point=$(echo "$line" | awk -v mc="$mount_col" '{print $mc}')
            echo "  🔴 $mount_point: ${pct}%"
        fi
    done < <(df -h 2>/dev/null | grep '^/dev/' || true)
    if [[ "$has_warning" -eq 1 ]]; then
        echo
        warn "$(_tf 'Run "%s clean" to free up space' "$0")"
    fi
}

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
        printf '%s\n> ' "$(_tf 'Number=drill down into this directory  u=up one level  c=change count (current %s, e.g. 10/20/30/50)  q=quit' "$count")"
        if ! read -r ans; then
            # EOF（Ctrl-D）安全退出
            break
        fi
        case "$ans" in
            q|Q|"")
                break
                ;;
            u|U)
                if [[ "$n" -le 1 ]]; then
                    info "$(_t 'Already at the top level')"
                else
                    unset "stack_paths[$((n - 1))]"
                    unset "stack_depths[$((n - 1))]"
                fi
                ;;
            c|C)
                printf '%s ' "$(_tf 'Enter the count (positive integer, press Enter to keep %s):' "$count")"
                if ! read -r new_count; then break; fi
                if [[ -z "$new_count" ]]; then
                    :
                elif [[ "$new_count" =~ ^[0-9]+$ && "$new_count" -ge 1 ]]; then
                    count="$new_count"
                else
                    warn "$(_tf 'Invalid count, keeping %s' "$count")"
                fi
                ;;
            *[!0-9]*)
                warn "$(_tf 'Invalid input: %s' "$ans")"
                ;;
            *)
                n_paths=${#_top_last_paths[@]}
                if [[ "$n_paths" -eq 0 ]]; then
                    warn "$(_t 'The current list is empty, there is no directory to drill into')"
                elif [[ "$ans" -ge 1 && "$ans" -le "$n_paths" ]]; then
                    idx=$((ans - 1))
                    stack_paths+=("${_top_last_paths[$idx]}")
                    stack_depths+=(1)
                else
                    warn "$(_tf 'Index out of range (1-%s)' "${n_paths}")"
                fi
                ;;
        esac
    done
    return 0
}

# ============================================================
# top - 大文件/目录排行（--depth 下钻 + 智能 TTY 交互）
# ============================================================

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

top_disk() {
    local scan_path
    scan_path=$(_norm_path "${1:-/}")

    # 参数校验（count/depth 正整数；min-size 必须带单位）
    case "${TOP_COUNT:-10}" in
        ''|*[!0-9]*|0) error "--count $(_tf 'Must be a positive integer: %s' "${TOP_COUNT:-}")"; usage; exit 1 ;;
    esac
    case "${TOP_DEPTH:-1}" in
        ''|*[!0-9]*|0) error "--depth $(_tf 'Must be a positive integer: %s' "${TOP_DEPTH:-}")"; usage; exit 1 ;;
    esac
    TOP_MIN_SIZE_KB=""
    if [[ -n "${TOP_MIN_SIZE:-}" ]]; then
        TOP_MIN_SIZE_KB=$(_parse_size_to_kb "$TOP_MIN_SIZE") || {
            error "--min-size $(_t 'Must carry a K/M/G unit, e.g. 100M')"; usage; exit 1
        }
    fi

    if [[ ! -d "$scan_path" ]]; then
        error "$(_tf 'Path does not exist: %s' "$scan_path")"
        exit 1
    fi

    # 仅初始路径为 / 时整体加 sudo 前缀（一次授权全程有效，交互下钻不重复弹密码）
    if [[ "$scan_path" == "/" ]]; then
        USE_SUDO=1
    else
        USE_SUDO=0
    fi

    if [[ -t 0 && -t 1 && -z "${TOP_NO_INTERACTIVE:-}" ]]; then
        _top_interactive "$scan_path" "${TOP_DEPTH:-1}" "${TOP_COUNT:-10}"
    else
        echo
        _top_print_dirs "$scan_path" "${TOP_DEPTH:-1}" "${TOP_COUNT:-10}"
        echo
        _top_print_files "$scan_path" "${TOP_COUNT:-10}"
        echo
    fi
}

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
        warn "$(_t 'The current du does not support depth scanning, fell back to single level mode')" >&2
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

# 探测当前 find 是否支持 -size 的 M/G 后缀：GNU find 支持；BusyBox find 只有
# c/b/k/w（实测 Alpine）。不支持时文件榜降级跳过，而不是静默输出「无匹配」误导用户。
_top_find_supports_size_m() {
    local probe rc
    probe="$(mktemp)" || return 1
    printf 'x' > "$probe"
    find "$probe" -size +1M >/dev/null 2>&1
    rc=$?
    rm -f "$probe"
    # GNU find：1 字节文件不匹配 +1M，退出 0；BusyBox find：不认 M 后缀，退出非 0
    [[ $rc -eq 0 ]]
}

# 文件扫描：find -type f -size +50M → du -k，数字排序取前 count
_top_scan_files() {
    local count="$1"; shift
    local raw
    if ! _top_find_supports_size_m; then
        warn "$(_t 'The current find does not support M/G size filtering (BusyBox?), the file list is skipped (install findutils to restore)')" >&2
        return 0
    fi
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
    info "$(_tf 'Scanning (depth %s, large directories may take a while)...' "${depth}")"
    _top_last_paths=()
    local lines
    lines=$(_top_scan_dirs "$path" "$depth" "$count") || true
    header "═══════════════════════════════════════"
    header "  $(_tf '📊 Largest directories under %s (Top %s · depth %s)' "${path}" "${count}" "${depth}")"
    header "═══════════════════════════════════════"
    if [[ -z "$lines" ]]; then
        info "  $(_t '(no matching subdirectories)')"
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
    header "  $(_tf '📄 Largest files (Top %s, only >50M listed)' "${count}")"
    if [[ ${#search_paths[@]} -eq 0 ]]; then
        info "  $(_t '(no file path to scan)')"
        return 0
    fi
    local lines kb p
    lines=$(_top_scan_files "$count" "${search_paths[@]}") || true
    if [[ -z "$lines" ]]; then
        info "  $(_t '(no files larger than 50M found)')"
        return 0
    fi
    while IFS=$'\t' read -r kb p; do
        [[ -z "$kb" ]] && continue
        printf "   ‣ %8s  %s\n" "$(_fmt_kb "$kb")" "$p"
    done <<< "$lines"
    return 0
}

# ============================================================
# monitor - 监控告警
# ============================================================
monitor_disk() {
    local threshold="${MONITOR_THRESHOLD:-90}"

    # --install: 写入 crontab
    if [[ "${MONITOR_INSTALL:-}" == "1" ]]; then
        _monitor_install "$threshold"
        return
    fi

    # --uninstall: 移除 crontab
    if [[ "${MONITOR_UNINSTALL:-}" == "1" ]]; then
        _monitor_uninstall
        return
    fi

    # 默认：执行一次检查
    _monitor_check "$threshold"
}

_monitor_check() {
    local threshold="$1"
    local has_alert=0

    header "═══════════════════════════════════════"
    header "  $(_tf '🔍 Disk space monitoring (threshold: %s%%)' "${threshold}")"
    header "═══════════════════════════════════════"
    echo

    local mount_col=6
    [[ "$OS_TYPE" == "darwin" ]] && mount_col=9
    while IFS= read -r line; do
        local fs pct mount
        fs=$(echo "$line" | awk '{print $1}')
        pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mount=$(echo "$line" | awk -v mc="$mount_col" '{print $mc}')

        if [[ "$pct" =~ ^[0-9]+$ ]]; then
            if [[ "$pct" -ge "$threshold" ]]; then
                has_alert=1
                error "$(_tf '🔴 %s (%s): %s%% — exceeds threshold %s%%' "$mount" "$fs" "${pct}" "${threshold}")"
            elif [[ "$pct" -ge $((threshold - 10)) ]]; then
                warn "$(_tf '🟡 %s (%s): %s%% — close to threshold %s%%' "$mount" "$fs" "${pct}" "${threshold}")"
            else
                success "🟢 $mount ($fs): ${pct}%"
            fi
        fi
    done < <(df -h 2>/dev/null | grep '^/dev/' || true)

    echo
    if [[ "$has_alert" -eq 1 ]]; then
        error "$(_tf 'Out of disk space on some mount points! Run "%s clean" to free space' "$0")"
        return 1
    else
        success "$(_t 'All mount points have enough space ✅')"
        return 0
    fi
}

_monitor_install() {
    local threshold="$1"
    require_sudo

    info "$(_tf 'Installing the disk space monitoring cron job (checks daily at 08:00, threshold: %s%%)' "${threshold}")"

    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"

    local cron_line="0 8 * * * NO_COLOR=1 ${script_path} monitor --threshold ${threshold} >> ${CRON_LOG} 2>&1"

    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -qF "disk-usage/install.sh monitor"; then
        warn "$(_t 'The disk monitoring cron job already exists, it will be updated')"
        _monitor_uninstall
    fi

    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    success "$(_t 'Cron job installed')"
    info "$(_tf 'Log file: %s' "${CRON_LOG}")"
    info "$(_t 'View the job: crontab -l | grep disk-usage')"
    info "$(_tf 'Uninstall the job: %s monitor --uninstall' "$0")"
}

_monitor_uninstall() {
    require_sudo

    if ! crontab -l 2>/dev/null | grep -qF "disk-usage/install.sh monitor"; then
        warn "$(_t 'No disk monitoring cron job found')"
        return 0
    fi

    crontab -l 2>/dev/null | grep -vF "disk-usage/install.sh monitor" | crontab -
    success "$(_t 'Cron job removed')"
}

# ============================================================
# clean - 一键清理
# ============================================================
clean_disk() {
    detect_os
    local total_freed=0

    header "═══════════════════════════════════════"
    header "  $(_t '🧹 Disk space cleanup')"
    header "═══════════════════════════════════════"
    echo

    if [[ "${CLEAN_ALL:-}" == "1" ]]; then
        CLEAN_LOGS=1
        CLEAN_CACHE=1
        CLEAN_DOCKER=1
    fi

    # 如果没有指定任何选项，显示帮助
    if [[ -z "${CLEAN_LOGS:-}" && -z "${CLEAN_CACHE:-}" && -z "${CLEAN_DOCKER:-}" ]]; then
        warn "$(_t 'Please specify the cleanup type:')"
        echo "  --logs     $(_t 'Clean up system logs')"
        echo "  --cache    $(_t 'Clean up the package manager cache')"
        echo "  --docker   $(_t 'Clean up Docker junk (Docker must be installed)')"
        echo "  --all      $(_t 'Clean up everything')"
        echo
        printf '%s\n' "$(_tf 'Example: %s clean --all' "$0")"
        echo "      $0 clean --logs --cache"
        return 1
    fi

    # -- 清理日志 --
    if [[ -n "${CLEAN_LOGS:-}" ]]; then
        header "$(_t '── Clean up system logs ──')"
        if [[ "$OS_TYPE" == "linux" ]] && os_has_cmd journalctl; then
            local journal_size
            journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]' || printf '%s\n' "$(_t 'Unknown')")
            info "$(_tf 'Current journal log size: %s' "$journal_size")"

            if [[ "${DRY_RUN:-}" == "1" ]]; then
                info "[dry-run] $(_t 'Will run: journalctl --vacuum-time=3d')"
            else
                if yes_no "$(_t 'Clean up journal logs older than 3 days?')"; then
                    sudo journalctl --vacuum-time=3d
                    success "journal $(_t 'Journal logs cleaned')"
                fi
            fi
        fi

        # 清理大日志文件（>100M）
        local large_logs
        if [[ "$OS_TYPE" == "darwin" ]]; then
            large_logs=$(find /var/log -type f -size +100M 2>/dev/null || true)
        else
            large_logs=$(find /var/log -type f -size +100M 2>/dev/null || true)
        fi

        if [[ -n "$large_logs" ]]; then
            info "$(_t 'Found the following log files larger than 100M:')"
            echo "$large_logs" | while IFS= read -r f; do
                local fsize
                fsize=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
                printf "  %10s  %s\n" "$fsize" "$f"
            done
            echo
            if [[ "${DRY_RUN:-}" == "1" ]]; then
                info "[dry-run] $(_t 'Will truncate the large log files above')"
            else
                if yes_no "$(_t 'Truncate the large log files above (keep the empty files)?')"; then
                    echo "$large_logs" | while IFS= read -r f; do
                        sudo truncate -s 0 "$f" 2>/dev/null || true
                    done
                    success "$(_t 'Large log files truncated')"
                fi
            fi
        else
            info "$(_t 'No log files larger than 100M found')"
        fi
        echo
    fi

    # -- 清理包管理器缓存 --
    if [[ -n "${CLEAN_CACHE:-}" ]]; then
        header "$(_t '── Clean up the package manager cache ──')"
        detect_pkg_manager || true
        case "${PKG_MANAGER:-}" in
            apt-get)
                local apt_size
                apt_size=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || printf '%s\n' "$(_t 'Unknown')")
                info "APT $(_tf 'Cache size: %s' "$apt_size")"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] $(_t 'Will run: apt-get clean')"
                else
                    if yes_no "$(_t 'Clean up the APT cache?')"; then
                        sudo apt-get clean
                        success "APT $(_t 'Cache cleaned')"
                    fi
                fi
                ;;
            dnf)
                local dnf_size
                dnf_size=$(du -sh /var/cache/dnf 2>/dev/null | awk '{print $1}' || printf '%s\n' "$(_t 'Unknown')")
                info "DNF $(_tf 'Cache size: %s' "$dnf_size")"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] $(_t 'Will run: dnf clean all')"
                else
                    if yes_no "$(_t 'Clean up the DNF cache?')"; then
                        sudo dnf clean all
                        success "DNF $(_t 'Cache cleaned')"
                    fi
                fi
                ;;
            yum)
                local yum_size
                yum_size=$(du -sh /var/cache/yum 2>/dev/null | awk '{print $1}' || printf '%s\n' "$(_t 'Unknown')")
                info "YUM $(_tf 'Cache size: %s' "$yum_size")"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] $(_t 'Will run: yum clean all')"
                else
                    if yes_no "$(_t 'Clean up the YUM cache?')"; then
                        sudo yum clean all
                        success "YUM $(_t 'Cache cleaned')"
                    fi
                fi
                ;;
            brew)
                if [[ "$OS_TYPE" == "darwin" ]]; then
                    local brew_size
                    brew_size=$(du -sh "$(brew --cache)" 2>/dev/null | awk '{print $1}' || printf '%s\n' "$(_t 'Unknown')")
                    info "Homebrew $(_tf 'Cache size: %s' "$brew_size")"
                    if [[ "${DRY_RUN:-}" == "1" ]]; then
                        info "[dry-run] $(_t 'Will run: brew cleanup --prune=all')"
                    else
                        if yes_no "$(_t 'Clean up the Homebrew cache?')"; then
                            brew cleanup --prune=all 2>/dev/null || true
                            success "Homebrew $(_t 'Cache cleaned')"
                        fi
                    fi
                fi
                ;;
            *)
                info "$(_t 'No known package manager detected, skipping the cache cleanup')"
                ;;
        esac

        # 清理 pip 缓存
        if os_has_cmd pip3 || os_has_cmd pip; then
            local pip_cmd="pip3"
            os_has_cmd pip3 || pip_cmd="pip"
            local pip_cache_dir
            pip_cache_dir=$($pip_cmd cache dir 2>/dev/null || echo "")
            if [[ -n "$pip_cache_dir" && -d "$pip_cache_dir" ]]; then
                local pip_size
                pip_size=$(du -sh "$pip_cache_dir" 2>/dev/null | awk '{print $1}' || printf '%s\n' "$(_t 'Unknown')")
                info "pip $(_tf 'Cache size: %s (%s)' "$pip_size" "$pip_cache_dir")"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] $(_tf 'Will run: %s cache purge' "$pip_cmd")"
                else
                    if yes_no "$(_t 'Clean up the pip cache?')"; then
                        $pip_cmd cache purge
                        success "pip $(_t 'Cache cleaned')"
                    fi
                fi
            fi
        fi

        # 清理 npm 缓存
        if os_has_cmd npm; then
            local npm_cache_dir
            npm_cache_dir=$(npm config get cache 2>/dev/null || echo "")
            if [[ -n "$npm_cache_dir" && -d "$npm_cache_dir" ]]; then
                local npm_size
                npm_size=$(du -sh "$npm_cache_dir" 2>/dev/null | awk '{print $1}' || printf '%s\n' "$(_t 'Unknown')")
                info "npm $(_tf 'Cache size: %s' "$npm_size")"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] $(_t 'Will run: npm cache clean --force')"
                else
                    if yes_no "$(_t 'Clean up the npm cache?')"; then
                        npm cache clean --force
                        success "npm $(_t 'Cache cleaned')"
                    fi
                fi
            fi
        fi

        # 清理 bun 缓存
        if os_has_cmd bun; then
            local bun_cache_dir="${HOME}/.bun/install/cache"
            if [[ -d "$bun_cache_dir" ]]; then
                local bun_size
                bun_size=$(du -sh "$bun_cache_dir" 2>/dev/null | awk '{print $1}' || printf '%s\n' "$(_t 'Unknown')")
                info "bun $(_tf 'Cache size: %s' "$bun_size")"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] $(_tf 'Will clean %s' "$bun_cache_dir")"
                else
                    if yes_no "$(_t 'Clean up the bun cache?')"; then
                        rm -rf "${bun_cache_dir:?}"/*
                        success "bun $(_t 'Cache cleaned')"
                    fi
                fi
            fi
        fi
        echo
    fi

    # -- 清理 Docker --
    if [[ -n "${CLEAN_DOCKER:-}" ]]; then
        header "$(_t '── Clean up Docker ──')"
        if ! os_has_cmd docker; then
            warn "Docker $(_t 'not installed, skipping')"
        else
            if ! docker info >/dev/null 2>&1; then
                warn "Docker $(_t 'the service is not running, skipping')"
            else
                info "Docker $(_t 'Disk usage:')"
                docker system df 2>/dev/null || true
                echo
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] $(_t 'Will run: docker system prune -af --volumes')"
                else
                    if yes_no "$(_t 'Clean up unused Docker images, containers, networks and volumes?')"; then
                        docker system prune -af --volumes
                        success "Docker $(_t 'Docker junk cleaned')"
                    fi
                fi
            fi
        fi
        echo
    fi

    success "$(_t '🎉 Cleanup finished')"
}

# ============================================================
# help
# ============================================================
usage() {
    cat <<EOF
用法: disk-usage {status|top|monitor|clean|help}

$(_t 'Disk space management tool — view the storage overview, the large file ranking, monitoring alerts, one-click cleanup.')

$(_t 'Subcommands:')
  status                     $(_t 'View the storage overview (default action)')
                             $(_t 'Show the usage of each mount point, memory and Swap status')

  top [$(_t 'path argument')] [--count N] [--depth D] [--min-size SIZE] [--no-interactive]
                             $(_t 'Large file/directory ranking (path defaults to /, count defaults to 10)')
    --depth D                $(_t 'Directory scan depth (defaults to 1); 2 shows the second level subdirectories')
    --min-size SIZE          $(_t 'Only show the entries not smaller than the given size (must carry a K/M/G unit, e.g. 100M)')
    --no-interactive         $(_t 'Disable the interactive mode (disabled automatically under a pipe/CI)')
                             $(_t 'Interactive keys: number=drill down  u=up one level  c=change count  q=quit')

  monitor [--threshold N]    $(_t 'Check whether the usage exceeds the threshold (defaults to 90%)')
    --install                $(_t 'Write to crontab (checks daily at 08:00)')
    --uninstall              $(_t 'Remove the crontab cron job')

  clean                      $(_t 'One-click disk space cleanup')
    --logs                   $(_t 'Clean up system logs (journal + large log files)')
    --cache                  $(_t 'Clean up the package manager cache (apt/dnf/yum/brew/pip/npm/bun)')
    --docker                 $(_t 'Clean up Docker junk (Docker must be installed)')
    --all                    $(_t 'Clean up everything')
    --dry-run                $(_t 'Preview only, do not execute')

  help                       $(_t 'Show this help')

$(_t 'Examples:')
  disk-usage status              $(_t '# View the storage overview')
  disk-usage top /home           $(_t '# View the large directories under /home')
  disk-usage top --count 20      $(_t '# View the Top 20 large directories')
  disk-usage top /var --depth 2  $(_t '# Two level drill down: /var and /var/lib/docker in one screen')
  disk-usage top ~ --min-size 100M  $(_t '# Only show the big ones above 100M')
  disk-usage monitor             $(_t '# Check whether it exceeds 90%')
  disk-usage monitor --threshold 80 --install   $(_t '# Install the scheduled monitoring with an 80% threshold')
  disk-usage clean --all         $(_t '# Clean up everything')
  disk-usage clean --logs --dry-run  $(_t '# Preview the log cleanup')
EOF
}

# ============================================================
# main
# ============================================================
main() {
    local action="${1:-status}"
    shift || true

    # 解析剩余参数
    local positional_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --count)      TOP_COUNT="$2"; shift 2 ;;
            --depth)      TOP_DEPTH="$2"; shift 2 ;;
            --min-size)   TOP_MIN_SIZE="$2"; shift 2 ;;
            --no-interactive) TOP_NO_INTERACTIVE=1; shift ;;
            --threshold)  MONITOR_THRESHOLD="$2"; shift 2 ;;
            --install)    MONITOR_INSTALL=1; shift ;;
            --uninstall)  MONITOR_UNINSTALL=1; shift ;;
            --logs)       CLEAN_LOGS=1; shift ;;
            --cache)      CLEAN_CACHE=1; shift ;;
            --docker)     CLEAN_DOCKER=1; shift ;;
            --all)        CLEAN_ALL=1; shift ;;
            --dry-run)    DRY_RUN=1; export UNIX_SCRIPT_DRY_RUN=1; shift ;;
            -*)           error "$(_tf 'Unknown option: %s' "$1")"; usage; exit 1 ;;
            *)            positional_args+=("$1"); shift ;;
        esac
    done

    detect_os
    case "$action" in
        status)   status_disk ;;
        top)      top_disk "${positional_args[0]:-/}" ;;
        monitor)  monitor_disk ;;
        clean)    clean_disk ;;
        help|--help|-h) usage ;;
        *)        error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
