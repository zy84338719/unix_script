#!/usr/bin/env bash
# sys-tools/disk/install.sh
#
# 磁盘管理工具箱：列盘 / 分区 / 格式化 / 挂载 / fstab / SMART 健康 / 擦除签名。
# 仅 Linux。破坏性操作受三层严格护栏保护（见 _disk_guard_destructive），无 --yes 绕过。
#
# 用法: install.sh {list|wizard|partition|format|mount|umount|fstab|smart|wipe|install|uninstall|status|help}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

readonly DISK_SUPPORTED_FS="ext4 xfs vfat exfat ntfs"

# ============================================================
# 平台与依赖
# ============================================================

_linux_require() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        warn "disk 仅支持 Linux（当前：${OS_TYPE}）"
        return 1
    fi
}

_disk_require_tool() {
    local t
    for t in "$@"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            error "缺少命令: ${t}（可运行: ./install.sh disk install 补装依赖）"
            return 1
        fi
    done
}

# 文件系统 → mkfs 工具映射，缺失时自动补装对应包
_disk_ensure_mkfs() {
    local fs="$1" pkgs=""
    case "$fs" in
        ext4)  command -v mkfs.ext4  >/dev/null 2>&1 && return 0; pkgs="e2fsprogs" ;;
        xfs)   command -v mkfs.xfs   >/dev/null 2>&1 && return 0; pkgs="xfsprogs" ;;
        vfat)  command -v mkfs.vfat  >/dev/null 2>&1 && return 0; pkgs="dosfstools" ;;
        exfat) command -v mkfs.exfat >/dev/null 2>&1 && return 0
               pkgs="exfatprogs"
               # 老发行版（apt 无 exfatprogs）兜底 exfat-fuse + exfat-utils
               if command -v apt-get >/dev/null 2>&1; then
                   if ! apt-cache show exfatprogs >/dev/null 2>&1; then
                       pkgs="exfat-fuse exfat-utils"
                   fi
               fi
               ;;
        ntfs)  command -v mkfs.ntfs  >/dev/null 2>&1 && return 0; pkgs="ntfs-3g" ;;
    esac
    info "补装 $fs 工具: $pkgs"
    # shellcheck disable=SC2086  # $pkgs 为受控包名列表，需按空格拆分传参
    pkg_install $pkgs
}

# ============================================================
# 设备事实查询（纯函数，不修改系统）
# ============================================================

# 归一化设备名：sdb → /dev/sdb；校验为块设备后输出绝对路径
_disk_resolve() {
    local d="$1"
    [[ -n "$d" ]] || { error "未指定设备"; return 1; }
    [[ "$d" == /dev/* ]] || d="/dev/$d"
    [[ -b "$d" ]] || { error "块设备不存在: $d"; return 1; }
    echo "$d"
}

_disk_type() { lsblk -no TYPE "$1" 2>/dev/null | head -1; }

# 系统关键设备（根/启动/EFI/激活 swap），每行一个，btrfs subvol 后缀已剥离
_disk_system_devices() {
    local m
    for m in / /boot /boot/efi; do
        findmnt -rn -o SOURCE "$m" 2>/dev/null || true
    done | sed 's/\[.*\]//' | sort -u
    swapon --show=NAME --noheadings 2>/dev/null || true
}

# 设备所属整盘：分区 → 父盘；整盘 → 自身
_disk_base_disk() {
    local parent
    parent=$(lsblk -no PKNAME "$1" 2>/dev/null | head -1)
    if [[ -n "$parent" ]]; then echo "/dev/$parent"; else echo "$1"; fi
}

# 0 = 受保护（系统/启动/swap 所在的设备或其整盘）
_disk_is_protected() {
    local dev="$1" base sysd
    base=$(_disk_base_disk "$dev")
    while IFS= read -r sysd; do
        [[ -z "$sysd" ]] && continue
        [[ "$(_disk_base_disk "$sysd")" == "$base" ]] && return 0
    done < <(_disk_system_devices)
    return 1
}

# 0 = 使用中（已挂载 / swap 签名 / raid·lvm 成员）
_disk_in_use() {
    local dev="$1"
    lsblk -rno MOUNTPOINT "$dev" 2>/dev/null | grep -q '[^[:space:]]' && return 0
    lsblk -rno FSTYPE "$dev" 2>/dev/null | grep -Eq 'swap|linux_raid_member|LVM2_member|bios_grub' && return 0
    return 1
}

_disk_show_detail() {
    echo "目标设备详情："
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL "$1" 2>/dev/null || true
}

# ============================================================
# 严格护栏：破坏性操作统一入口（三层，无绕过）
# ============================================================
_disk_guard_destructive() {
    local dev="$1" action="$2" typed
    if [[ ! -t 0 ]]; then
        error "拒绝：$action 属破坏性操作，仅允许在交互终端执行（安全护栏，无 --yes 跳过）"
        return 1
    fi
    if _disk_is_protected "$dev"; then
        error "拒绝：$dev 是系统/启动/swap 所在盘或其分区，禁止破坏性操作"
        return 1
    fi
    if _disk_in_use "$dev"; then
        error "拒绝：$dev 正在使用中（已挂载 / swap / raid·lvm 成员），请先 umount / swapoff / 停 raid"
        return 1
    fi
    _disk_show_detail "$dev"
    read -r -p "⚠️  $action 将清除 $dev 上的全部数据。请输入完整设备名（如 sdb 或 sdb1）确认: " typed
    if [[ "${typed#/dev/}" != "${dev#/dev/}" || -z "$typed" ]]; then
        error "输入不一致（期望: ${dev#/dev/}），已取消"
        return 1
    fi
}

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

# ============================================================
# 子命令实现
# ============================================================

cmd_list() {
    _linux_require || return 1
    _disk_require_tool lsblk || return 1
    info "块设备一览（⚠️ 行见下方受保护清单）："
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL 2>/dev/null || lsblk
    echo
    echo "受保护设备（系统/启动/swap 相关，禁止破坏性操作）："
    local found=false d info_line
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        found=true
        # pipefail 下 head 提前关管道会 SIGPIPE 中止（见 submenus.sh 同款注释）→ || true 兜底；
        # lsblk 对分区会连带输出祖先行，目标行在最后 → tail -1；mapper 设备直接输出原路径
        info_line=$(lsblk -rno SIZE,TYPE,FSTYPE,MOUNTPOINT "$d" 2>/dev/null | tail -1 || true)
        printf '  ⚠️  %-40s %s\n' "$d" "$info_line"
    done < <(_disk_system_devices)
    $found || echo "  （无）"
}

# 实际格式化（无护栏；护栏由调用方负责）
_disk_format_device() {
    local dev="$1" fs="$2"
    _disk_ensure_mkfs "$fs"
    info "格式化 $dev → $fs ..."
    case "$fs" in
        ext4)  sudo mkfs.ext4 -F "$dev" ;;
        xfs)   sudo mkfs.xfs -f "$dev" ;;
        vfat)  sudo mkfs.vfat -F 32 "$dev" ;;
        exfat) sudo mkfs.exfat "$dev" ;;
        ntfs)  sudo mkfs.ntfs -f "$dev" ;;   # -f 快速格式化（不清零全盘）
    esac
    sync
    # mkfs 后 udev 数据库有延迟：紧接着读 UUID（wizard 的 fstab add）可能拿到旧签名
    # 的缓存 UUID（实测 FAT→ext4 复现），settle 等待 udev 刷新
    command -v udevadm >/dev/null 2>&1 && sudo udevadm settle 2>/dev/null || true
}

cmd_format() {
    local dev_s="${1:-}" fs="${2:-ext4}" dev
    [[ -n "$dev_s" ]] || { error "用法: format <设备> [ext4|xfs|vfat|exfat|ntfs]（默认 ext4）"; return 1; }
    case " $DISK_SUPPORTED_FS " in *" $fs "*) ;; *) error "不支持的文件系统: ${fs}（支持: ${DISK_SUPPORTED_FS}）"; return 1 ;; esac
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    _disk_guard_destructive "$dev" "格式化" || return 1
    _disk_format_device "$dev" "$fs"
    success "格式化完成: $dev ($fs)，UUID=$(lsblk -no UUID "$dev" 2>/dev/null | head -1)"
    echo "  下一步: ./install.sh disk fstab add ${dev} /mnt/point"
}

cmd_partition() {
    local dev_s="${1:-}" dev child
    [[ -n "$dev_s" ]] || { error "用法: partition <整盘>（GPT 单分区全盘）"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    _disk_require_tool parted || return 1
    require_sudo
    [[ "$(_disk_type "$dev")" == "disk" ]] || { error "$dev 不是整盘（向导/分区只接受整盘，分区请直接 format）"; return 1; }
    _disk_guard_destructive "$dev" "分区（清签名 + GPT 单分区）" || return 1
    sudo wipefs -a "$dev"
    sudo parted -s "$dev" mklabel gpt mkpart primary 1MiB 100%
    sudo partprobe "$dev" 2>/dev/null || true
    sync; sleep 1
    child=$(lsblk -rno NAME,TYPE "$dev" | awk '$2=="part" {print "/dev/" $1; exit}')
    [[ -n "$child" ]] || { error "分区创建失败"; return 1; }
    success "分区完成: ${child}（GPT）。下一步: ./install.sh disk format $child ext4"
}

cmd_mount() {
    local dev_s="${1:-}" mp="${2:-}" persist="${3:-}" dev fs
    [[ -n "$dev_s" && -n "$mp" ]] || { error "用法: mount <设备> <挂载点> [--fstab]"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    if [[ "$persist" == "--fstab" ]]; then
        _disk_fstab_add "$dev" "${4:-defaults,nofail}" "$mp"
        return
    fi
    fs=$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -1)
    [[ -n "$fs" ]] || { error "$dev 无文件系统签名，请先 format"; return 1; }
    sudo mkdir -p "$mp"
    sudo mount "$dev" "$mp"
    success "已挂载: $dev → ${mp}（持久化请用 --fstab 或 fstab add）"
}

cmd_umount() {
    local target="${1:-}"
    [[ -n "$target" ]] || { error "用法: umount <挂载点|设备>"; return 1; }
    _linux_require || return 1
    require_sudo
    sudo umount "$target"
    success "已卸载: $target"
    if grep -qs "[[:space:]]${target}[[:space:]]" /etc/fstab 2>/dev/null; then
        warn "$target 仍在 fstab 中，重启后会重新挂载；如需移除: ./install.sh disk fstab remove $target"
    fi
}

cmd_fstab() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)   _linux_require || return 1; info "fstab 非注释条目："; grep -v '^\s*#' /etc/fstab | grep -v '^\s*$' || true ;;
        add)    _disk_fstab_add_cmd "$@" ;;
        remove) _disk_fstab_remove "${1:-}" ;;
        *)      error "用法: fstab {list|add <设备> <挂载点> [选项]|remove <挂载点>}"; return 1 ;;
    esac
}

_disk_fstab_add_cmd() {
    local dev_s="${1:-}" mp="${2:-}" opt="${3:-defaults,nofail}" dev
    [[ -n "$dev_s" && -n "$mp" ]] || { error "用法: fstab add <设备> <挂载点> [选项]（默认 defaults,nofail）"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    _disk_fstab_add "$dev" "$opt" "$mp"
}

# 实际写入 fstab：挂载验证 → 备份 → 追加 → mount -a 验证 → 失败回滚
_disk_fstab_add() {
    local dev="$1" opt="${2:-defaults,nofail}" mp="${3:-}" fs uuid ts
    [[ -n "$mp" ]] || { error "未指定挂载点"; return 1; }
    fs=$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -1)
    [[ -n "$fs" ]] || { error "$dev 无文件系统签名，请先 format"; return 1; }
    uuid=$(lsblk -no UUID "$dev" 2>/dev/null | head -1)
    [[ -n "$uuid" ]] || { error "无法获取 $dev 的 UUID"; return 1; }
    sudo mkdir -p "$mp"
    if ! findmnt -rn -o SOURCE "$mp" 2>/dev/null | grep -q "^${dev}"; then
        sudo mount "$dev" "$mp" || { error "挂载 $dev → $mp 失败，fstab 未写入"; return 1; }
    fi
    ts=$(date +%s)
    sudo cp -a /etc/fstab "/etc/fstab.bak.$ts"
    echo "UUID=$uuid $mp $fs $opt 0 2" | sudo tee -a /etc/fstab >/dev/null
    if ! sudo mount -a 2>/dev/null; then
        error "mount -a 验证失败，已回滚 fstab（备份: /etc/fstab.bak.${ts}）"
        sudo cp -a "/etc/fstab.bak.$ts" /etc/fstab
        return 1
    fi
    success "已写入 fstab: UUID=$uuid → ${mp}（$fs, ${opt}），备份: /etc/fstab.bak.$ts"
}

_disk_fstab_remove() {
    local mp="${1:-}" ts
    [[ -n "$mp" ]] || { error "用法: fstab remove <挂载点>"; return 1; }
    _linux_require || return 1
    require_sudo
    grep -qs "[[:space:]]${mp}[[:space:]]" /etc/fstab || { warn "fstab 中没有 ${mp} 的条目"; return 0; }
    ts=$(date +%s)
    sudo cp -a /etc/fstab "/etc/fstab.bak.$ts"
    sudo awk -v m="$mp" '$2 != m' /etc/fstab | sudo tee /etc/fstab.new >/dev/null
    sudo mv /etc/fstab.new /etc/fstab
    sudo mount -a 2>/dev/null || true
    success "已移除 fstab 条目: ${mp}（备份: /etc/fstab.bak.${ts}）"
}

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
    local dev="$1" h a vout verdict reasons model size
    h=$(sudo smartctl -H "$dev" 2>/dev/null || true)
    a=$(sudo smartctl -A "$dev" 2>/dev/null || true)
    vout=$(_smart_verdict "$h" "$a" "$(_smart_bus "$dev")")
    verdict=${vout%%|*}
    reasons=${vout#*|}
    if uxs_is_machine_mode; then
        emit_status "$verdict" "${dev} $(_smart_verdict_cn "$verdict")"
        emit_extra "dev=${dev##*/} model=${model} reasons=${reasons}"
    else
        model=$(lsblk -dno MODEL "$dev" 2>/dev/null | head -1 || true)
        size=$(lsblk -dno SIZE "$dev" 2>/dev/null | head -1 || true)
        emit_status "$verdict" "$(_smart_verdict_emoji "$verdict") ${dev##*/}  ${model:-?}  ${size:-?}  $(_smart_verdict_cn "$verdict")${reasons:+（${reasons}）}"
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

cmd_wipe() {
    local dev_s="${1:-}" dev
    [[ -n "$dev_s" ]] || { error "用法: wipe <设备>（清文件系统/分区表签名）"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    _disk_guard_destructive "$dev" "擦除签名（wipefs）" || return 1
    sudo wipefs -a "$dev"
    sync
    success "已清除 $dev 的所有签名"
}

cmd_wizard() {
    _linux_require || return 1
    _disk_require_tool lsblk parted || return 1
    require_sudo
    if [[ ! -t 0 ]]; then
        error "向导需要交互终端（安全护栏）"
        return 1
    fi
    header "🧙 新盘一键上线向导：分区 → 格式化 → 挂载 → fstab"
    echo "========================================"
    cmd_list || true
    local ds dev fs mp child
    read -r -p "选择要上线的整盘（如 sdb）: " ds
    dev=$(_disk_resolve "$ds") || return 1
    [[ "$(_disk_type "$dev")" == "disk" ]] || { error "$dev 不是整盘，向导只接受整盘（分区请直接用 format）"; return 1; }
    _disk_guard_destructive "$dev" "新盘向导（分区+格式化）" || return 1
    read -r -p "文件系统 [$DISK_SUPPORTED_FS]（回车=ext4）: " fs
    fs=${fs:-ext4}
    case " $DISK_SUPPORTED_FS " in *" $fs "*) ;; *) error "不支持的文件系统: $fs"; return 1 ;; esac
    read -r -p "挂载点（回车=/mnt/${ds}）: " mp
    mp=${mp:-/mnt/${ds}}
    case "$mp" in /*) ;; *) error "挂载点必须是绝对路径: $mp"; return 1 ;; esac

    info "① 分区（GPT 单分区全盘）..."
    sudo wipefs -a "$dev"
    sudo parted -s "$dev" mklabel gpt mkpart primary 1MiB 100%
    sudo partprobe "$dev" 2>/dev/null || true
    sync; sleep 1
    child=$(lsblk -rno NAME,TYPE "$dev" | awk '$2=="part" {print "/dev/" $1; exit}')
    [[ -n "$child" ]] || { error "分区创建失败，向导中止"; return 1; }

    info "② 格式化 $child → $fs ..."
    _disk_format_device "$child" "$fs"

    info "③ 挂载 + 写 fstab + 验证 ..."
    if ! _disk_fstab_add "$child" "defaults,nofail" "$mp"; then
        warn "分区与格式化已完成，但 fstab 未写入。可手动补: ./install.sh disk fstab add $child $mp"
        return 1
    fi
    echo
    success "🎉 新盘上线完成: $child ($fs) → ${mp}（已持久化，重启自动挂载）"
}

cmd_install() {
    _linux_require || return 1
    detect_pkg_manager || { error "无法识别包管理器"; return 1; }
    require_sudo
    info "🚀 安装磁盘管理工具箱依赖（parted/xfsprogs/dosfstools/exfatprogs/ntfs-3g/smartmontools）..."
    pkg_install parted xfsprogs dosfstools exfatprogs ntfs-3g smartmontools \
        || { warn "按包名安装失败（老发行版 exfat 包名不同），尝试兜底 exfat-utils..."; pkg_install exfat-utils; }
    success "磁盘管理工具箱依赖安装完成"
    echo "  可用: ./install.sh disk list | wizard | format | fstab | smart ..."
}

cmd_uninstall() {
    _linux_require || return 1
    detect_pkg_manager || true
    warn "uninstall 仅移除本模块安装的辅助工具（parted xfsprogs dosfstools exfatprogs ntfs-3g smartmontools）"
    warn "不会触碰任何磁盘数据、挂载与 fstab"
    if ! yes_no "确认卸载这些工具包？"; then
        info "已取消"
        return 0
    fi
    # e2fsprogs 是系统基础包，不参与卸载
    pkg_remove parted xfsprogs dosfstools exfatprogs ntfs-3g smartmontools 2>/dev/null \
        || pkg_remove parted xfsprogs dosfstools ntfs-3g smartmontools 2>/dev/null \
        || warn "部分包未能移除（可能未安装或被其他软件依赖），不影响系统"
    success "磁盘管理工具箱辅助工具已卸载"
}

cmd_status() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "disk 仅支持 Linux（当前：${OS_TYPE}）"
        return 0
    fi
    local miss_tools="" t opt_missing="" disks=0
    for t in lsblk parted; do
        command -v "$t" >/dev/null 2>&1 || miss_tools="$miss_tools$t "
    done
    command -v mkfs.ext4 >/dev/null 2>&1 || miss_tools="$miss_tools mkfs.ext4"
    if [[ -n "$miss_tools" ]]; then
        emit_status "not_installed" "⚠️  磁盘工具箱依赖缺失:${miss_tools}（运行 ./install.sh disk install 补齐）"
        emit_extra "missing=${miss_tools// /,}"
        return 0
    fi
    for t in smartctl mkfs.xfs mkfs.vfat mkfs.exfat mkfs.ntfs; do
        command -v "$t" >/dev/null 2>&1 || opt_missing="$opt_missing$t,"
    done
    disks=$(lsblk -drno TYPE 2>/dev/null | grep -c '^disk$' || true)
    emit_status "installed" "✅ 磁盘管理工具箱就绪（${disks} 块整盘）"
    emit_version "n/a"
    emit_extra "disks=$disks"
    if [[ -n "$opt_missing" ]]; then
        emit_extra "optional_missing=${opt_missing%,}"
        if [[ "${UXS_STATUS_MODE:-human}" == "human" ]]; then
            warn "可选工具未安装:${opt_missing%,}（对应功能首次使用时会自动补装）"
        fi
    fi
    return 0
}

usage() {
    cat <<EOF
磁盘管理工具箱（仅 Linux）：分区 / 格式化 / 挂载 / fstab / SMART / 擦除签名

用法: install.sh {list|wizard|partition|format|mount|umount|fstab|smart|wipe|install|uninstall|status|help}

  list                          列出块设备与受保护设备（默认动作）
  wizard                        新盘一键上线：分区→格式化→挂载→fstab（交互）
  partition <整盘>              GPT 单分区全盘（先清签名）
  format <设备> [类型]          格式化：ext4(默认)/xfs/vfat/exfat/ntfs
  mount <设备> <挂载点> [--fstab]  挂载（--fstab 同时持久化）
  umount <挂载点|设备>          卸载
  fstab list|add|remove         fstab 管理（UUID 方式，写前备份写后验证）
  smart [整盘]                  SMART 健康体检（无参=全部整盘概览；单盘=详情+判读）
  wipe <设备>                   清除文件系统/分区表签名（wipefs）
  install                       补装依赖工具
  uninstall                     移除辅助工具（不碰磁盘数据）
  status                        查看状态（机器可读: UXS_STATUS_MODE=machine）

⚠️  安全护栏（严格，无 --yes 绕过）：
  · 根盘/启动盘/EFI/swap 及其所在整盘硬拒绝，使用中设备硬拒绝
  · 破坏性操作仅限交互终端，且需手动输入完整设备名确认
  · fstab 写入前自动备份，mount -a 验证失败自动回滚
  · smart/scan 为只读体检：不写盘，scan 对使用中设备仅警告不拒绝
EOF
}

main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        list)      cmd_list "$@" ;;
        wizard)    cmd_wizard "$@" ;;
        partition) cmd_partition "$@" ;;
        format)    cmd_format "$@" ;;
        mount)     cmd_mount "$@" ;;
        umount|unmount) cmd_umount "$@" ;;
        fstab)     cmd_fstab "$@" ;;
        smart)     cmd_smart "$@" ;;
        wipe)      cmd_wipe "$@" ;;
        install)   cmd_install ;;
        uninstall) cmd_uninstall ;;
        status)    cmd_status ;;
        help|-h|--help) usage ;;
        *) usage; error "未知子命令: $cmd"; return 1 ;;
    esac
}

# 允许单测 source 本文件只取纯函数；直接执行时照常入口
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
