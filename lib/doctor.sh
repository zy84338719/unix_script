#!/usr/bin/env bash
#
# lib/doctor.sh
#
# 环境诊断：检查运行 unix_script 所需的前提条件。
#

# 幂等保护
if [[ -n "${_DOCTOR_SH_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_DOCTOR_SH_LOADED=1

run_doctor() {
    local issues=0

    header "🔍 unix_script 环境诊断"
    echo "=========================================="
    echo

    # Bash version
    info "检查 Bash 版本..."
    local bash_ver
    bash_ver=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local bash_major="${bash_ver%%.*}"
    if (( bash_major >= 4 )); then
        success "Bash $bash_ver ✓"
    else
        warn "Bash ${bash_ver}（建议 4.0+，部分功能可能受限）"
        ((issues++))
    fi

    # Essential commands
    info "检查必要工具..."
    local cmd
    for cmd in curl tar git sudo; do
        if command_exists "$cmd"; then
            success "$cmd ✓"
        else
            error "$cmd ✗（缺失）"
            ((issues++))
        fi
    done

    # Optional tools
    info "检查可选工具..."
    for cmd in shellcheck jq; do
        if command_exists "$cmd"; then
            success "$cmd ✓"
        else
            warn "$cmd 未安装（可选）"
        fi
    done

    # OS detection
    echo
    info "系统信息..."
    detect_os
    detect_arch
    success "操作系统：$OS_TYPE ($OS_KERNEL)"
    success "CPU 架构：$ARCH_TYPE"

    # Distro detection（发行版识别，覆盖麒麟/统信/openEuler 等国产系统）
    detect_distro
    if [[ -n "$DISTRO_ID" ]]; then
        success "发行版：$DISTRO_NAME（ID=$DISTRO_ID 版本=${DISTRO_VERSION_ID:-未知}，${DISTRO_FAMILY} 系）"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "macOS 不适用发行版检测（已跳过）"
    else
        warn "未能识别发行版（缺少 /etc/os-release，包系族按包管理器判定）"
    fi

    # Desktop detection（桌面环境：麒麟桌面 UKUI / 统信·深度 DDE / GNOME / KDE 等）
    detect_desktop
    if [[ "$IS_DESKTOP" == 1 ]]; then
        success "桌面环境：${DESKTOP_ENV}（桌面系统）"
    else
        info "桌面环境：无（服务器/CLI 环境）"
    fi

    # Package manager
    info "检查包管理器..."
    detect_pkg_manager
    if [[ -n "${PKG_MANAGER:-}" ]]; then
        success "包管理器：$PKG_MANAGER"
    else
        error "未检测到支持的包管理器"
        ((issues++))
    fi

    # Disk space
    echo
    info "检查磁盘空间..."
    local avail
    if [[ "$OS_TYPE" == "darwin" ]]; then
        avail=$(df -g / | awk 'NR==2{print $4}')
    else
        avail=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    fi
    if (( avail >= 1 )); then
        success "可用空间：${avail}GB ✓"
    else
        warn "可用空间不足：${avail}GB（建议至少 1GB）"
        ((issues++))
    fi

    # Network
    info "检查网络连通性..."
    if curl -sf --max-time 5 https://api.github.com >/dev/null 2>&1; then
        success "GitHub API 可达 ✓"
    else
        warn "GitHub API 不可达（可能影响版本检查和下载）"
        ((issues++))
    fi

    # Sudo
    echo
    info "检查 sudo 权限..."
    if [[ $EUID -eq 0 ]]; then
        success "当前以 root 运行 ✓"
    elif [[ ! -t 0 ]]; then
        # 无 TTY 时 sudo -v 无法交互输密码，检测必然失败——按跳过处理，不计问题
        info "无法检测 sudo（非交互环境），已跳过"
    elif sudo -n true 2>/dev/null; then
        success "sudo 可用（免密） ✓"
    elif sudo -v 2>/dev/null; then
        success "sudo 可用 ✓"
    else
        warn "sudo 不可用（部分安装操作可能失败）"
        ((issues++))
    fi

    # Summary
    echo
    echo "=========================================="
    if (( issues == 0 )); then
        success "🎉 环境检查通过，一切就绪！"
    else
        warn "发现 $issues 个问题，请根据上述提示修复"
    fi

    return "$issues"
}
