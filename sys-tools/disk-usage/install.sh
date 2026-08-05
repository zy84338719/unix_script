#!/usr/bin/env bash
#
# disk-usage/install.sh
#
# 磁盘空间管理工具：查看存储概况、大文件排行、监控告警、一键清理。
# 支持 Linux / macOS。
#
# 子命令：status | top | monitor | clean | help
#

set -e

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
        # Linux
        df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x squashfs 2>/dev/null \
        | awk 'NR==1 {
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
        free -h | awk 'NR==1 {printf "  %-10s %10s %10s %10s %10s %10s\n", "", "总量", "已用", "可用", "共享", "缓存"}
                        NR==2 {printf "  %-10s %10s %10s %10s %10s %10s\n", $1, $2, $3, $4, $5, $6}'
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

# ============================================================
# top - 大文件/目录排行
# ============================================================
top_disk() {
    local scan_path="${1:-/}"
    local count="${TOP_COUNT:-10}"

    if [[ ! -d "$scan_path" ]]; then
        error "路径不存在: $scan_path"
        exit 1
    fi

    header "═══════════════════════════════════════"
    header "  📊 ${scan_path} 下最大的 ${count} 个目录"
    header "═══════════════════════════════════════"
    echo

    info "正在扫描（大目录可能需要一些时间）..."
    echo

    # 大目录排行（扫描根目录时用 sudo，其他路径直接 du）
    local du_cmd="du"
    if [[ "$scan_path" == "/" ]]; then
        du_cmd="sudo du"
    fi
    if [[ "$OS_TYPE" == "darwin" ]]; then
        $du_cmd -sh "$scan_path"/* 2>/dev/null | sort -rh | head -n "$count" \
        | awk '{
            size=$1; path=""
            for(i=2;i<=NF;i++) path=path (i>2?" ":"") $i
            printf "  %10s  %s\n", size, path
        }'
    else
        $du_cmd -sh "$scan_path"/* 2>/dev/null | sort -rh | head -n "$count" \
        | awk '{
            printf "  %10s  %s\n", $1, $2
        }'
    fi
    echo

    # 大文件排行（仅扫描常见位置，避免太慢）
    header "═══════════════════════════════════════"
    header "  📄 常见位置最大的 ${count} 个文件"
    header "═══════════════════════════════════════"
    echo

    local search_paths=("/var/log" "/tmp" "/var/cache")
    if [[ "$OS_TYPE" == "darwin" ]]; then
        search_paths=("/var/log" "/tmp" "$HOME/Library/Logs" "$HOME/Library/Caches")
    fi

    local find_args=()
    for p in "${search_paths[@]}"; do
        [[ -d "$p" ]] && find_args+=("$p")
    done

    if [[ ${#find_args[@]} -gt 0 ]]; then
        find "${find_args[@]}" -type f -exec du -sh {} + 2>/dev/null \
        | sort -rh | head -n "$count" \
        | while IFS= read -r line; do
            local size path
            size=$(echo "$line" | awk '{print $1}')
            path=$(echo "$line" | awk '{print $2}')
            printf "  %10s  %s\n" "$size" "$path"
        done
    else
        echo "  未找到可扫描的路径"
    fi
    echo
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

  top [路径] [--count N]     大文件/目录排行
                             路径默认为 /，数量默认 10

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
