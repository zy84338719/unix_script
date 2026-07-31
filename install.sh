#!/usr/bin/env bash
set -e

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# 是否处于交互模式（无参数的菜单/状态页会等待回车；非交互命令不等待）
INTERACTIVE=true

# ============================================================
# 统一安装菜单 - 服务与环境管理工具
# ============================================================

# 在子 shell 中执行某目录下的脚本（避免 cd 污染当前工作目录）
run_in_dir() {
    local dir="$1"; shift
    ( cd "$SCRIPT_DIR/$dir" && bash "$@" )
}

# ---------------- 系统信息 ----------------
show_system_info() {
    header "🖥️  系统信息"
    echo "───────────────────────────────"
    echo "操作系统: $OS_TYPE"
    echo "CPU架构:  $ARCH_TYPE"
    echo "───────────────────────────────"
    echo
}

# ---------------- 主菜单 ----------------
show_main_menu() {
    clear
    header "🚀 一键安装脚本 - 服务与环境管理工具"
    echo "========================================"
    show_system_info

    menu "请选择要安装的服务或配置环境："
    echo
    echo "  --- 服务安装 ---"
    echo "  1) Node Exporter     - Prometheus 系统监控数据收集器"
    echo "  2) DDNS-GO           - 动态域名解析服务"
    echo "  3) WireGuard         - 现代、快速、安全的 VPN"
    echo "  4) Tailscale         - 免公网 IP 的组网 VPN"
    echo "  5) Docker            - 容器引擎 (Engine / Desktop)"
    echo "  6) Fail2ban          - SSH 暴力破解防护 (仅 Linux)"
    echo "  7) OpenList          - 文件列表 / 网盘聚合 (端口 5244，原 Alist)"
    echo "  8) Uptime Kuma       - 服务可用性监控面板 (Docker)"
    echo "  9) Cockpit           - Linux Web 管理面板 (端口 9090, 仅 Linux)"
    echo
    echo "  --- 装机必备 / 必设置 ---"
    echo "  10) 装机必备工具包   - curl/wget/git/vim/htop/tmux/jq 等一键装齐"
    echo "  11) 系统初始化配置   - 换源/时区/系统优化/SSH 加固/自动安全更新"
    echo "  12) Swap 虚拟内存    - 创建/调整 swap (小内存 VPS 必备)"
    echo "  13) BBR 网络加速     - 开启 TCP BBR 拥塞控制"
    echo "  14) nvm              - Node.js 多版本管理"
    echo
    echo "  --- 开发环境配置 ---"
    echo "  15) Zsh & Oh My Zsh  - 自动配置 Zsh 开发环境"
    echo "  16) minikube         - 本地 Kubernetes 开发环境 (kubectl + minikube)"
    echo "  17) 终端 TUI 工具    - lazydocker + lazygit"
    echo
    echo "  --- AI 工具 ---"
    echo "  18) OpenCode         - 终端 AI 编程助手 (sst/opencode)"
    echo "  19) Ollama           - 本地大模型运行时 (跑 Llama/Qwen/DeepSeek)"
    echo
    echo "  --- 系统工具 ---"
    echo "  20) 自动关机管理     - 设置临时或每日定时关机"
    echo "  21) 进程管理工具     - 智能搜索和管理系统进程"
    echo "  22) Deskflow         - 键鼠共享 (Flatpak, 仅 Linux 图形环境)"
    echo "  23) safe-rm 回收站   - 安全删除替代 rm，防误删灾难"
    echo "  24) Clash (mihomo)   - 代理核心 + 快速配置 + TUN 透明代理"
    echo "  25) 多网卡策略路由   - 指定服务/用户/端口走指定网卡"
    echo
    echo "  --- 管理 ---"
    echo "  s) 查看已安装状态    - 检查服务和环境的安装情况"
    echo "  u) 卸载服务/环境     - 移除已安装的服务或环境"
    echo "  q) 退出"
    echo
    echo "========================================"
}

# ---------------- 状态检查函数 ----------------
check_service_status() {
    local service_name="$1"
    local binary_path="$2"
    local service_file="$3"

    local is_installed=false
    local is_running=false
    local version=""

    if command -v "$service_name" &> /dev/null || [ -f "$binary_path" ]; then
        is_installed=true
        if command -v "$service_name" &> /dev/null; then
            version=$("$service_name" --version 2>/dev/null | head -1 || echo "未知版本")
        fi
    fi

    if [[ "$OS_TYPE" == "linux" ]]; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            is_running=true
        fi
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        if sudo launchctl list | grep -q "$service_file" 2>/dev/null; then
            is_running=true
        fi
    fi

    if $is_installed; then
        if $is_running; then
            echo -e "${GREEN}✅ 已安装并运行${NC} ($version)"
        else
            echo -e "${YELLOW}⚠️  已安装但未运行${NC} ($version)"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

check_shutdown_timer_status() {
    local is_configured=false
    if [[ "$OS_TYPE" == "darwin" ]]; then
        [ -f "/Library/LaunchDaemons/com.user.dailyshutdown.plist" ] && is_configured=true
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if crontab -l 2>/dev/null | grep -q "# AUTO_SHUTDOWN_SCRIPT"; then
            is_configured=true
        fi
    fi
    if $is_configured; then
        echo -e "${GREEN}✅ 已配置每日定时关机${NC}"
    else
        echo -e "${RED}❌ 未配置${NC}"
    fi
}

check_wireguard_status() {
    local wg_installed=false
    local service_running=false
    local interface="wg0"
    command -v wg &> /dev/null && wg_installed=true
    if [[ "$OS_TYPE" == "linux" ]]; then
        systemctl is-active --quiet "wg-quick@${interface}" 2>/dev/null && service_running=true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl list | grep -q "com.wireguard.${interface}" 2>/dev/null && service_running=true
    fi
    if $wg_installed; then
        if $service_running; then
            echo -e "${GREEN}✅ 已安装并运行${NC} (接口: ${interface})"
        else
            echo -e "${YELLOW}⚠️  已安装但服务未运行${NC}"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

check_zsh_status() {
    local zsh_installed=false
    local omz_installed=false
    command -v zsh &> /dev/null && zsh_installed=true
    [ -d "$HOME/.oh-my-zsh" ] && omz_installed=true
    if $zsh_installed && $omz_installed; then
        echo -e "${GREEN}✅ Zsh & Oh My Zsh 已安装${NC}"
    elif $zsh_installed; then
        echo -e "${YELLOW}⚠️  已安装 Zsh，但未安装 Oh My Zsh${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

check_process_manager_status() {
    local is_installed=false
    if [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ]; then
        is_installed=true
    fi
    if $is_installed; then
        if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
            echo -e "${GREEN}✅ 已安装并配置${NC}"
        else
            echo -e "${YELLOW}⚠️  已安装但PATH未配置${NC}"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# Tailscale / Docker / Fail2ban / minikube / deskflow 状态委托给各模块的 status 子命令
status_tailscale_module() { run_in_dir tailscale install.sh status; }
status_docker_module()    { run_in_dir docker install.sh status; }
status_fail2ban_module()  { run_in_dir fail2ban install.sh status; }
status_minikube_module()  { run_in_dir minikube install.sh status; }
status_deskflow_module()  { run_in_dir deskflow install.sh status; }
status_openlist_module()     { run_in_dir openlist install.sh status; }
status_uptime_kuma_module() { run_in_dir uptime-kuma install.sh status; }
status_cockpit_module()   { run_in_dir cockpit install.sh status; }
status_dev_tui_module()   { run_in_dir dev-tui install.sh status; }
status_essential_module() { run_in_dir essential-pkgs install.sh status; }
status_sys_setup_module() { run_in_dir sys-setup install.sh status; }
status_swap_module()      { run_in_dir swap install.sh status; }
status_bbr_module()       { run_in_dir bbr install.sh status; }
status_nvm_module()       { run_in_dir nvm install.sh status; }
status_safe_rm_module()   { run_in_dir safe-rm install.sh status; }
status_clash_module()     { run_in_dir clash install.sh status; }
status_multinet_module()  { run_in_dir multi-net install.sh status; }
status_opencode_module()  { run_in_dir opencode install.sh status; }
status_ollama_module()    { run_in_dir ollama install.sh status; }

# ---------------- 已安装状态总览 ----------------
show_installed_services() {
    if $INTERACTIVE; then clear; fi
    header "📊 已安装状态"
    echo "========================================"

    echo "--- 服务 ---"
    echo "Node Exporter:  $(check_service_status "node_exporter" "/usr/local/bin/node_exporter" "com.prometheus.node_exporter")"
    echo "DDNS-GO:        $(check_service_status "ddns-go" "/opt/ddns-go/ddns-go" "jeessy.ddns-go")"
    echo "WireGuard:      $(check_wireguard_status)"
    echo "Tailscale:      $(status_tailscale_module)"
    echo "Docker:         $(status_docker_module)"
    echo "Fail2ban:       $(status_fail2ban_module)"
    echo "OpenList:          $(status_openlist_module)"
    echo "Uptime Kuma:    $(status_uptime_kuma_module)"
    echo "Cockpit:        $(status_cockpit_module)"
    echo
    echo "--- 装机必备 ---"
    echo "必备工具包:     $(status_essential_module)"
    echo "BBR 加速:       $(status_bbr_module)"
    echo "Swap:           $(status_swap_module)"
    echo "nvm:            $(status_nvm_module)"
    echo
    echo "--- 开发环境 ---"
    echo "Zsh 环境:       $(check_zsh_status)"
    echo "minikube:       $(status_minikube_module)"
    echo "终端 TUI 工具:  $(status_dev_tui_module)"
    echo
    echo "--- AI 工具 ---"
    echo "OpenCode:       $(status_opencode_module)"
    echo "Ollama:         $(status_ollama_module)"
    echo
    echo "--- 系统工具 ---"
    echo "自动关机任务:   $(check_shutdown_timer_status)"
    echo "进程管理工具:   $(check_process_manager_status)"
    echo "Deskflow:       $(status_deskflow_module)"
    echo "safe-rm 回收站: $(status_safe_rm_module)"
    echo "Clash (mihomo): $(status_clash_module)"
    echo "多网卡策略路由: $(status_multinet_module)"

    echo
    echo "========================================"
    if [[ "$OS_TYPE" == "linux" ]]; then
        info "Linux 服务管理命令："
        echo "  查看状态: sudo systemctl status <service-name>"
        echo "  查看日志: sudo journalctl -u <service-name> -f"
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        info "macOS 服务管理命令："
        echo "  查看状态: sudo launchctl list | grep <service>"
        echo "  查看日志: tail -f /var/log/<service>.log"
    fi
    echo
    if $INTERACTIVE; then read -r -p "按回车键返回主菜单..."; fi
}

# ---------------- 执行安装脚本 ----------------
run_install_script() {
    local script_path="$1"
    local service_name="$2"

    if [ ! -f "$script_path" ]; then
        error "安装脚本不存在：$script_path"
        return 1
    fi
    [ -x "$script_path" ] || chmod +x "$script_path"

    info "开始安装 $service_name..."
    echo
    if "$script_path"; then
        echo
        success "$service_name 安装完成！"
    else
        echo
        error "$service_name 安装失败！"
        return 1
    fi
    echo
    read -r -p "按回车键返回主菜单..."
}

# ---------------- WireGuard 子菜单 ----------------
manage_wireguard() {
    local script_path="$SCRIPT_DIR/wireguard/install.sh"
    if [ ! -f "$script_path" ]; then
        error "脚本不存在: $script_path"
        sleep 2
        return
    fi
    chmod +x "$script_path"

    while true; do
        clear
        header "🔧 WireGuard 管理"
        echo "========================================"
        echo "当前状态:"
        local wg_tool_state
        if command -v wg &>/dev/null; then
            wg_tool_state="${GREEN}✅ 已安装${NC}"
        else
            wg_tool_state="${RED}❌ 未安装${NC}"
        fi
        echo "  - WireGuard 工具: $wg_tool_state"
        local wg_status_output
        wg_status_output=$(check_wireguard_status)
        if [[ $wg_status_output == *"运行"* ]]; then
            echo -e "  - 开机自启服务: ${GREEN}✅ 已配置并运行${NC}"
        elif [[ $wg_status_output == *"未运行"* ]]; then
            echo -e "  - 开机自启服务: ${YELLOW}⚠️  已配置但未运行${NC}"
        else
            echo -e "  - 开机自启服务: ${RED}❌ 未配置${NC}"
        fi
        echo
        menu "请选择操作:"
        echo "  1) 安装/更新 WireGuard 工具"
        echo "  2) 配置/重置开机自启服务"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-2]: " wg_choice

        case $wg_choice in
            1) info "正在调用 WireGuard 工具安装脚本..."; "$script_path" install_tools; echo; read -r -p "按回车键继续..." ;;
            2) info "正在调用 WireGuard 服务配置脚本..."; "$script_path" configure_service; echo; read -r -p "按回车键继续..." ;;
            0) break ;;
            *) error "无效选项，请重新输入！"; sleep 1 ;;
        esac
    done
}

# ---------------- Docker 管理（含国内镜像源） ----------------
manage_docker() {
    local script_path="$SCRIPT_DIR/docker/install.sh"
    [ -f "$script_path" ] || { error "脚本不存在: $script_path"; sleep 2; return; }
    chmod +x "$script_path"

    while true; do
        clear
        header "🐳 Docker 管理（含国内镜像源）"
        echo "========================================"
        echo "当前状态: $(status_docker_module)"
        echo
        menu "请选择操作："
        echo "  1) 标准安装/更新 Docker（官方源，可选国内源）"
        echo "  2) 国内镜像源安装/换源（linuxmirrors.cn，含镜像加速）"
        echo "  3) 仅更换镜像加速器（不重装 Docker）"
        echo "  4) 卸载 Docker"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-4]: " dk_choice

        case $dk_choice in
            1) run_in_dir docker install.sh install; echo; read -r -p "按回车键继续..." ;;
            2) run_in_dir docker install.sh mirror; echo; read -r -p "按回车键继续..." ;;
            3) run_in_dir docker install.sh registry; echo; read -r -p "按回车键继续..." ;;
            4)
                if yes_no "确认卸载 Docker？"; then
                    run_in_dir docker install.sh uninstall
                fi
                echo; read -r -p "按回车键继续..."
                ;;
            0) break ;;
            *) error "无效选项，请重新输入！"; sleep 1 ;;
        esac
    done
}

# ---------------- 系统初始化配置（装机必设置） ----------------
manage_sys_setup() {
    local script_path="$SCRIPT_DIR/sys-setup/install.sh"
    [ -f "$script_path" ] || { error "脚本不存在: $script_path"; sleep 2; return; }
    chmod +x "$script_path"

    while true; do
        clear
        header "⚙️  系统初始化配置（装机必设置，仅 Linux）"
        echo "========================================"
        echo "当前状态："
        run_in_dir sys-setup install.sh status 2>/dev/null | sed 's/^/  /'
        echo
        menu "请选择要执行的配置："
        echo "  1) all           - 一次性执行全部（推荐）"
        echo "  2) mirror        - 更换软件源（国内镜像）"
        echo "  3) timezone      - 设置时区 + NTP 时间同步"
        echo "  4) optimize      - 系统参数优化（文件描述符/内核）"
        echo "  5) ssh           - SSH 加固（⚠️ 需先配好密钥）"
        echo "  6) autoupdate    - 启用自动安全更新"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-6]: " ss_choice

        case $ss_choice in
            1) run_in_dir sys-setup install.sh all ;;
            2) run_in_dir sys-setup install.sh mirror ;;
            3) run_in_dir sys-setup install.sh timezone ;;
            4) run_in_dir sys-setup install.sh optimize ;;
            5) run_in_dir sys-setup install.sh ssh ;;
            6) run_in_dir sys-setup install.sh autoupdate ;;
            0) break ;;
            *) error "无效选项，请重新输入！"; sleep 1 ;;
        esac
        echo
        read -r -p "按回车键继续..."
    done
}

# ---------------- Clash (mihomo) 管理 ----------------
manage_clash() {
    local script_path="$SCRIPT_DIR/clash/install.sh"
    [ -f "$script_path" ] || { error "脚本不存在: $script_path"; sleep 2; return; }
    chmod +x "$script_path"
    while true; do
        clear
        header "🌐 Clash (mihomo) 管理"
        echo "========================================"
        echo "当前状态: $(status_clash_module)"
        echo
        menu "请选择操作："
        echo "  1) 安装/更新 mihomo (二进制 + systemd)"
        echo "  2) 放入配置 (订阅URL或本地文件)"
        echo "  3) 生成示例配置"
        echo "  4) 开启 TUN 透明代理 (全局)"
        echo "  5) 关闭 TUN"
        echo "  6) 启动服务"
        echo "  7) 停止服务"
        echo "  8) 重启服务"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-8]: " cl_choice
        case $cl_choice in
            1) run_in_dir clash install.sh install ;;
            2)
                read -r -p "输入订阅URL或本地文件路径: " cl_src
                run_in_dir clash install.sh config "$cl_src"
                ;;
            3) run_in_dir clash install.sh example ;;
            4) run_in_dir clash install.sh tun-on ;;
            5) run_in_dir clash install.sh tun-off ;;
            6) run_in_dir clash install.sh start ;;
            7) run_in_dir clash install.sh stop ;;
            8) run_in_dir clash install.sh restart ;;
            0) break ;;
            *) error "无效选项"; sleep 1 ;;
        esac
        echo; read -r -p "按回车键继续..."
    done
}

# ---------------- 多网卡策略路由管理 ----------------
manage_multinet() {
    local script_path="$SCRIPT_DIR/multi-net/install.sh"
    [ -f "$script_path" ] || { error "脚本不存在: $script_path"; sleep 2; return; }
    chmod +x "$script_path"
    while true; do
        clear
        header "🔀 多网卡策略路由管理"
        echo "========================================"
        echo "当前状态: $(status_multinet_module)"
        echo "本机网卡:"
        (command -v ip >/dev/null 2>&1 && ip -br link show 2>/dev/null | awk '{print "  "$1}' || echo "  (需 Linux)") | head -8
        echo
        menu "请选择操作："
        echo "  1) 初始化某网卡策略路由 (setup)"
        echo "  2) 让某用户走指定网卡 (route-user)"
        echo "  3) 让某端口走指定网卡 (route-port)"
        echo "  4) 查看当前策略路由规则 (list)"
        echo "  5) 清除所有规则 (clear)"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-5]: " mn_choice
        case $mn_choice in
            1) read -r -p "网卡名 (如 eth1): " mn_if; run_in_dir multi-net install.sh setup "$mn_if" ;;
            2) read -r -p "用户名 网卡名 (空格分隔): " mn_u mn_if; run_in_dir multi-net install.sh route-user "$mn_u" "$mn_if" ;;
            3) read -r -p "目的端口 网卡名 (空格分隔): " mn_p mn_if; run_in_dir multi-net install.sh route-port "$mn_p" "$mn_if" ;;
            4) run_in_dir multi-net install.sh list ;;
            5) run_in_dir multi-net install.sh clear ;;
            0) break ;;
            *) error "无效选项"; sleep 1 ;;
        esac
        echo; read -r -p "按回车键继续..."
    done
}

# ---------------- 自动关机管理 ----------------
manage_shutdown_timer() {
    local script_path="$SCRIPT_DIR/shutdown_timer/shutdown_timer.sh"
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

# 取消每日自动关机（供卸载菜单调用）
uninstall_shutdown_timer() {
    info "正在取消每日自动关机任务..."
    local script_path="$SCRIPT_DIR/shutdown_timer/shutdown_timer.sh"
    if [ ! -f "$script_path" ]; then
        error "脚本不存在: $script_path"
        return
    fi
    chmod +x "$script_path"
    "$script_path" cancel_daily_shutdown_internal
}

# ---------------- 进程管理工具子菜单 ----------------
manage_process_tool() {
    while true; do
        clear
        header "🔧 进程管理工具"
        echo "========================================"

        local install_script="$SCRIPT_DIR/process_manager_tool/install_process_manager.sh"
        local process_script="$SCRIPT_DIR/process_manager_tool/process_manager.sh"
        local wrapper_script="$SCRIPT_DIR/process_manager_tool/pm_wrapper.sh"

        local is_installed=false
        if [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ]; then
            is_installed=true
            success "✅ 进程管理工具已安装到 ~/.tools/bin"
        else
            info "ℹ️  进程管理工具尚未安装"
        fi

        echo
        menu "请选择操作："
        echo "  1) 安装/更新进程管理工具到 ~/.tools 目录"
        echo "  2) 检查系统依赖"
        echo "  3) 运行进程管理工具（交互式）"
        echo "  4) 查看工具配置和状态"
        echo "  5) 卸载进程管理工具"
        echo "  0) 返回主菜单"
        echo
        read -r -p "请输入选项 [0-5]: " pm_choice

        case $pm_choice in
            1)
                if [ ! -f "$install_script" ]; then error "安装脚本不存在"; sleep 2; continue; fi
                chmod +x "$install_script"
                run_in_dir process_manager_tool install_process_manager.sh
                echo; read -r -p "按回车键继续..."
                ;;
            2)
                local check_script="$SCRIPT_DIR/process_manager_tool/check_dependencies.sh"
                [ -f "$check_script" ] || { error "依赖检查脚本不存在"; sleep 2; continue; }
                chmod +x "$check_script"
                run_in_dir process_manager_tool check_dependencies.sh
                echo; read -r -p "按回车键继续..."
                ;;
            3)
                if [ "$is_installed" = true ] && command -v pm >/dev/null 2>&1; then
                    info "运行已安装的进程管理工具..."
                    pm
                else
                    info "运行开发版本的进程管理工具..."
                    [ -f "$process_script" ] || { error "脚本不存在"; sleep 2; continue; }
                    chmod +x "$process_script"
                    run_in_dir process_manager_tool process_manager.sh
                fi
                echo; read -r -p "按回车键继续..."
                ;;
            4)
                if [ "$is_installed" = true ] && command -v pm >/dev/null 2>&1; then
                    pm --config
                elif [ -f "$wrapper_script" ]; then
                    chmod +x "$wrapper_script"
                    run_in_dir process_manager_tool pm_wrapper.sh --config
                else
                    error "包装脚本不存在: $wrapper_script"
                fi
                echo; read -r -p "按回车键继续..."
                ;;
            5)
                if [ "$is_installed" = true ]; then
                    if yes_no "确认卸载进程管理工具？"; then
                        info "开始卸载..."
                        run_in_dir process_manager_tool install_process_manager.sh uninstall
                    else
                        info "已取消卸载"
                    fi
                else
                    warn "工具尚未安装，无需卸载"
                fi
                echo; read -r -p "按回车键继续..."
                ;;
            0) return ;;
            *) error "无效选项，请重新选择"; sleep 1 ;;
        esac
    done
}

# ============================================================
# 卸载相关
# ============================================================
uninstall_node_exporter() {
    info "正在卸载 Node Exporter..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop node_exporter &>/dev/null || true
        sudo systemctl disable node_exporter &>/dev/null || true
        sudo rm -f /etc/systemd/system/node_exporter.service
        sudo systemctl daemon-reload &>/dev/null || true
        sudo rm -f /usr/local/bin/node_exporter
        id "node_exporter" &>/dev/null && sudo userdel node_exporter
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist &>/dev/null || true
        sudo rm -f /Library/LaunchDaemons/com.prometheus.node_exporter.plist
        sudo rm -f /usr/local/bin/node_exporter
        sudo rm -f /var/log/node_exporter.log /var/log/node_exporter.err
    fi
    success "Node Exporter 已成功卸载！"
}

uninstall_ddns_go() {
    info "正在卸载 DDNS-GO..."
    if [[ "$OS_TYPE" == "linux" ]]; then
        sudo systemctl stop ddns-go &>/dev/null || true
        sudo systemctl disable ddns-go &>/dev/null || true
        sudo rm -rf /opt/ddns-go
        sudo systemctl daemon-reload
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        sudo launchctl bootout system /Library/LaunchDaemons/jeessy.ddns-go.plist &>/dev/null || true
        sudo rm -f /Library/LaunchDaemons/jeessy.ddns-go.plist
        sudo rm -rf /opt/ddns-go
    fi
    success "DDNS-GO 已成功卸载！"
}

uninstall_wireguard() {
    local script_path="$SCRIPT_DIR/wireguard/install.sh"
    [ -f "$script_path" ] || { error "脚本不存在: $script_path"; return; }
    info "正在卸载 WireGuard 开机自启服务..."
    "$script_path" uninstall_service
    echo
    if yes_no "是否删除 wireguard 目录下的 .conf 配置文件？"; then
        if [[ "$OS_TYPE" == "linux" ]]; then
            sudo rm -f /etc/wireguard/*.conf
        elif [[ "$OS_TYPE" == "darwin" ]]; then
            sudo rm -f /usr/local/etc/wireguard/*.conf
        fi
        success "配置文件已删除。"
    fi
    warn "服务已移除。要完全卸载，请使用包管理器 (apt/brew 等) 手动移除 'wireguard-tools'。"
    success "WireGuard 卸载完成！"
}

# 卸载 Zsh & Oh My Zsh（显示说明）
uninstall_zsh_omz() {
    warn "卸载 Zsh 和 Oh My Zsh 是一个敏感操作，建议手动执行以避免风险。"
    info "Oh My Zsh 官方提供了一个卸载脚本，您可以运行它："
    echo "  uninstall_oh_my_zsh"
    echo
    info "卸载 Zsh 本身，请使用系统的包管理器，例如："
    echo "  - Ubuntu/Debian: sudo apt-get remove --purge zsh"
    echo "  - CentOS/RHEL:   sudo yum remove zsh"
    echo "  - macOS (Homebrew): brew uninstall zsh"
    echo
    warn "在卸载 Zsh 之前，请务必将您的默认 shell 切换回 bash 或其他 shell！"
    echo "  chsh -s /bin/bash"
    echo
    info "更多详细信息，请参考项目的 README.md 文档。"
}

# 卸载菜单
show_uninstall_menu() {
    clear
    header "🗑️  卸载服务与环境"
    echo "========================================"
    warn "注意：卸载操作将完全移除服务及其配置文件！"
    echo
    echo "  1) 卸载 Node Exporter"
    echo "  2) 卸载 DDNS-GO"
    echo "  3) 卸载 WireGuard (服务和配置)"
    echo "  4) 卸载 Tailscale"
    echo "  5) 卸载 Docker"
    echo "  6) 卸载 Fail2ban"
    echo "  7) 卸载 OpenList"
    echo "  8) 卸载 Uptime Kuma"
    echo "  9) 卸载 Cockpit"
    echo "  10) 卸载 Zsh & Oh My Zsh (查看说明)"
    echo "  11) 卸载 minikube"
    echo "  12) 卸载终端 TUI 工具 (lazydocker + lazygit)"
    echo "  13) 取消每日自动关机任务"
    echo "  14) 卸载进程管理工具"
    echo "  15) 卸载 Deskflow"
    echo "  16) 关闭 BBR 网络加速 (恢复默认)"
    echo "  17) 卸载 Swap 虚拟内存"
    echo "  18) 卸载 nvm"
    echo "  19) 卸载 safe-rm 回收站"
    echo "  20) 卸载 Clash (mihomo)"
    echo "  21) 清除多网卡策略路由规则"
    echo "  22) 卸载 OpenCode"
    echo "  23) 卸载 Ollama"
    echo "  0) 返回主菜单"
    echo
    echo "========================================"
}

# 处理卸载选择
do_uninstall() {
    local choice="$1"
    case $choice in
        1) if yes_no "确认卸载 Node Exporter？"; then uninstall_node_exporter; fi ;;
        2) if yes_no "确认卸载 DDNS-GO？"; then uninstall_ddns_go; fi ;;
        3) if yes_no "确认卸载 WireGuard 服务和相关配置？"; then uninstall_wireguard; fi ;;
        4) run_in_dir tailscale install.sh uninstall ;;
        5) run_in_dir docker install.sh uninstall ;;
        6) run_in_dir fail2ban install.sh uninstall ;;
        7) run_in_dir openlist install.sh uninstall ;;
        8) run_in_dir uptime-kuma install.sh uninstall ;;
        9) run_in_dir cockpit install.sh uninstall ;;
        10) uninstall_zsh_omz ;;
        11) run_in_dir minikube install.sh uninstall ;;
        12) run_in_dir dev-tui install.sh uninstall ;;
        13) uninstall_shutdown_timer ;;
        14)
            if yes_no "确认卸载进程管理工具？"; then
                info "开始卸载进程管理工具..."
                run_in_dir process_manager_tool install_process_manager.sh uninstall
            fi
            ;;
        15) run_in_dir deskflow install.sh uninstall ;;
        16) run_in_dir bbr install.sh disable ;;
        17) run_in_dir swap install.sh uninstall ;;
        18) run_in_dir nvm install.sh uninstall ;;
        19) run_in_dir safe-rm install.sh uninstall ;;
        20) run_in_dir clash install.sh uninstall ;;
        21) run_in_dir multi-net install.sh clear ;;
        22) run_in_dir opencode install.sh uninstall ;;
        23) run_in_dir ollama install.sh uninstall ;;
        0) return 1 ;;
        *) error "无效选项，请重新输入！"; sleep 1 ;;
    esac
    echo
    read -r -p "按回车键继续..."
    return 0
}

# ---------------- 模块名 -> 安装动作（非交互用） ----------------
dispatch_module() {
    local name="$1"
    case "$name" in
        node_exporter|nodeexporter) run_install_script "$SCRIPT_DIR/node_exporter/install.sh" "Node Exporter" ;;
        ddns-go|ddnsgo|ddns)        run_install_script "$SCRIPT_DIR/ddns-go/install.sh" "DDNS-GO" ;;
        wireguard|wg)               "$SCRIPT_DIR/wireguard/install.sh" install_tools ;;
        tailscale|ts)               run_in_dir tailscale install.sh install ;;
        docker)                     run_in_dir docker install.sh install ;;
        fail2ban|f2b)               run_in_dir fail2ban install.sh install ;;
        openlist)                    run_in_dir openlist install.sh install ;;
        uptime-kuma|uptime_kuma)    run_in_dir uptime-kuma install.sh install ;;
        cockpit)                    run_in_dir cockpit install.sh install ;;
        dev-tui|dev_tui|tui)        run_in_dir dev-tui install.sh install ;;
        opencode)                   run_in_dir opencode install.sh install ;;
        ollama)                     run_in_dir ollama install.sh install ;;
        essential-pkgs|essential_pkgs|essential) run_in_dir essential-pkgs install.sh install ;;
        sys-setup|sys_setup)        run_in_dir sys-setup install.sh all ;;
        swap)                       run_in_dir swap install.sh install ;;
        bbr)                        run_in_dir bbr install.sh enable ;;
        nvm)                        run_in_dir nvm install.sh install ;;
        safe-rm|safe_rm|safesrm)    run_in_dir safe-rm install.sh install ;;
        clash|mihomo)               run_in_dir clash install.sh install ;;
        multi-net|multinet|multi_net) run_in_dir multi-net install.sh list ;;
        zsh)                        run_install_script "$SCRIPT_DIR/zsh_setup/install.sh" "Zsh & Oh My Zsh" ;;
        minikube)                   run_in_dir minikube install.sh install ;;
        deskflow)                   run_in_dir deskflow install.sh install ;;
        shutdown|shutdown_timer)    manage_shutdown_timer ;;
        process_manager|pm)         manage_process_tool ;;
        *)
            error "未知模块: $name"
            show_noninteractive_usage
            exit 1
            ;;
    esac
}

# ---------------- 用法 ----------------
show_usage() {
    cat <<EOF
用法: $0 [选项] [模块名]

选项:
  -h, --help        显示本帮助
  -v, --version     显示版本
  -s, --status      查看所有模块的安装状态后退出（非交互）
  --list            列出可用模块名后退出
  check-update      检查远端是否有新版本（不修改本地）
  update            安全检查 + 确认后执行 git pull 更新本地仓库

模块名（用于非交互安装）:
  node_exporter | ddns-go | wireguard | tailscale | docker |
  fail2ban | openlist | uptime-kuma | cockpit |
  essential-pkgs | sys-setup | swap | bbr | nvm |
  zsh | minikube | dev-tui | opencode | ollama | deskflow | shutdown_timer | process_manager | safe-rm | clash | multi-net

示例:
  $0                       # 进入交互式主菜单
  $0 --status              # 直接打印安装状态
  $0 docker                # 直接安装 docker
  $0 tailscale             # 直接安装 tailscale
  $0 check-update          # 检查是否有新版本
  $0 update                # 更新到最新版本（需确认）
EOF
}

show_noninteractive_usage() {
    show_usage
}

# 判断是否应在启动时自动检查更新。
# 跳过条件：UNIX_SCRIPT_NO_UPDATE_CHECK=1、或 CI=true、或非交互（非 TTY）。
should_auto_check_update() {
    [[ "${UNIX_SCRIPT_NO_UPDATE_CHECK:-0}" == "1" ]] && return 1
    [[ "${CI:-false}" == "true" ]] && return 1
    [[ -t 1 ]] || return 1   # 非 TTY（管道/重定向）不自动检查
    return 0
}

# ---------------- 主函数 ----------------
main() {
    detect_os
    detect_arch

    # 启动时自动检查远端新版本（仅提示，不阻塞、不影响退出码）
    if should_auto_check_update; then
        print_update_hint 2>/dev/null || true
    fi

    # 无参数 -> 交互式
    if [[ $# -eq 0 ]]; then
        interactive_main
        return
    fi

    # 处理参数
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        -v|--version) echo "unix_script $(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
        -s|--status)  INTERACTIVE=false; show_installed_services; exit 0 ;;
        --list)
            echo "node_exporter ddns-go wireguard tailscale docker fail2ban openlist uptime-kuma cockpit essential-pkgs sys-setup swap bbr nvm zsh minikube dev-tui opencode ollama deskflow shutdown_timer process_manager safe-rm clash multi-net"
            exit 0
            ;;
        check-update)
            info "检查远端最新版本..."
            if check_for_update 2>/dev/null; then
                warn "有新版本：当前 $(get_local_version) → 远端 ${REMOTE_LATEST}"
                info "运行 ./install.sh update 一键更新"
            else
                if [[ -n "${REMOTE_LATEST:-}" ]]; then
                    success "已是最新版本：$(get_local_version)（远端 ${REMOTE_LATEST}）"
                else
                    warn "无法获取远端版本（网络问题或未发布 release），当前版本 $(get_local_version)"
                fi
            fi
            exit 0
            ;;
        update)
            do_self_update
            exit $?
            ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)  dispatch_module "$1" ;;
    esac
}

# 交互式主循环
interactive_main() {
    while true; do
        show_main_menu
        read -r -p "请输入选项: " choice
        case $choice in
            1) run_install_script "$SCRIPT_DIR/node_exporter/install.sh" "Node Exporter" ;;
            2) run_install_script "$SCRIPT_DIR/ddns-go/install.sh" "DDNS-GO" ;;
            3) manage_wireguard ;;
            4) run_in_dir tailscale install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            5) manage_docker ;;
            6) run_in_dir fail2ban install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            7) run_in_dir openlist install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            8) run_in_dir uptime-kuma install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            9) run_in_dir cockpit install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            10) run_in_dir essential-pkgs install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            11) manage_sys_setup ;;
            12) run_in_dir swap install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            13) run_in_dir bbr install.sh enable; echo; read -r -p "按回车键返回主菜单..." ;;
            14) run_in_dir nvm install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            15) run_install_script "$SCRIPT_DIR/zsh_setup/install.sh" "Zsh & Oh My Zsh" ;;
            16) run_in_dir minikube install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            17) run_in_dir dev-tui install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            18) run_in_dir opencode install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            19) run_in_dir ollama install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            20) manage_shutdown_timer ;;
            21) manage_process_tool ;;
            22) run_in_dir deskflow install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            23) run_in_dir safe-rm install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            24) manage_clash ;;
            25) manage_multinet ;;
            s|S) show_installed_services ;;
            u|U)
                while true; do
                    show_uninstall_menu
                    read -r -p "请输入选项 [0-23]: " uninstall_choice
                    if ! do_uninstall "$uninstall_choice"; then
                        break
                    fi
                done
                ;;
            q|Q|0) info "感谢使用！再见！"; exit 0 ;;
            *) error "无效选项，请重新输入！"; sleep 1 ;;
        esac
    done
}

# --- 脚本入口 ---
main "$@"
