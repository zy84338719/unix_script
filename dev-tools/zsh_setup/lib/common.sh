#!/bin/bash
#
# zsh_setup/lib/common.sh
# zsh-setup 模块公共函数库
#
# 复用项目根目录的 lib/common.sh，仅补充 zsh-setup 专用定义。
#

# ---- 幂等保护 ----
if [[ -n "${_ZSH_SETUP_COMMON_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_ZSH_SETUP_COMMON_LOADED=1

# ---- 定位本文件所在目录 ----
ZSH_SETUP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 加载项目公共库 ----
# shellcheck source=../../../lib/common.sh
source "${ZSH_SETUP_LIB_DIR}/../../../lib/common.sh"

# ---- JSON 安全转义 ----
# 将字符串转义为可安全嵌入 JSON 字符串的值（不包含外层引号）。
# 处理：反斜杠、双引号、换行符。
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"     # escape backslashes
    s="${s//\"/\\\"}"     # escape double quotes
    s="${s//$'\n'/\\n}"   # escape newlines
    printf '%s' "$s"
}

# ---- zsh-setup 专用：检测当前 zsh 框架 ----
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

# ---- zsh-setup 专用：配置目录 ----
CONFIG_DIR="${HOME}/.config/zsh_setup"
BACKUP_DIR="${CONFIG_DIR}/backups"
