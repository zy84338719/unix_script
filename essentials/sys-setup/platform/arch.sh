#!/usr/bin/env bash
#
# essentials/sys-setup/platform/arch.sh — Arch 族（arch/manjaro/garuda）
# mirrorlist 按 ID + uname -m 选路径（修 aarch64 误写 archlinux 路径的 bug）：
#   arch    x86_64→archlinux           aarch64→archlinuxarm
#   manjaro x86_64→manjaro/stable      aarch64→manjaro-arm/stable
#   garuda  无把握路径，降级指引

_arch_mirror_line() {
    local m
    m=$(uname -m)
    case "$DISTRO_ID" in
        arch)
            case "$m" in
                x86_64)  echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch' ;;
                aarch64) echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$repo/os/$arch' ;;
            esac
            ;;
        manjaro)
            case "$m" in
                x86_64)  echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/manjaro/stable/$repo/$arch' ;;
                aarch64) echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/manjaro-arm/stable/$repo/$arch' ;;
            esac
            ;;
    esac
}

plat_mirror_preview() {
    case "$DISTRO_ID" in
        arch|manjaro)
            echo "  1. 备份 /etc/pacman.d/mirrorlist"
            echo "  2. 重写为清华 TUNA（${DISTRO_ID} · $(uname -m) 路径）"
            echo "  3. sudo pacman -Sy"
            ;;
        *)
            echo "  1. ${DISTRO_ID} 暂无把握的镜像路径，仅打印指引（不改动系统）"
            ;;
    esac
}

plat_mirror_apply() {
    local line ts
    line=$(_arch_mirror_line)
    ts=$(date +%s)
    if [[ -z "$line" ]]; then
        warn "${DISTRO_ID} · $(uname -m) 暂无把握的镜像路径，保持 mirrorlist 不变"
        return 0
    fi
    sudo cp -a /etc/pacman.d/mirrorlist "/etc/pacman.d/mirrorlist.bak.$ts" 2>/dev/null || true
    sudo tee /etc/pacman.d/mirrorlist >/dev/null <<EOF
# 由 unix_script sys-setup 生成 —— ${DISTRO_ID} 清华镜像（$(uname -m)）
${line}
EOF
    sudo pacman -Sy 2>/dev/null || true
    success "${DISTRO_ID} mirrorlist 已替换为清华镜像（$(uname -m) 路径）"
}

plat_autoupdate() {
    pkg_install pacman-contrib 2>/dev/null || true
    info "Arch 为滚动发布，建议定期执行 sudo pacman -Syu 保持更新"
}
