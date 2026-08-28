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
    # 注意写成 if：`A && B || true` 会触发老版 shellcheck 的 SC2015（CI 红屏根因）
    if command -v udevadm >/dev/null 2>&1; then
        sudo udevadm settle 2>/dev/null || true
    fi
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

cmd_smart() {
    local dev_s="${1:-}" dev base
    [[ -n "$dev_s" ]] || { error "用法: smart <整盘>（如 sda）"; return 1; }
    dev=$(_disk_resolve "$dev_s") || return 1
    _linux_require || return 1
    require_sudo
    if ! command -v smartctl >/dev/null 2>&1; then
        info "未安装 smartmontools，正在补装..."
        pkg_install smartmontools
    fi
    base=$(_disk_base_disk "$dev")
    header "SMART 健康总评（${base}）："
    sudo smartctl -H "$base" || true   # 健康异常时 smartctl 退出非零是正常语义，以输出为准
    echo
    sudo smartctl -A "$base" || true
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
    local missing="" t opt_missing="" disks=0
    for t in lsblk parted; do
        command -v "$t" >/dev/null 2>&1 || missing="$missing$t "
    done
    command -v mkfs.ext4 >/dev/null 2>&1 || missing="$missing mkfs.ext4"
    if [[ -n "$missing" ]]; then
        emit_status "not_installed" "⚠️  磁盘工具箱依赖缺失:${missing}（运行 ./install.sh disk install 补齐）"
        emit_extra "missing=${missing// /,}"
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
  smart <整盘>                  SMART 健康检查（缺 smartmontools 自动补装）
  wipe <设备>                   清除文件系统/分区表签名（wipefs）
  install                       补装依赖工具
  uninstall                     移除辅助工具（不碰磁盘数据）
  status                        查看状态（机器可读: UXS_STATUS_MODE=machine）

⚠️  安全护栏（严格，无 --yes 绕过）：
  · 根盘/启动盘/EFI/swap 及其所在整盘硬拒绝，使用中设备硬拒绝
  · 破坏性操作仅限交互终端，且需手动输入完整设备名确认
  · fstab 写入前自动备份，mount -a 验证失败自动回滚
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

main "$@"
