#!/usr/bin/env bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${CYAN}$1${NC}"; }
print_menu() { echo -e "${PURPLE}$1${NC}"; }

# 检查操作系统
check_os() {
    os_name=$(uname -s)
    case "$os_name" in
        "Darwin")
            OS_TYPE="macOS"
            ;;
        "Linux")
            OS_TYPE="Linux"
            ;;
        *)
            print_error "不支持的操作系统：$os_name"
            exit 1
            ;;
    esac
}

# 检查架构
check_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            ARCH_TYPE="x86_64"
            ;;
        aarch64|arm64)
            ARCH_TYPE="ARM64"
            ;;
        armv7l)
            ARCH_TYPE="ARMv7"
            ;;
        *)
            ARCH_TYPE="$arch"
            ;;
    esac
}

# 显示系统信息
show_system_info() {
    print_header "🖥️  系统信息"
    echo "───────────────────────────────"
    echo "操作系统: $OS_TYPE"
    echo "CPU架构:  $ARCH_TYPE"
    echo "───────────────────────────────"
    echo
}

# 显示主菜单
show_main_menu() {
    clear
    print_header "🚀 一键安装脚本 - 服务与环境管理工具"
    echo "========================================"
    show_system_info
    
    print_menu "请选择要安装的服务或配置环境："
    echo
    echo "  --- 服务安装 ---"
    echo "  1) Node Exporter     - Prometheus 系统监控数据收集器"
    echo "  2) DDNS-GO           - 动态域名解析服务"
    echo "  3) WireGuard         - 现代、快速、安全的 VPN"
    echo
    echo "  --- 开发环境配置 ---"
    echo "  4) Zsh & Oh My Zsh   - 自动配置 Zsh 开发环境"
    echo
    echo "  --- 系统工具 ---"
    echo "  5) 自动关机管理     - 设置临时或每日定时关机"
    echo "  6) 进程管理工具     - 智能搜索和管理系统进程"
    echo
    echo "  --- Kubernetes 开发 ---"
    echo "  7) minikube 环境    - 本地 Kubernetes 开发环境"
    echo
    echo "  --- 管理 ---"
    echo "  8) 查看已安装状态    - 检查服务和环境的安装情况"
    echo "  9) 卸载服务/环境     - 移除已安装的服务或环境"
    echo "  0) 退出"
    echo
    echo "========================================"
}

# 检查服务是否已安装
check_service_status() {
    local service_name="$1"
    local binary_path="$2"
    local service_file="$3"
    
    local is_installed=false
    local is_running=false
    local version=""
    
    # 检查二进制文件是否存在
    if command -v "$service_name" &> /dev/null || [ -f "$binary_path" ]; then
        is_installed=true
        if command -v "$service_name" &> /dev/null; then
            version=$($service_name --version 2>/dev/null | head -1 || echo "未知版本")
        fi
    fi
    
    # 检查服务是否运行
    if [[ "$OS_TYPE" == "Linux" ]]; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            is_running=true
        fi
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        if sudo launchctl list | grep -q "$service_file" 2>/dev/null; then
            is_running=true
        fi
    fi
    
    # 返回状态
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

# 检查每日关机任务是否已配置
check_shutdown_timer_status() {
    local is_configured=false
    if [[ "$OS_TYPE" == "macOS" ]]; then
        if [ -f "/Library/LaunchDaemons/com.user.dailyshutdown.plist" ]; then
            is_configured=true
        fi
    elif [[ "$OS_TYPE" == "Linux" ]]; then
        # crontab -l 在没有 crontab 时会返回非零退出码
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

# 检查 WireGuard 是否已安装
check_wireguard_status() {
    local wg_installed=false
    local service_running=false
    local interface="wg0"

    if command -v wg &> /dev/null; then
        wg_installed=true
    fi

    if [[ "$OS_TYPE" == "Linux" ]]; then
        if systemctl is-active --quiet "wg-quick@${interface}" 2>/dev/null; then
            service_running=true
        fi
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        if sudo launchctl list | grep -q "com.wireguard.${interface}" 2>/dev/null; then
            service_running=true
        fi
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

# 管理 WireGuard 的子菜单
manage_wireguard() {
    local script_path="./wireguard/install.sh"

    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        sleep 2
        return
    fi
    chmod +x "$script_path"

    while true; do
        clear
        print_header "🔧 WireGuard 管理"
        echo "========================================"
        echo "当前状态:"
        echo "  - WireGuard 工具: $(command -v wg &>/dev/null && echo -e "${GREEN}✅ 已安装${NC}" || echo -e "${RED}❌ 未安装${NC}")"
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
        print_menu "请选择操作:"
        echo "  1) 安装/更新 WireGuard 工具"
        echo "  2) 配置/重置开机自启服务"
        echo "  0) 返回主菜单"
        echo "========================================"
        read -r -p "请输入选项 [0-2]: " wg_choice

        case $wg_choice in
            1)
                print_info "正在调用 WireGuard 工具安装脚本..."
                "$script_path" install_tools
                echo
                read -r -p "按回车键继续..."
                ;;
            2)
                print_info "正在调用 WireGuard 服务配置脚本..."
                "$script_path" configure_service
                echo
                read -r -p "按回车键继续..."
                ;;
            0)
                break
                ;;
            *)
                print_error "无效选项，请重新输入！"
                sleep 1
                ;;
        esac
    done
}

# 检查 Zsh 和 Oh My Zsh 是否已安装
check_zsh_status() {
    local zsh_installed=false
    local omz_installed=false
    
    if command -v zsh &> /dev/null; then
        zsh_installed=true
    fi
    
    if [ -d "$HOME/.oh-my-zsh" ]; then
        omz_installed=true
    fi
    
    if $zsh_installed && $omz_installed; then
        echo -e "${GREEN}✅ Zsh & Oh My Zsh 已安装${NC}"
    elif $zsh_installed; then
        echo -e "${YELLOW}⚠️  已安装 Zsh，但未安装 Oh My Zsh${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 检查进程管理工具是否已安装
check_process_manager_status() {
    local is_installed=false
    
    # 检查是否安装到 ~/.tools/bin
    if [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ]; then
        is_installed=true
    fi
    
    if $is_installed; then
        # 检查 PATH 是否包含 ~/.tools/bin
        if echo "$PATH" | grep -q "$HOME/.tools/bin"; then
            echo -e "${GREEN}✅ 已安装并配置${NC}"
        else
            echo -e "${YELLOW}⚠️  已安装但PATH未配置${NC}"
        fi
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# 检查 minikube 状态
check_minikube_status() {
    local install_dir="$HOME/.tools/minikube"
    local kubectl_path="$install_dir/bin/kubectl"
    local minikube_path="$install_dir/bin/minikube"
    
    if [[ -d "$install_dir" && -x "$kubectl_path" && -x "$minikube_path" ]]; then
        # 检查是否在 PATH 中
        if echo "$PATH" | grep -q "$install_dir/bin"; then
            # 检查集群状态
            if command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then
                echo "✅ 已安装并运行"
            else
                echo "🟡 已安装未运行"
            fi
        else
            echo "🟡 已安装需配置"
        fi
    else
        echo "❌ 未安装"
    fi
}


# 显示已安装服务状态
show_installed_services() {
    clear
    print_header "📊 已安装状态"
    echo "========================================"
    
    echo "--- 服务 ---"
    echo "Node Exporter:  $(check_service_status "1" "/usr/local/bin/node_exporter" "com.prometheus.node_exporter")"
    echo "DDNS-GO:        $(check_service_status "ddns-go" "/opt/ddns-go/ddns-go" "jeessy.ddns-go")"
    echo "WireGuard:      $(check_wireguard_status)"
    echo
    echo "--- 开发环境 ---"
    echo "Zsh 环境:       $(check_zsh_status)"
    echo
    echo "--- 系统工具 ---"
    echo "自动关机任务: $(check_shutdown_timer_status)"
    echo "进程管理工具: $(check_process_manager_status)"
    echo
    echo "--- Kubernetes 开发 ---"
    echo "minikube 环境:  $(check_minikube_status)"

    echo
    echo "========================================"
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        print_info "Linux 服务管理命令："
        echo "  查看状态: sudo systemctl status <service-name>"
        echo "  查看日志: sudo journalctl -u <service-name> -f"
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        print_info "macOS 服务管理命令："
        echo "  查看状态: sudo launchctl list | grep <service>"
        echo "  查看日志: tail -f /var/log/<service>.log"
    fi
    
    echo
    read -r -p "按回车键返回主菜单..."
}

# 卸载服务菜单
show_uninstall_menu() {
    clear
    print_header "🗑️  卸载服务与环境"
    echo "========================================"
    
    print_warning "注意：卸载操作将完全移除服务及其配置文件！"
    echo
    
    echo "  1) 卸载 Node Exporter"
    echo "  2) 卸载 DDNS-GO"
    echo "  3) 卸载 WireGuard (服务和配置)"
    echo "  4) 卸载 Zsh & Oh My Zsh (查看说明)"
    echo "  5) 取消每日自动关机任务"
    echo "  6) 卸载进程管理工具"
    echo "  7) 卸载 minikube 环境"
    echo "  0) 返回主菜单"
    echo
    echo "========================================"
}

# 卸载 Node Exporter
uninstall_node_exporter() {
    print_info "正在卸载 Node Exporter..."
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        sudo systemctl stop node_exporter &>/dev/null || true
        sudo systemctl disable node_exporter &>/dev/null || true
        sudo rm -f /etc/systemd/system/node_exporter.service
        sudo systemctl daemon-reload &>/dev/null || true
        sudo rm -f /usr/local/bin/node_exporter
        # 只有当用户存在时才尝试删除
        if id "node_exporter" &>/dev/null; then
            sudo userdel node_exporter
        fi
        print_success "Node Exporter 已卸载。"
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        sudo launchctl bootout system /Library/LaunchDaemons/com.prometheus.node_exporter.plist &>/dev/null || true
        sudo rm -f /Library/LaunchDaemons/com.prometheus.node_exporter.plist
        sudo rm -f /usr/local/bin/node_exporter
        sudo rm -f /var/log/node_exporter.log
        sudo rm -f /var/log/node_exporter.err
    fi
    
    print_success "Node Exporter 已成功卸载！"
}

# 取消每日自动关机
uninstall_shutdown_timer() {
    print_info "正在取消每日自动关机任务..."
    local script_path="./shutdown_timer/shutdown_timer.sh"
    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        return
    fi
    # 使用脚本自身的取消功能
    chmod +x "$script_path"
    # 非交互式地调用取消功能
    "$script_path" cancel_daily_shutdown_internal
}

# 卸载 DDNS-GO
uninstall_ddns_go() {
    print_info "正在卸载 DDNS-GO..."
    
    if [[ "$OS_TYPE" == "Linux" ]]; then
        sudo systemctl stop ddns-go &>/dev/null || true
        sudo systemctl disable ddns-go &>/dev/null || true
        sudo rm -rf /opt/ddns-go
        sudo systemctl daemon-reload
    elif [[ "$OS_TYPE" == "macOS" ]]; then
        sudo launchctl bootout system /Library/LaunchDaemons/jeessy.ddns-go.plist &>/dev/null || true
        sudo rm -f /Library/LaunchDaemons/jeessy.ddns-go.plist
        sudo rm -rf /opt/ddns-go
    fi
    
    print_success "DDNS-GO 已成功卸载！"
}

# 卸载 WireGuard
uninstall_wireguard() {
    local script_path="./wireguard/install.sh"
    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        return
    fi

    print_info "正在卸载 WireGuard 开机自启服务..."
    "$script_path" uninstall_service

    echo
    read -r -p "是否删除 /etc/wireguard/ 目录下的 .conf 配置文件？[y/N]: " -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$OS_TYPE" == "Linux" ]]; then
            sudo rm -f /etc/wireguard/*.conf
        elif [[ "$OS_TYPE" == "macOS" ]]; then
            sudo rm -f /usr/local/etc/wireguard/*.conf
        fi
        print_success "配置文件已删除。"
    fi

    print_warning "服务已移除。要完全卸载，请使用包管理器 (e.g., apt, brew) 手动移除 'wireguard-tools'。"
    print_success "WireGuard 卸载完成！"
}

# 卸载 Zsh & Oh My Zsh (提供说明)
uninstall_zsh_omz() {
    print_warning "卸载 Zsh 和 Oh My Zsh 是一个敏感操作，建议手动执行以避免风险。"
    print_info "Oh My Zsh 官方提供了一个卸载脚本，您可以运行它："
    echo "  uninstall_oh_my_zsh"
    echo
    print_info "卸载 Zsh 本身，请使用系统的包管理器，例如："
    echo "  - Ubuntu/Debian: sudo apt-get remove --purge zsh"
    echo "  - CentOS/RHEL:   sudo yum remove zsh"
    echo "  - macOS (Homebrew): brew uninstall zsh"
    echo
    print_warning "在卸载 Zsh 之前，请务必将您的默认 shell 切换回 bash 或其他 shell！"
    echo "  chsh -s /bin/bash"
    echo
    print_info "更多详细信息，请参考项目的 README.md 文档。"
}


# 执行安装脚本
run_install_script() {
    local script_path="$1"
    local service_name="$2"
    
    if [ ! -f "$script_path" ]; then
        print_error "安装脚本不存在：$script_path"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        print_info "设置脚本执行权限..."
        chmod +x "$script_path"
    fi
    
    print_info "开始安装 $service_name..."
    echo
    
    if "$script_path"; then
        echo
        print_success "$service_name 安装完成！"
    else
        echo
        print_error "$service_name 安装失败！"
        return 1
    fi
    
    echo
    read -r -p "按回车键返回主菜单..."
}

# 主函数
main() {
    # 检查系统信息
    check_os
    check_arch
    
    while true; do
        show_main_menu
        
        read -r -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1)
                run_install_script "./node_exporter/install.sh" "Node Exporter"
                ;;
            2)
                run_install_script "./ddns-go/install.sh" "DDNS-GO"
                ;;
            3)
                manage_wireguard
                ;;
            4)
                run_install_script "./zsh_setup/install.sh" "Zsh & Oh My Zsh"
                ;;
            5)
                manage_shutdown_timer
                ;;
            6)
                manage_process_tool
                ;;
            7)
                manage_minikube
                ;;
            8)
                show_installed_services
                ;;
            9)
                while true; do
                    show_uninstall_menu
                    read -r -p "请输入选项 [0-7]: " uninstall_choice
                    
                    case $uninstall_choice in
                        1)
                            echo
                            read -r -p "确认卸载 Node Exporter？[y/N]: " -n 1
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_node_exporter
                                echo
                                read -r -p "按回车键继续..."
                            fi
                            ;;
                        2)
                            echo
                            read -r -p "确认卸载 DDNS-GO？[y/N]: " -n 1
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_ddns_go
                                echo
                                read -r -p "按回车键继续..."
                            fi
                            ;;
                        3)
                            echo
                            read -r -p "确认卸载 WireGuard 服务和相关配置？[y/N]: " -n 1
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                uninstall_wireguard
                                echo
                                read -r -p "按回车键继续..."
                            fi
                            ;;
                        4)
                            print_warning "卸载 Zsh & Oh My Zsh 是一个敏感操作，建议您按照 README 中的说明手动执行。"
                            read -r -p "按回车键返回..."
                            ;;
                        5)
                            uninstall_shutdown_timer
                            read -r -p "按回车键继续..."
                            ;;
                        6)
                            echo
                            read -r -p "确认卸载进程管理工具？[y/N]: " -n 1
                            echo
                            if [[ $REPLY =~ ^[Yy]$ ]]; then
                                print_info "开始卸载进程管理工具..."
                                local uninstall_script="./process_manager_tool/install_process_manager.sh"
                                if [ -f "$uninstall_script" ]; then
                                    chmod +x "$uninstall_script"
                                    cd process_manager_tool && bash install_process_manager.sh uninstall && cd ..
                                else
                                    print_error "卸载脚本不存在: $uninstall_script"
                                fi
                                echo
                                read -r -p "按回车键继续..."
                            fi
                            ;;
                        0)
                            break
                            ;;
                        *)
                            print_error "无效选项，请重新输入！"
                            sleep 1
                            ;;
                    esac
                done
                ;;
            0)
                print_info "感谢使用！再见！"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新输入！"
                sleep 1
                ;;
        esac
    done
}

# 管理自动关机脚本
manage_shutdown_timer() {
    local script_path="./shutdown_timer/shutdown_timer.sh"
    if [ ! -f "$script_path" ]; then
        print_error "脚本不存在: $script_path"
        sleep 2
        return
    fi
    chmod +x "$script_path"
    # 直接执行脚本，进入其交互式菜单
    clear
    "$script_path"
    print_info "已从自动关机管理返回主菜单。"
    read -r -p "按回车键继续..."
}

# 管理进程管理工具
manage_process_tool() {
    clear
    print_header "🔧 进程管理工具"
    echo "========================================"
    
    local install_script="./process_manager_tool/install_process_manager.sh"
    local process_script="./process_manager_tool/process_manager.sh"
    local wrapper_script="./process_manager_tool/pm_wrapper.sh"
    
    # 检查是否已安装
    local is_installed=false
    if [ -f "$HOME/.tools/bin/process_manager" ] && [ -f "$HOME/.tools/bin/pm" ]; then
        is_installed=true
        print_success "✅ 进程管理工具已安装到 ~/.tools/bin"
    else
        print_info "ℹ️  进程管理工具尚未安装"
    fi
    
    echo
    print_menu "请选择操作："
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
            echo
            print_info "开始安装进程管理工具..."
            if [ ! -f "$install_script" ]; then
                print_error "安装脚本不存在: $install_script"
                sleep 2
                return
            fi
            chmod +x "$install_script"
            cd process_manager_tool && bash install_process_manager.sh && cd ..
            echo
            read -r -p "按回车键继续..."
            ;;
        2)
            echo
            print_info "检查系统依赖..."
            local check_script="./process_manager_tool/check_dependencies.sh"
            if [ ! -f "$check_script" ]; then
                print_error "依赖检查脚本不存在: $check_script"
                sleep 2
                return
            fi
            chmod +x "$check_script"
            cd process_manager_tool && bash check_dependencies.sh && cd ..
            echo
            read -r -p "按回车键继续..."
            ;;
        3)
            echo
            if [ "$is_installed" = true ]; then
                print_info "运行已安装的进程管理工具..."
                if command -v pm >/dev/null 2>&1; then
                    pm
                else
                    print_warning "pm 命令不可用，请重新加载 Shell 配置或重启终端"
                    print_info "手动运行: source ~/.bashrc 或 source ~/.zshrc"
                fi
            else
                print_info "运行开发版本的进程管理工具..."
                if [ ! -f "$process_script" ]; then
                    print_error "脚本不存在: $process_script"
                    sleep 2
                    return
                fi
                chmod +x "$process_script"
                cd process_manager_tool && bash process_manager.sh && cd ..
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        4)
            echo
            print_info "查看工具配置和状态..."
            if [ "$is_installed" = true ]; then
                if command -v pm >/dev/null 2>&1; then
                    pm --config
                else
                    print_warning "pm 命令不可用"
                fi
            else
                if [ -f "$wrapper_script" ]; then
                    chmod +x "$wrapper_script"
                    cd process_manager_tool && bash pm_wrapper.sh --config && cd ..
                else
                    print_error "包装脚本不存在: $wrapper_script"
                fi
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        5)
            echo
            if [ "$is_installed" = true ]; then
                read -r -p "确认卸载进程管理工具？[y/N]: " -n 1
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    print_info "开始卸载..."
                    cd process_manager_tool && bash install_process_manager.sh uninstall && cd ..
                else
                    print_info "已取消卸载"
                fi
            else
                print_warning "工具尚未安装，无需卸载"
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        0)
            return
            ;;
        *)
            print_error "无效选项，请重新选择"
            sleep 1
            ;;
    esac
    
    # 如果不是返回主菜单，则继续显示进程管理工具菜单
    if [ "$pm_choice" != "0" ]; then
        manage_process_tool
    fi
}

# minikube 管理
manage_minikube() {
    clear
    print_header "🐳 minikube Kubernetes 开发环境"
    echo "========================================"
    
    local install_dir="$HOME/.tools/minikube"
    local install_script="./minikube/install.sh"
    local check_script="./minikube/check_minikube.sh"
    
    # 检查是否已安装
    local is_installed=false
    if [[ -d "$install_dir" && -x "$install_dir/bin/kubectl" && -x "$install_dir/bin/minikube" ]]; then
        is_installed=true
        print_success "✅ minikube 已安装到 $install_dir"
        
        # 检查环境变量
        if echo "$PATH" | grep -q "$install_dir/bin"; then
            print_success "✅ PATH 配置正确"
        else
            print_warning "⚠️  PATH 未配置，请运行: source ~/.zshrc"
        fi
        
        # 检查集群状态
        if command -v minikube >/dev/null 2>&1; then
            if minikube status >/dev/null 2>&1; then
                print_success "✅ minikube 集群正在运行"
            else
                print_warning "⚠️  minikube 集群未运行"
            fi
        else
            print_warning "⚠️  minikube 命令不可用"
        fi
    else
        print_info "ℹ️  minikube 尚未安装"
    fi
    
    echo
    print_menu "请选择操作："
    echo "  1) 安装/更新 minikube 和 kubectl"
    echo "  2) 启动 minikube 集群"
    echo "  3) 检查环境状态"
    echo "  4) 停止 minikube 集群"
    echo "  5) 打开 Kubernetes 仪表板"
    echo "  6) 查看集群信息"
    echo "  7) 重置集群"
    echo "  8) 卸载 minikube"
    echo "  9) 运行 smoke test (快速验证安装与启动)"
    echo "  0) 返回主菜单"
    echo
    
    read -r -p "请输入选项 [0-8]: " mk_choice
    
    case $mk_choice in
        1)
            echo
            print_info "开始安装 minikube 和 kubectl..."
            if [[ ! -f "$install_script" ]]; then
                print_error "安装脚本不存在: $install_script"
                sleep 2
                return
            fi
            chmod +x "$install_script"
            bash "$install_script"
            echo
            read -r -p "按回车键继续..."
            ;;
        2)
            echo
            if [[ "$is_installed" = true ]] && command -v minikube >/dev/null 2>&1; then
                print_info "启动 minikube 集群..."
                if [[ -x "$install_dir/start-minikube.sh" ]]; then
                    bash "$install_dir/start-minikube.sh"
                else
                    minikube start --cpus=2 --memory=4096 --disk-size=20g
                fi
            else
                print_error "minikube 未安装或不可用"
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        3)
            echo
            print_info "检查 minikube 环境状态..."
            if [[ -f "$check_script" ]]; then
                chmod +x "$check_script"
                bash "$check_script"
            else
                print_warning "状态检查脚本不存在: $check_script"
                if [[ "$is_installed" = true ]]; then
                    if [[ -x "$install_dir/check-status.sh" ]]; then
                        bash "$install_dir/check-status.sh"
                    else
                        print_info "手动检查状态..."
                        echo "kubectl version: $(kubectl version --client --short 2>/dev/null || echo '不可用')"
                        echo "minikube version: $(minikube version --short 2>/dev/null || echo '不可用')"
                        echo "minikube status:"
                        minikube status 2>/dev/null || echo "集群未运行"
                    fi
                fi
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        4)
            echo
            if command -v minikube >/dev/null 2>&1; then
                print_info "停止 minikube 集群..."
                minikube stop
                print_success "集群已停止"
            else
                print_error "minikube 命令不可用"
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        5)
            echo
            if command -v minikube >/dev/null 2>&1; then
                print_info "打开 Kubernetes 仪表板..."
                if minikube status >/dev/null 2>&1; then
                    minikube dashboard
                else
                    print_warning "集群未运行，请先启动集群"
                fi
            else
                print_error "minikube 命令不可用"
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        6)
            echo
            if command -v kubectl >/dev/null 2>&1 && command -v minikube >/dev/null 2>&1; then
                print_info "集群信息："
                echo
                echo "=== 集群状态 ==="
                minikube status 2>/dev/null || echo "集群未运行"
                echo
                echo "=== 节点信息 ==="
                kubectl get nodes 2>/dev/null || echo "无法连接到集群"
                echo
                echo "=== 系统 Pod ==="
                kubectl get pods -n kube-system 2>/dev/null || echo "无法获取 Pod 信息"
            else
                print_error "kubectl 或 minikube 命令不可用"
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
        7)
            echo
            if command -v minikube >/dev/null 2>&1; then
                read -r -p "确认重置 minikube 集群？这将删除所有数据 [y/N]: " -n 1
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    print_info "重置 minikube 集群..."
                    minikube delete
                    print_success "集群已删除，可以重新启动"
                else
                    print_info "已取消重置"
                fi
            else
                print_error "minikube 命令不可用"
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
    8)
            echo
            if [[ "$is_installed" = true ]]; then
                read -r -p "确认卸载 minikube 和 kubectl？[y/N]: " -n 1
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    print_info "开始卸载..."
                    # 先停止和删除集群
                    if command -v minikube >/dev/null 2>&1; then
                        minikube stop 2>/dev/null || true
                        minikube delete 2>/dev/null || true
                    fi
                    
                    # 运行卸载脚本
                    if [[ -x "$install_dir/uninstall.sh" ]]; then
                        bash "$install_dir/uninstall.sh"
                    else
                        # 手动卸载
                        rm -rf "$install_dir"
                        print_success "minikube 已卸载"
                        print_warning "请手动从 shell 配置文件中删除 PATH 配置"
                    fi
                else
                    print_info "已取消卸载"
                fi
            else
                print_warning "minikube 尚未安装，无需卸载"
            fi
            echo
            read -r -p "按回车键继续..."
            ;;
            9)
                echo
                local smoke_script="./minikube/smoke_test.sh"
                if [[ -f "$smoke_script" ]]; then
                    chmod +x "$smoke_script"
                    bash "$smoke_script"
                else
                    print_warning "smoke test 脚本不存在: $smoke_script"
                fi
                echo
                read -r -p "按回车键继续..."
                ;;
        0)
            return
            ;;
        *)
            print_error "无效选项，请重新选择"
            sleep 1
            ;;
    esac
    
    # 如果不是返回主菜单，则继续显示 minikube 菜单
    if [[ "$mk_choice" != "0" ]]; then
        manage_minikube
    fi
}

# --- 脚本入口 ---
main
