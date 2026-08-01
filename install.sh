#!/usr/bin/env bash
set -e
# status_*_module 函数通过 $(...) 命令替换被间接调用，SC2329 为误报
# shellcheck disable=SC2329

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
    echo "  15) dev-mirror       - 开发换源加速（npm/Go/Rust/Python，默认国内源）"
    echo "  16) Zsh & Oh My Zsh  - 自动配置 Zsh 开发环境"
    echo "  17) minikube         - 本地 Kubernetes 开发环境 (kubectl + minikube)"
    echo "  18) 终端 TUI 工具    - lazydocker + lazygit"
    echo "  19) Bun              - JavaScript/TypeScript 运行时与工具链"
    echo "  20) Deno             - 安全的 JavaScript/TypeScript 运行时"
    echo "  21) pnpm             - 快速节省磁盘的 Node.js 包管理器"
    echo "  22) Go               - Go 语言环境 (官方二进制)"
    echo "  23) Rust             - Rust 语言环境 (rustup, macOS+Linux)"
    echo "  24) 开发工具增强     - Neovim+LazyVim / git增强(delta) / tmux配置"
    echo "  25) 现代 CLI 工具    - bat/eza/rg/fd/fzf/zoxide/starship"
    echo
    echo "  --- AI 工具 ---"
    echo "  26) OpenCode         - 终端 AI 编程助手 (sst/opencode)"
    echo "  27) Ollama           - 本地大模型运行时 (跑 Llama/Qwen/DeepSeek)"
    echo "  28) Pi               - AI 编程代理框架 (pi.dev, 多模型/可扩展)"
    echo
    echo "  --- 系统工具 ---"
    echo "  29) 自动关机管理     - 设置临时或每日定时关机"
    echo "  30) 进程管理工具     - 智能搜索和管理系统进程"
    echo "  31) Deskflow         - 键鼠共享 (Flatpak, 仅 Linux 图形环境)"
    echo "  32) safe-rm 回收站   - 安全删除替代 rm，防误删灾难"
    echo "  33) Clash (mihomo)   - 代理核心 + 快速配置 + TUN 透明代理"
    echo "  34) 多网卡策略路由   - 指定服务/用户/端口走指定网卡"
    echo "  35) Docker 镜像导出   - 拉取公网镜像并导出为 .tar.gz（离线分发/备份）"
    echo
    echo "  --- 管理 ---"
    echo "  s) 查看已安装状态    - 检查服务和环境的安装情况"
    echo "  u) 卸载服务/环境     - 移除已安装的服务或环境"
    echo "  q) 退出"
    echo
    echo "========================================"
}

# ---------------- 状态检查函数 ----------------

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
status_node_exporter_module() { run_in_dir node_exporter install.sh status; }
status_ddns_go_module()    { run_in_dir ddns-go install.sh status; }
status_wireguard_module()  { run_in_dir wireguard install.sh status; }
status_zsh_module()        { run_in_dir zsh_setup install.sh status; }
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
status_dev_mirror_module() { run_in_dir dev-mirror install.sh status 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/ *$//'; }
status_safe_rm_module()   { run_in_dir safe-rm install.sh status; }
status_clash_module()     { run_in_dir clash install.sh status; }
status_multinet_module()  { run_in_dir multi-net install.sh status; }
status_docker_image_module() { run_in_dir docker-image install.sh status; }
status_opencode_module()  { run_in_dir opencode install.sh status; }
status_ollama_module()    { run_in_dir ollama install.sh status; }
status_bun_module()       { run_in_dir bun install.sh status; }
status_pi_module()        { run_in_dir pi install.sh status; }
status_deno_module()      { run_in_dir deno install.sh status; }
status_pnpm_module()      { run_in_dir pnpm install.sh status; }
status_go_module()        { run_in_dir go install.sh status; }
status_rust_module()      { run_in_dir rust install.sh status; }
status_dev_enhance_module() { run_in_dir dev-enhance install.sh status; }
status_modern_cli_module() { run_in_dir modern-cli install.sh status; }

# ---------------- 已安装状态总览 ----------------
show_installed_services() {
    if $INTERACTIVE; then clear; fi
    header "📊 已安装状态"
    echo "========================================"

    echo "--- 服务 ---"
    echo "Node Exporter:  $(status_node_exporter_module)"
    echo "DDNS-GO:        $(status_ddns_go_module)"
    echo "WireGuard:      $(status_wireguard_module)"
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
    echo "dev-mirror:     $(status_dev_mirror_module)"
    echo
    echo "--- 开发环境 ---"
    echo "Zsh 环境:       $(status_zsh_module)"
    echo "minikube:       $(status_minikube_module)"
    echo "终端 TUI 工具:  $(status_dev_tui_module)"
    echo "Bun:            $(status_bun_module)"
    echo "Deno:           $(status_deno_module)"
    echo "pnpm:           $(status_pnpm_module)"
    echo "Go:             $(status_go_module)"
    echo "Rust:           $(status_rust_module)"
status_rust_module()      { run_in_dir rust install.sh status; }
    echo "开发工具增强:   $(status_dev_enhance_module)"
    echo "现代 CLI 工具:  $(status_modern_cli_module)"
    echo
    echo "--- AI 工具 ---"
    echo "OpenCode:       $(status_opencode_module)"
    echo "Ollama:         $(status_ollama_module)"
    echo "Pi:             $(status_pi_module)"
status_deno_module()      { run_in_dir deno install.sh status; }
status_pnpm_module()      { run_in_dir pnpm install.sh status; }
status_go_module()        { run_in_dir go install.sh status; }
status_rust_module()      { run_in_dir rust install.sh status; }
    echo
    echo "--- 系统工具 ---"
    echo "自动关机任务:   $(check_shutdown_timer_status)"
    echo "进程管理工具:   $(check_process_manager_status)"
    echo "Deskflow:       $(status_deskflow_module)"
    echo "safe-rm 回收站: $(status_safe_rm_module)"
    echo "Clash (mihomo): $(status_clash_module)"
    echo "多网卡策略路由: $(status_multinet_module)"
    echo "Docker 镜像导出: $(status_docker_image_module)"

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

# ---------------- 机器可读输出（供 AI agent / 脚本解析）----------------

# --list-modules: TSV 输出模块名 + 支持的子命令
show_list_modules() {
    # 遍历所有模块目录，从 install.sh 的 usage 或 case 提取子命令
    local mod
    for mod_dir in "$SCRIPT_DIR"/*/; do
        mod=$(basename "$mod_dir")
        local script="$mod_dir/install.sh"
        [[ -f "$script" ]] || continue
        # 跳过非模块目录
        case "$mod" in lib|tests|process_manager_tool) continue ;; esac
        # 提取子命令：从 usage 行的 {install|...} 或 case 分支
        local subs=""
        local usage_line
        usage_line=$(grep -m1 '用法:' "$script" 2>/dev/null)
        if [[ "$usage_line" == *"{"*"}"* ]]; then
            subs=$(echo "$usage_line" | sed 's/.*{//;s/}.*//' | tr '|' ' ')
        fi
        # 若 usage 没提取到，尝试从 case 分支提取
        if [[ -z "$subs" ]]; then
            subs=$(grep -oE '^\s+(install|uninstall|status|help|mirror|unmirror|start|stop|restart|enable|disable|pull|all|config|example|tun-on|tun-off|clear|list|setup|route-user|route-port|save)\)' "$script" 2>/dev/null | tr -d ' )' | sort -u | tr '\n' ' ')
        fi
        [[ -z "$subs" ]] && subs="install"
        printf '%s\t%s\n' "$mod" "$subs"
    done
}

# --status-json: key:value 格式输出各模块状态（无颜色、无 emoji）
show_status_json() {
    detect_os
    detect_arch
    echo "os:$OS_TYPE"
    echo "arch:$ARCH_TYPE"
    echo "version:$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"
    # 遍历模块取 status（去 ANSI + emoji）
    local mod
    for mod_dir in "$SCRIPT_DIR"/*/; do
        mod=$(basename "$mod_dir")
        local script="$mod_dir/install.sh"
        [[ -f "$script" ]] || continue
        case "$mod" in lib|tests|process_manager_tool) continue ;; esac
        # 调模块 status，去 ANSI 颜色码
        local raw
        raw=$(bash "$script" status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | head -1 || echo "unknown")
        # 归一化：提取关键字
        local val="unknown"
        if echo "$raw" | grep -qiE '✅|已安装并运行'; then
            val="installed:running"
        elif echo "$raw" | grep -qiE '已安装但未运行|已安装，但|已安装但服务'; then
            val="installed:stopped"
        elif echo "$raw" | grep -qiE '已安装'; then
            val="installed"
        elif echo "$raw" | grep -qiE '未安装'; then
            val="not_installed"
        elif echo "$raw" | grep -qiE '不适用|仅 Linux'; then
            val="n/a"
        elif echo "$raw" | grep -qiE '已配置'; then
            val="configured"
        elif echo "$raw" | grep -qiE '未配置'; then
            val="not_configured"
        fi
        printf '%s:%s\n' "$mod" "$val"
    done
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

# ---------------- 开发换源加速（npm/Go/Rust/Python）----------------
manage_dev_mirror() {
    local script_path="$SCRIPT_DIR/dev-mirror/install.sh"
    [ -f "$script_path" ] || { error "脚本不存在: $script_path"; sleep 2; return; }
    chmod +x "$script_path"

    while true; do
        clear
        header "📦 dev-mirror 管理（npm/Go/Rust/Python 换源加速）"
        echo "========================================"
        echo "当前镜像状态："
        run_in_dir dev-mirror install.sh status 2>/dev/null | sed 's/^/  /'
        echo
        menu "请选择操作："
        echo "  1) 换源 - 交互选择（生态 + 源）"
        echo "  2) 一键全部换国内默认源（npm/Go/Rust/Python）"
        echo "  3) 还原官方源 - 交互选择生态"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-3]: " dm_choice

        case $dm_choice in
            1) run_in_dir dev-mirror install.sh install; echo; read -r -p "按回车键继续..." ;;
            2) run_in_dir dev-mirror install.sh install all default; echo; read -r -p "按回车键继续..." ;;
            3) run_in_dir dev-mirror install.sh uninstall; echo; read -r -p "按回车键继续..." ;;
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



# 卸载 Zsh & Oh My Zsh（显示说明）

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
    echo "  24) 还原开发镜像源 (dev-mirror: npm/Go/Rust/Python)"
    echo "  25) 卸载 Pi"
    echo "  0) 返回主菜单"
    echo
    echo "========================================"
}

# 处理卸载选择
do_uninstall() {
    local choice="$1"
    case $choice in
        1) if yes_no "确认卸载 Node Exporter？"; then run_in_dir node_exporter install.sh uninstall; fi ;;
        2) if yes_no "确认卸载 DDNS-GO？"; then run_in_dir ddns-go install.sh uninstall; fi ;;
        3) if yes_no "确认卸载 WireGuard 服务和相关配置？"; then run_in_dir wireguard install.sh uninstall; fi ;;
        4) run_in_dir tailscale install.sh uninstall ;;
        5) run_in_dir docker install.sh uninstall ;;
        6) run_in_dir fail2ban install.sh uninstall ;;
        7) run_in_dir openlist install.sh uninstall ;;
        8) run_in_dir uptime-kuma install.sh uninstall ;;
        9) run_in_dir cockpit install.sh uninstall ;;
        10) run_in_dir zsh_setup install.sh uninstall ;;
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
        24) run_in_dir dev-mirror install.sh uninstall all <<< "y" ;;
        25) run_in_dir pi install.sh uninstall ;;
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
        node_exporter|nodeexporter) run_in_dir node_exporter install.sh install ;;
        ddns-go|ddnsgo|ddns)        run_in_dir ddns-go install.sh install ;;
        wireguard|wg)               run_in_dir wireguard install.sh install ;;
        tailscale|ts)               run_in_dir tailscale install.sh install ;;
        docker)                     run_in_dir docker install.sh install ;;
        fail2ban|f2b)               run_in_dir fail2ban install.sh install ;;
        openlist)                    run_in_dir openlist install.sh install ;;
        uptime-kuma|uptime_kuma)    run_in_dir uptime-kuma install.sh install ;;
        cockpit)                    run_in_dir cockpit install.sh install ;;
        dev-tui|dev_tui|tui)        run_in_dir dev-tui install.sh install ;;
        bun)                        run_in_dir bun install.sh install ;;
        pi)                         run_in_dir pi install.sh install ;;
        deno)                       run_in_dir deno install.sh install ;;
        pnpm)                       run_in_dir pnpm install.sh install ;;
        go|golang)                  run_in_dir go install.sh install ;;
        rust|rustup)                run_in_dir rust install.sh install ;;
        dev-enhance)                run_in_dir dev-enhance install.sh install ;;
        modern-cli|modern_cli|moderncli) run_in_dir modern-cli install.sh install ;;
        opencode)                   run_in_dir opencode install.sh install ;;
        ollama)                     run_in_dir ollama install.sh install ;;
        essential-pkgs|essential_pkgs|essential) run_in_dir essential-pkgs install.sh install ;;
        sys-setup|sys_setup)        run_in_dir sys-setup install.sh all ;;
        swap)                       run_in_dir swap install.sh install ;;
        bbr)                        run_in_dir bbr install.sh enable ;;
        nvm)                        run_in_dir nvm install.sh install ;;
        dev-mirror|dev_mirror|devmirror) run_in_dir dev-mirror install.sh install all default ;;
        npm-mirror|npm_mirror|npmmirror) run_in_dir dev-mirror install.sh install npm taobao ;;
        safe-rm|safe_rm|safesrm)    run_in_dir safe-rm install.sh install ;;
        clash|mihomo)               run_in_dir clash install.sh install ;;
        multi-net|multinet|multi_net) run_in_dir multi-net install.sh list ;;
        docker-image|docker_image|dockerimage) run_in_dir docker-image install.sh save ;;
        zsh)                        run_in_dir zsh_setup install.sh install ;;
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
  --list-modules    机器可读：模块名 + 支持子命令（TSV，供 AI/脚本）
  --status-json     机器可读：模块状态 key:value（无颜色，供 AI/脚本）
  check-update      检查远端是否有新版本（不修改本地）
  update            安全检查 + 确认后执行 git pull 更新本地仓库
  cli               安装全局命令 uxs 到 ~/.tools/bin（之后可在任意目录 uxs <子命令>）
  uninstall-cli     卸载全局命令 uxs
  check-update      检查远端是否有新版本（不修改本地）
  update            安全检查 + 确认后执行 git pull 更新本地仓库
  cli               安装全局命令 uxs 到 ~/.tools/bin（之后可在任意目录 uxs <子命令>）
  uninstall-cli     卸载全局命令 uxs

模块名（用于非交互安装）:
  node_exporter | ddns-go | wireguard | tailscale | docker |
  fail2ban | openlist | uptime-kuma | cockpit |
  essential-pkgs | sys-setup | swap | bbr | nvm | dev-mirror |
  zsh | minikube | dev-tui | bun | pi | deno | pnpm | go | rust | dev-enhance | modern-cli | opencode | ollama | docker-image | deskflow | shutdown_timer | process_manager | safe-rm | clash | multi-net

示例:
  $0                       # 进入交互式主菜单
  $0 --status              # 直接打印安装状态
  $0 docker                # 直接安装 docker
  $0 tailscale             # 直接安装 tailscale
  $0 check-update          # 检查是否有新版本
  $0 update                # 更新到最新版本（需确认）
  $0 cli                   # 安装全局命令 uxs（之后可 uxs docker-image 等）
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

# ---------------- 安装为全局命令 (uxs) ----------------
# 将本仓库的 install.sh 包装成全局命令 `uxs`，安装到 ~/.tools/bin/ 并配置 PATH。
# 之后用户可在任意目录直接：uxs docker-image / uxs --status / uxs check-update
UXS_CMD_NAME="uxs"
UXS_TOOLS_BIN="$HOME/.tools/bin"

# 检测当前用户的 shell 及对应 rc 文件，设置 UXS_SHELL_RC / UXS_USER_SHELL。
detect_shell_rc() {
    UXS_USER_SHELL="$(basename "${SHELL:-/bin/sh}")"
    case "$UXS_USER_SHELL" in
        bash)
            if [[ "$OS_TYPE" == "darwin" ]]; then
                UXS_SHELL_RC="$HOME/.bash_profile"
            else
                UXS_SHELL_RC="$HOME/.bashrc"
            fi
            ;;
        zsh)  UXS_SHELL_RC="$HOME/.zshrc" ;;
        fish) UXS_SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)    UXS_SHELL_RC="$HOME/.profile" ;;
    esac
}

# 安装 uxs 命令：创建 wrapper + symlink + 配置 PATH
install_cli() {
    detect_os
    detect_shell_rc

    header "🔧 安装全局命令：uxs"
    echo "───────────────────────────────"

    # 1) 创建 ~/.tools/bin 目录
    if [[ ! -d "$UXS_TOOLS_BIN" ]]; then
        info "创建目录：$UXS_TOOLS_BIN"
        mkdir -p "$UXS_TOOLS_BIN" || { error "无法创建 $UXS_TOOLS_BIN"; return 1; }
    fi

    # 2) 创建 wrapper 脚本（指向本仓库 install.sh，透传所有参数）
    #    用 wrapper 而非直接 symlink，是为了固定 SCRIPT_DIR，使相对路径模块调用正确。
    local repo_install="$SCRIPT_DIR/install.sh"
    if [[ ! -f "$repo_install" ]]; then
        error "未找到 install.sh：$repo_install"
        return 1
    fi
    local wrapper="$UXS_TOOLS_BIN/$UXS_CMD_NAME"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
# 由 unix_script install.sh cli 生成 —— 全局命令 uxs
# 透传所有参数给仓库的 install.sh
exec bash "$repo_install" "\$@"
EOF
    chmod +x "$wrapper"
    success "已创建命令：$wrapper → $repo_install"

    # 3) 配置 PATH（若已包含则跳过）
    if echo "$PATH" | grep -q "$UXS_TOOLS_BIN"; then
        info "PATH 中已包含 $UXS_TOOLS_BIN"
    else
        info "配置 PATH（写入 $UXS_USER_SHELL 的 $UXS_SHELL_RC）..."
        if ! grep -q "/.tools/bin" "$UXS_SHELL_RC" 2>/dev/null; then
            # 备份 rc 文件（若存在）
            if [[ -f "$UXS_SHELL_RC" ]]; then
                cp "$UXS_SHELL_RC" "${UXS_SHELL_RC}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            fi
            if [[ "$UXS_USER_SHELL" == "fish" ]]; then
                {
                    echo ""
                    echo "# 添加 ~/.tools/bin 到 PATH（由 unix_script cli 添加）"
                    echo "set -gx PATH \$HOME/.tools/bin \$PATH"
                } >> "$UXS_SHELL_RC"
            else
                {
                    echo ""
                    echo "# 添加 ~/.tools/bin 到 PATH（由 unix_script cli 添加）"
                    # shellcheck disable=SC2016  # 故意用单引号：字面写入 rc，运行时再展开
                    echo 'export PATH="$HOME/.tools/bin:$PATH"'
                } >> "$UXS_SHELL_RC"
            fi
            success "已更新 $UXS_SHELL_RC"
        else
            info "$UXS_SHELL_RC 已含 ~/.tools/bin 配置（跳过）"
        fi
    fi

    echo
    header "✅ 安装完成"
    echo "  命令：uxs"
    echo "  位置：$wrapper"
    echo
    if echo "$PATH" | grep -q "$UXS_TOOLS_BIN"; then
        info "当前 shell 已可直接使用，试运行：uxs --version"
    else
        warn "PATH 尚未在当前 shell 生效，请执行以下任一操作："
        echo "    source $UXS_SHELL_RC      # 当前终端立即生效"
        echo "    # 或重新打开终端"
    fi
    echo
    info "用法示例：uxs docker-image  |  uxs --status  |  uxs check-update  |  uxs update"
}

# 卸载 uxs 命令：删除 wrapper，并清理 PATH 配置（可选）
uninstall_cli() {
    detect_os
    detect_shell_rc

    header "🗑️  卸载全局命令：uxs"
    echo "───────────────────────────────"

    local wrapper="$UXS_TOOLS_BIN/$UXS_CMD_NAME"
    local removed=false

    # 1) 删除 wrapper
    if [[ -f "$wrapper" ]]; then
        rm -f "$wrapper" && success "已删除：$wrapper" && removed=true
    else
        info "未找到 $wrapper（可能未安装）"
    fi

    # 2) 询问是否清理 PATH 配置
    if [[ -f "$UXS_SHELL_RC" ]] && grep -q "/.tools/bin" "$UXS_SHELL_RC" 2>/dev/null; then
        echo
        warn "$UXS_SHELL_RC 中含 ~/.tools/bin 的 PATH 配置。"
        warn "（注意：process_manager 等其它工具可能也在用该目录，清理需谨慎）"
        if yes_no "是否从 $UXS_SHELL_RC 移除 ~/.tools/bin 的 PATH 配置？"; then
            cp "$UXS_SHELL_RC" "${UXS_SHELL_RC}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            # 删除本工具写入的 PATH 行（含标识注释）
            if [[ "$UXS_USER_SHELL" == "fish" ]]; then
                sed -i.tmp '/# 添加 .*\.tools\/bin 到 PATH（由 unix_script cli 添加）/,/^$/d' "$UXS_SHELL_RC" 2>/dev/null || true
            else
                sed -i.tmp '/# 添加 .*\.tools\/bin 到 PATH（由 unix_script cli 添加）/,/^$/d' "$UXS_SHELL_RC" 2>/dev/null || true
            fi
            rm -f "${UXS_SHELL_RC}.tmp" 2>/dev/null || true
            success "已从 $UXS_SHELL_RC 移除本工具添加的 PATH 配置"
        else
            info "保留 PATH 配置（~/.tools/bin 仍可用）"
        fi
    fi

    echo
    if $removed; then
        success "uxs 命令已卸载"
    else
        warn "无需清理的内容"
    fi
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
        # stdin 非 TTY（如 curl|bash 管道场景）：read 收不到终端输入，
        # 菜单会因 EOF 无限循环。此时不进菜单，改为打印帮助+提示后退出。
        if [[ ! -t 0 ]]; then
            warn "检测到非交互环境（标准输入来自管道，无法显示菜单）。"
            echo
            info "若要使用交互式菜单，请先克隆仓库后在终端直接运行："
            echo "    git clone https://github.com/zy84338719/unix_script && cd unix_script && ./install.sh"
            echo
            info "或通过 bootstrap 透传参数（非交互），例如："
            echo "    curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- --status"
            echo "    curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- docker"
            echo
            show_usage
            exit 0
        fi
        interactive_main
        return
    fi

    # 处理参数
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        -v|--version) echo "unix_script $(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo unknown)"; exit 0 ;;
        -s|--status)  INTERACTIVE=false; show_installed_services; exit 0 ;;
        --list)
            echo "node_exporter ddns-go wireguard tailscale docker fail2ban openlist uptime-kuma cockpit essential-pkgs sys-setup swap bbr nvm dev-mirror zsh minikube dev-tui bun pi deno pnpm go rust dev-enhance modern-cli opencode ollama deskflow shutdown_timer process_manager safe-rm clash multi-net docker-image"
            exit 0
            ;;
        --list-modules)
            show_list_modules
            exit 0
            ;;
        --status-json)
            show_status_json
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
        cli|install-cli)
            install_cli
            exit $?
            ;;
        uninstall-cli|remove-cli)
            uninstall_cli
            exit $?
            ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)
            # 支持透传模块子命令：如 `install.sh bun mirror`、`install.sh clash start`
            # 当第一个参数是已知的模块目录、且第二个参数存在时，转发给该模块的 install.sh
            if [[ $# -ge 2 ]] && [[ -d "$SCRIPT_DIR/$1" ]] && [[ -f "$SCRIPT_DIR/$1/install.sh" ]]; then
                local mod="$1"; shift
                info "执行模块 $mod: install.sh $*"
                run_in_dir "$mod" install.sh "$@"
            else
                dispatch_module "$1"
            fi
            ;;
    esac
}

# 交互式主循环
interactive_main() {
    while true; do
        show_main_menu
        read -r -p "请输入选项: " choice
        case $choice in
            1) run_in_dir node_exporter install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            2) run_in_dir ddns-go install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            3) run_in_dir wireguard install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
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
            15) manage_dev_mirror ;;
            16) run_in_dir zsh_setup install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            17) run_in_dir minikube install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            18) run_in_dir dev-tui install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            19) run_in_dir bun install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            20) run_in_dir deno install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            21) run_in_dir pnpm install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            22) run_in_dir go install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            23) run_in_dir rust install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            24) run_in_dir dev-enhance install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            25) run_in_dir modern-cli install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            26) run_in_dir opencode install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            27) run_in_dir ollama install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            28) run_in_dir pi install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            29) manage_shutdown_timer ;;
            30) manage_process_tool ;;
            31) run_in_dir deskflow install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            32) run_in_dir safe-rm install.sh install; echo; read -r -p "按回车键返回主菜单..." ;;
            33) manage_clash ;;
            34) manage_multinet ;;
            35) run_in_dir docker-image install.sh save; echo; read -r -p "按回车键返回主菜单..." ;;
            s|S) show_installed_services ;;
            u|U)
                while true; do
                    show_uninstall_menu
                    read -r -p "请输入选项 [0-25]: " uninstall_choice
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
