#!/usr/bin/env bash
#
# ollama/install.sh
#
# 安装 Ollama —— 本地大语言模型运行时（在本地跑 Llama/Qwen 等开源模型）。
# Linux（官方脚本 + systemd）+ macOS（app）。
#
# 子命令：install | pull <模型> | start | stop | status | uninstall | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://ollama.com/install.sh"
SERVICE_NAME="ollama"

preflight() {
    detect_os
    check_commands curl
}

install_ollama() {
    preflight
    info "$(_t '🧠 Installing Ollama (the local large model runtime)')"

    if os_has_cmd ollama; then
        local cur
        cur=$(ollama --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'Ollama detected (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reinstall/update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]]; then
        if os_has_cmd brew; then
            info "$(_t 'Installing ollama via Homebrew...')"
            brew install ollama
        else
            error "macOS $(_t 'Homebrew is required, or download the app from https://ollama.com/download')"
            exit 1
        fi
    else
        # Linux：官方脚本（自动装二进制 + systemd 服务）
        require_sudo
        info "$(_t 'Installing with the official script (including the systemd service)...')"
        if ! curl -fsSL "$OFFICIAL_INSTALLER" | sh; then
            error "$(_t 'The official installation script failed, see https://github.com/ollama/ollama')"
            exit 1
        fi
    fi

    if ! os_has_cmd ollama; then
        error "$(_t 'ollama was not found after the installation, reopen the terminal or check PATH')"
        exit 1
    fi

    success "$(_t '🎉 Ollama installation complete!')"
    echo
    info "$(_t 'Quick start:')"
    echo "  ollama run qwen3:8b        # $(_t 'Download and run a model (the first pull is slow)')"
    echo "  ollama pull llama3.2       # $(_t 'Download the model only')"
    echo "  ollama list                # $(_t 'The model has been downloaded')"
    echo "  ollama serve               # $(_t 'Start the API service (port 11434 by default)')"
    echo
    info "$(_t 'Common models: qwen3:8b / llama3.2 / deepseek-r1 / gemma3')"
    info "$(_t 'Model library: https://ollama.com/library')"
}

# pull <模型>：拉取模型
do_pull() {
    preflight
    local model="${1:-qwen3:8b}"
    info "$(_tf 'Pulling the model: %s' "$model")"
    ollama pull "$model"
    success "$(_tf 'The model %s is ready, run it with ollama run %s' "$model" "$model")"
}

do_status() {
    detect_os
    if ! os_has_cmd ollama; then
        uxs_emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"; return
    fi
    local running=false
    if [[ "$OS_TYPE" == "linux" ]]; then
        uxs_svc is-active "$SERVICE_NAME" 2>/dev/null && running=true
    elif [[ "$OS_TYPE" == "darwin" ]]; then
        pgrep -x ollama >/dev/null 2>&1 && running=true
    fi
    local ver
    # 不用 `| head -1`：head 命中即退会给上游 SIGPIPE(141)；grep 无匹配时退出 1。
    # 两者在 pipefail 下都会让整条管道非 0，set -e 会让 status 子命令整体中止
    # （违反「状态子命令恒 0」契约）。改用 sed 取首行（sed 读完整个输入才退出），
    # 取不到版本号就回落成空值。
    ver=$(ollama --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | sed -n '1p') || ver=""
    if $running; then
        uxs_emit_status "installed:running" "${GREEN}$(_t '✅ Installed and running')${NC}"
    else
        uxs_emit_status "installed:stopped" "${YELLOW}$(_t '⚠️  Installed but the service is not running')${NC}"
    fi
    # 收尾用 if 而不是 `[[ -n "$ver" ]] && ...`：后者在版本号为空时返回 1，
    # 会让 status 子命令整体退出 1（同样是「status 恒 0」契约）。
    if [[ -n "$ver" ]]; then
        uxs_emit_version "$ver"
    fi
    return 0
}

uninstall_ollama() {
    preflight
    if [[ "$OS_TYPE" == "darwin" ]]; then
        os_has_cmd brew && brew uninstall ollama 2>/dev/null
        success "$(_t 'ollama has been uninstalled (macOS)')"
        return 0
    fi
    require_sudo
    if ! yes_no "$(_t 'Uninstall Ollama?')"; then
        info "$(_t 'Cancelled')"; return 0
    fi
    uxs_svc stop "$SERVICE_NAME" 2>/dev/null || true
    uxs_svc disable "$SERVICE_NAME" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service" /usr/local/bin/ollama
    uxs_svc daemon-reload 2>/dev/null || true
    if yes_no "$(_t 'Delete all the downloaded models (~/.ollama, it may be large)?')"; then
        sudo rm -rf ~/.ollama /usr/share/ollama/.ollama 2>/dev/null || true
        success "$(_t 'The model data has been deleted')"
    fi
    success "Ollama $(_t 'Uninstalled')"
}

usage() {
    cat <<EOF
用法: $0 {install|pull|status|uninstall|help}

  install         $(_t 'Install Ollama (the local large model runtime)')
  pull <$(_t 'model>     pull a model (qwen3:8b by default)')
  status          $(_t 'View the status')
  uninstall       $(_t 'Uninstall (optionally delete the downloaded models)')

$(_t 'Examples:')
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
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
