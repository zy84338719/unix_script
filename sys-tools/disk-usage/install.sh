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
    emit_status "installed" "${GREEN}✅ 磁盘仪表盘可用${NC}（纯命令封装）"
    emit_extra "dashboard=yes"

    # 仪表盘多行表格仅在人类模式输出（机器模式只发 STATE=/EXTRA=）
    if ! uxs_is_machine_mode; then
        _status_disk_dashboard
    fi
}

# 仪表盘实现（人类模式专用）。从 status_disk 抽出，便于人类守卫包裹。
_status_disk_dashboard() {
    header "═══════════════════════════════════════"
    header "       💾 磁盘空间概况"
    header "═══════════════════════════════════════"
    echo

    # -- 各挂载点使用率 --
    info "📁 挂载点使用率："
    echo
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS: df -h 输出格式略有不同，用 awk 格式化
        df -h | awk 'NR==1 {
            printf "%-25s %8s %8s %8s %5s  %s\n", "文件系统", "容量", "已用", "可用", "使用率", "挂载点"
        }
        NR>1 && $1 ~ /^\/dev\// {
            pct = $5; gsub(/%/, "", pct)
            if (pct+0 >= 90) color = "\033[0;31m"      # 红色
            else if (pct+0 >= 80) color = "\033[0;33m"  # 黄色
            else color = "\033[0;32m"                    # 绿色
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
        echo "$df_data" | awk 'NR==1 {
            printf "%-25s %8s %8s %8s %5s  %s\n", "文件系统", "容量", "已用", "可用", "使用率", "挂载点"
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
    info "🧠 内存使用："
    echo
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS 内存信息
        local mem_total mem_used mem_free
        mem_total=$(sysctl -n hw.memsize 2>/dev/null)
        if [[ -n "$mem_total" ]]; then
            local mem_total_gb=$((mem_total / 1024 / 1024 / 1024))
            # 用 vm_stat 获取页面信息
            local page_size free_pages active_pages inactive_pages speculative_pages wired_pages
            page_size=$(vm_stat | head -1 | grep -oE '[0-9]+' || echo 4096)
            free_pages=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
            active_pages=$(vm_stat | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')
            inactive_pages=$(vm_stat | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')
            wired_pages=$(vm_stat | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')
            local used_kb=$(( (active_pages + wired_pages) * page_size / 1024 ))
            local free_kb=$(( (free_pages + inactive_pages) * page_size / 1024 ))
            local used_gb=$((used_kb / 1024 / 1024))
            local free_gb=$((free_kb / 1024 / 1024))
            printf "  总内存: %dGB | 已用: %dGB | 可用: %dGB\n" "$mem_total_gb" "$used_gb" "$free_gb"
        fi
    else
        # free 属 procps/procps-ng，极简容器（CI routing 阶段，essential-pkgs 未装前）可能缺失；
        # 缺失时降级提示而非中止（status 命令不应因一个可选工具缺失而硬失败）。
        if command_exists free; then
            free -h | awk 'NR==1 {printf "  %-10s %10s %10s %10s %10s %10s\n", "", "总量", "已用", "可用", "共享", "缓存"}
                            NR==2 {printf "  %-10s %10s %10s %10s %10s %10s\n", $1, $2, $3, $4, $5, $6}'
        else
            echo "  (free 命令不可用，安装 procps/procps-ng 后可查看内存详情)"
        fi
    fi
    echo

    # -- Swap 状态 --
    info "🔄 Swap 状态："
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
            printf "  总量: %s | 已用: %s | 可用: %s\n" "$swap_total" "$swap_used" "$swap_free"
        else
            echo "  无法获取 swap 信息"
        fi
    else
        if swapon --show 2>/dev/null | grep -q .; then
            swapon --show
        else
            echo "  未启用 swap"
        fi
    fi
    echo

    # -- 告警检查 --
    local has_warning=0
    local mount_col=6  # Linux 默认挂载点在第 6 列
    [[ "$OS_TYPE" == "darwin" ]] && mount_col=9  # macOS 在第 9 列
    while IFS= read -r line; do
        local pct
        pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
        if [[ "$pct" =~ ^[0-9]+$ ]] && [[ "$pct" -ge 90 ]]; then
            if [[ "$has_warning" -eq 0 ]]; then
                warn "⚠️  以下挂载点使用率超过 90%："
                has_warning=1
            fi
            local mount_point
            mount_point=$(echo "$line" | awk -v mc="$mount_col" '{print $mc}')
            echo "  🔴 $mount_point: ${pct}%"
        fi
    done < <(df -h 2>/dev/null | grep '^/dev/' || true)
    if [[ "$has_warning" -eq 1 ]]; then
        echo
        warn "建议运行 '$0 clean' 清理空间"
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
    header "  🔍 磁盘空间监控（阈值: ${threshold}%）"
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
                error "🔴 $mount ($fs): ${pct}% — 超过阈值 ${threshold}%"
            elif [[ "$pct" -ge $((threshold - 10)) ]]; then
                warn "🟡 $mount ($fs): ${pct}% — 接近阈值 ${threshold}%"
            else
                success "🟢 $mount ($fs): ${pct}%"
            fi
        fi
    done < <(df -h 2>/dev/null | grep '^/dev/' || true)

    echo
    if [[ "$has_alert" -eq 1 ]]; then
        error "存在空间不足的挂载点！建议运行 '$0 clean' 清理"
        return 1
    else
        success "所有挂载点空间充足 ✅"
        return 0
    fi
}

_monitor_install() {
    local threshold="$1"
    require_sudo

    info "安装磁盘空间监控定时任务（每天 08:00 检查，阈值: ${threshold}%）"

    local script_path
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh"

    local cron_line="0 8 * * * NO_COLOR=1 ${script_path} monitor --threshold ${threshold} >> ${CRON_LOG} 2>&1"

    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -qF "disk-usage/install.sh monitor"; then
        warn "已存在磁盘监控定时任务，将更新"
        _monitor_uninstall
    fi

    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    success "定时任务已安装"
    info "日志文件: ${CRON_LOG}"
    info "查看任务: crontab -l | grep disk-usage"
    info "卸载任务: $0 monitor --uninstall"
}

_monitor_uninstall() {
    require_sudo

    if ! crontab -l 2>/dev/null | grep -qF "disk-usage/install.sh monitor"; then
        warn "未找到磁盘监控定时任务"
        return 0
    fi

    crontab -l 2>/dev/null | grep -vF "disk-usage/install.sh monitor" | crontab -
    success "定时任务已移除"
}

# ============================================================
# clean - 一键清理
# ============================================================
clean_disk() {
    detect_os
    local total_freed=0

    header "═══════════════════════════════════════"
    header "  🧹 磁盘空间清理"
    header "═══════════════════════════════════════"
    echo

    if [[ "${CLEAN_ALL:-}" == "1" ]]; then
        CLEAN_LOGS=1
        CLEAN_CACHE=1
        CLEAN_DOCKER=1
    fi

    # 如果没有指定任何选项，显示帮助
    if [[ -z "${CLEAN_LOGS:-}" && -z "${CLEAN_CACHE:-}" && -z "${CLEAN_DOCKER:-}" ]]; then
        warn "请指定清理类型："
        echo "  --logs     清理系统日志"
        echo "  --cache    清理包管理器缓存"
        echo "  --docker   清理 Docker 垃圾（需已安装 Docker）"
        echo "  --all      全部清理"
        echo
        echo "示例: $0 clean --all"
        echo "      $0 clean --logs --cache"
        return 1
    fi

    # -- 清理日志 --
    if [[ -n "${CLEAN_LOGS:-}" ]]; then
        header "── 清理系统日志 ──"
        if [[ "$OS_TYPE" == "linux" ]] && command_exists journalctl; then
            local journal_size
            journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[MG]' || echo "未知")
            info "当前 journal 日志大小: $journal_size"

            if [[ "${DRY_RUN:-}" == "1" ]]; then
                info "[dry-run] 将执行: journalctl --vacuum-time=3d"
            else
                if yes_no "清理 3 天前的 journal 日志？"; then
                    sudo journalctl --vacuum-time=3d
                    success "journal 日志已清理"
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
            info "发现以下大于 100M 的日志文件："
            echo "$large_logs" | while IFS= read -r f; do
                local fsize
                fsize=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
                printf "  %10s  %s\n" "$fsize" "$f"
            done
            echo
            if [[ "${DRY_RUN:-}" == "1" ]]; then
                info "[dry-run] 将截断以上大日志文件"
            else
                if yes_no "截断以上大日志文件（保留空文件）？"; then
                    echo "$large_logs" | while IFS= read -r f; do
                        sudo truncate -s 0 "$f" 2>/dev/null || true
                    done
                    success "大日志文件已截断"
                fi
            fi
        else
            info "未发现大于 100M 的日志文件"
        fi
        echo
    fi

    # -- 清理包管理器缓存 --
    if [[ -n "${CLEAN_CACHE:-}" ]]; then
        header "── 清理包管理器缓存 ──"
        detect_pkg_manager || true
        case "${PKG_MANAGER:-}" in
            apt-get)
                local apt_size
                apt_size=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo "未知")
                info "APT 缓存大小: $apt_size"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] 将执行: apt-get clean"
                else
                    if yes_no "清理 APT 缓存？"; then
                        sudo apt-get clean
                        success "APT 缓存已清理"
                    fi
                fi
                ;;
            dnf)
                local dnf_size
                dnf_size=$(du -sh /var/cache/dnf 2>/dev/null | awk '{print $1}' || echo "未知")
                info "DNF 缓存大小: $dnf_size"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] 将执行: dnf clean all"
                else
                    if yes_no "清理 DNF 缓存？"; then
                        sudo dnf clean all
                        success "DNF 缓存已清理"
                    fi
                fi
                ;;
            yum)
                local yum_size
                yum_size=$(du -sh /var/cache/yum 2>/dev/null | awk '{print $1}' || echo "未知")
                info "YUM 缓存大小: $yum_size"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] 将执行: yum clean all"
                else
                    if yes_no "清理 YUM 缓存？"; then
                        sudo yum clean all
                        success "YUM 缓存已清理"
                    fi
                fi
                ;;
            brew)
                if [[ "$OS_TYPE" == "darwin" ]]; then
                    local brew_size
                    brew_size=$(du -sh "$(brew --cache)" 2>/dev/null | awk '{print $1}' || echo "未知")
                    info "Homebrew 缓存大小: $brew_size"
                    if [[ "${DRY_RUN:-}" == "1" ]]; then
                        info "[dry-run] 将执行: brew cleanup --prune=all"
                    else
                        if yes_no "清理 Homebrew 缓存？"; then
                            brew cleanup --prune=all 2>/dev/null || true
                            success "Homebrew 缓存已清理"
                        fi
                    fi
                fi
                ;;
            *)
                info "未检测到已知包管理器，跳过缓存清理"
                ;;
        esac

        # 清理 pip 缓存
        if command_exists pip3 || command_exists pip; then
            local pip_cmd="pip3"
            command_exists pip3 || pip_cmd="pip"
            local pip_cache_dir
            pip_cache_dir=$($pip_cmd cache dir 2>/dev/null || echo "")
            if [[ -n "$pip_cache_dir" && -d "$pip_cache_dir" ]]; then
                local pip_size
                pip_size=$(du -sh "$pip_cache_dir" 2>/dev/null | awk '{print $1}' || echo "未知")
                info "pip 缓存大小: $pip_size ($pip_cache_dir)"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] 将执行: $pip_cmd cache purge"
                else
                    if yes_no "清理 pip 缓存？"; then
                        $pip_cmd cache purge
                        success "pip 缓存已清理"
                    fi
                fi
            fi
        fi

        # 清理 npm 缓存
        if command_exists npm; then
            local npm_cache_dir
            npm_cache_dir=$(npm config get cache 2>/dev/null || echo "")
            if [[ -n "$npm_cache_dir" && -d "$npm_cache_dir" ]]; then
                local npm_size
                npm_size=$(du -sh "$npm_cache_dir" 2>/dev/null | awk '{print $1}' || echo "未知")
                info "npm 缓存大小: $npm_size"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] 将执行: npm cache clean --force"
                else
                    if yes_no "清理 npm 缓存？"; then
                        npm cache clean --force
                        success "npm 缓存已清理"
                    fi
                fi
            fi
        fi

        # 清理 bun 缓存
        if command_exists bun; then
            local bun_cache_dir="${HOME}/.bun/install/cache"
            if [[ -d "$bun_cache_dir" ]]; then
                local bun_size
                bun_size=$(du -sh "$bun_cache_dir" 2>/dev/null | awk '{print $1}' || echo "未知")
                info "bun 缓存大小: $bun_size"
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] 将清理 $bun_cache_dir"
                else
                    if yes_no "清理 bun 缓存？"; then
                        rm -rf "${bun_cache_dir:?}"/*
                        success "bun 缓存已清理"
                    fi
                fi
            fi
        fi
        echo
    fi

    # -- 清理 Docker --
    if [[ -n "${CLEAN_DOCKER:-}" ]]; then
        header "── 清理 Docker ──"
        if ! command_exists docker; then
            warn "Docker 未安装，跳过"
        else
            if ! docker info >/dev/null 2>&1; then
                warn "Docker 服务未运行，跳过"
            else
                info "Docker 磁盘使用情况："
                docker system df 2>/dev/null || true
                echo
                if [[ "${DRY_RUN:-}" == "1" ]]; then
                    info "[dry-run] 将执行: docker system prune -af --volumes"
                else
                    if yes_no "清理 Docker 未使用的镜像、容器、网络和卷？"; then
                        docker system prune -af --volumes
                        success "Docker 垃圾已清理"
                    fi
                fi
            fi
        fi
        echo
    fi

    success "🎉 清理操作完成"
}

# ============================================================
# help
# ============================================================
usage() {
    cat <<'EOF'
用法: disk-usage {status|top|monitor|clean|help}

磁盘空间管理工具 — 查看存储概况、大文件排行、监控告警、一键清理。

子命令:
  status                     查看存储概况（默认动作）
                             显示各挂载点使用率、内存、Swap 状态

  top [路径] [--count N] [--depth D] [--min-size SIZE] [--no-interactive]
                             大文件/目录排行（路径默认 /，数量默认 10）
    --depth D                目录扫描深度（默认 1）；2 可看第二层子目录
    --min-size SIZE          只显示不小于该大小的条目（需带 K/M/G 单位，如 100M）
    --no-interactive         禁用交互（管道/CI 下自动禁用）
                             交互键位：序号=下钻  u=上一层  c=改数量  q=退出

  monitor [--threshold N]    检查使用率是否超阈值（默认 90%）
    --install                写入 crontab（每天 08:00 检查）
    --uninstall              移除 crontab 定时任务

  clean                      一键清理磁盘空间
    --logs                   清理系统日志（journal + 大日志文件）
    --cache                  清理包管理器缓存（apt/dnf/yum/brew/pip/npm/bun）
    --docker                 清理 Docker 垃圾（需已安装 Docker）
    --all                    全部清理
    --dry-run                仅预览，不执行

  help                       显示本帮助

示例:
  disk-usage status              # 查看存储概况
  disk-usage top /home           # 查看 /home 下大目录
  disk-usage top --count 20      # 查看 Top 20 大目录
  disk-usage top /var --depth 2  # 二层下钻：/var 与 /var/lib/docker 一屏可见
  disk-usage top ~ --min-size 100M  # 只看 100M 以上的大家伙
  disk-usage monitor             # 检查是否超过 90%
  disk-usage monitor --threshold 80 --install   # 安装 80% 阈值的定时监控
  disk-usage clean --all         # 全部清理
  disk-usage clean --logs --dry-run  # 预览日志清理
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
            -*)           error "未知选项: $1"; usage; exit 1 ;;
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
        *)        error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
