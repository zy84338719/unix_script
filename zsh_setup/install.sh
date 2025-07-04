#!/bin/bash

#
# zsh_setup/install.sh
#
# This script automates the installation and configuration of Zsh, Oh My Zsh,
# and essential plugins (zsh-autosuggestions, zsh-syntax-highlighting).
#

# --- Color Definitions ---
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[0;33m'
BLUE='[0;34m'
NC='[0m' # No Color

# --- Log Functions ---
info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# --- Helper Functions ---

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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


# --- Main Execution ---
main() {
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

# Run the main function
main
