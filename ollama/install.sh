#!/usr/bin/env bash
#
# ollama/install.sh
#
# 安装 Ollama —— 本地大语言模型运行时（在本地跑 Llama/Qwen 等开源模型）。
# Linux（官方脚本 + systemd）+ macOS（app）。
#
# 子命令：install | pull <模型> | start | stop | status | uninstall | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OFFICIAL_INSTALLER="https://ollama.com/install.sh"
SERVICE_NAME="ollama"

preflight() {
    detect_os
    check_commands curl
}

install_ollama() {
    preflight
    info "🧠 安装 Ollama（本地大模型运行时）"

    if command_exists ollama; then
        local cur
        cur=$(ollama --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 Ollama（$cur）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if command_exists brew; then
            info "通过 Homebrew 安装 ollama..."
            brew install ollama
        else
            error "macOS 需要 Homebrew，或从 https://ollama.com/download 下载 app"
            exit 1
        fi
    else
        # Linux：官方脚本（自动装二进制 + systemd 服务）
        require_sudo
        info "通过官方脚本安装（含 systemd 服务）..."
        if ! curl -fsSL "$OFFICIAL_INSTALLER" | sh; then
            error "官方安装脚本执行失败，请参考 https://github.com/ollama/ollama"
            exit 1
        fi
    fi

    if ! command_exists ollama; then
        error "安装后仍找不到 ollama，请重新打开终端或检查 PATH"
        exit 1
    fi

    success "🎉 Ollama 安装完成！"
    echo
    info "快速开始："
    echo "  ollama run qwen3:8b        # 下载并运行模型（首次拉取较慢）"
    echo "  ollama pull llama3.2       # 仅下载模型"
    echo "  ollama list                # 已下载模型"
    echo "  ollama serve               # 启动 API 服务（默认 11434 端口）"
    echo
    info "常用模型：qwen3:8b / llama3.2 / deepseek-r1 / gemma3"
    info "模型库：https://ollama.com/library"
}

# pull <模型>：拉取模型
do_pull() {
    preflight
    local model="${1:-qwen3:8b}"
    info "拉取模型：$model"
    ollama pull "$model"
    success "模型 $model 已就绪，用 'ollama run $model' 启动"
}

do_status() {
    detect_os
    if ! command_exists ollama; then
        echo -e "${RED}❌ 未安装${NC}"; return
    fi
    local running=false
    if [[ "$OS_TYPE" == "linux" ]]; then
        systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null && running=true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        pgrep -x ollama >/dev/null 2>&1 && running=true
    fi
    if $running; then
        echo -e "${GREEN}✅ 已安装并运行${NC}"
    else
        echo -e "${YELLOW}⚠️  已安装但服务未运行${NC}"
    fi
}

uninstall_ollama() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        command_exists brew && brew uninstall ollama 2>/dev/null
        success "已卸载 ollama（macOS）"
        return 0
    fi
    require_sudo
    if ! yes_no "确认卸载 Ollama？"; then
        info "已取消"; return 0
    fi
    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service" /usr/local/bin/ollama
    sudo systemctl daemon-reload 2>/dev/null || true
    if yes_no "是否删除所有已下载模型（~/.ollama，可能很大）？"; then
        sudo rm -rf ~/.ollama /usr/share/ollama/.ollama 2>/dev/null || true
        success "模型数据已删除"
    fi
    success "Ollama 已卸载"
}

usage() {
    cat <<EOF
用法: $0 {install|pull|status|uninstall|help}

  install         安装 Ollama（本地大模型运行时）
  pull <模型>     拉取模型（默认 qwen3:8b）
  status          查看状态
  uninstall       卸载（可选删除已下载模型）

示例:
  $0 install
  $0 pull deepseek-r1
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_ollama ;;
        pull)      shift; do_pull "$@" ;;
        status)    do_status ;;
        uninstall) uninstall_ollama ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
