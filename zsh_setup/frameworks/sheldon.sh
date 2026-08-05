#!/bin/bash
#
# zsh_setup/frameworks/sheldon.sh
# sheldon 适配器
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

SHELDON_CONFIG="${HOME}/.config/sheldon/plugins.toml"

# 安装 sheldon
install_sheldon() {
    if command_exists sheldon; then
        warn "sheldon 已安装"
        return 0
    fi

    info "正在安装 sheldon..."
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon

    if ! command_exists sheldon; then
        error "sheldon 安装失败"
        return 1
    fi

    # 创建配置目录
    mkdir -p "$(dirname "$SHELDON_CONFIG")"

    # 创建默认配置
    if [ ! -f "$SHELDON_CONFIG" ]; then
        cat > "$SHELDON_CONFIG" << 'EOF'
# ~/.config/sheldon/plugins.toml

[plugins]

# Example:
# [plugins.zsh-autosuggestions]
# github = "zsh-users/zsh-autosuggestions"
EOF
    fi

    success "sheldon 安装成功"
}

# 卸载 sheldon
uninstall_sheldon() {
    if ! command_exists sheldon; then
        warn "sheldon 未安装"
        return 0
    fi

    if ! yes_no "确定要卸载 sheldon 吗？"; then
        info "取消卸载"
        return 0
    fi

    info "正在卸载 sheldon..."

    # 删除 sheldon 二进制文件
    local sheldon_path
    sheldon_path=$(command -v sheldon)
    if [ -n "$sheldon_path" ]; then
        rm -f "$sheldon_path"
    fi

    success "sheldon 已卸载"
}

# sheldon 状态
status_sheldon() {
    if ! command_exists sheldon; then
        echo "sheldon: 未安装"
        return 0
    fi

    echo "sheldon: 已安装"

    # 列出插件
    echo "插件:"
    list_plugins_sheldon
}

# 列出 sheldon 插件
list_plugins_sheldon() {
    if [ ! -f "$SHELDON_CONFIG" ]; then
        warn "未找到 sheldon 配置文件"
        return 0
    fi

    # 从配置文件中提取插件
    grep "^\[plugins\." "$SHELDON_CONFIG" | sed 's/\[plugins\.\(.*\)\]/\1/'
}

# 安装插件
install_plugin_sheldon() {
    local plugin_name="$1"
    local plugin_repo="$2"

    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi

    if [ -z "$plugin_repo" ]; then
        error "请指定插件仓库 (格式: user/repo)"
        return 1
    fi

    if [ ! -f "$SHELDON_CONFIG" ]; then
        mkdir -p "$(dirname "$SHELDON_CONFIG")"
        cat > "$SHELDON_CONFIG" << 'EOF'
[plugins]
EOF
    fi

    # 检查插件是否已存在
    if grep -q "^\[plugins\.$plugin_name\]" "$SHELDON_CONFIG"; then
        warn "插件 $plugin_name 已存在"
        return 0
    fi

    # 添加插件到配置
    cat >> "$SHELDON_CONFIG" << EOF

[plugins.$plugin_name]
github = "$plugin_repo"
EOF

    success "插件 $plugin_name 已添加"
}

# 卸载插件
uninstall_plugin_sheldon() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi

    if [ ! -f "$SHELDON_CONFIG" ]; then
        warn "未找到 sheldon 配置文件"
        return 0
    fi

    # 删除插件配置（使用 sed 删除从 [plugins.name] 到下一个 [ 或文件末尾的内容）
    sed -i.bak "/^\[plugins\.$plugin_name\]/,/^\[/{ /^\[plugins\.$plugin_name\]/d; /^\[/!d; }" "$SHELDON_CONFIG"
    rm -f "${SHELDON_CONFIG}.bak"
    success "插件 $plugin_name 已移除"
}
