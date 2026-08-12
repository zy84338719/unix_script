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
        warn "Prezto 已安装"
        return 0
    fi

    info "正在安装 Prezto..."
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "$PREZTO_DIR"

    if [ ! -d "$PREZTO_DIR" ]; then
        error "Prezto 安装失败"
        return 1
    fi

    # 创建符号链接
    for rcfile in "$PREZTO_DIR"/runcoms/z*; do
        local basename
        basename="$(basename "$rcfile")"
        [ -f "${ZDOTDIR:-$HOME}/.${basename}" ] && continue
        ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${basename}"
    done

    success "Prezto 安装成功"
}

# 卸载 Prezto
uninstall_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        warn "Prezto 未安装"
        return 0
    fi

    if ! yes_no "确定要卸载 Prezto 吗？"; then
        info "取消卸载"
        return 0
    fi

    info "正在卸载 Prezto..."

    # 删除符号链接
    for rcfile in "$PREZTO_DIR"/runcoms/z*; do
        local basename
        basename="$(basename "$rcfile")"
        local target="${ZDOTDIR:-$HOME}/.${basename}"
        [ -L "$target" ] && rm -f "$target"
    done

    rm -rf "$PREZTO_DIR"
    success "Prezto 已卸载"
}

# Prezto 状态
status_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        echo "Prezto: 未安装"
        return 0
    fi

    echo "Prezto: 已安装"

    # 检测主题
    if [ -f "${ZDOTDIR:-$HOME}/.zpreztorc" ]; then
        local theme
        theme=$(grep "^zstyle ':prezto:module:prompt' theme" "${ZDOTDIR:-$HOME}/.zpreztorc" | awk '{print $NF}' || true)
        echo "主题: ${theme:-未设置}"
    fi

    # 列出模块
    echo "模块:"
    list_plugins_prezto
}

# 列出 Prezto 模块
list_plugins_prezto() {
    if [ ! -d "$PREZTO_DIR" ]; then
        warn "Prezto 未安装"
        return 0
    fi

    # 内置模块
    echo "内置模块:"
    ls "$PREZTO_DIR/modules/" 2>/dev/null || true

    # 外部模块（contrib）
    if [ -d "$PREZTO_DIR/contrib" ]; then
        echo ""
        echo "外部模块:"
        ls "$PREZTO_DIR/contrib/" 2>/dev/null || true
    fi
}

# 启用模块
enable_module_prezto() {
    local module_name="$1"

    if [ -z "$module_name" ]; then
        error "请指定模块名称"
        return 1
    fi

    local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"

    if [ ! -f "$preztorc" ]; then
        error "未找到 .zpreztorc 文件"
        return 1
    fi

    # 检查模块是否已启用
    if grep -q "'$module_name'" "$preztorc"; then
        warn "模块 $module_name 已启用"
        return 0
    fi

    # 添加模块到 zpreztorc
    # NOTE: 硬编码锚点 'completion' — 假设默认 prezto 配置包含此行。
    # 若用户自定义了 zpreztorc 且无 'completion' 行，sed 将不匹配。
    sed -i.bak "s/^\(  'completion'\)/\1\n  '$module_name'/" "$preztorc"
    rm -f "${preztorc}.bak"
    success "模块 $module_name 已启用"
}

# 禁用模块
disable_module_prezto() {
    local module_name="$1"

    if [ -z "$module_name" ]; then
        error "请指定模块名称"
        return 1
    fi

    local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"

    if [ ! -f "$preztorc" ]; then
        error "未找到 .zpreztorc 文件"
        return 1
    fi

    # 删除模块
    sed -i.bak "/'$module_name'/d" "$preztorc"
    rm -f "${preztorc}.bak"
    success "模块 $module_name 已禁用"
}
