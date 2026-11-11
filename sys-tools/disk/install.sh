#!/usr/bin/env bash
# sys-tools/disk/install.sh
#
# 磁盘管理工具箱：列盘 / 分区 / 格式化 / 挂载 / fstab / SMART 健康 / 擦除签名。
# 仅 Linux。破坏性操作受三层严格护栏保护（见 _disk_guard_destructive），无 --yes 绕过。
#
# 用法: install.sh {list|wizard|partition|format|mount|umount|fstab|smart|scan|wipe|install|uninstall|status|help}
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
        warn "disk $(_tf 'Linux-only (current: %s)' "${OS_TYPE}")"
        return 1
    fi
}

_disk_require_tool() {
    local t
    for t in "$@"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            error "$(_tf 'Missing command: %s (run ./install.sh disk install)' "${t}")"
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
    info "$(_tf 'Installing %s tools: %s' "$fs" "$pkgs")"
    # shellcheck disable=SC2086  # $pkgs 为受控包名列表，需按空格拆分传参
    pkg_install $pkgs
}

# ============================================================
# 设备事实查询（纯函数，不修改系统）
# ============================================================

# 归一化设备名：sdb → /dev/sdb；校验为块设备后输出绝对路径
_disk_resolve() {
    local d="$1"
    [[ -n "$d" ]] || { error "$(_t 'No device specified')"; return 1; }
    [[ "$d" == /dev/* ]] || d="/dev/$d"
    [[ -b "$d" ]] || { error "$(_tf 'Block device does not exist: %s' "$d")"; return 1; }
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

# 占用原因检测（机器可读行 KIND|DEV|DETAIL，供详细报错与 wipe 放宽判定）：
#   MOUNT|<dev>|<挂载点>   已挂载（硬阻断，wipe 也不例外）
#   HOLD|<dev>|<holder>    被激活的内核 DM/MD 设备持有（硬阻断；未挂载的激活 LV 也算）
#   SIG|<dev>|<签名>       旧签名残留（swap/raid/lvm/bios_grub；wipe 可解除）
_DISK_SYS_BLOCK="${_DISK_SYS_BLOCK:-/sys/class/block}"

_disk_in_use_reasons() {
    local dev="$1" d rest h
    while IFS=' ' read -r d rest; do
        [[ -n "$rest" ]] && echo "MOUNT|/dev/$d|$rest"
    done < <(lsblk -rno NAME,MOUNTPOINT "$dev" 2>/dev/null)
    while IFS=' ' read -r d rest; do
        case "$rest" in
            swap|linux_raid_member|LVM2_member|bios_grub) echo "SIG|/dev/$d|$rest" ;;
        esac
    done < <(lsblk -rno NAME,FSTYPE "$dev" 2>/dev/null)
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        for h in "$_DISK_SYS_BLOCK/$d"/holders/*; do
            [[ -e "$h" ]] && echo "HOLD|/dev/$d|$(basename "$h")"
        done
    done < <(lsblk -rno NAME "$dev" 2>/dev/null)
    return 0
}

_disk_in_use() {
    [[ -n "$(_disk_in_use_reasons "$1")" ]]
}

# LVM PV 所属 VG 名（lvm2 缺失/无 root 时返回空，仅用于提示；sudo -n 复用护栏前缓存的授权）
_disk_lvm_pv_vg() {
    command -v pvs >/dev/null 2>&1 || return 0
    sudo -n pvs --noheadings -o vg_name "$1" 2>/dev/null | tr -d ' ' | head -1
    return 0
}

# 人类可读的占用详情（逐条说明谁在占用 + 解除方法）
_disk_in_use_report() {
    local dev="$1" kind rd dt vg
    while IFS='|' read -r kind rd dt; do
        case "$kind" in
            MOUNT)
                printf '  %s\n' "$(_tf '⛔ %s is mounted at %s (umount it first)' "$rd" "$dt")" ;;
            HOLD)
                printf '  %s\n' "$(_tf '⛔ %s is held by kernel device %s (LVM LV/RAID; deactivate it)' "$rd" "$dt")" ;;
            SIG)
                if [[ "$dt" == "LVM2_member" ]]; then
                    vg=$(_disk_lvm_pv_vg "$rd")
                    if [[ -n "$vg" ]]; then
                        printf '  %s\n' "$(_tf '⛔ %s is an LVM PV (VG %s, not activated)' "$rd" "$vg")"
                    else
                        printf '  %s\n' "$(_tf '⛔ %s holds an LVM PV signature (old VG leftover)' "$rd")"
                    fi
                else
                    printf '  %s\n' "$(_tf '⛔ %s holds a %s signature' "$rd" "$dt")"
                fi ;;
        esac
    done < <(_disk_in_use_reasons "$dev")
}

_disk_show_detail() {
    printf '%s\n' "$(_t 'Target device details:')"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL "$1" 2>/dev/null || true
}

# ============================================================
# 严格护栏：破坏性操作统一入口（三层，无绕过）
# ============================================================
_disk_guard_destructive() {
    local dev="$1" action="$2" allow_sig_only="${3:-0}" typed reasons
    if [[ ! -t 0 ]]; then
        error "$(_tf 'Refused: %s is destructive, interactive terminal only (no --yes bypass)' "$action")"
        return 1
    fi
    if _disk_is_protected "$dev"; then
        error "$(_tf 'Refused: %s is the system/boot/swap disk or a partition of it' "$dev")"
        return 1
    fi
    reasons=$(_disk_in_use_reasons "$dev")
    if [[ -n "$reasons" ]]; then
        if [[ "$allow_sig_only" == "1" ]] && ! grep -qE '^(MOUNT\||HOLD\|)' <<< "$reasons"; then
            # wipe 特例：无挂载、无激活占用，仅旧签名——擦签名正是解除它们的操作
            warn "$dev $(_t 'Not mounted, no holder, only old signatures (wipefs clears):')"
            _disk_in_use_report "$dev"
        else
            error "$(_tf 'Refused: %s is in use:' "$dev")"
            _disk_in_use_report "$dev"
            info "$(_t 'Hint: only old signatures left? clear them with wipe and retry')"
            return 1
        fi
    fi
    _disk_show_detail "$dev"
    read -r -p "$(_tf '⚠️  %s will erase all data on %s. Type the full device name:' "$action" "$dev") " typed
    if [[ "${typed#/dev/}" != "${dev#/dev/}" || -z "$typed" ]]; then
        error "$(_tf 'Input mismatch (expected: %s), cancelled' "${dev#/dev/}")"
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
        reasons="SMART $(_t 'overall verdict FAILED')"
    elif [[ -z "$health" ]]; then
        echo "unknown|$(_t 'Cannot read SMART data (USB bridge/RAID unsupported, or no rights)')"
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
                reasons="${reasons:+${reasons};}$(_tf 'Media errors(Media Errors)=%s' "${media}")"
            fi
            if [[ "$spare" =~ ^[0-9]+$ && "$spare_th" =~ ^[0-9]+$ ]] && (( 10#$spare < 10#$spare_th )); then
                verdict="critical"
                reasons="${reasons:+${reasons};}$(_tf 'Available spare %s%% below threshold %s%%' "${spare}" "${spare_th}")"
            fi
            if _smart_num_gt "$pct" 89; then
                [[ "$verdict" == "healthy" ]] && verdict="warning"
                reasons="${reasons:+${reasons};}$(_tf 'Lifetime used up %s%%' "${pct}")"
            fi
            ;;
        *)
            # 待定/不可修复/不可纠正 → 危险
            for id in 197 198 187; do
                raw=$(_smart_ata_raw "$a_out" "$id")
                if _smart_num_gt "$raw" 0; then
                    verdict="critical"
                    case "$id" in
                        197) reasons="${reasons:+${reasons};}$(_tf 'Pending sectors(Current_Pending)=%s' "${raw}")" ;;
                        198) reasons="${reasons:+${reasons};}$(_tf 'Uncorrectable sectors(Offline_Uncorrectable)=%s' "${raw}")" ;;
                        187) reasons="${reasons:+${reasons};}$(_tf 'Uncorrectable errors(Reported_Uncorrect)=%s' "${raw}")" ;;
                    esac
                fi
            done
            # 重映射扇区/事件 → 注意（盘在自愈）
            for id in 5 196; do
                raw=$(_smart_ata_raw "$a_out" "$id")
                if _smart_num_gt "$raw" 0; then
                    [[ "$verdict" == "healthy" ]] && verdict="warning"
                    case "$id" in
                        5)   reasons="${reasons:+${reasons};}$(_tf 'Reallocated sectors(Reallocated_Sector)=%s' "${raw}")" ;;
                        196) reasons="${reasons:+${reasons};}$(_tf 'Reallocation events(Reallocation_Event)=%s' "${raw}")" ;;
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
        healthy)  printf '%s\n' "$(_t 'Healthy')" ;;
        warning)  printf '%s\n' "$(_t 'Warning')" ;;
        critical) printf '%s\n' "$(_t 'Dangerous')" ;;
        *)        printf '%s\n' "$(_t 'Unknown')" ;;
    esac
}

# ============================================================
# 子命令实现
# ============================================================

cmd_list() {
    _linux_require || return 1
    _disk_require_tool lsblk || return 1
    info "$(_t 'Block device overview (⚠️ see the protected list below):')"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL 2>/dev/null || lsblk
    echo
    printf '%s\n' "$(_t 'Protected devices (system/boot/swap: no destructive ops):')"
    local found=false d info_line
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        found=true
        # pipefail 下 head 提前关管道会 SIGPIPE 中止（见 submenus.sh 同款注释）→ || true 兜底；
        # lsblk 对分区会连带输出祖先行，目标行在最后 → tail -1；mapper 设备直接输出原路径
        info_line=$(lsblk -rno SIZE,TYPE,FSTYPE,MOUNTPOINT "$d" 2>/dev/null | tail -1 || true)
        printf '  ⚠️  %-40s %s\n' "$d" "$info_line"
    done < <(_disk_system_devices)
    $found || echo "  $(_t '(none)')"
}

# 实际格式化（无护栏；护栏由调用方负责）
_disk_format_device() {
    local dev="$1" fs="$2"
    _disk_ensure_mkfs "$fs"
    info "$(_tf 'Formatting %s -> %s ...' "$dev" "$fs")"
    case "$fs" in
        ext4)  sudo mkfs.ext4 -F "$dev" ;;
        xfs)   sudo mkfs.xfs -f "$dev" ;;
        vfat)  sudo mkfs.vfat -F 32 "$dev" ;;
        exfat) sudo mkfs.exfat "$dev" ;;
        # -f 快速格式化（不清零全盘）
        ntfs)  sudo mkfs.ntfs -f "$dev" ;;
    esac
    sync
    # mkfs 后 udev 数据库有延迟：紧接着读 UUID（wizard 的 fstab add）可能拿到旧签名
    # 的缓存 UUID（实测 FAT→ext4 复现），settle 等待 udev 刷新
    # 注意写成 if：`A && B || true` 会触发老版 shellcheck 的 SC2015（CI 红屏根因）
    if command -v udevadm >/dev/null 2>&1; then
        sudo udevadm settle 2>/dev/null || true
    fi
}

cmd_format() {
    local dev_s="${1:-}" fs="${2:-ext4}" dev
    [[ -n "$dev_s" ]] || { error "$(_t 'Usage: format <device> [ext4|xfs|vfat|exfat|ntfs] (default ext4)')"; return 1; }
    case " $DISK_SUPPORTED_FS " in *" $fs "*) ;; *) error "$(_tf 'Unsupported file system: %s (supported: %s)' "${fs}" "${DISK_SUPPORTED_FS}")"; return 1 ;; esac
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    _disk_guard_destructive "$dev" "$(_t 'format')" || return 1
    _disk_format_device "$dev" "$fs"
    success "$(_tf 'Format complete: %s (%s),' "$dev" "$fs")UUID=$(lsblk -no UUID "$dev" 2>/dev/null | head -1)"
    echo "  $(_tf 'Next step: ./install.sh disk fstab add %s /mnt/point' "${dev}")"
}

cmd_partition() {
    local dev_s="${1:-}" dev child
    [[ -n "$dev_s" ]] || { error "$(_t 'Usage: partition <whole disk> (GPT single partition of the whole disk)')"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    _disk_require_tool parted || return 1
    require_sudo
    [[ "$(_disk_type "$dev")" == "disk" ]] || { error "$dev $(_t 'Not a whole disk (wizard/partition need a whole disk; use format)')"; return 1; }
    _disk_guard_destructive "$dev" "$(_t 'partition (clear signatures + GPT single partition)')" || return 1
    sudo wipefs -a "$dev"
    sudo parted -s "$dev" mklabel gpt mkpart primary 1MiB 100%
    sudo partprobe "$dev" 2>/dev/null || true
    sync; sleep 1
    child=$(lsblk -rno NAME,TYPE "$dev" | awk '$2=="part" {print "/dev/" $1; exit}')
    [[ -n "$child" ]] || { error "$(_t 'Partition creation failed')"; return 1; }
    success "$(_tf 'Partition complete: %s (GPT). Next: ./install.sh disk format %s ext4' "${child}" "$child")"
}

cmd_mount() {
    local dev_s="${1:-}" mp="${2:-}" persist="${3:-}" dev fs
    [[ -n "$dev_s" && -n "$mp" ]] || { error "$(_t 'Usage: mount <device> <mount point> [--fstab]')"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    if [[ "$persist" == "--fstab" ]]; then
        _disk_fstab_add "$dev" "${4:-defaults,nofail}" "$mp"
        return
    fi
    fs=$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -1)
    [[ -n "$fs" ]] || { error "$dev $(_t 'No file system signature, please run format first')"; return 1; }
    sudo mkdir -p "$mp"
    sudo mount "$dev" "$mp"
    success "$(_tf 'Mounted: %s -> %s (use --fstab or fstab add to persist)' "$dev" "${mp}")"
}

cmd_umount() {
    local target="${1:-}"
    [[ -n "$target" ]] || { error "$(_t 'Usage: umount <mount point|device>')"; return 1; }
    _linux_require || return 1
    require_sudo
    sudo umount "$target"
    success "$(_tf 'Unmounted: %s' "$target")"
    if grep -qs "[[:space:]]${target}[[:space:]]" /etc/fstab 2>/dev/null; then
        warn "$target $(_tf 'Still in fstab, mounted again after reboot; remove: fstab remove %s' "$target")"
    fi
}

cmd_fstab() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        list)   _linux_require || return 1; info "fstab $(_t 'Non-comment entries:')"; grep -v '^\s*#' /etc/fstab | grep -v '^\s*$' || true ;;
        add)    _disk_fstab_add_cmd "$@" ;;
        remove) _disk_fstab_remove "${1:-}" ;;
        *)      error "$(_t 'Usage: fstab {list|add <dev> <mount point> [opts]|remove <mount point>}')"; return 1 ;;
    esac
}

_disk_fstab_add_cmd() {
    local dev_s="${1:-}" mp="${2:-}" opt="${3:-defaults,nofail}" dev
    [[ -n "$dev_s" && -n "$mp" ]] || { error "$(_t 'Usage: fstab add <dev> <mount point> [opts] (default defaults,nofail)')"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    _disk_fstab_add "$dev" "$opt" "$mp"
}

# 实际写入 fstab：挂载验证 → 备份 → 追加 → mount -a 验证 → 失败回滚
_disk_fstab_add() {
    local dev="$1" opt="${2:-defaults,nofail}" mp="${3:-}" fs uuid ts
    [[ -n "$mp" ]] || { error "$(_t 'No mount point specified')"; return 1; }
    fs=$(lsblk -no FSTYPE "$dev" 2>/dev/null | head -1)
    [[ -n "$fs" ]] || { error "$dev $(_t 'No file system signature, please run format first')"; return 1; }
    uuid=$(lsblk -no UUID "$dev" 2>/dev/null | head -1)
    [[ -n "$uuid" ]] || { error "$(_tf 'Cannot get the UUID of %s' "$dev")"; return 1; }
    sudo mkdir -p "$mp"
    if ! findmnt -rn -o SOURCE "$mp" 2>/dev/null | grep -q "^${dev}"; then
        sudo mount "$dev" "$mp" || { error "$(_tf 'Mounting %s -> %s failed, fstab was not written' "$dev" "$mp")"; return 1; }
    fi
    ts=$(date +%s)
    sudo cp -a /etc/fstab "/etc/fstab.bak.$ts"
    echo "UUID=$uuid $mp $fs $opt 0 2" | sudo tee -a /etc/fstab >/dev/null
    if ! sudo mount -a 2>/dev/null; then
        error "mount -a $(_tf 'validation failed, fstab rolled back (backup: /etc/fstab.bak.%s)' "${ts}")"
        sudo cp -a "/etc/fstab.bak.$ts" /etc/fstab
        return 1
    fi
    success "$(_tf 'Written to fstab: UUID=%s -> %s (%s, %s), backup: /etc/fstab.bak.%s' "$uuid" "${mp}" "$fs" "${opt}" "$ts")"
}

_disk_fstab_remove() {
    local mp="${1:-}" ts
    [[ -n "$mp" ]] || { error "$(_t 'Usage: fstab remove <mount point>')"; return 1; }
    _linux_require || return 1
    require_sudo
    grep -qs "[[:space:]]${mp}[[:space:]]" /etc/fstab || { warn "fstab $(_tf 'No entry for %s in fstab' "${mp}")"; return 0; }
    ts=$(date +%s)
    sudo cp -a /etc/fstab "/etc/fstab.bak.$ts"
    sudo awk -v m="$mp" '$2 != m' /etc/fstab | sudo tee /etc/fstab.new >/dev/null
    sudo mv /etc/fstab.new /etc/fstab
    sudo mount -a 2>/dev/null || true
    success "$(_tf 'fstab entry removed: %s (backup: /etc/fstab.bak.%s)' "${mp}" "${ts}")"
}

# smartctl 统一读取：自动探测失败（提示 SAT 层，某些 SAT 层/USB 桥/虚拟化环境会出现）时
# 自动以 -d ata 重试。输出三段（-i、-H、-A），以记录分隔符 \x1e 拼接
_smartctl_read() {
    local dev="$1" i h a
    i=$(sudo smartctl -i "$dev" 2>/dev/null || true)
    if grep -qi "SAT layer" <<<"$i"; then
        i=$(sudo smartctl -i -d ata "$dev" 2>/dev/null || true)
        h=$(sudo smartctl -H -d ata "$dev" 2>/dev/null || true)
        a=$(sudo smartctl -A -d ata "$dev" 2>/dev/null || true)
    else
        h=$(sudo smartctl -H "$dev" 2>/dev/null || true)
        a=$(sudo smartctl -A "$dev" 2>/dev/null || true)
    fi
    printf '%s\x1e%s\x1e%s' "$i" "$h" "$a"
}

# 总线类型：NVMe 走 NVMe 判读，其余按 ATA（SAS 仅总评可判）
_smart_bus() {
    local i
    i=$(sudo smartctl -i "$1" 2>/dev/null || true)
    if grep -qi "SAT layer" <<<"$i"; then
        i=$(sudo smartctl -i -d ata "$1" 2>/dev/null || true)
    fi
    if grep -qi 'NVMe Version' <<<"$i"; then
        echo nvme
    else
        echo ata
    fi
}

# 单盘一行结论（概览用；机器模式输出 STATE/EXTRA）
_smart_report_one() {
    local dev="$1" raw h a vout verdict reasons model size
    raw=$(_smartctl_read "$dev")
    # 丢弃 -i 段（概览不需要设备信息）
    raw=${raw#*$'\x1e'}
    h=${raw%%$'\x1e'*}
    a=${raw#*$'\x1e'}
    vout=$(_smart_verdict "$h" "$a" "$(_smart_bus "$dev")")
    verdict=${vout%%|*}
    reasons=${vout#*|}
    if uxs_is_machine_mode; then
        emit_status "$verdict" "${dev} $(_smart_verdict_cn "$verdict")"
        emit_extra "dev=${dev##*/} model=${model} reasons=${reasons}"
    else
        model=$(lsblk -dno MODEL "$dev" 2>/dev/null | head -1 || true)
        size=$(lsblk -dno SIZE "$dev" 2>/dev/null | head -1 || true)
        local rdetail=""
        if [[ -n "$reasons" ]]; then
            rdetail="$(_tf 'SMART reason detail: (%s)' "$reasons")"
        fi
        emit_status "$verdict" "$(_smart_verdict_emoji "$verdict") ${dev##*/}  ${model:-?}  ${size:-?}  $(_smart_verdict_cn "$verdict")$rdetail"
    fi
}

# 单盘详情：设备信息 + 总评 + 关键指标 + 属性表 + 结论
_smart_report_detail() {
    local dev="$1" raw i h a vout verdict reasons temp hours
    raw=$(_smartctl_read "$dev")
    i=${raw%%$'\x1e'*}; raw=${raw#*$'\x1e'}
    h=${raw%%$'\x1e'*}; a=${raw#*$'\x1e'}
    vout=$(_smart_verdict "$h" "$a" "$(_smart_bus "$dev")")
    verdict=${vout%%|*}
    reasons=${vout#*|}
    if uxs_is_machine_mode; then
        emit_status "$verdict" "${dev}"
        emit_extra "dev=${dev##*/} reasons=${reasons}"
        return 0
    fi
    header "$(_tf '═══ SMART health check: %s ═══' "${dev}")"
    printf '%s\n' "$(_t '—— Device information ——')"
    sed -n '1,20p' <<<"$i"
    echo
    printf '%s\n' "$(_t '—— SMART overall verdict ——')"
    # 健康异常时 smartctl 退出非零是正常语义，以输出为准
    cat <<<"$h"
    echo
    printf '%s\n' "$(_t '—— Key metrics ——')"
    temp=$(_smart_ata_raw "$a" 194)
    [[ -n "$temp" ]] || temp=$(_smart_pct "$(_smart_nvme_val "$a" "Temperature:")")
    hours=$(_smart_ata_raw "$a" 9)
    [[ -n "$hours" ]] || hours=$(_smart_nvme_val "$a" "Power On Hours:")
    [[ -n "$temp" ]] && printf '%s\n' "$(_tf 'Temperature: %s°C' "${temp}")"
    [[ -n "$hours" ]] && printf '%s\n' "$(_tf 'Power on time: %s hours' "${hours}")"
    echo
    printf '%s\n' "$(_t '—— Attribute table ——')"
    cat <<<"$a"
    echo
    case "$verdict" in
        healthy)  success "$(_smart_verdict_emoji healthy) $(_t 'Conclusion: healthy — no abnormal metrics found')" ;;
        warning)  warn "$(_smart_verdict_emoji warning) $(_tf 'Conclusion: warning — %s (disk self-healing, watch trend, keep backups)' "${reasons}")" ;;
        critical) error "$(_smart_verdict_emoji critical) $(_tf 'Conclusion: dangerous — %s (back up data now, consider a new disk)' "${reasons}")" ;;
        *)        warn "$(_smart_verdict_emoji unknown) $(_tf 'Conclusion: unknown — %s' "${reasons}")" ;;
    esac
    [[ "$verdict" == "critical" ]] && return 1
    return 0
}

cmd_smart() {
    _linux_require || return 1
    if ! command -v smartctl >/dev/null 2>&1; then
        info "$(_t 'smartmontools is not installed, installing it now...')"
        pkg_install smartmontools
    fi
    require_sudo
    if [[ $# -eq 0 ]]; then
        header "SMART $(_t 'Health overview (all whole disks):')"
        local d any=false
        while IFS= read -r d; do
            any=true
            _smart_report_one "/dev/$d"
        done < <(lsblk -drno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')
        $any || warn "$(_t 'No whole disk device found')"
        return 0
    fi
    local dev_s="$1" dev
    dev=$(_disk_resolve "$dev_s") || return 1
    dev=$(_disk_base_disk "$dev")
    _smart_report_detail "$dev"
}

cmd_scan() {
    local dev_s="${1:-}" dev base size est_min bb_out badn rc
    [[ -n "$dev_s" ]] || { error "$(_t 'Usage: scan <whole disk|partition> (e.g. sdb or sdb1)')"; return 1; }
    _linux_require || return 1
    dev=$(_disk_resolve "$dev_s") || return 1
    if ! command -v badblocks >/dev/null 2>&1; then
        info "$(_t 'badblocks (e2fsprogs) is not installed, installing it now...')"
        pkg_install e2fsprogs
    fi
    require_sudo
    base=$(_disk_base_disk "$dev")
    _disk_show_detail "$dev"
    # 只读扫描不走破坏性护栏：使用中/系统盘仅警告 IO 竞争，不拒绝（不写盘，数据零风险）
    if _disk_in_use "$dev" || _disk_is_protected "$base"; then
        warn "$(_tf 'Scan is read-only, but %s is in use or a system disk: it will be slow' "${dev}")"
    fi
    size=$(lsblk -bno SIZE "$dev" 2>/dev/null | head -1 || true)
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        est_min=$(( size / 1048576 / 150 / 60 ))
        (( est_min < 1 )) && est_min=1
        info "$(_tf 'Estimated time: %s h %s min (at ~150MB/s, SSD is usually faster)' "$(( est_min / 60 ))" "$(( est_min % 60 ))")"
    fi
    header "$(_t 'Starting a read-only disk scan (badblocks). Ctrl-C stops it, rerun.')"
    bb_out=$(mktemp "${TMPDIR:-/tmp}/uxs-badblocks.XXXXXX")
    rc=0
    sudo badblocks -sv -b 4096 -o "$bb_out" "$dev" || rc=$?
    badn=$(wc -l < "$bb_out" 2>/dev/null || true)
    badn=$(printf '%s' "${badn:-0}" | tr -d '[:space:]')
    if (( badn > 0 )); then
        error "$(_tf '🔴 Found %s bad blocks! Back up data; check disk smart %s for trends' "${badn}" "${base##*/}")"
        printf '%s\n' "$(_tf 'Bad block LBA list (first 20 lines; full list: %s):' "${bb_out}")"
        head -20 "$bb_out" || true
        return 1
    elif (( rc != 0 )); then
        error "$(_tf 'The scan exited abnormally (rc=%s; bit2 = interrupted). Just rerun it' "${rc}")"
        return 1
    fi
    rm -f "$bb_out"
    success "$(_tf '✅ Disk surface is healthy: a full scan of %s found no bad blocks' "${dev}")"
}

cmd_wipe() {
    local dev_s="${1:-}" dev
    [[ -n "$dev_s" ]] || { error "$(_t 'Usage: wipe <device> (clear file system/partition table signatures)')"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    _disk_guard_destructive "$dev" "$(_t 'erase signatures (wipefs)')" 1 || return 1
    sudo wipefs -a "$dev"
    sync
    success "$(_tf 'All signatures of %s have been cleared' "$dev")"
}

cmd_wizard() {
    _linux_require || return 1
    _disk_require_tool lsblk parted || return 1
    require_sudo
    if [[ ! -t 0 ]]; then
        error "$(_t 'The wizard needs an interactive terminal (safety guard)')"
        return 1
    fi
    header "$(_t '🧙 New disk one-click wizard: partition -> format -> mount -> fstab')"
    echo "========================================"
    cmd_list || true
    local ds dev fs mp child
    read -r -p "$(_t 'Select the whole disk to bring online (e.g. sdb):') " ds
    dev=$(_disk_resolve "$ds") || return 1
    [[ "$(_disk_type "$dev")" == "disk" ]] || { error "$dev $(_t 'Not a whole disk, the wizard needs a whole disk (use format)')"; return 1; }
    _disk_guard_destructive "$dev" "$(_t 'new disk wizard (partition+format)')" || return 1
    read -r -p "$(_tf 'File system [%s] (press Enter for ext4):' "$DISK_SUPPORTED_FS") " fs
    fs=${fs:-ext4}
    case " $DISK_SUPPORTED_FS " in *" $fs "*) ;; *) error "$(_tf 'Unsupported file system: %s' "$fs")"; return 1 ;; esac
    read -r -p "$(_tf 'Mount point (press Enter for /mnt/%s):' "${ds}") " mp
    mp=${mp:-/mnt/${ds}}
    case "$mp" in /*) ;; *) error "$(_tf 'The mount point must be an absolute path: %s' "$mp")"; return 1 ;; esac

    info "$(_t '① Partition (GPT single partition of the whole disk)...')"
    sudo wipefs -a "$dev"
    sudo parted -s "$dev" mklabel gpt mkpart primary 1MiB 100%
    sudo partprobe "$dev" 2>/dev/null || true
    sync; sleep 1
    child=$(lsblk -rno NAME,TYPE "$dev" | awk '$2=="part" {print "/dev/" $1; exit}')
    [[ -n "$child" ]] || { error "$(_t 'Partition creation failed, the wizard aborts')"; return 1; }

    info "$(_tf '② Format %s -> %s ...' "$child" "$fs")"
    _disk_format_device "$child" "$fs"

    info "$(_t '③ Mount + write fstab + verify ...')"
    if ! _disk_fstab_add "$child" "defaults,nofail" "$mp"; then
        warn "$(_tf 'Done, but fstab not written. Add manually: disk fstab add %s %s' "$child" "$mp")"
        return 1
    fi
    echo
    success "$(_tf '🎉 New disk is online: %s (%s) -> %s (persisted, auto-mounted)' "$child" "$fs" "${mp}")"
}

cmd_install() {
    _linux_require || return 1
    detect_pkg_manager || { error "$(_t 'Cannot detect the package manager')"; return 1; }
    require_sudo
    info "$(_t '🚀 Installing the disk toolbox dependencies (parted/xfsprogs/...)...')"
    pkg_install parted xfsprogs dosfstools exfatprogs ntfs-3g smartmontools \
        || { warn "$(_t 'Install by package name failed, trying the exfat-utils fallback...')"; pkg_install exfat-utils; }
    success "$(_t 'Disk toolbox dependencies installed')"
    echo "  $(_t 'Available: ./install.sh disk list | wizard | format | fstab | smart ...')"
}

cmd_uninstall() {
    _linux_require || return 1
    detect_pkg_manager || true
    warn "uninstall $(_t 'Only removes the helper tools this module installed')"
    warn "$(_t 'It will not touch any disk data, mounts or fstab')"
    if ! yes_no "$(_t 'Confirm uninstalling these tool packages?')"; then
        info "$(_t 'Cancelled')"
        return 0
    fi
    # e2fsprogs 是系统基础包，不参与卸载
    pkg_remove parted xfsprogs dosfstools exfatprogs ntfs-3g smartmontools 2>/dev/null \
        || pkg_remove parted xfsprogs dosfstools ntfs-3g smartmontools 2>/dev/null \
        || warn "$(_t 'Some packages could not be removed (not installed or needed); system OK')"
    success "$(_t 'Disk toolbox helper tools uninstalled')"
}

cmd_status() {
    detect_os
    if [[ "$OS_TYPE" != "linux" ]]; then
        emit_status "n/a" "disk $(_tf 'Linux-only (current: %s)' "${OS_TYPE}")"
        return 0
    fi
    local miss_tools="" t opt_missing="" disks=0
    for t in lsblk parted; do
        command -v "$t" >/dev/null 2>&1 || miss_tools="$miss_tools$t "
    done
    command -v mkfs.ext4 >/dev/null 2>&1 || miss_tools="$miss_tools mkfs.ext4"
    if [[ -n "$miss_tools" ]]; then
        emit_status "not_installed" "$(_tf '⚠️  Disk toolbox dependencies missing: %s (run disk install)' "${miss_tools}")"
        emit_extra "missing=${miss_tools// /,}"
        return 0
    fi
    for t in smartctl mkfs.xfs mkfs.vfat mkfs.exfat mkfs.ntfs; do
        command -v "$t" >/dev/null 2>&1 || opt_missing="$opt_missing$t,"
    done
    disks=$(lsblk -drno TYPE 2>/dev/null | grep -c '^disk$' || true)
    emit_status "installed" "$(_tf '✅ Disk toolbox is ready (%s whole disks)' "${disks}")"
    # 不 emit_version：工具箱无版本概念；输出 VERSION=n/a 会污染 status --json（拼成 disk:installed:n/a）
    emit_extra "disks=$disks"
    if [[ -n "$opt_missing" ]]; then
        emit_extra "optional_missing=${opt_missing%,}"
        if [[ "${UXS_STATUS_MODE:-human}" == "human" ]]; then
            warn "$(_tf 'Optional tools not installed: %s (auto-installed on first use)' "${opt_missing%,}")"
        fi
    fi
    return 0
}

usage() {
    cat <<EOF
$(_t 'Disk toolbox (Linux only): partition/format/mount/fstab/SMART/erase')

用法: install.sh {list|wizard|partition|format|mount|umount|fstab|smart|scan|wipe|install|uninstall|status|help}

  list                          $(_t 'List block devices and protected devices (default action)')
  wizard                        $(_t 'New disk wizard: partition -> format -> mount -> fstab (interactive)')
  partition <$(_t 'whole disk')>              $(_t 'GPT single partition of the whole disk (signatures cleared first)')
  format <$(_t 'disk device')> [$(_t 'file system type')]          $(_t 'Format: ext4 (default)/xfs/vfat/exfat/ntfs')
  mount <$(_t 'disk device')> <$(_t 'mount point')> [--fstab]  $(_t 'Mount (--fstab also persists it)')
  umount <$(_t 'mount point or device')>          $(_t 'Unmount')
  fstab list|add|remove         fstab $(_t 'management (UUID based, backs up before writing and verifies after)')
  smart [$(_t 'whole disk')]                  SMART $(_t 'health check (no arg = all disks overview; one disk = details)')
  scan <$(_t 'whole disk or partition')>              $(_t 'Read-only bad block scan (badblocks does not write, may take hours)')
  wipe <$(_t 'disk device')>                   $(_t 'Clear file system/partition table signatures (wipefs)')
  install                       $(_t 'Install the missing dependency tools')
  uninstall                     $(_t 'Remove the helper tools (does not touch disk data)')
  status                        $(_t 'View status (machine readable: UXS_STATUS_MODE=machine)')

$(_t '⚠️  Safety guard (strict, no --yes bypass):')
  · $(_t 'Root/boot/EFI/swap disks and devices in use are hard-rejected')
  · $(_t 'Destructive ops need an interactive terminal and the typed device name')
  · $(_t 'fstab is backed up before writing; a failed mount -a rolls back')
  · $(_t 'smart/scan are read-only checks: no disk writes, scan only warns')
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
        scan)      cmd_scan "$@" ;;
        wipe)      cmd_wipe "$@" ;;
        install)   cmd_install ;;
        uninstall) cmd_uninstall ;;
        status)    cmd_status ;;
        help|-h|--help) usage ;;
        *) usage; error "$(_tf 'Unknown disk subcommand: %s' "$cmd")"; return 1 ;;
    esac
}

# 仅直接执行时进入分发；被 source（单测复用纯函数）时不执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
