#!/usr/bin/env bash
#
# dev-enhance/install.sh
#
# 开发工具增强：Neovim（+LazyVim）、git 全局配置（+delta）、tmux 配置（+tpm）。
# Linux + macOS。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    check_commands curl
}

# -------- Neovim --------
install_neovim() {
    info "📝 安装 Neovim..."
    if command_exists nvim; then
        success "Neovim 已安装（$(nvim --version | head -1)）"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
            brew install neovim
        else
            pkg_install neovim 2>/dev/null || {
                warn "包管理器未装到 neovim，尝试 AppImage..."
                local url="https://github.com/neovim/neovim/releases/latest/download/nvim.appimage"
                curl -fSL "$url" -o /tmp/nvim.appimage && chmod +x /tmp/nvim.appimage
                sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
            }
        fi
        if command_exists nvim; then
            success "Neovim 安装完成"
        else
            warn "Neovim 安装可能失败"
        fi
    fi
    # LazyVim 模板（Neovim 的现代配置发行版）
    if command_exists nvim && [[ ! -d "$HOME/.config/nvim" ]]; then
        info "安装 LazyVim 配置模板..."
        if command_exists git; then
            git clone https://github.com/LazyVim/starter "$HOME/.config/nvim" 2>/dev/null || true
            rm -rf "$HOME/.config/nvim/.git" 2>/dev/null || true
            success "LazyVim 模板已安装到 ~/.config/nvim（首次启动 nvim 会自动装插件）"
        fi
    fi
}

# -------- git 增强 --------
install_git_enhance() {
    info "🔧 配置 git 增强..."
    if ! command_exists git; then
        warn "git 未安装，跳过 git 增强"
        return 0
    fi
    # 全局配置
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.editor "$(command -v nvim || command -v vim || echo vi)"
    git config --global color.ui auto
    # 有用别名
    git config --global alias.st status
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.unstage 'reset HEAD --'
    git config --global alias.last 'log -1 HEAD'
    git config --global alias.visual '!gitk'
    git config --global alias.lg "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all"
    success "git 全局配置已增强（别名/颜色/编辑器）"

    # delta：diff 高亮工具
    if ! command_exists delta; then
        info "安装 delta（diff 高亮）..."
        if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
            brew install git-delta
        else
            pkg_install git-delta 2>/dev/null || warn "delta 自动安装失败，可从 https://github.com/dandavison/delta 手动安装"
        fi
    fi
    if command_exists delta; then
        git config --global core.pager delta
        git config --global interactive.diffFilter 'delta --color-only'
        git config --global delta.navigate true
        git config --global delta.line-numbers true
        git config --global merge.conflictstyle diff3
        success "delta diff 高亮已集成到 git"
    fi
}

# -------- tmux 配置 --------
install_tmux_config() {
    info "🖥️  配置 tmux..."
    if ! command_exists tmux; then
        info "安装 tmux..."
        pkg_install tmux 2>/dev/null || brew install tmux 2>/dev/null || warn "tmux 安装失败"
    fi
    if ! command_exists tmux; then
        warn "tmux 未安装，跳过配置"
        return 0
    fi
    # tpm：tmux 插件管理器
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [[ ! -d "$tpm_dir" ]] && command_exists git; then
        info "安装 tpm（tmux 插件管理器）..."
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir" 2>/dev/null || true
    fi
    # 写一份实用的 .tmux.conf（若不存在）
    local tmux_conf="$HOME/.tmux.conf"
    if [[ ! -f "$tmux_conf" ]]; then
        cat > "$tmux_conf" <<'TMUXEOF'
# === unix_script tmux 配置 ===
# 前缀键改为 Ctrl+a（更顺手）
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# 鼠标支持
set -g mouse on

# 256 色 + true color
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# 分屏快捷键（用 | 和 - 更直观）
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
unbind '"'
unbind %

# 新窗口/窗格保持当前路径
bind c new-window -c "#{pane_current_path}"

# vim 风格切换窗格
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# 从 1 开始编号
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# 快速重载配置
bind r source-file ~/.tmux.conf \; display "tmux.conf reloaded!"

# === 插件（tpm 管理）===
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-restore 'on'

# 初始化 tpm（保持在最后一行）
run '~/.tmux/plugins/tpm/tpm'
TMUXEOF
        success "tmux 配置已写入 ~/.tmux.conf（前缀 Ctrl+a，鼠标，vim 切换，tpm 插件）"
        info "首次进入 tmux 后按 prefix + I（Ctrl+a 再按大写 I）安装插件"
    else
        info "$HOME/.tmux.conf 已存在，跳过"
    fi
}

install_all() {
    preflight
    info "🚀 开发工具增强（Neovim + git + tmux）"
    install_neovim
    echo
    install_git_enhance
    echo
    install_tmux_config
    echo
    success "🎉 开发工具增强完成！"
    info "Neovim:  nvim（首次启动自动装 LazyVim 插件）"
    info "git:     git lg（彩色日志树）/ git st（状态）"
    info "tmux:    tmux（Ctrl+a 前缀，| 分屏，vim 切换窗格）"
}

uninstall_dev_enhance() {
    detect_os
    warn "dev-enhance 卸载说明："
    echo "  Neovim 配置: rm -rf ~/.config/nvim ~/.local/share/nvim"
    echo "  git 增强:    git config --global --unset core.pager; git config --global --remove-section delta 2>/dev/null"
    echo "  tmux 配置:   rm ~/.tmux.conf; rm -rf ~/.tmux"
    echo "  delta/brew:  brew uninstall git-delta neovim"
    info "（均为用户配置，按需手动清理）"
}

status_dev_enhance() {
    detect_os
    local nvim_ok=false git_ok=false tmux_ok=false
    command_exists nvim && nvim_ok=true
    command_exists git && git config --global alias.lg >/dev/null 2>&1 && git_ok=true
    command_exists tmux && [[ -f "$HOME/.tmux.conf" ]] && tmux_ok=true
    local parts=""
    $nvim_ok && parts="${parts}nvim "
    $git_ok && parts="${parts}git-enhanced "
    $tmux_ok && parts="${parts}tmux-configured"
    parts="${parts:-无}"
    if [[ "$parts" != "无" ]]; then
        echo -e "${GREEN}✅ 已配置${NC} ($parts)"
    else
        echo -e "${RED}❌ 未配置${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 Neovim(+LazyVim) + git 增强(delta+别名) + tmux 配置(tpm)
  uninstall   显示卸载说明
  status      查看状态
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_all ;;
        uninstall) uninstall_dev_enhance ;;
        status)    status_dev_enhance ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
