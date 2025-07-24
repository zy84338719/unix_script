#!/usr/bin/env bash
#
# UV 安装脚本 - macOS 平台
#
# 通过 Astral 官方安装脚本安装 UV 工具

set -euo pipefail

# 导入通用工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common/colors.sh"
source "${SCRIPT_DIR}/../../common/utils.sh"

URL="https://astral.sh/uv/install.sh"

# 安装 UV
install_uv() {
    echo -e "${BLUE}[INFO]${NC} 开始安装 UV..."
    
    # 使用 curl 或 wget
    if command_exists curl; then
        echo -e "${BLUE}[INFO]${NC} 使用 curl 下载并安装 UV"
        if curl -LsSf "$URL" | sh; then
            echo -e "${GREEN}[SUCCESS]${NC} UV 安装完成"
        else
            echo -e "${RED}[ERROR]${NC} UV 安装失败"
            exit 1
        fi
    elif command_exists wget; then
        echo -e "${BLUE}[INFO]${NC} 使用 wget 下载并安装 UV"
        if wget -qO- "$URL" | sh; then
            echo -e "${GREEN}[SUCCESS]${NC} UV 安装完成"
        else
            echo -e "${RED}[ERROR]${NC} UV 安装失败"
            exit 1
        fi
    else
        echo -e "${RED}[ERROR]${NC} 未检测到 curl 或 wget，请先安装依赖"
        exit 1
    fi
}

# 主入口
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}          UV 安装脚本（macOS）        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    if ! confirm "是否继续安装 UV？" "y"; then
        echo -e "${YELLOW}[INFO]${NC} 安装已取消"
        exit 0
    fi
    
    install_uv
}

main "$@"
