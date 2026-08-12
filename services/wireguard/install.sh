#!/bin/bash
set -euo pipefail

#
# wireguard/install.sh
#
# This script provides functions to install WireGuard tools, configure the
# auto-start service, and uninstall it. It's designed to be called from
# the main menu script.
#

# 引入公共函数库（颜色 / 打印 / command_exists / detect_pkg_manager 等）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# Check for root/sudo privileges
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        error "This action requires sudo or root privileges."
        exit 1
    fi
}

# Detect OS and package manager
detect_os() {
    OS="$(uname -s)"
    if [[ "$OS" == "Linux" ]]; then
        if command_exists apt-get; then
            PKG_MANAGER="apt-get"
        elif command_exists yum; then
            PKG_MANAGER="yum"
        elif command_exists dnf; then
            PKG_MANAGER="dnf"
        else
            error "Unsupported Linux distribution. Please install WireGuard tools manually."
            exit 1
        fi
    elif [[ "$OS" != "Darwin" ]]; then
        error "Unsupported operating system: $OS"
        exit 1
    fi
}

# --- Core Functions ---

# Install WireGuard tools
install_tools() {
    info "Starting WireGuard tools installation..."
    check_privileges
    detect_os

    if command_exists wg; then
        info "WireGuard tools are already installed."
        return 0
    fi

    info "WireGuard tools not found. Attempting to install..."
    if [[ "$OS" == "Linux" ]]; then
        ensure_epel
        pkg_install wireguard-tools || { error "wireguard-tools 安装失败（${PKG_MANAGER}）"; exit 1; }
    elif [[ "$OS" == "Darwin" ]]; then
        if ! command_exists brew; then
            error "Homebrew is not installed. Please install it first: https://brew.sh/"
            exit 1
        fi
        info "Installing WireGuard via Homebrew..."
        brew install wireguard-tools
    fi

    if ! command_exists wg; then
        error "WireGuard installation failed. Please install it manually."
        exit 1
    fi
    success "WireGuard tools have been installed successfully."
}

# Configure WireGuard auto-start service
configure_service() {
    info "Configuring WireGuard auto-start service..."
    check_privileges
    detect_os

    local interface="wg0"
    local conf_file=""

    if [[ "$OS" == "Linux" ]]; then
        conf_file="/etc/wireguard/${interface}.conf"
    elif [[ "$OS" == "Darwin" ]]; then
        conf_file="/usr/local/etc/wireguard/${interface}.conf"
    fi

    warn "This script will enable WireGuard to start on boot using the default interface '${interface}'."
    info "Please make sure your configuration file exists at: ${conf_file}"
    
    if [ ! -f "$conf_file" ]; then
        warn "Configuration file not found!"
        read -r -p "Do you want to create a placeholder file now? (y/N) "
        echo
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            sudo mkdir -p "$(dirname "$conf_file")"
            sudo touch "$conf_file"
            sudo chmod 600 "$conf_file"
            success "Placeholder file created at ${conf_file}. You MUST edit it with your WireGuard configuration."
        else
            error "Setup cannot proceed without a configuration file. Please create it and run this script again."
            return 1
        fi
    fi

    info "Enabling WireGuard service for interface '${interface}'..."
    if [[ "$OS" == "Linux" ]]; then
        sudo systemctl enable wg-quick@${interface}.service
        sudo systemctl restart wg-quick@${interface}.service
        if systemctl is-active --quiet "wg-quick@${interface}"; then
            success "WireGuard service for ${interface} is enabled and started."
        else
            error "Failed to start WireGuard service. Check your configuration with 'sudo wg-quick up ${interface}' and logs with 'sudo journalctl -u wg-quick@${interface}'."
            return 1
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        local plist_file="/Library/LaunchDaemons/com.wireguard.${interface}.plist"
        local wg_quick_path
        wg_quick_path="$(command -v wg-quick)"

        if [ -z "$wg_quick_path" ]; then
            error "Could not find wg-quick executable. Please install wireguard-tools first."
            return 1
        fi

        local plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>com.wireguard.${interface}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${wg_quick_path}</string>
        <string>up</string>
        <string>${interface}</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/var/log/wireguard.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/wireguard.log</string>
</dict>
</plist>"
        
        echo "$plist_content" | sudo tee "$plist_file" > /dev/null
        sudo launchctl bootout system "$plist_file" &>/dev/null || true
        sudo launchctl bootstrap system "$plist_file"

        if sudo launchctl list | grep -q "com.wireguard.${interface}"; then
            success "WireGuard service for ${interface} is enabled and loaded."
            info "Logs can be found at /var/log/wireguard.log"
        else
            error "Failed to load WireGuard service. Please check system logs for details."
            return 1
        fi
    fi
}

# Uninstall WireGuard auto-start service
uninstall_service() {
    info "Uninstalling WireGuard auto-start service..."
    check_privileges
    detect_os

    local interface="wg0"
    if [[ "$OS" == "Linux" ]]; then
        sudo systemctl stop "wg-quick@${interface}" &>/dev/null || true
        sudo systemctl disable "wg-quick@${interface}" &>/dev/null || true
        sudo rm -f "/etc/systemd/system/wg-quick@${interface}.service"
        sudo systemctl daemon-reload
        success "WireGuard service for ${interface} has been disabled and stopped."
    elif [[ "$OS" == "Darwin" ]]; then
        local plist_file="/Library/LaunchDaemons/com.wireguard.${interface}.plist"
        sudo launchctl bootout system "$plist_file" &>/dev/null || true
        sudo rm -f "$plist_file"
        success "WireGuard service for ${interface} has been unloaded and removed."
    fi
}

# --- 状态 ---
status_wireguard() {
    local wg_installed=false service_running=false interface="wg0"
    detect_os
    command_exists wg && wg_installed=true
    # 本模块自带 detect_os()（覆盖 common.sh 的），它设置 OS（值为 Linux/Darwin，即 uname -s）。
    # 原本 status_wireguard 未调用 detect_os → $OS 未定义 → Linux 上 service_running 恒为 false，
    # 状态误报为 stopped。status_wireguard 起首已补 detect_os 调用。
    if [[ "$OS" == "Linux" ]]; then
        systemctl is-active --quiet "wg-quick@${interface}" 2>/dev/null && service_running=true
    elif [[ "$OS" == "Darwin" ]]; then
        sudo launchctl list 2>/dev/null | grep -q "com.wireguard.${interface}" && service_running=true
    fi
    if $wg_installed; then
        if $service_running; then
            emit_status "installed:running" "${GREEN}✅ 已安装并运行${NC} (接口: ${interface})"
            emit_extra "interface=${interface}"
        else
            emit_status "installed:stopped" "${YELLOW}⚠️  已安装但服务未运行${NC}"
        fi
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
    fi
}

# --- 完整卸载（服务 + 配置） ---
uninstall_wireguard_full() {
    detect_os
    check_privileges
    uninstall_service
    echo
    if yes_no "是否删除 wireguard 目录下的 .conf 配置文件？"; then
        if [[ "$OS" == "Linux" ]]; then
            sudo rm -f /etc/wireguard/*.conf
        elif [[ "$OS" == "Darwin" ]]; then
            sudo rm -f /usr/local/etc/wireguard/*.conf
        fi
        success "配置文件已删除。"
    fi
    warn "服务已移除。要完全卸载，请使用包管理器 (apt/brew 等) 手动移除 'wireguard-tools'。"
    success "WireGuard 卸载完成！"
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}  (兼容旧词 install_tools/configure_service/uninstall_service)

  install              安装 WireGuard 工具（同 install_tools）
  uninstall            卸载服务 + 询问删除 .conf（完整卸载）
  status               查看安装与运行状态
  configure_service    配置开机自启（保留旧名）
EOF
}

# --- Main Execution ---
main() {
    # If an argument is provided, execute the corresponding function non-interactively.
    if [ -n "$1" ]; then
        case "$1" in
            install|install_tools)
                install_tools
                ;;
            uninstall)
                uninstall_wireguard_full
                ;;
            configure_service)
                configure_service
                ;;
            uninstall_service)
                uninstall_service
                ;;
            status)
                status_wireguard
                ;;
            help|--help|-h)
                usage
                ;;
            *)
                error "Invalid action: $1"
                usage
                exit 1
                ;;
        esac
    else
        # Otherwise, show an interactive menu.
        info "WireGuard Management Menu"
        echo "Select an option:"
        echo "  1. Install WireGuard Tools"
        echo "  2. Configure Auto-start Service"
        echo "  3. Uninstall (service + config)"
        echo "  4. Status"
        echo "  5. Exit"

        local choice
        read -r -p "Enter choice [1-5]: " choice

        case $choice in
            1) install_tools ;;
            2) configure_service ;;
            3) uninstall_wireguard_full ;;
            4) status_wireguard ;;
            5) info "Exiting." ;;
            *) error "Invalid option. Please try again." ;;
        esac
    fi
}

# Run the main function if the script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
