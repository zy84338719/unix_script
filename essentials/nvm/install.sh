#!/usr/bin/env bash
#
# nvm/install.sh
#
# 安装 nvm（Node Version Manager）—— Node.js 多版本管理工具。
# Linux + macOS。安装到 ~/.nvm，并配置 shell 启动文件。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

NVM_DIR="$HOME/.nvm"
NVM_REPO="creationix/nvm"

preflight() {
    detect_os
    check_commands curl
}

# 获取 nvm 最新版本 tag（含 v）
# 复用 common.sh 的 github_latest_tag（jq 优先 + grep 回退 + 认证）；补回 nvm 的 v 前缀。
nvm_latest() {
    local tag
    tag=$(github_latest_tag "$NVM_REPO")
    [[ -n "$tag" ]] && tag="v$tag"
    echo "$tag"
}

install_nvm() {
    preflight
    info "$(_t '🚀 Installing nvm (the Node version manager)')"

    if [[ -d "$NVM_DIR" ]]; then
        warn "$(_tf 'nvm detected (%s)' "${NVM_DIR}")"
        if ! yes_no "$(_t 'Reinstall/update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
        info "$(_t 'To update nvm, run this after the installation: nvm install-latest-nvm')"
    fi

    local version
    version=$(nvm_latest)
    if [[ -z "$version" ]]; then
        error "$(_t 'Cannot fetch the latest nvm version (check the network or set GH_TOKEN)')"
        exit 1
    fi
    success "$(_tf 'Latest version: %s' "$version")"

    info "$(_t 'Downloading the installation script...')"
    # 使用官方安装脚本（兼容性最好）
    local installer_url="https://raw.githubusercontent.com/${NVM_REPO}/${version}/install.sh"
    if ! curl -fsSL "$installer_url" | bash; then
        error "nvm $(_t 'Installation failed')"
        exit 1
    fi

    success "nvm $(_tf 'The installation is complete in %s' "$NVM_DIR")"

    # 配置 shell 启动文件（官方脚本通常会自动配置，这里确保覆盖）
    ensure_shell_config

    echo
    info "$(_t 'Activate nvm (run one of them):')"
    echo "  source ~/.bashrc   # bash"
    echo "  source ~/.zshrc    # zsh"
    echo
    info "$(_t 'Common commands:')"
    echo "  nvm install --lts   # $(_t 'Install the latest LTS version of Node')"
    echo "  nvm install 20      # $(_t 'Install a specific version')"
    echo "  nvm use 20"
    echo "  nvm ls"
}

ensure_shell_config() {
    local rc_files=("$HOME/.bashrc" "$HOME/.zshrc")
    local profile="$HOME/.profile"
    # block 内容需以字面量写入 rc 文件（$HOME/$NVM_DIR 在 shell 启动时展开），故用单引号（SC2016 误报）
    # shellcheck disable=SC2016
    local block='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'

    local f
    for f in "${rc_files[@]}" "$profile"; do
        if [[ -f "$f" ]] && ! grep -q 'NVM_DIR' "$f" 2>/dev/null; then
            {
                echo ""
                echo "# nvm $(_t 'the configuration (added by unix_script)')"
                echo "$block"
            } >> "$f"
            info "$(_t 'nvm configuration has been added to') $(basename "$f") $(_t 'by unix_script')"
        fi
    done
}

uninstall_nvm() {
    preflight
    if [[ ! -d "$NVM_DIR" ]]; then
        warn "$(_t 'nvm is not installed')"; return 0
    fi
    if ! yes_no "$(_tf 'Confirm uninstalling nvm (it will delete %s)?' "${NVM_DIR}")"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    rm -rf "$NVM_DIR"
    # 清理 shell 配置中的 nvm 行
    local f
    for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$f" ]]; then
            # 删除 NVM_DIR 相关行与注释
            # 只匹配语言无关的标识：rc 里写入的 block 只含 NVM_DIR / nvm.sh / bash_completion。
            # （原来还匹配中文「nvm 配置」—— 那是早期版本写进 rc 的中文注释，现已不再写入；
            #  留着它会让卸载时的 sed 在英文环境下匹配不到，rc 残留。）
            sed -i.bak '/NVM_DIR\|nvm\.sh\|bash_completion/d' "$f" 2>/dev/null || true
        fi
    done
    success "nvm $(_t 'It has been uninstalled (the related lines in the shell configuration have been removed)')"
}

status_nvm() {
    detect_os
    if [[ -d "$NVM_DIR" ]] && [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # 不污染当前 shell，子 shell 加载后取版本
        local ver
        ver=$(bash -c "source '$NVM_DIR/nvm.sh' && nvm --version" 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
        emit_status "installed" "${GREEN}$(_tf '✅ nvm v%s is installed' "${ver}")${NC}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     $(_t 'Install nvm into ~/.nvm and configure bash/zsh/profile')
  uninstall   $(_t 'Uninstall nvm')
  status      $(_t 'View the installation status')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_nvm ;;
        uninstall) uninstall_nvm ;;
        status)    status_nvm ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
