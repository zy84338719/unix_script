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
        warn "$(_t 'No framework installed')"
        return 0
    fi

    info "$(_tf 'Current framework: %s' "$framework")"

    case "$framework" in
        oh-my-zsh)
            printf '%s\n' "$(_t 'Available themes:')"
            find "$HOME/.oh-my-zsh/themes" -maxdepth 1 -name '*.zsh-theme' -exec basename {} .zsh-theme \; 2>/dev/null
            if [ -d "$HOME/.oh-my-zsh/custom/themes" ]; then
                echo ""
                printf '%s\n' "$(_t 'Custom themes:')"
                find "$HOME/.oh-my-zsh/custom/themes" -maxdepth 1 -name '*.zsh-theme' -exec basename {} .zsh-theme \; 2>/dev/null
            fi
            ;;
        prezto)
            printf '%s\n' "$(_t 'Available themes:')"
            find "${ZDOTDIR:-$HOME}/.zprezto/modules/prompt/external/themes" -maxdepth 1 -mindepth 1 -exec basename {} \; 2>/dev/null
            ;;
        zinit)
            printf '%s\n' "$(_t 'Common themes:')"
            echo "  - powerlevel10k"
            echo "  - starship"
            echo "  - pure"
            ;;
        sheldon)
            printf '%s\n' "$(_t 'Common themes:')"
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
        error "$(_t 'Please specify a theme name')"
        return 1
    fi

    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        error "$(_t 'No framework installed')"
        return 1
    fi

    case "$framework" in
        oh-my-zsh)
            local zshrc="$HOME/.zshrc"
            if [ ! -f "$zshrc" ]; then
                error "$(_t '.zshrc file not found')"
                return 1
            fi

            # 更新主题
            sed -i.bak "s/^ZSH_THEME=.*/ZSH_THEME=\"$theme_name\"/" "$zshrc"
            success "$(_tf 'Theme set to %s' "$theme_name")"
            ;;
        prezto)
            local preztorc="${ZDOTDIR:-$HOME}/.zpreztorc"
            if [ ! -f "$preztorc" ]; then
                error "$(_t '.zpreztorc file not found')"
                return 1
            fi

            # 更新主题
            sed -i.bak "s/^zstyle ':prezto:module:prompt' theme.*/zstyle ':prezto:module:prompt' theme '$theme_name'/" "$preztorc"
            success "$(_tf 'Theme set to %s' "$theme_name")"
            ;;
        zinit)
            info "$(_t 'Add the theme configuration in .zshrc')"
            printf '%s\n' "$(_t 'Example:')"
            echo "  zinit ice depth=1; zinit light romkatv/powerlevel10k"
            ;;
        sheldon)
            info "$(_t 'Add the theme config in ~/.config/sheldon/plugins.toml')"
            ;;
    esac
}

# 安装 Powerlevel10k
theme_install_p10k() {
    local framework
    framework=$(detect_framework)

    if [ "$framework" == "none" ]; then
        error "$(_t 'No framework installed')"
        return 1
    fi

    info "$(_t 'Installing Powerlevel10k...')"

    case "$framework" in
        oh-my-zsh)
            local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
            if [ -d "$theme_dir" ]; then
                warn "$(_t 'Powerlevel10k is already installed')"
                return 0
            fi
            if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"; then
                error "$(_t 'Failed to clone Powerlevel10k')"
                return 1
            fi
            theme_set "powerlevel10k/powerlevel10k"
            ;;
        prezto)
            local theme_dir="${ZDOTDIR:-$HOME}/.zprezto/modules/prompt/external/themes/powerlevel10k"
            if [ -d "$theme_dir" ]; then
                warn "$(_t 'Powerlevel10k is already installed')"
                return 0
            fi
            if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"; then
                error "$(_t 'Failed to clone Powerlevel10k')"
                return 1
            fi
            theme_set "powerlevel10k"
            ;;
        zinit)
            local zshrc="$HOME/.zshrc"
            if ! grep -q "powerlevel10k" "$zshrc" 2>/dev/null; then
                echo 'zinit ice depth=1; zinit light romkatv/powerlevel10k' >> "$zshrc"
            fi
            success "$(_t 'Powerlevel10k added to .zshrc')"
            ;;
        sheldon)
            load_framework "sheldon" || return 1
            install_plugin_sheldon "powerlevel10k" "romkatv/powerlevel10k"
            ;;
    esac

    success "$(_t 'Powerlevel10k installation complete')"
    info "$(_t 'Run p10k configure to set it up')"
}
