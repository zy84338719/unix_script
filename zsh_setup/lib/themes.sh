#!/bin/bash
#
# zsh_setup/lib/themes.sh
# 主题管理模块
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/framework.sh"

# 列出主题
theme_list() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        warn "未安装框架"
        return 0
    fi

    info "当前框架: $framework"

    case "$framework" in
        oh-my-zsh)
            echo "可用主题:"
            ls "$HOME/.oh-my-zsh/themes/" 2>/dev/null | sed 's/.zsh-theme$//'
            if [ -d "$HOME/.oh-my-zsh/custom/themes" ]; then
                echo ""
                echo "自定义主题:"
                ls "$HOME/.oh-my-zsh/custom/themes/" 2>/dev/null | sed 's/.zsh-theme$//'
            fi
            ;;
        prezto)
            echo "可用主题:"
            ls "${ZDOTDIR:-$HOME}/.zprezto/modules/prompt/external/themes/" 2>/dev/null
            ;;
        zinit)
            echo "常用主题:"
            echo "  - powerlevel10k"
            echo "  - starship"
            echo "  - pure"
            ;;
        sheldon)
            echo "常用主题:"
            echo "  - powerlevel10k"
            echo "  - starship"
            echo "  - pure"
            ;;
    esac
}

# 设置主题
theme_set() {
    local theme_name="$1"

    if [ -z "$theme_name" ]; then
        error "请指定主题名称"
        return 1
    fi

    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        error "未安装框架"
        return 1
    fi

    case "$framework" in
        oh-my-zsh)
            local zshrc="$HOME/.zshrc"
            if [ ! -f "$zshrc" ]; then
                error "未找到 .zshrc 文件"
                return 1
            fi

            # 更新主题
            sed -i.bak "s/^ZSH_THEME=.*/ZSH_THEME=\"$theme_name\"/" "$zshrc"
            success "主题已设置为 $theme_name"
            ;;
        prezto)
            local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"
            if [ ! -f "$preztorc" ]; then
                error "未找到 .zpreztorc 文件"
                return 1
            fi

            # 更新主题
            sed -i.bak "s/^zstyle ':prezto:module:prompt' theme.*/zstyle ':prezto:module:prompt' theme '$theme_name'/" "$preztorc"
            success "主题已设置为 $theme_name"
            ;;
        zinit)
            info "请在 .zshrc 中添加主题配置"
            echo "示例:"
            echo "  zinit ice depth=1; zinit light romkatv/powerlevel10k"
            ;;
        sheldon)
            info "请在 ~/.config/sheldon/plugins.toml 中添加主题配置"
            ;;
    esac
}

# 安装 Powerlevel10k
theme_install_p10k() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        error "未安装框架"
        return 1
    fi

    info "正在安装 Powerlevel10k..."

    case "$framework" in
        oh-my-zsh)
            local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
            if [ -d "$theme_dir" ]; then
                warn "Powerlevel10k 已安装"
                return 0
            fi
            if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"; then
                error "Powerlevel10k 克隆失败"
                return 1
            fi
            theme_set "powerlevel10k/powerlevel10k"
            ;;
        prezto)
            local theme_dir="${ZDOTDIR:-$HOME}/.zprezto/modules/prompt/external/themes/powerlevel10k"
            if [ -d "$theme_dir" ]; then
                warn "Powerlevel10k 已安装"
                return 0
            fi
            if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"; then
                error "Powerlevel10k 克隆失败"
                return 1
            fi
            theme_set "powerlevel10k"
            ;;
        zinit)
            local zshrc="$HOME/.zshrc"
            if ! grep -q "powerlevel10k" "$zshrc" 2>/dev/null; then
                echo 'zinit ice depth=1; zinit light romkatv/powerlevel10k' >> "$zshrc"
            fi
            success "Powerlevel10k 已添加到 .zshrc"
            ;;
        sheldon)
            load_framework "sheldon" || return 1
            install_plugin_sheldon "powerlevel10k" "romkatv/powerlevel10k"
            ;;
    esac

    success "Powerlevel10k 安装完成"
    info "请运行 'p10k configure' 进行配置"
}
