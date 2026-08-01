#!/bin/bash

#
# zsh_setup/install.sh
#
# This script automates the installation and configuration of Zsh, Oh My Zsh,
# and essential plugins (zsh-autosuggestions, zsh-syntax-highlighting).
#

# 引入公共函数库（颜色 / 打印 / command_exists / detect_pkg_manager 等）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Detect OS and package manager
detect_os() {
    OS="$(uname -s)"
    if [[ "$OS" == "Linux" ]]; then
        if command_exists apt-get; then
            PKG_MANAGER="apt-get"
        elif command_exists yum; then
            PKG_MANAGER="yum"
        else
            error "Unsupported Linux distribution. Please install Zsh manually."
            exit 1
        fi
    elif [[ "$OS" != "Darwin" ]]; then
        error "Unsupported operating system: $OS"
        exit 1
    fi
}

# Install Zsh if not present
install_zsh() {
    if command_exists zsh; then
        info "Zsh is already installed."
        return
    fi

    info "Zsh not found. Attempting to install..."
    if [[ "$OS" == "Linux" ]]; then
        sudo "$PKG_MANAGER" update -y
        sudo "$PKG_MANAGER" install -y zsh
    elif [[ "$OS" == "Darwin" ]]; then
        if ! command_exists brew; then
            error "Homebrew is not installed. Please install it first: https://brew.sh/"
            exit 1
        fi
        brew install zsh
    fi

    if ! command_exists zsh; then
        error "Zsh installation failed. Please install it manually."
        exit 1
    fi
    success "Zsh has been installed successfully."
}

# Install Oh My Zsh
install_oh_my_zsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "Oh My Zsh is already installed."
        return
    fi

    info "Installing Oh My Zsh..."
    # The installer will back up existing .zshrc and create a new one
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        error "Oh My Zsh installation failed."
        exit 1
    fi
    success "Oh My Zsh has been installed successfully."
}

# Install Zsh plugins
install_plugins() {
    ZSH_CUSTOM_PLUGINS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    AUTOSUGGESTIONS_DIR="$ZSH_CUSTOM_PLUGINS_DIR/zsh-autosuggestions"
    SYNTAX_HIGHLIGHTING_DIR="$ZSH_CUSTOM_PLUGINS_DIR/zsh-syntax-highlighting"

    info "Installing Zsh plugins..."

    # Install zsh-autosuggestions
    if [ ! -d "$AUTOSUGGESTIONS_DIR" ]; then
        info "Cloning zsh-autosuggestions..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGESTIONS_DIR"
    else
        info "zsh-autosuggestions is already installed. Skipping."
    fi

    # Install zsh-syntax-highlighting
    if [ ! -d "$SYNTAX_HIGHLIGHTING_DIR" ]; then
        info "Cloning zsh-syntax-highlighting..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HIGHLIGHTING_DIR"
    else
        info "zsh-syntax-highlighting is already installed. Skipping."
    fi
    success "Plugins installed."
}

# Configure .zshrc to enable plugins
configure_zshrc() {
    ZSHRC_FILE="$HOME/.zshrc"
    PLUGINS_LINE="plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"

    if ! grep -q "plugins=(git)" "$ZSHRC_FILE"; then
        warn "Could not find the default plugin line in .zshrc. Manual configuration may be needed."
        echo "Please add the following line to your $ZSHRC_FILE:"
        echo "$PLUGINS_LINE"
        return
    fi

    if grep -q "zsh-autosuggestions" "$ZSHRC_FILE"; then
        info "Plugins seem to be already configured in .zshrc."
        return
    fi

    info "Configuring .zshrc to enable plugins..."
    sed -i.bak 's/^plugins=(git)$/'"$PLUGINS_LINE"'/' "$ZSHRC_FILE"
    success ".zshrc has been configured."
}

# Offer to change the default shell
change_default_shell() {
    if [[ "$SHELL" == */zsh ]]; then
        info "Your default shell is already Zsh."
        return
    fi

    info "Your current default shell is $SHELL."
    read -r -p "Do you want to change your default shell to Zsh? (y/N) "
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        if chsh -s "$(command -v zsh)"; then
            success "Default shell changed to Zsh."
            info "You will need to log out and log back in for the change to take effect."
        else
            error "Failed to change the default shell. Please do it manually."
        fi
    else
        info "Skipping default shell change."
    fi
}


# --- 安装流程 ---
install_zsh_setup() {
    info "Starting Zsh & Oh My Zsh environment setup..."

    # Check for required tools
    if ! command_exists git || ! command_exists curl; then
        error "'git' and 'curl' are required for this script. Please install them first."
        exit 1
    fi

    detect_os
    install_zsh
    install_oh_my_zsh
    install_plugins
    configure_zshrc
    change_default_shell

    success "Zsh setup is complete!"
    warn "Please restart your terminal or log out and log back in to apply all changes."
}

# --- 状态 ---
status_zsh_setup() {
    local zsh_installed=false omz_installed=false
    command_exists zsh && zsh_installed=true
    [ -d "$HOME/.oh-my-zsh" ] && omz_installed=true
    if $zsh_installed && $omz_installed; then
        echo -e "${GREEN}✅ Zsh & Oh My Zsh 已安装${NC}"
    elif $zsh_installed; then
        echo -e "${YELLOW}⚠️  已安装 Zsh，但未安装 Oh My Zsh${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

# --- 卸载说明（敏感操作，仅给出指引） ---
uninstall_zsh_setup() {
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
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Zsh + Oh My Zsh + 插件（默认动作）
  uninstall   显示卸载说明（敏感操作，手动执行）
  status      查看安装状态
EOF
}

main() {
    local action="${1:-install}"
    case "$action" in
        install)   install_zsh_setup ;;
        uninstall) uninstall_zsh_setup ;;
        status)    status_zsh_setup ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
