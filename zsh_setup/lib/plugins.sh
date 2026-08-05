#!/bin/bash
#
# zsh_setup/lib/plugins.sh
# 插件管理模块
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/framework.sh"

# 常用插件名称列表
COMMON_PLUGIN_NAMES=(
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
    zsh-history-substring-search
    zsh-autopair
    zsh-bat
    zsh-fzf
    zsh-eza
)

# 常用插件仓库映射（bash 3.2 兼容）
_common_plugin_repo() {
    case "$1" in
        zsh-autosuggestions)          echo "zsh-users/zsh-autosuggestions" ;;
        zsh-syntax-highlighting)      echo "zsh-users/zsh-syntax-highlighting" ;;
        zsh-completions)              echo "zsh-users/zsh-completions" ;;
        zsh-history-substring-search) echo "zsh-users/zsh-history-substring-search" ;;
        zsh-autopair)                 echo "hlissner/zsh-autopair" ;;
        zsh-bat)                      echo "fdellwing/zsh-bat" ;;
        zsh-fzf)                      echo "unixorn/fzf-zsh-plugin" ;;
        zsh-eza)                      echo "z-shell/zsh-eza" ;;
        *)                            echo "" ;;
    esac
}

# 列出插件
plugin_list() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi

    info "当前框架: $framework"
    framework_list_plugins
}

# 添加插件
plugin_add() {
    local plugin_name="$1"
    local plugin_repo="$2"

    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        echo "常用插件:"
        for name in "${COMMON_PLUGIN_NAMES[@]}"; do
            echo "  - $name"
        done
        return 1
    fi

    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        error "未安装框架，请先安装框架"
        return 1
    fi

    # 如果未指定仓库，使用常用插件列表
    if [ -z "$plugin_repo" ]; then
        plugin_repo=$(_common_plugin_repo "$plugin_name")
    fi

    load_framework "$framework" || return 1

    case "$framework" in
        oh-my-zsh)
            install_plugin_oh_my_zsh "$plugin_name" "$plugin_repo"
            ;;
        prezto)
            enable_module_prezto "$plugin_name"
            ;;
        zinit)
            install_plugin_zinit "$plugin_repo"
            ;;
        sheldon)
            install_plugin_sheldon "$plugin_name" "$plugin_repo"
            ;;
    esac
}

# 移除插件
plugin_remove() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        error "请指定插件名称"
        return 1
    fi

    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        error "未安装框架"
        return 1
    fi

    load_framework "$framework" || return 1

    case "$framework" in
        oh-my-zsh)
            uninstall_plugin_oh_my_zsh "$plugin_name"
            ;;
        prezto)
            disable_module_prezto "$plugin_name"
            ;;
        zinit)
            uninstall_plugin_zinit "$plugin_name"
            ;;
        sheldon)
            uninstall_plugin_sheldon "$plugin_name"
            ;;
    esac
}

# 同步插件
plugin_sync() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi

    info "正在同步 $framework 插件..."

    case "$framework" in
        oh-my-zsh)
            # 更新 Oh My Zsh
            if [ -d "$HOME/.oh-my-zsh" ]; then
                (cd "$HOME/.oh-my-zsh" && git pull)
            fi
            # 更新自定义插件
            for plugin_dir in "$HOME/.oh-my-zsh/custom/plugins/"*/; do
                [ -d "$plugin_dir" ] && (cd "$plugin_dir" && git pull)
            done
            ;;
        prezto)
            # 更新 Prezto
            if [ -d "${ZDOTDIR:-$HOME}/.zprezto" ]; then
                (cd "${ZDOTDIR:-$HOME}/.zprezto" && git pull && git submodule update --init --recursive)
            fi
            ;;
        zinit)
            # 更新 Zinit 插件
            if [ -d "$HOME/.local/share/zinit" ]; then
                (cd "$HOME/.local/share/zinit/zinit.git" && git pull)
            fi
            ;;
        sheldon)
            # sheldon 会在下次加载时自动更新
            info "sheldon 插件将在下次加载时更新"
            ;;
    esac

    success "插件同步完成"
}
