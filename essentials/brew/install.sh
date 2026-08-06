#!/usr/bin/env bash
#
# brew/install.sh
#
# 安装 Homebrew —— macOS（及 Linux）上最流行的包管理器。
# 仅支持 macOS；Linux 上提示使用 Linuxbrew 或跳过。
#
# 子命令：install | uninstall | mirror | unmirror | status | help
#

set -e

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
        warn "Homebrew 主要面向 macOS"
        if ! yes_no "Linux 上将使用 Linuxbrew（部分 formula 不支持），是否继续？"; then
            info "已取消"; exit 0
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

    info "将 brew shellenv 写入 $rc"
    {
        echo ""
        echo "$BREW_ENV_MARKER"
        echo "$shellenv_line"
        echo "# <<< homebrew <<<"
    } >> "$rc"
    success "已写入 $rc（重新打开终端或 source $rc 生效）"
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
    info "已从 $rc 移除 brew shellenv 配置"
}

install_brew() {
    preflight
    info "🍺 安装 Homebrew 包管理器"

    if command_exists brew; then
        local cur
        cur=$(brew --version 2>/dev/null | head -1 || echo "已安装")
        warn "检测到已安装 Homebrew（$cur）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    info "通过官方脚本安装（$BREW_INSTALLER）..."
    /bin/bash -c "$(curl -fsSL "$BREW_INSTALLER")"

    # 配置 PATH
    _ensure_shellenv

    # 立即生效（当前 shell）
    local prefix
    prefix="$(_brew_prefix)"
    eval "$("$prefix/bin/brew" shellenv)"

    if ! command_exists brew; then
        error "安装后仍找不到 brew，请重新打开终端或执行："
        echo "  eval \"\$($(_brew_prefix)/bin/brew shellenv)\""
        exit 1
    fi

    success "🎉 Homebrew 安装完成！"
    info "快速开始："
    echo "  brew install <包名>      # 安装软件包"
    echo "  brew search <关键词>     # 搜索软件包"
    echo "  brew list               # 已安装列表"
    echo "  brew update             # 更新索引"
    echo "  brew upgrade            # 升级所有已安装包"
    echo "  brew info <包名>        # 查看包信息"
    echo
    info "文档：https://docs.brew.sh"
}

uninstall_brew() {
    detect_os
    if ! command_exists brew; then
        warn "未检测到 Homebrew，可能已卸载"
        return 0
    fi

    local prefix
    prefix="$(brew --prefix 2>/dev/null || echo "/opt/homebrew")"

    if ! yes_no "确认卸载 Homebrew？这将删除 $prefix 下所有通过 brew 安装的包"; then
        info "已取消"; return 0
    fi

    info "卸载 Homebrew..."
    # 官方卸载脚本是非交互式的
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" -- --yes 2>/dev/null || true

    # 如果官方卸载脚本不可用，手动清理
    if [[ -d "$prefix" ]]; then
        warn "官方卸载脚本未完全清理，尝试手动删除..."
        if yes_no "确认删除 $prefix 目录？"; then
            sudo rm -rf "$prefix"
        fi
    fi

    # 清理 shell 配置
    _remove_shellenv

    success "Homebrew 已卸载"
    info "请重新打开终端使 PATH 变更生效"
}

mirror_brew() {
    detect_os
    if ! command_exists brew; then
        error "Homebrew 未安装，请先运行：$0 install"
        exit 1
    fi

    info "🌐 配置 Homebrew 国内镜像源（清华 TUNA）"
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

    success "已配置清华镜像源（写入 $rc）"
    info "镜像地址："
    echo "  API:      $MIRROR_API_DOMAIN"
    echo "  Brew:     $MIRROR_BREW_REMOTE"
    echo "  Core:     $MIRROR_CORE_REMOTE"
    echo "  Bottles:  $MIRROR_BOTTLE_DOMAIN"
    echo
    info "重新打开终端或 source $rc 使配置持久生效"
    info "运行 brew update 验证镜像是否生效"
}

unmirror_brew() {
    local rc
    rc="$(_shell_rc)"
    if [[ ! -f "$rc" ]] || ! grep -qF "# >>> brew-mirror >>>" "$rc" 2>/dev/null; then
        info "未检测到 brew 镜像配置，已是官方源"; return 0
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

    success "已还原 Homebrew 官方源"
    info "重新打开终端或 source $rc 使配置生效"
}

status_brew() {
    detect_os
    if ! command_exists brew; then
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
        return 0
    fi

    local ver prefix cur_src="(官方源)"
    ver=$(brew --version 2>/dev/null | head -1 || echo "")
    # 显示前缀
    prefix=$(brew --prefix 2>/dev/null || echo "")

    # 检测当前源（官方 or 镜像）—— 计算在 emit_status 之前，但 STATE= 必须是首行
    if [[ -n "${HOMEBREW_BOTTLE_DOMAIN:-}" ]]; then
        if [[ "$HOMEBREW_BOTTLE_DOMAIN" == *"tsinghua"* ]]; then
            cur_src="(清华镜像)"
        elif [[ "$HOMEBREW_BOTTLE_DOMAIN" == *"ustc"* ]]; then
            cur_src="(中科大镜像)"
        elif [[ "$HOMEBREW_BOTTLE_DOMAIN" == *"aliyun"* ]]; then
            cur_src="(阿里云镜像)"
        else
            cur_src="(自定义镜像: $HOMEBREW_BOTTLE_DOMAIN)"
        fi
    elif [[ -f "$(_shell_rc)" ]] && grep -qF "# >>> brew-mirror >>>" "$(_shell_rc)" 2>/dev/null; then
        cur_src="(已配置镜像，当前 shell 未加载)"
    fi

    emit_status "installed" "${GREEN}✅ 已安装${NC} ${ver:+($ver)}"
    emit_version "$ver"
    if [[ -n "$prefix" ]]; then
        emit_extra "prefix=$prefix"
        if ! uxs_is_machine_mode; then
            echo "   prefix: $prefix"
        fi
    fi
    emit_extra "source=$cur_src"
    if ! uxs_is_machine_mode; then
        echo "   source: $cur_src"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|mirror|unmirror|status|help}

  install     安装 Homebrew（默认动作）
  uninstall   卸载 Homebrew（交互确认）
  mirror      配置国内镜像源（清华 TUNA，加速下载）
  unmirror    还原官方源
  status      查看安装状态和当前源
  help        显示此帮助
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
