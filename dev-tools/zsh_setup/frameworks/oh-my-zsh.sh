#!/bin/bash
#
# zsh_setup/frameworks/oh-my-zsh.sh
# Oh My Zsh 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_DIR="${ZSH_CUSTOM:-$OH_MY_ZSH_DIR/custom}"

# 安装 Oh My Zsh
install_oh_my_zsh() {
    if [ -d "$OH_MY_ZSH_DIR" ]; then
        warn "$(_t 'Oh My Zsh is already installed')"
        return 0
    fi

    info "$(_t 'Installing Oh My Zsh...')"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        error "$(_t 'Failed to install Oh My Zsh')"
        return 1
    fi

    success "$(_t 'Oh My Zsh installed successfully')"
}

# 卸载 Oh My Zsh
uninstall_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        warn "$(_t 'Oh My Zsh is not installed')"
        return 0
    fi

    if ! yes_no "$(_t 'Uninstall Oh My Zsh?')"; then
        info "$(_t 'Uninstall cancelled')"
        return 0
    fi

    info "$(_t 'Uninstalling Oh My Zsh...')"

    # 使用官方卸载脚本
    if [ -f "$OH_MY_ZSH_DIR/tools/uninstall.sh" ]; then
        bash "$OH_MY_ZSH_DIR/tools/uninstall.sh"
    else
        rm -rf "$OH_MY_ZSH_DIR"
    fi

    success "$(_t 'Oh My Zsh uninstalled')"
}

# Oh My Zsh 状态
status_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        printf '%s\n' "$(_t 'Oh My Zsh: not installed')"
        return 0
    fi

    printf '%s\n' "$(_t 'Oh My Zsh: installed')"

    # 检测主题
    if [ -f "$HOME/.zshrc" ]; then
        local theme
        theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2 || true)
        echo "$(_t 'Theme:') ${theme:-$(_t 'not set')}"
    fi

    # 列出插件
    printf '%s\n' "$(_t 'Plugins:')"
    list_plugins_oh_my_zsh
}

# 列出 Oh My Zsh 插件
list_plugins_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        warn "$(_t 'Oh My Zsh is not installed')"
        return 0
    fi

    # 内置插件
    printf '%s\n' "$(_t 'Built-in plugins:')"
    # 目录可能缺失（部分安装）；ls 失败在 set -e 下会中止，用 || true 兜底（仅展示）
    ls "$OH_MY_ZSH_DIR/plugins/" 2>/dev/null || true

    # 自定义插件
    if [ -d "$CUSTOM_DIR/plugins" ]; then
        echo ""
        printf '%s\n' "$(_t 'Custom plugins:')"
        ls "$CUSTOM_DIR/plugins/" 2>/dev/null || true
    fi
}

# 安装插件
install_plugin_oh_my_zsh() {
    local plugin_name="$1"
    local plugin_url="$2"

    if [ -z "$plugin_name" ]; then
        error "$(_t 'Please specify a plugin name')"
        return 1
    fi

    local plugin_dir="$CUSTOM_DIR/plugins/$plugin_name"

    if [ -d "$plugin_dir" ]; then
        warn "$(_tf 'Plugin %s is already installed' "$plugin_name")"
        return 0
    fi

    if [ -z "$plugin_url" ]; then
        # 使用默认插件仓库
        plugin_url="https://github.com/zsh-users/$plugin_name.git"
    fi

    info "$(_tf 'Installing plugin %s...' "$plugin_name")"
    if git clone "$plugin_url" "$plugin_dir"; then
        success "$(_tf 'Plugin %s installed successfully' "$plugin_name")"
        info "$(_tf 'Add %s to the plugins array in .zshrc' "$plugin_name")"
    else
        error "$(_tf 'Failed to install plugin %s' "$plugin_name")"
        return 1
    fi
}

# 卸载插件
uninstall_plugin_oh_my_zsh() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        error "$(_t 'Please specify a plugin name')"
        return 1
    fi

    local plugin_dir="$CUSTOM_DIR/plugins/$plugin_name"

    if [ ! -d "$plugin_dir" ]; then
        warn "$(_tf 'Plugin %s is not installed' "$plugin_name")"
        return 0
    fi

    if ! yes_no "$(_tf 'Uninstall plugin %s?' "$plugin_name")"; then
        info "$(_t 'Uninstall cancelled')"
        return 0
    fi

    rm -rf "$plugin_dir"
    success "$(_tf 'Plugin %s uninstalled' "$plugin_name")"
    info "$(_tf 'Remove %s from the plugins array in .zshrc' "$plugin_name")"
}
