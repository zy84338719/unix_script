#!/usr/bin/env bash
#
# NVM (Node Version Manager) 安装脚本 - macOS 平台
#
# 通过官方安装脚本安装 NVM，并配置 Node.js LTS

set -euo pipefail

# 导入通用工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common/colors.sh"
source "${SCRIPT_DIR}/../../common/utils.sh"

# 配置变量
NVM_VERSION="${NVM_VERSION:-v0.39.7}"  # NVM 版本
NODE_LTS_VERSION="${NODE_LTS_VERSION:-lts}"  # Node.js 版本
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
PROFILE_FILE=""

show_info() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  NVM (Node Version Manager) 安装脚本  ${NC}"
    echo -e "${BLUE}            macOS 平台              ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}NVM 版本:${NC} ${NVM_VERSION}"
    echo -e "${YELLOW}Node.js 版本:${NC} ${NODE_LTS_VERSION}"
    echo ""
}

detect_shell_profile() {
    local sh
    sh=$(basename "${SHELL}")
    case "$sh" in
        zsh) PROFILE_FILE="$HOME/.zshrc" ;; 
        bash) PROFILE_FILE="$HOME/.bash_profile" ;; 
        *) PROFILE_FILE="$HOME/.profile" ;; 
    esac
    [[ -f "$PROFILE_FILE" ]] || touch "$PROFILE_FILE"
    echo -e "${GREEN}[SUCCESS]${NC} 将使用配置文件: $PROFILE_FILE"
}

install_nvm() {
    echo -e "${BLUE}[INFO]${NC} 安装 NVM ${NVM_VERSION}..."
    local url="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
    if command_exists curl; then
        curl -fsSL "$url" | bash
    elif command_exists wget; then
        wget -qO- "$url" | bash
    else
        echo -e "${RED}[ERROR]${NC} 缺少 curl 或 wget，请先安装"
        exit 1
    fi
    echo -e "${GREEN}[SUCCESS]${NC} NVM 安装脚本执行完成"
}

configure_environment() {
    echo -e "${BLUE}[INFO]${NC} 配置 NVM 环境变量..."
    local conf="\n# NVM 配置\nexport NVM_DIR=\"$HOME/.nvm\"\n[ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"\n[ -s \"$NVM_DIR/bash_completion\" ] && . \"$NVM_DIR/bash_completion\""
    if ! grep -q "NVM_DIR" "$PROFILE_FILE"; then
        printf "%b" "$conf" >> "$PROFILE_FILE"
        echo -e "${GREEN}[SUCCESS]${NC} 已添加环境变量到 $PROFILE_FILE"
    else
        echo -e "${YELLOW}[INFO]${NC} 环境变量已存在，跳过"
    fi
}

install_nodejs() {
    echo -e "${BLUE}[INFO]${NC} 安装 Node.js ${NODE_LTS_VERSION}..."
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install "$NODE_LTS_VERSION"
    nvm alias default "$NODE_LTS_VERSION"
    echo -e "${GREEN}[SUCCESS]${NC} Node.js 安装完成: $(node --version)"
}

show_usage() {
    echo -e "${BLUE}安装完成!${NC} 重新打开终端或运行: source $PROFILE_FILE"
}

main() {
    show_info
    if ! confirm "是否继续安装 NVM？" "y"; then
        echo -e "${YELLOW}[INFO]${NC} 已取消"
        exit 0
    fi
    detect_shell_profile
    install_nvm
    configure_environment
    install_nodejs
    show_usage
}

main "$@"
