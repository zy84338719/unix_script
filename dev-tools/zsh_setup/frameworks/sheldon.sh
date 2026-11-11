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
    if os_has_cmd sheldon; then
        warn "$(_t 'sheldon is already installed')"
        return 0
    fi

    info "$(_t 'Installing sheldon...')"
    # 信任模型：crate.sh 通用安装器从 GitHub release 拉取 tarball，并校验其内嵌的 SHA256，
    # 故二进制完整性已自校验；仅需信任传输层（HTTPS）。
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon

    if ! os_has_cmd sheldon; then
        error "$(_t 'Failed to install sheldon')"
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

    success "$(_t 'sheldon installed successfully')"
}

# 卸载 sheldon
uninstall_sheldon() {
    if ! os_has_cmd sheldon; then
        warn "$(_t 'sheldon is not installed')"
        return 0
    fi

    if ! yes_no "$(_t 'Uninstall sheldon?')"; then
        info "$(_t 'Uninstall cancelled')"
        return 0
    fi

    info "$(_t 'Uninstalling sheldon...')"

    # 删除 sheldon 二进制文件
    local sheldon_path
    sheldon_path=$(command -v sheldon)
    if [ -n "$sheldon_path" ]; then
        rm -f "$sheldon_path"
    fi

    success "$(_t 'sheldon uninstalled')"
}

# sheldon 状态
status_sheldon() {
    if ! os_has_cmd sheldon; then
        printf '%s\n' "$(_t 'sheldon: not installed')"
        return 0
    fi

    printf '%s\n' "$(_t 'sheldon: installed')"

    # 列出插件
    printf '%s\n' "$(_t 'Plugins:')"
    list_plugins_sheldon
}

# 列出 sheldon 插件
list_plugins_sheldon() {
    if [ ! -f "$SHELDON_CONFIG" ]; then
        warn "$(_t 'sheldon config file not found')"
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
        error "$(_t 'Please specify a plugin name')"
        return 1
    fi

    if [ -z "$plugin_repo" ]; then
        error "$(_t 'Please specify the plugin repo (format: user/repo)')"
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
        warn "$(_tf 'Plugin %s already exists' "$plugin_name")"
        return 0
    fi

    # 添加插件到配置
    cat >> "$SHELDON_CONFIG" << EOF

[plugins.$plugin_name]
github = "$plugin_repo"
EOF

    success "$(_tf 'Plugin %s added' "$plugin_name")"
}

# 卸载插件
uninstall_plugin_sheldon() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        error "$(_t 'Please specify a plugin name')"
        return 1
    fi

    if [ ! -f "$SHELDON_CONFIG" ]; then
        warn "$(_t 'sheldon config file not found')"
        return 0
    fi

    # 删除插件配置（使用 sed 删除从 [plugins.name] 到下一个 [ 或文件末尾的内容）
    sed -i.bak "/^\[plugins\.$plugin_name\]/,/^\[/{ /^\[plugins\.$plugin_name\]/d; /^\[/!d; }" "$SHELDON_CONFIG"
    rm -f "${SHELDON_CONFIG}.bak"
    success "$(_tf 'Plugin %s removed' "$plugin_name")"
}
