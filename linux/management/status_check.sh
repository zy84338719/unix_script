#!/usr/bin/env bash
#
# 系统状态检查 - Linux 平台
#

# 导入通用工具
source "${COMMON_DIR}/colors.sh"
source "${COMMON_DIR}/utils.sh"

# 检查服务状态
check_service_status() {
    local service_name="$1"
    local binary_path="$2"
    local port="$3"
    
    local installed=false
    local running=false
    local listening=false
    
    # 检查二进制文件是否存在
    if [[ -f "$binary_path" ]]; then
        installed=true
    fi
    
    # 检查服务状态
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        running=true
    fi
    
    # 检查端口监听
    if [[ -n "$port" ]] && check_port "$port"; then
        listening=true
    fi
    
    # 输出状态
    if $installed; then
        if $running; then
            if [[ -n "$port" ]] && $listening; then
                echo -e "${GREEN}✅ 已安装并运行${NC} (端口: $port)"
            elif [[ -n "$port" ]]; then
                echo -e "${YELLOW}⚠️  已安装并运行，但端口 $port 未监听${NC}"
            else
                echo -e "${GREEN}✅ 已安装并运行${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  已安装但服务未运行${NC}"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 检查 Node Exporter 状态
check_node_exporter() {
    print_info "Node Exporter:"
    check_service_status "node_exporter" "/usr/local/bin/node_exporter" "9100"
}

# 检查 DDNS-GO 状态  
check_ddns_go() {
    print_info "DDNS-GO:"
    check_service_status "ddns-go" "/opt/ddns-go/ddns-go" "9876"
}

# 检查 WireGuard 状态
check_wireguard() {
    print_info "WireGuard:"
    local wg_installed=false
    local service_running=false
    local interface="wg0"

    if command_exists wg; then
        wg_installed=true
    fi

    if systemctl is-active --quiet "wg-quick@${interface}" 2>/dev/null; then
        service_running=true
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

# 检查 Zsh 环境
check_zsh_environment() {
    print_info "Zsh & Oh My Zsh:"
    local zsh_installed=false
    local ohmyzsh_installed=false
    local is_default_shell=false
    
    if command_exists zsh; then
        zsh_installed=true
    fi
    
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ohmyzsh_installed=true
    fi
    
    if [[ "$SHELL" == *"zsh"* ]]; then
        is_default_shell=true
    fi
    
    if $zsh_installed && $ohmyzsh_installed; then
        if $is_default_shell; then
            echo -e "${GREEN}✅ 已安装并配置为默认Shell${NC}"
        else
            echo -e "${YELLOW}⚠️  已安装但未设为默认Shell${NC}"
        fi
    elif $zsh_installed; then
        echo -e "${YELLOW}⚠️  Zsh已安装，但Oh My Zsh未安装${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 检查进程管理工具
check_process_manager() {
    print_info "进程管理工具:"
    local pm_installed=false
    
    if [[ -f "$HOME/.tools/bin/pm" ]] && command_exists pm; then
        pm_installed=true
        echo -e "${GREEN}✅ 已安装${NC} (系统版本)"
    elif [[ -f "${LINUX_DIR}/tools/process_manager.sh" ]]; then
        echo -e "${YELLOW}⚠️  开发版本可用${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 检查关机定时器
check_shutdown_timer() {
    print_info "自动关机管理:"
    local timer_configured=false
    
    # 检查是否有相关的 crontab 或 systemd timer
    if crontab -l 2>/dev/null | grep -q "shutdown\|poweroff"; then
        timer_configured=true
    fi
    
    if $timer_configured; then
        echo -e "${GREEN}✅ 已配置定时关机${NC}"
    else
        echo -e "${RED}❌ 未配置${NC}"
    fi
}

# 显示系统信息
show_system_info() {
    print_header "📊 系统信息"
    echo "───────────────────────────────"
    echo "操作系统: $(uname -s) $(uname -r)"
    echo "CPU架构:  $(uname -m)"
    echo "主机名:   $(hostname)"
    echo "当前用户: $(whoami)"
    echo "Shell:    $SHELL"
    echo "───────────────────────────────"
    echo
}

# 主函数
main() {
    clear
    print_header "🐧 Linux 系统状态检查"
    echo "========================================"
    
    show_system_info
    
    print_header "📋 服务状态"
    echo "───────────────────────────────"
    check_node_exporter
    check_ddns_go  
    check_wireguard
    echo
    
    print_header "🛠️  开发环境状态"
    echo "───────────────────────────────"
    check_zsh_environment
    echo
    
    print_header "🔧 系统工具状态"
    echo "───────────────────────────────"
    check_process_manager
    check_shutdown_timer
    echo
    
    print_success "状态检查完成"
}

# 如果脚本被直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
