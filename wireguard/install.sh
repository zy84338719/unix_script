#!/bin/bash

#
# wireguard/install.sh
#
# This script provides functions to install WireGuard tools, configure the
# auto-start service, and uninstall it. It's designed to be called from
# the main menu script.
#

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Log Functions ---
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Helper Functions ---

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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
        if [[ "$PKG_MANAGER" == "apt-get" ]]; then
            sudo apt-get update -y
            sudo apt-get install -y wireguard-tools
        elif [[ "$PKG_MANAGER" == "yum" || "$PKG_MANAGER" == "dnf" ]]; then
            if ! rpm -q epel-release &>/dev/null; then
                info "Installing EPEL repository..."
                sudo "$PKG_MANAGER" install -y epel-release
            fi
            sudo "$PKG_MANAGER" install -y wireguard-tools
        fi
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

# --- Main Execution ---
main() {
    # If an argument is provided, execute the corresponding function non-interactively.
    if [ -n "$1" ]; then
        case "$1" in
            install_tools)
                install_tools
                ;;
            configure_service)
                configure_service
                ;;
            uninstall_service)
                uninstall_service
                ;;
            *)
                error "Invalid action: $1"
                echo "Usage: $0 {install_tools|configure_service|uninstall_service}"
                exit 1
                ;;
        esac
    else
        # Otherwise, show an interactive menu.
        info "WireGuard Management Menu"
        echo "Select an option:"
        echo "  1. Install WireGuard Tools"
        echo "  2. Configure Auto-start Service"
        echo "  3. Uninstall Auto-start Service"
        echo "  4. Exit"
        
        local choice
        read -r -p "Enter choice [1-4]: " choice

        case $choice in
            1)
                install_tools
                ;;
            2)
                configure_service
                ;;
            3)
                uninstall_service
                ;;
            4)
                info "Exiting."
                ;;
            *)
                error "Invalid option. Please try again."
                ;;
        esac
    fi
}

# Run the main function if the script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
