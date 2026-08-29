#!/usr/bin/env bash
#
# lib/submenus.sh
#
# 各模块子菜单的回调函数与 manage_* 入口。
# 通过 run_submenu() 框架统一调度。
#
# 入口命名约定：子菜单入口函数名必须为 manage_<模块名>（即 .manifest 的
# HAS_SUBMENU 值），菜单按 "manage_${HAS_SUBMENU}" 动态分发，二者不一致
# 会导致菜单找不到入口。
#

# 幂等保护
if [[ -n "${_SUBMENUS_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
_SUBMENUS_LOADED=1

# ============================================================
# Docker 子菜单
# ============================================================
_docker_status()  { echo "当前状态: $(module_status docker)"; }
_docker_display() {
    echo "  1) 标准安装/更新 Docker（官方源，可选国内源）"
    echo "  2) 国内镜像源安装/换源（linuxmirrors.cn，含镜像加速）"
    echo "  3) 仅更换镜像加速器（不重装 Docker）"
    echo "  4) 卸载 Docker"
}
_docker_action() {
    case "$1" in
        1) run_in_dir services/docker install.sh install ;;
        2) run_in_dir services/docker install.sh mirror ;;
        3) run_in_dir services/docker install.sh registry ;;
        4) if yes_no "确认卸载 Docker？"; then run_in_dir services/docker install.sh uninstall; fi ;;
        *) error "无效选项，请重新输入！"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_docker() {
    [ -f "$SCRIPT_DIR/services/docker/install.sh" ] || { error "脚本不存在"; sleep 2; return; }
    run_submenu "🐳 Docker 管理（含国内镜像源）" _docker_status _docker_display _docker_action
}

# ============================================================
# dev-mirror 子菜单
# ============================================================
_dev_mirror_status() {
    echo "当前镜像状态："
    run_in_dir dev-tools/dev-mirror install.sh status 2>/dev/null | sed 's/^/  /'
}
_dev_mirror_display() {
    echo "  1) 换源 - 交互选择（生态 + 源）"
    echo "  2) 一键全部换国内默认源（npm/Go/Rust/Python）"
    echo "  3) 还原官方源 - 交互选择生态"
}
_dev_mirror_action() {
    case "$1" in
        1) run_in_dir dev-tools/dev-mirror install.sh install ;;
        2) run_in_dir dev-tools/dev-mirror install.sh install all default ;;
        3) run_in_dir dev-tools/dev-mirror install.sh uninstall ;;
        *) error "无效选项，请重新输入！"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_dev-mirror() {
    [ -f "$SCRIPT_DIR/dev-tools/dev-mirror/install.sh" ] || { error "脚本不存在"; sleep 2; return; }
    run_submenu "📦 dev-mirror 管理（npm/Go/Rust/Python 换源加速）" _dev_mirror_status _dev_mirror_display _dev_mirror_action
}

# ============================================================
# sys-setup 子菜单
# ============================================================
_sys_setup_status() {
    echo "当前状态："
    run_in_dir essentials/sys-setup install.sh status 2>/dev/null | sed 's/^/  /'
}
_sys_setup_display() {
    echo "  1) all           - 一次性执行全部（推荐）"
    echo "  2) mirror        - 更换软件源（国内镜像）"
    echo "  3) timezone      - 设置时区 + NTP 时间同步"
    echo "  4) ntp           - 配置自定义 NTP 服务器（阿里云/清华/华为/自定义）"
    echo "  5) optimize      - 系统参数优化（文件描述符/内核）"
    echo "  6) ssh           - SSH 加固（⚠️ 需先配好密钥）"
    echo "  7) autoupdate    - 启用自动安全更新"
}
_sys_setup_action() {
    case "$1" in
        1) run_in_dir essentials/sys-setup install.sh all ;;
        2) run_in_dir essentials/sys-setup install.sh mirror ;;
        3) run_in_dir essentials/sys-setup install.sh timezone ;;
        4) run_in_dir essentials/sys-setup install.sh ntp ;;
        5) run_in_dir essentials/sys-setup install.sh optimize ;;
        6) run_in_dir essentials/sys-setup install.sh ssh ;;
        7) run_in_dir essentials/sys-setup install.sh autoupdate ;;
        *) error "无效选项，请重新输入！"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_sys-setup() {
    [ -f "$SCRIPT_DIR/essentials/sys-setup/install.sh" ] || { error "脚本不存在"; sleep 2; return; }
    run_submenu "⚙️  系统初始化配置（装机必设置，仅 Linux）" _sys_setup_status _sys_setup_display _sys_setup_action
}

# ============================================================
# Clash 子菜单
# ============================================================
_clash_status()  { echo "当前状态: $(module_status clash)"; }
_clash_display() {
    echo "  1) 安装/更新 mihomo (二进制 + systemd)"
    echo "  2) 放入配置 (订阅URL或本地文件)"
    echo "  3) 生成示例配置"
    echo "  4) 开启 TUN 透明代理 (全局)"
    echo "  5) 关闭 TUN"
    echo "  6) 启动服务"
    echo "  7) 停止服务"
    echo "  8) 重启服务"
}
_clash_action() {
    case "$1" in
        1) run_in_dir sys-tools/clash install.sh install ;;
        2)
            local cl_src
            read -r -p "输入订阅URL或本地文件路径: " cl_src
            run_in_dir sys-tools/clash install.sh config "$cl_src"
            ;;
        3) run_in_dir sys-tools/clash install.sh example ;;
        4) run_in_dir sys-tools/clash install.sh tun-on ;;
        5) run_in_dir sys-tools/clash install.sh tun-off ;;
        6) run_in_dir sys-tools/clash install.sh start ;;
        7) run_in_dir sys-tools/clash install.sh stop ;;
        8) run_in_dir sys-tools/clash install.sh restart ;;
        *) error "无效选项"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_clash() {
    [ -f "$SCRIPT_DIR/sys-tools/clash/install.sh" ] || { error "脚本不存在"; sleep 2; return; }
    run_submenu "🌐 Clash (mihomo) 管理" _clash_status _clash_display _clash_action
}

# ============================================================
# 多网卡策略路由子菜单
# ============================================================
_multinet_status() {
    echo "当前状态: $(module_status multi-net)"
    echo "本机网卡:"
    # pipefail 下 head -8 提前关管道会触发子 shell SIGPIPE → 用 || true 兜底（仅展示）
    (command -v ip >/dev/null 2>&1 && ip -br link show 2>/dev/null | awk '{print "  "$1}' || echo "  (需 Linux)") | head -8 || true
}
_multinet_display() {
    echo "  1) 初始化某网卡策略路由 (setup)"
    echo "  2) 让某用户走指定网卡 (route-user)"
    echo "  3) 让某端口走指定网卡 (route-port)"
    echo "  4) 查看当前策略路由规则 (list)"
    echo "  5) 清除所有规则 (clear)"
}
_multinet_action() {
    local mn_if mn_u mn_p
    case "$1" in
        1) read -r -p "网卡名 (如 eth1): " mn_if; run_in_dir sys-tools/multi-net install.sh setup "$mn_if" ;;
        2) read -r -p "用户名 网卡名 (空格分隔): " mn_u mn_if; run_in_dir sys-tools/multi-net install.sh route-user "$mn_u" "$mn_if" ;;
        3) read -r -p "目的端口 网卡名 (空格分隔): " mn_p mn_if; run_in_dir sys-tools/multi-net install.sh route-port "$mn_p" "$mn_if" ;;
        4) run_in_dir sys-tools/multi-net install.sh list ;;
        5) run_in_dir sys-tools/multi-net install.sh clear ;;
        *) error "无效选项"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_multi-net() {
    [ -f "$SCRIPT_DIR/sys-tools/multi-net/install.sh" ] || { error "脚本不存在"; sleep 2; return; }
    run_submenu "🔀 多网卡策略路由管理" _multinet_status _multinet_display _multinet_action
}

# ============================================================
# 进程管理工具子菜单
# ============================================================
_pm_status() {
    if [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ]; then
        success "✅ 进程管理工具已安装到 ~/.tools/bin"
    else
        info "ℹ️  进程管理工具尚未安装"
    fi
}
_pm_display() {
    echo "  1) 安装/更新进程管理工具到 ~/.tools 目录"
    echo "  2) 检查系统依赖"
    echo "  3) 运行进程管理工具（交互式）"
    echo "  4) 查看工具配置和状态"
    echo "  5) 卸载进程管理工具"
}
_pm_action() {
    local install_script="$SCRIPT_DIR/sys-tools/process_manager_tool/install_process_manager.sh"
    local process_script="$SCRIPT_DIR/sys-tools/process_manager_tool/process_manager.sh"
    local wrapper_script="$SCRIPT_DIR/sys-tools/process_manager_tool/pm_wrapper.sh"
    local is_installed=false
    [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ] && is_installed=true

    case "$1" in
        1)
            [ -f "$install_script" ] || { error "安装脚本不存在"; sleep 2; return 0; }
            run_in_dir sys-tools/process_manager_tool install_process_manager.sh
            ;;
        2)
            local check_script="$SCRIPT_DIR/sys-tools/process_manager_tool/check_dependencies.sh"
            [ -f "$check_script" ] || { error "依赖检查脚本不存在"; sleep 2; return 0; }
            run_in_dir sys-tools/process_manager_tool check_dependencies.sh
            ;;
        3)
            if [ "$is_installed" = true ] && command -v pm >/dev/null 2>&1; then
                info "运行已安装的进程管理工具..."
                pm
            else
                info "运行开发版本的进程管理工具..."
                [ -f "$process_script" ] || { error "脚本不存在"; sleep 2; return 0; }
                run_in_dir sys-tools/process_manager_tool process_manager.sh
            fi
            ;;
        4)
            if [ "$is_installed" = true ] && command -v pm >/dev/null 2>&1; then
                pm --config
            elif [ -f "$wrapper_script" ]; then
                run_in_dir sys-tools/process_manager_tool pm_wrapper.sh --config
            else
                error "包装脚本不存在: $wrapper_script"
            fi
            ;;
        5)
            if [ "$is_installed" = true ]; then
                if yes_no "确认卸载进程管理工具？"; then
                    info "开始卸载..."
                    run_in_dir sys-tools/process_manager_tool install_process_manager.sh uninstall
                else
                    info "已取消卸载"
                fi
            else
                warn "工具尚未安装，无需卸载"
            fi
            ;;
        *) error "无效选项，请重新选择"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_process_manager_tool() {
    run_submenu "🔧 进程管理工具" _pm_status _pm_display _pm_action
}

# ============================================================
# 磁盘管理工具箱子菜单
# ============================================================
_disk_menu_status() { echo "当前状态: $(module_status disk)"; }
_disk_menu_display() {
    echo "  1) 列出磁盘/分区"
    echo "  2) 新盘一键上线向导（分区→格式化→挂载→fstab）"
    echo "  3) 格式化分区/整盘"
    echo "  4) 分区（GPT 单分区全盘）"
    echo "  5) 挂载"
    echo "  6) 卸载"
    echo "  7) fstab 管理（list）"
    echo "  8) SMART 健康体检（回车=全部整盘概览）"
    echo "  9) 擦除文件系统签名 (wipe)"
    echo " 10) 坏块只读扫描（badblocks，不写盘）"
}
_disk_menu_action() {
    local dk dk2 mp
    case "$1" in
        1) run_in_dir sys-tools/disk install.sh list ;;
        2) run_in_dir sys-tools/disk install.sh wizard ;;
        3)
            read -r -p "目标设备 (如 sdb1): " dk
            read -r -p "文件系统 ext4/xfs/vfat/exfat/ntfs（回车=ext4）: " dk2
            run_in_dir sys-tools/disk install.sh format "$dk" "${dk2:-ext4}"
            ;;
        4)
            read -r -p "整盘 (如 sdb): " dk
            run_in_dir sys-tools/disk install.sh partition "$dk"
            ;;
        5)
            read -r -p "设备 (如 sdb1): " dk
            read -r -p "挂载点 (如 /data): " mp
            read -r -p "写入 fstab 持久化？(y/N): " dk2
            if [[ "$dk2" =~ ^[Yy] ]]; then
                run_in_dir sys-tools/disk install.sh mount "$dk" "$mp" --fstab
            else
                run_in_dir sys-tools/disk install.sh mount "$dk" "$mp"
            fi
            ;;
        6)
            read -r -p "挂载点或设备 (如 /data): " dk
            run_in_dir sys-tools/disk install.sh umount "$dk"
            ;;
        7) run_in_dir sys-tools/disk install.sh fstab list ;;
        8)
            read -r -p "整盘 (如 sda，回车=全部整盘概览): " dk
            run_in_dir sys-tools/disk install.sh smart ${dk:+"$dk"}
            ;;
        9)
            read -r -p "设备 (如 sdb1): " dk
            run_in_dir sys-tools/disk install.sh wipe "$dk"
            ;;
        10)
            read -r -p "整盘或分区 (如 sdb / sdb1): " dk
            run_in_dir sys-tools/disk install.sh scan "$dk"
            ;;
        *) error "无效选项，请重新输入！"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_disk() {
    [ -f "$SCRIPT_DIR/sys-tools/disk/install.sh" ] || { error "脚本不存在"; sleep 2; return; }
    run_submenu "💾 磁盘管理（分区/格式化/挂载/健康，严格防误删，仅 Linux）" _disk_menu_status _disk_menu_display _disk_menu_action
}

# ============================================================
# 自动关机管理（特殊：直接委托给脚本，无子菜单循环）
# ============================================================
manage_shutdown_timer() {
    local script_path="$SCRIPT_DIR/sys-tools/shutdown_timer/shutdown_timer.sh"
    if [ ! -f "$script_path" ]; then
        error "脚本不存在: $script_path"
        sleep 2
        return
    fi
    chmod +x "$script_path"
    clear
    "$script_path"
    info "已从自动关机管理返回主菜单。"
    read -r -p "按回车键继续..."
}

# ============================================================
# 运维工具箱子菜单（inspect 巡检 / log 日志 / svc 服务 / audit 基线）
# ============================================================
_ops_kit_menu_status() { echo "当前状态: $(module_status ops-kit)"; }
_ops_kit_menu_display() {
    echo "  1) 一键巡检报告（inspect，只读）"
    echo "  2) 巡检结果 JSON 输出"
    echo "  3) 日志占用概览（log status）"
    echo "  4) 清理 journald（log vacuum，写操作）"
    echo "  5) logrotate 条目列表（rotate list）"
    echo "  6) systemd 失败单元排查（svc failed）"
    echo "  7) 查看服务日志（svc logs）"
    echo "  8) 服务启停管理（svc start/stop/restart/enable/disable）"
    echo "  9) 安全基线自查（audit all，只读）"
}
_ops_kit_menu_action() {
    local a u
    case "$1" in
        1) run_in_dir sys-tools/ops-kit install.sh inspect ;;
        2) run_in_dir sys-tools/ops-kit install.sh inspect --json ;;
        3) run_in_dir sys-tools/ops-kit install.sh log status ;;
        4)
            read -r -p "清理目标（如 200M / 2weeks）: " a
            run_in_dir sys-tools/ops-kit install.sh log vacuum "$a"
            ;;
        5) run_in_dir sys-tools/ops-kit install.sh log rotate list ;;
        6) run_in_dir sys-tools/ops-kit install.sh svc failed ;;
        7)
            read -r -p "服务单元 (如 nginx.service): " a
            run_in_dir sys-tools/ops-kit install.sh svc logs "$a"
            ;;
        8)
            read -r -p "动作 (start/stop/restart/enable/disable): " a
            read -r -p "服务单元: " u
            run_in_dir sys-tools/ops-kit install.sh svc "$a" "$u"
            ;;
        9) run_in_dir sys-tools/ops-kit install.sh audit all ;;
        *) error "无效选项，请重新输入！"; sleep 1; return 0 ;;
    esac
    echo; read -r -p "按回车键继续..."
    return 0
}
manage_ops-kit() {
    [ -f "$SCRIPT_DIR/sys-tools/ops-kit/install.sh" ] || { error "脚本不存在"; sleep 2; return; }
    run_submenu "🧰 运维工具箱（巡检/日志/服务/安全基线，仅 Linux）" _ops_kit_menu_status _ops_kit_menu_display _ops_kit_menu_action
}
