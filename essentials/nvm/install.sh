#!/usr/bin/env bash
#
# nvm/install.sh
#
# 安装 nvm（Node Version Manager）—— Node.js 多版本管理工具。
# Linux + macOS。安装到 ~/.nvm，并配置 shell 启动文件。
#
# 子命令：install | uninstall | status | help
#

set -e

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
nvm_latest() {
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local auth=()
    if [[ -n "$token" ]]; then auth=(-H "Authorization: Bearer $token"); fi
    curl -fsSL "${auth[@]}" "https://api.github.com/repos/${NVM_REPO}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

install_nvm() {
    preflight
    info "🚀 安装 nvm（Node 版本管理）"

    if [[ -d "$NVM_DIR" ]]; then
        warn "检测到已安装 nvm（$NVM_DIR）"
        if ! yes_no "是否重新安装/更新？"; then
            info "已取消"; return 0
        fi
        info "如需更新 nvm，安装后执行：nvm install-latest-nvm"
    fi

    local version
    version=$(nvm_latest)
    if [[ -z "$version" ]]; then
        error "无法获取 nvm 最新版本（请检查网络或设置 GH_TOKEN）"
        exit 1
    fi
    success "最新版本：$version"

    info "下载安装脚本..."
    # 使用官方安装脚本（兼容性最好）
    local installer_url="https://raw.githubusercontent.com/${NVM_REPO}/${version}/install.sh"
    if ! curl -fsSL "$installer_url" | bash; then
        error "nvm 安装失败"
        exit 1
    fi

    success "nvm 安装完成到 $NVM_DIR"

    # 配置 shell 启动文件（官方脚本通常会自动配置，这里确保覆盖）
    ensure_shell_config

    echo
    info "激活 nvm（执行其一）："
    echo "  source ~/.bashrc   # bash"
    echo "  source ~/.zshrc    # zsh"
    echo
    info "常用命令："
    echo "  nvm install --lts   # 安装最新 LTS 版 Node"
    echo "  nvm install 20      # 安装指定版本"
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
                echo "# nvm 配置（由 unix_script 添加）"
                echo "$block"
            } >> "$f"
            info "已为 $(basename "$f") 添加 nvm 配置"
        fi
    done
}

uninstall_nvm() {
    preflight
    if [[ ! -d "$NVM_DIR" ]]; then
        warn "未安装 nvm"; return 0
    fi
    if ! yes_no "确认卸载 nvm（将删除 $NVM_DIR）？"; then
        info "已取消"; return 0
    fi
    rm -rf "$NVM_DIR"
    # 清理 shell 配置中的 nvm 行
    local f
    for f in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [[ -f "$f" ]]; then
            # 删除 NVM_DIR 相关行与注释
            sed -i.bak '/NVM_DIR\|nvm.sh\|nvm 配置/d' "$f" 2>/dev/null || true
        fi
    done
    success "nvm 已卸载（shell 配置中的相关行已移除）"
}

status_nvm() {
    detect_os
    if [[ -d "$NVM_DIR" ]] && [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # 不污染当前 shell，子 shell 加载后取版本
        local ver
        ver=$(bash -c "source '$NVM_DIR/nvm.sh' && nvm --version" 2>/dev/null || echo "未知")
        echo -e "${GREEN}✅ 已安装 nvm v${ver}${NC}"
    else
        echo -e "${RED}❌ 未安装${NC}"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help}

  install     安装 nvm 到 ~/.nvm 并配置 bash/zsh/profile
  uninstall   卸载 nvm
  status      查看安装状态
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
