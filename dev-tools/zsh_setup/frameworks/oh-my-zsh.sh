#!/bin/bash
#
# zsh_setup/frameworks/oh-my-zsh.sh
# Oh My Zsh 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

OH_MY_ZSH_DIR="$HOME/.oh-my-zsh"
CUSTOM_DIR="${ZSH_CUSTOM:-$OH_MY_ZSH_DIR/custom}"

# 安装 Oh My Zsh
install_oh_my_zsh() {
    if [ -d "$OH_MY_ZSH_DIR" ]; then
        warn "Oh My Zsh 已安装"
        return 0
    fi

    info "正在安装 Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        error "Oh My Zsh 安装失败"
        return 1
    fi

    success "Oh My Zsh 安装成功"
}

# 卸载 Oh My Zsh
uninstall_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        warn "Oh My Zsh 未安装"
        return 0
    fi

    if ! yes_no "确定要卸载 Oh My Zsh 吗？"; then
        info "取消卸载"
        return 0
    fi

    info "正在卸载 Oh My Zsh..."

    # 使用官方卸载脚本
    if [ -f "$OH_MY_ZSH_DIR/tools/uninstall.sh" ]; then
        bash "$OH_MY_ZSH_DIR/tools/uninstall.sh"
    else
        rm -rf "$OH_MY_ZSH_DIR"
    fi

    success "Oh My Zsh 已卸载"
}

# Oh My Zsh 状态
status_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        echo "Oh My Zsh: 未安装"
        return 0
    fi

    echo "Oh My Zsh: 已安装"

    # 检测主题
    if [ -f "$HOME/.zshrc" ]; then
        local theme
        theme=$(grep "^ZSH_THEME=" "$HOME/.zshrc" | cut -d'"' -f2)
        echo "主题: ${theme:-未设置}"
    fi

    # 列出插件
    echo "插件:"
    list_plugins_oh_my_zsh
}

# 列出 Oh My Zsh 插件
list_plugins_oh_my_zsh() {
    if [ ! -d "$OH_MY_ZSH_DIR" ]; then
        warn "Oh My Zsh 未安装"
        return 0
    fi

    # 内置插件
    echo "内置插件:"
    ls "$OH_MY_ZSH_DIR/plugins/" 2>/dev/null

    # 自定义插件
    if [ -d "$CUSTOM_DIR/plugins" ]; then
        echo ""
        echo "自定义插件:"
        ls "$CUSTOM_DIR/plugins/" 2>/dev/null
    fi
}

# 安装插件
install_plugin_oh_my_zsh() {
    local plugin_name="$1"
    local plugin_url="$2"

    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi

    local plugin_dir="$CUSTOM_DIR/plugins/$plugin_name"

    if [ -d "$plugin_dir" ]; then
        warn "插件 $plugin_name 已安装"
        return 0
    fi

    if [ -z "$plugin_url" ]; then
        # 使用默认插件仓库
        plugin_url="https://github.com/zsh-users/$plugin_name.git"
    fi

    info "正在安装插件 $plugin_name..."
    if git clone "$plugin_url" "$plugin_dir"; then
        success "插件 $plugin_name 安装成功"
        info "请在 .zshrc 的 plugins 数组中添加 $plugin_name"
    else
        error "插件 $plugin_name 安装失败"
        return 1
    fi
}

# 卸载插件
uninstall_plugin_oh_my_zsh() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi

    local plugin_dir="$CUSTOM_DIR/plugins/$plugin_name"

    if [ ! -d "$plugin_dir" ]; then
        warn "插件 $plugin_name 未安装"
        return 0
    fi

    if ! yes_no "确定要卸载插件 $plugin_name 吗？"; then
        info "取消卸载"
        return 0
    fi

    rm -rf "$plugin_dir"
    success "插件 $plugin_name 已卸载"
    info "请从 .zshrc 的 plugins 数组中移除 $plugin_name"
}
