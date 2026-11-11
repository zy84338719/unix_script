#!/bin/bash
#
# zsh_setup/frameworks/zinit.sh
# Zinit 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

ZINIT_DIR="${HOME}/.local/share/zinit/zinit.git"

# 安装 Zinit
install_zinit() {
    if [ -d "$ZINIT_DIR" ]; then
        warn "$(_t 'Zinit is already installed')"
        return 0
    fi

    info "$(_t 'Installing Zinit...')"
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

    if [ ! -d "$ZINIT_DIR" ]; then
        error "$(_t 'Failed to install Zinit')"
        return 1
    fi

    success "$(_t 'Zinit installed successfully')"
}

# 卸载 Zinit
uninstall_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        warn "$(_t 'Zinit is not installed')"
        return 0
    fi

    if ! yes_no "$(_t 'Uninstall Zinit?')"; then
        info "$(_t 'Uninstall cancelled')"
        return 0
    fi

    info "$(_t 'Uninstalling Zinit...')"
    rm -rf "$ZINIT_DIR"
    rm -rf "${HOME}/.local/share/zinit"

    success "$(_t 'Zinit uninstalled')"
}

# Zinit 状态
status_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        printf '%s\n' "$(_t 'Zinit: not installed')"
        return 0
    fi

    printf '%s\n' "$(_t 'Zinit: installed')"

    # 列出插件
    printf '%s\n' "$(_t 'Plugins:')"
    list_plugins_zinit
}

# 列出 Zinit 插件
list_plugins_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        warn "$(_t 'Zinit is not installed')"
        return 0
    fi

    # 从 .zshrc 中提取插件
    if [ -f "$HOME/.zshrc" ]; then
        grep "zinit light" "$HOME/.zshrc" | sed 's/.*zinit light //' | sed 's/["]//g'
    fi
}

# 安装插件
# 参数 plugin_spec 可以是 user/repo 格式或简写
install_plugin_zinit() {
    local plugin_spec="$1"

    if [ -z "$plugin_spec" ]; then
        error "$(_t 'Please specify a plugin name')"
        return 1
    fi

    local zshrc="$HOME/.zshrc"

    if [ ! -f "$zshrc" ]; then
        error "$(_t '.zshrc file not found')"
        return 1
    fi

    # 检查插件是否已安装
    if grep -q "zinit light $plugin_spec" "$zshrc"; then
        warn "$(_tf 'Plugin %s is already installed' "$plugin_spec")"
        return 0
    fi

    # 添加插件到 .zshrc
    echo "zinit light $plugin_spec" >> "$zshrc"
    success "$(_tf 'Plugin %s added' "$plugin_spec")"
    info "$(_t 'Run source ~/.zshrc or restart the terminal to load plugins')"
}

# 卸载插件
uninstall_plugin_zinit() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        error "$(_t 'Please specify a plugin name')"
        return 1
    fi

    local zshrc="$HOME/.zshrc"

    if [ ! -f "$zshrc" ]; then
        error "$(_t '.zshrc file not found')"
        return 1
    fi

    # 删除插件
    sed -i.bak "/zinit light $plugin_name/d" "$zshrc"
    rm -f "${zshrc}.bak"
    success "$(_tf 'Plugin %s removed' "$plugin_name")"
}
