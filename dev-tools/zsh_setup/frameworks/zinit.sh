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
        warn "Zinit 已安装"
        return 0
    fi

    info "正在安装 Zinit..."
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

    if [ ! -d "$ZINIT_DIR" ]; then
        error "Zinit 安装失败"
        return 1
    fi

    success "Zinit 安装成功"
}

# 卸载 Zinit
uninstall_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        warn "Zinit 未安装"
        return 0
    fi

    if ! yes_no "确定要卸载 Zinit 吗？"; then
        info "取消卸载"
        return 0
    fi

    info "正在卸载 Zinit..."
    rm -rf "$ZINIT_DIR"
    rm -rf "${HOME}/.local/share/zinit"

    success "Zinit 已卸载"
}

# Zinit 状态
status_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        echo "Zinit: 未安装"
        return 0
    fi

    echo "Zinit: 已安装"

    # 列出插件
    echo "插件:"
    list_plugins_zinit
}

# 列出 Zinit 插件
list_plugins_zinit() {
    if [ ! -d "$ZINIT_DIR" ]; then
        warn "Zinit 未安装"
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
        error "请指定插件名称"
        return 1
    fi

    local zshrc="$HOME/.zshrc"

    if [ ! -f "$zshrc" ]; then
        error "未找到 .zshrc 文件"
        return 1
    fi

    # 检查插件是否已安装
    if grep -q "zinit light $plugin_spec" "$zshrc"; then
        warn "插件 $plugin_spec 已安装"
        return 0
    fi

    # 添加插件到 .zshrc
    echo "zinit light $plugin_spec" >> "$zshrc"
    success "插件 $plugin_spec 已添加"
    info "请运行 'source ~/.zshrc' 或重启终端以加载插件"
}

# 卸载插件
uninstall_plugin_zinit() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi

    local zshrc="$HOME/.zshrc"

    if [ ! -f "$zshrc" ]; then
        error "未找到 .zshrc 文件"
        return 1
    fi

    # 删除插件
    sed -i.bak "/zinit light $plugin_name/d" "$zshrc"
    rm -f "${zshrc}.bak"
    success "插件 $plugin_name 已移除"
}
