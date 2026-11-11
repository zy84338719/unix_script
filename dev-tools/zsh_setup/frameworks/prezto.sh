#!/bin/bash
#
# zsh_setup/frameworks/prezto.sh
# Prezto 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

PREZTO_DIR="${ZDOTDIR:-$HOME}/.zprezto"

# 安装 Prezto
install_prezto() {
    if [ -d "$PREZTO_DIR" ]; then
        warn "$(_t 'Prezto is already installed')"
        return 0
    fi

    info "$(_t 'Installing Prezto...')"
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "$PREZTO_DIR"

    if [ ! -d "$PREZTO_DIR" ]; then
        error "$(_t 'Failed to install Prezto')"
        return 1
    fi

    # 创建符号链接
    for rcfile in "$PREZTO_DIR"/runcoms/z*; do
        local basename
        basename="$(basename "$rcfile")"
        [ -f "${ZDOTDIR:-$HOME}/.${basename}" ] && continue
        ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${basename}"
    done

    success "$(_t 'Prezto installed successfully')"
}

# 卸载 Prezto
uninstall_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        warn "$(_t 'Prezto is not installed')"
        return 0
    fi

    if ! yes_no "$(_t 'Uninstall Prezto?')"; then
        info "$(_t 'Uninstall cancelled')"
        return 0
    fi

    info "$(_t 'Uninstalling Prezto...')"

    # 删除符号链接
    for rcfile in "$PREZTO_DIR"/runcoms/z*; do
        local basename
        basename="$(basename "$rcfile")"
        local target="${ZDOTDIR:-$HOME}/.${basename}"
        [ -L "$target" ] && rm -f "$target"
    done

    rm -rf "$PREZTO_DIR"
    success "$(_t 'Prezto uninstalled')"
}

# Prezto 状态
status_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        printf '%s\n' "$(_t 'Prezto: not installed')"
        return 0
    fi

    printf '%s\n' "$(_t 'Prezto: installed')"

    # 检测主题
    if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
        local theme
        theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}' || true)
        echo "$(_t 'Theme:') ${theme:-$(_t 'not set')}"
    fi

    # 列出模块
    printf '%s\n' "$(_t 'Modules:')"
    list_plugins_prezto
}

# 列出 Prezto 模块
list_plugins_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        warn "$(_t 'Prezto is not installed')"
        return 0
    fi

    # 内置模块
    printf '%s\n' "$(_t 'Built-in modules:')"
    ls "$PREZTO_DIR/modules/" 2>/dev/null || true

    # 外部模块（contrib）
    if [ -d "$PREZTO_DIR/contrib" ]; then
        echo ""
        printf '%s\n' "$(_t 'External modules:')"
        ls "$PREZTO_DIR/contrib/" 2>/dev/null || true
    fi
}

# 启用模块
enable_module_prezto() {
    local module_name="$1"

    if [ -z "$module_name" ]; then
        error "$(_t 'Please specify a module name')"
        return 1
    fi

    local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"

    if [ ! -f "$preztorc" ]; then
        error "$(_t '.zpreztorc file not found')"
        return 1
    fi

    # 检查模块是否已启用
    if grep -q "'$module_name'" "$preztorc"; then
        warn "$(_tf 'Module %s is already enabled' "$module_name")"
        return 0
    fi

    # 添加模块到 zpreztorc
    # NOTE: 硬编码锚点 'completion' — 假设默认 prezto 配置包含此行。
    # 若用户自定义了 zpreztorc 且无 'completion' 行，sed 将不匹配。
    sed -i.bak "s/^\(  'completion'\)/\1\n  '$module_name'/" "$preztorc"
    rm -f "${preztorc}.bak"
    success "$(_tf 'Module %s enabled' "$module_name")"
}

# 禁用模块
disable_module_prezto() {
    local module_name="$1"

    if [ -z "$module_name" ]; then
        error "$(_t 'Please specify a module name')"
        return 1
    fi

    local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"

    if [ ! -f "$preztorc" ]; then
        error "$(_t '.zpreztorc file not found')"
        return 1
    fi

    # 删除模块
    sed -i.bak "/'$module_name'/d" "$preztorc"
    rm -f "${preztorc}.bak"
    success "$(_tf 'Module %s disabled' "$module_name")"
}
