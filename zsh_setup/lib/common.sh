#!/bin/bash
#
# zsh_setup/lib/common.sh
# 公共函数库
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 命令检测
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检测操作系统
detect_os() {
    OS="$(uname -s)"
    if [[ "$OS" == "Linux" ]]; then
        if command_exists apt-get; then
            PKG_MANAGER="apt-get"
        elif command_exists yum; then
            PKG_MANAGER="yum"
        elif command_exists dnf; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="unknown"
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        PKG_MANAGER="brew"
    else
        PKG_MANAGER="unknown"
    fi
}

# 检测当前框架
detect_framework() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "oh-my-zsh"
    elif [ -d "${ZDOTDIR:-$HOME}/.zprezto" ]; then
        echo "prezto"
    elif [ -d "$HOME/.local/share/zinit" ] || [ -d "$HOME/.zinit" ]; then
        echo "zinit"
    elif command_exists sheldon; then
        echo "sheldon"
    else
        echo "none"
    fi
}

# 确认提示
confirm() {
    local message="$1"
    read -r -p "$message (y/N) " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# 配置目录
CONFIG_DIR="${HOME}/.config/zsh_setup"
BACKUP_DIR="${CONFIG_DIR}/backups"
