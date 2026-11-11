#!/usr/bin/env bash
#
# brew/install.sh
#
# 安装 Homebrew —— macOS（及 Linux）上最流行的包管理器。
# 仅支持 macOS；Linux 上提示使用 Linuxbrew 或跳过。
#
# 子命令：install | uninstall | mirror | unmirror | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 官方安装脚本
BREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# Homebrew 环境变量前缀标记（用于清理）
BREW_ENV_MARKER="# >>> homebrew >>>"

# 国内镜像配置（清华源）
MIRROR_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
MIRROR_BREW_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
MIRROR_CORE_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
MIRROR_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"

preflight() {
    detect_os
    if [[ "$OS_TYPE" != "darwin" ]]; then
        warn "$(_t 'Homebrew mainly targets macOS')"
        if ! yes_no "$(_t 'Linuxbrew on Linux (some formulae are unsupported). Continue?')"; then
            info "$(_t 'Cancelled')"; exit 0
        fi
    fi
    check_commands curl git
}

# 获取 brew 前缀（Apple Silicon: /opt/homebrew, Intel/Linux: /usr/local）
_brew_prefix() {
    if [[ -x /opt/homebrew/bin/brew ]]; then
        echo "/opt/homebrew"
    elif [[ -x /usr/local/bin/brew ]]; then
        echo "/usr/local"
    else
        # 未安装时根据架构推测
        if [[ "$(uname -m)" == "arm64" ]]; then
            echo "/opt/homebrew"
        else
            echo "/usr/local"
        fi
    fi
}

# 检测当前使用的 shell 配置文件
_shell_rc() {
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
        echo "$HOME/.zprofile"
    elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == */bash ]]; then
        echo "$HOME/.bash_profile"
    else
        echo "$HOME/.profile"
    fi
}

# 将 brew shellenv 写入 shell 配置（幂等）
_ensure_shellenv() {
    local prefix
    prefix="$(_brew_prefix)"
    local rc
    rc="$(_shell_rc)"
    local shellenv_line="eval \"\$(${prefix}/bin/brew shellenv)\""

    if [[ -f "$rc" ]] && grep -qF "$shellenv_line" "$rc" 2>/dev/null; then
        return 0
    fi

    info "$(_tf 'Writing brew shellenv to %s' "$rc")"
    {
        echo ""
        echo "$BREW_ENV_MARKER"
        echo "$shellenv_line"
        echo "# <<< homebrew <<<"
    } >> "$rc"
    success "$(_tf 'Written to %s (reopen the terminal or source %s to apply)' "${rc}" "$rc")"
}

# 从 shell 配置中移除 brew shellenv 块
_remove_shellenv() {
    local rc
    rc="$(_shell_rc)"
    if [[ ! -f "$rc" ]]; then
        return 0
    fi
    if ! grep -qF "$BREW_ENV_MARKER" "$rc" 2>/dev/null; then
        return 0
    fi
    local tmp
    tmp=$(mktemp)
    # 移除 >>> homebrew >>> 到 <<< homebrew <<< 之间的内容（含标记行）
    awk '
        /# >>> homebrew >>>/ { skip=1; next }
        /# <<< homebrew <<</ { skip=0; next }
        !skip { print }
    ' "$rc" > "$tmp"
    mv "$tmp" "$rc"
    info "$(_tf 'Removed the brew shellenv configuration from %s' "$rc")"
}

install_brew() {
    preflight
    info "$(_t '🍺 Installing the Homebrew package manager')"

    if os_has_cmd brew; then
        local cur
        cur=$(brew --version 2>/dev/null | head -1 || printf '%s\n' "$(_t 'Homebrew is already installed')")
        warn "$(_tf 'Homebrew is already installed (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue with the reinstall/update?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    info "$(_tf 'Installing via the official script (%s)...' "${BREW_INSTALLER}")"
    /bin/bash -c "$(curl -fsSL "$BREW_INSTALLER")"

    # 配置 PATH
    _ensure_shellenv

    # 立即生效（当前 shell）
    local prefix
    prefix="$(_brew_prefix)"
    eval "$("$prefix/bin/brew" shellenv)"

    if ! os_has_cmd brew; then
        error "$(_t 'brew is still not found, reopen the terminal or run:')"
        echo "  eval \"\$($(_brew_prefix)/bin/brew shellenv)\""
        exit 1
    fi

    success "$(_t '🎉 Homebrew installation complete!')"
    info "$(_t 'Quick start:')"
    echo "  $(_t 'brew install <package>      # Install a package')"
    echo "  $(_t 'brew search <keyword>     # Search for packages')"
    echo "  $(_t 'brew list               # List the installed packages')"
    echo "  $(_t 'brew update             # Update the index')"
    echo "  $(_t 'brew upgrade            # Upgrade all the installed packages')"
    echo "  $(_t 'brew info <package>        # Show the package information')"
    echo
    info "$(_t 'Documentation: https://docs.brew.sh')"
}

uninstall_brew() {
    detect_os
    if ! os_has_cmd brew; then
        warn "$(_t 'Homebrew was not detected, it may already be uninstalled')"
        return 0
    fi

    local prefix
    prefix="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")"

    if ! yes_no "$(_tf 'Uninstall Homebrew? This deletes all brew packages under %s' "$prefix")"; then
        info "$(_t 'Cancelled')"; return 0
    fi

    info "$(_t 'Uninstalling Homebrew...')"
    # 官方卸载脚本是非交互式的
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" -- --yes 2>/dev/null || true

    # 如果官方卸载脚本不可用，手动清理
    if [[ -d "$prefix" ]]; then
        warn "$(_t 'The official uninstall script did not clean up fully, manual delete...')"
        if yes_no "$(_tf 'Delete the directory %s?' "$prefix")"; then
            sudo rm -rf "$prefix"
        fi
    fi

    # 清理 shell 配置
    _remove_shellenv

    success "$(_t 'Homebrew has been uninstalled')"
    info "$(_t 'Please reopen the terminal for the PATH change to take effect')"
}

mirror_brew() {
    detect_os
    if ! os_has_cmd brew; then
        error "$(_tf 'Homebrew is not installed, please run first: %s install' "$0")"
        exit 1
    fi

    info "$(_t '🌐 Configuring a domestic mirror source for Homebrew (Tsinghua TUNA)')"
    local rc
    rc="$(_shell_rc)"
    local tmp
    tmp=$(mktemp)

    # 移除已有的 Homebrew 镜像配置
    if [[ -f "$rc" ]]; then
        awk '
            /# >>> brew-mirror >>>/ { skip=1; next }
            /# <<< brew-mirror <<</ { skip=0; next }
            !skip { print }
        ' "$rc" > "$tmp"
    else
        : > "$tmp"
    fi

    # 写入新的镜像配置
    {
        cat "$tmp"
        echo ""
        echo "# >>> brew-mirror >>>"
        echo "export HOMEBREW_API_DOMAIN=\"$MIRROR_API_DOMAIN\""
        echo "export HOMEBREW_BREW_GIT_REMOTE=\"$MIRROR_BREW_REMOTE\""
        echo "export HOMEBREW_CORE_GIT_REMOTE=\"$MIRROR_CORE_REMOTE\""
        echo "export HOMEBREW_BOTTLE_DOMAIN=\"$MIRROR_BOTTLE_DOMAIN\""
        echo "# <<< brew-mirror <<<"
    } > "$rc"
    rm -f "$tmp"

    # 立即生效
    export HOMEBREW_API_DOMAIN="$MIRROR_API_DOMAIN"
    export HOMEBREW_BREW_GIT_REMOTE="$MIRROR_BREW_REMOTE"
    export HOMEBREW_CORE_GIT_REMOTE="$MIRROR_CORE_REMOTE"
    export HOMEBREW_BOTTLE_DOMAIN="$MIRROR_BOTTLE_DOMAIN"

    success "$(_tf 'The Tsinghua mirror source is configured (written to %s)' "${rc}")"
    info "$(_t 'Mirror addresses:')"
    echo "  API:      $MIRROR_API_DOMAIN"
    echo "  Brew:     $MIRROR_BREW_REMOTE"
    echo "  Core:     $MIRROR_CORE_REMOTE"
    echo "  Bottles:  $MIRROR_BOTTLE_DOMAIN"
    echo
    info "$(_tf 'Reopen the terminal or source %s to make the configuration persistent' "$rc")"
    info "$(_t 'Run brew update to verify whether the mirror is in effect')"
}

unmirror_brew() {
    local rc
    rc="$(_shell_rc)"
    if [[ ! -f "$rc" ]] || ! grep -qF "# >>> brew-mirror >>>" "$rc" 2>/dev/null; then
        info "$(_t 'No brew mirror configuration detected, already on the official source')"; return 0
    fi

    local tmp
    tmp=$(mktemp)
    awk '
        /# >>> brew-mirror >>>/ { skip=1; next }
        /# <<< brew-mirror <<</ { skip=0; next }
        !skip { print }
    ' "$rc" > "$tmp"
    mv "$tmp" "$rc"

    # 取消当前 shell 中的镜像变量
    unset HOMEBREW_API_DOMAIN HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE HOMEBREW_BOTTLE_DOMAIN 2>/dev/null || true

    success "$(_t 'Restored the official Homebrew source')"
    info "$(_tf 'Reopen the terminal or source %s to apply the configuration' "$rc")"
}

status_brew() {
    detect_os
    if [[ "$OS_TYPE" != "darwin" ]]; then
        uxs_emit_status "n/a" "${YELLOW}$(_t '⚠️  Not applicable (macOS only)')${NC}"
        return 0
    fi
    if ! os_has_cmd brew; then
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
        return 0
    fi

    local ver prefix cur_src; cur_src="$(_t '(official source)')"
    ver=$(brew --version 2>/dev/null | head -1 || echo "")
    # 显示前缀
    prefix=$(brew --prefix 2>/dev/null || echo "")

    # 检测当前源（官方 or 镜像）—— 计算在 uxs_emit_status 之前，但 STATE= 必须是首行
    if [[ -n "${HOMEBREW_BOTTLE_DOMAIN:-}" ]]; then
        if [[ "$HOMEBREW_BOTTLE_DOMAIN" == *"tsinghua"* ]]; then
            cur_src="$(_t '(Tsinghua mirror)')"
        elif [[ "$HOMEBREW_BOTTLE_DOMAIN" == *"ustc"* ]]; then
            cur_src="$(_t '(USTC mirror)')"
        elif [[ "$HOMEBREW_BOTTLE_DOMAIN" == *"aliyun"* ]]; then
            cur_src="$(_t '(Aliyun mirror)')"
        else
            cur_src="$(_tf '(custom mirror: %s)' "$HOMEBREW_BOTTLE_DOMAIN")"
        fi
    elif [[ -f "$(_shell_rc)" ]] && grep -qF "# >>> brew-mirror >>>" "$(_shell_rc)" 2>/dev/null; then
        cur_src="$(_t '(mirror configured, not loaded in the current shell)')"
    fi

    uxs_emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+($ver)}"
    uxs_emit_version "$ver"
    if [[ -n "$prefix" ]]; then
        uxs_emit_extra "prefix=$prefix"
        if ! uxs_is_machine_mode; then
            echo "   prefix: $prefix"
        fi
    fi
    uxs_emit_extra "source=$cur_src"
    if ! uxs_is_machine_mode; then
        echo "   source: $cur_src"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|mirror|unmirror|status|help}

  install     $(_t 'Install Homebrew (the default action)')
  uninstall   $(_t 'Uninstall Homebrew (with a confirmation)')
  mirror      $(_t 'Configure a domestic mirror (Tsinghua TUNA, faster downloads)')
  unmirror    $(_t 'Restore the official source')
  status      $(_t 'View the installation status and the current source')
  help        $(_t 'Show this brew help')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_brew ;;
        uninstall) uninstall_brew ;;
        mirror)    mirror_brew ;;
        unmirror)  unmirror_brew ;;
        status)    status_brew ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
