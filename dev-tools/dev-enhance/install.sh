#!/usr/bin/env bash
#
# dev-enhance/install.sh
#
# 开发工具增强：Neovim（+LazyVim）、git 全局配置（+delta）、tmux 配置（+tpm）。
# Linux + macOS。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

preflight() {
    detect_os
    check_commands curl
}

# -------- Neovim --------
install_neovim() {
    info "$(_t '📝 Installing Neovim...')"
    if command_exists nvim; then
        local nv_ver; nv_ver=$(nvim --version | head -1)
        success "$(_tf 'Neovim is installed (%s)' "$nv_ver")"
    else
        if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
            brew install neovim
        else
            pkg_install neovim 2>/dev/null || {
                warn "$(_t 'The package manager did not install neovim, trying AppImage...')"
                local url="https://github.com/neovim/neovim/releases/latest/download/nvim.appimage"
                curl -fSL "$url" -o /tmp/nvim.appimage && chmod +x /tmp/nvim.appimage
                sudo mv /tmp/nvim.appimage /usr/local/bin/nvim
            }
        fi
        if command_exists nvim; then
            success "Neovim $(_t 'Installation complete')"
        else
            warn "Neovim $(_t 'The installation may have failed')"
        fi
    fi
    # LazyVim 模板（Neovim 的现代配置发行版）
    if command_exists nvim && [[ ! -d "$HOME/.config/nvim" ]]; then
        info "$(_t 'Installing the LazyVim configuration template...')"
        if command_exists git; then
            git clone https://github.com/LazyVim/starter "$HOME/.config/nvim" 2>/dev/null || true
            rm -rf "$HOME/.config/nvim/.git" 2>/dev/null || true
            success "LazyVim $(_t 'The template is installed to ~/.config/nvim (nvim installs the plugins on the first start)')"
        fi
    fi
}

# -------- git 增强 --------
install_git_enhance() {
    info "$(_t '🔧 Configuring git enhancements...')"
    if ! command_exists git; then
        warn "git $(_t 'Not installed, skipping the git enhancements')"
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
    success "git $(_t 'The global configuration is enhanced (aliases/colors/editor)')"

    # delta：diff 高亮工具
    if ! command_exists delta; then
        info "$(_t 'Installing delta (diff highlighting)...')"
        if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
            brew install git-delta
        else
            pkg_install git-delta 2>/dev/null || warn "delta $(_t 'The automatic installation failed, you can install it manually from https://github.com/dandavison/delta')"
        fi
    fi
    if command_exists delta; then
        git config --global core.pager delta
        git config --global interactive.diffFilter 'delta --color-only'
        git config --global delta.navigate true
        git config --global delta.line-numbers true
        git config --global merge.conflictstyle diff3
        success "delta diff $(_t 'Highlighting is integrated into git')"
    fi
}

# -------- tmux 配置 --------
install_tmux_config() {
    info "$(_t '🖥️  Configuring tmux...')"
    if ! command_exists tmux; then
        info "$(_t 'Installing tmux...')"
        pkg_install tmux 2>/dev/null || brew install tmux 2>/dev/null || warn "tmux $(_t 'Installation failed')"
    fi
    if ! command_exists tmux; then
        warn "tmux $(_t 'Not installed, skipping the configuration')"
        return 0
    fi
    # tpm：tmux 插件管理器
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [[ ! -d "$tpm_dir" ]] && command_exists git; then
        info "$(_t 'Installing tpm (the tmux plugin manager)...')"
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
        success "tmux $(_t 'The configuration is written to ~/.tmux.conf (prefix Ctrl+a, mouse, vim switching, tpm plugins)')"
        info "$(_t 'After entering tmux for the first time, press prefix + I (Ctrl+a then uppercase I) to install the plugins')"
    else
        info "$HOME/.tmux.conf $(_t 'Already exists, skipping')"
    fi
}

install_all() {
    preflight
    info "$(_t '🚀 Development tool enhancements (Neovim + git + tmux)')"
    install_neovim
    echo
    install_git_enhance
    echo
    install_tmux_config
    echo
    success "$(_t '🎉 Development tool enhancements complete!')"
    info "Neovim:  nvim$(_t '(the LazyVim plugins are installed automatically on the first start)')"
    info "git:     git lg$(_t '(colored log tree) / git st (status)')"
    info "tmux:    tmux$(_t '(Ctrl+a prefix, | split, vim pane switching)')"
}

uninstall_dev_enhance() {
    detect_os
    warn "dev-enhance $(_t 'Uninstall instructions:')"
    echo "  Neovim $(_t 'Config: rm -rf ~/.config/nvim ~/.local/share/nvim')"
    echo "  git $(_t 'Enhancement:    git config --global --unset core.pager; git config --global --remove-section delta 2>/dev/null')"
    echo "  tmux $(_t 'Config:   rm ~/.tmux.conf; rm -rf ~/.tmux')"
    echo "  delta/brew:  brew uninstall git-delta neovim"
    info "$(_t '(all are user configurations, clean them up manually as needed)')"
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
    parts="${parts:-$(_t 'none')}"
    if [[ "$parts" != "$(_t 'None')" ]]; then
        emit_status "configured" "${GREEN}$(_t '✅ Configured')${NC} ($parts)"
        emit_extra "configured_parts=$parts"
    else
        emit_status "not_configured" "${RED}$(_t '❌ Not configured')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install Neovim(+LazyVim) + git enhancements(delta+aliases) + tmux configuration(tpm)')
  uninstall   $(_t 'Show the uninstall instructions')
  status      $(_t 'View the status')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
