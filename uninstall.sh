#!/usr/bin/env bash
#
# uninstall.sh
#
# 一键卸载入口：委托各模块的 install.sh uninstall 执行卸载。
#
# 用法:
#   ./uninstall.sh             # 交互式逐项询问
#   ./uninstall.sh --all       # 卸载全部（需二次确认）
#   ./uninstall.sh <模块名>    # 仅卸载指定模块（同 install.sh 的模块名）
#   ./uninstall.sh -h          # 帮助
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# 在子 shell 中执行某目录下的脚本（避免 cd 污染当前工作目录）
run_in_dir() {
    local dir="$1"; shift
    ( cd "$SCRIPT_DIR/$dir" && bash "$@" )
}

# 卸载单个模块（封装确认）
ask_and_uninstall() {
    local label="$1"; shift
    if yes_no "确认卸载 $label？"; then
        info "卸载 $label ..."
        "$@"
        success "$label 卸载流程结束。"
    else
        info "跳过 $label"
    fi
    echo
}

# --- 各模块卸载委托 ---
uninstall_node_exporter_mod() { run_in_dir node_exporter install.sh uninstall; }
uninstall_ddns_mod()          { run_in_dir ddns-go install.sh uninstall; }
uninstall_wireguard_mod()     { run_in_dir wireguard install.sh uninstall; }
uninstall_tailscale_mod()     { run_in_dir tailscale install.sh uninstall; }
uninstall_docker_mod()        { run_in_dir docker install.sh uninstall; }
uninstall_fail2ban_mod()      { run_in_dir fail2ban install.sh uninstall; }
uninstall_openlist_mod()      { run_in_dir openlist install.sh uninstall; }
uninstall_uptime_kuma_mod()   { run_in_dir uptime-kuma install.sh uninstall; }
uninstall_cockpit_mod()       { run_in_dir cockpit install.sh uninstall; }
uninstall_zsh_mod()           { run_in_dir zsh_setup install.sh uninstall; }
uninstall_minikube_mod()      { run_in_dir minikube install.sh uninstall; }
uninstall_dev_tui_mod()       { run_in_dir dev-tui install.sh uninstall; }
uninstall_deskflow_mod()      { run_in_dir deskflow install.sh uninstall; }
uninstall_bbr_mod()           { run_in_dir bbr install.sh disable; }
uninstall_swap_mod()          { run_in_dir swap install.sh uninstall; }
uninstall_nvm_mod()           { run_in_dir nvm install.sh uninstall; }
uninstall_safe_rm_mod()       { run_in_dir safe-rm install.sh uninstall; }
uninstall_clash_mod()         { run_in_dir clash install.sh uninstall; }
uninstall_multinet_mod()      { run_in_dir multi-net install.sh clear; }
uninstall_opencode_mod()      { run_in_dir opencode install.sh uninstall; }
uninstall_ollama_mod()        { run_in_dir ollama install.sh uninstall; }
uninstall_bun_mod()           { run_in_dir bun install.sh uninstall; }
uninstall_pi_mod()            { run_in_dir pi install.sh uninstall; }
uninstall_deno_mod()          { run_in_dir deno install.sh uninstall; }
uninstall_pnpm_mod()          { run_in_dir pnpm install.sh uninstall; }
uninstall_go_mod()            { run_in_dir go install.sh uninstall; }
uninstall_rust_mod()          { run_in_dir rust install.sh uninstall; }
uninstall_dev_mirror_mod()    { run_in_dir dev-mirror install.sh uninstall all <<< "y"; }
uninstall_docker_image_mod()  { run_in_dir docker-image install.sh uninstall; }
uninstall_essential_mod()     { run_in_dir essential-pkgs install.sh uninstall; }
uninstall_dev_enhance_mod()   { run_in_dir dev-enhance install.sh uninstall; }
uninstall_modern_cli_mod()    { run_in_dir modern-cli install.sh uninstall; }
uninstall_sys_cmd_mod()       { run_in_dir sys-cmd install.sh uninstall; }
uninstall_upftp_mod()         { run_in_dir upftp install.sh uninstall; }
uninstall_pm_mod()            { run_in_dir process_manager_tool install_process_manager.sh uninstall; }

uninstall_shutdown_mod() {
    local sp="$SCRIPT_DIR/shutdown_timer/shutdown_timer.sh"
    if [ -f "$sp" ]; then
        chmod +x "$sp"
        "$sp" cancel_daily_shutdown_internal
    fi
}

# --- 卸载全部 ---
uninstall_all() {
    warn "⚠️  即将卸载所有已安装的服务与环境！此操作不可逆。"
    if ! yes_no "再次确认卸载全部？"; then
        info "已取消"
        exit 0
    fi
    uninstall_node_exporter_mod
    uninstall_ddns_mod
    uninstall_wireguard_mod
    uninstall_tailscale_mod
    uninstall_docker_mod
    uninstall_fail2ban_mod
    uninstall_openlist_mod
    uninstall_uptime_kuma_mod
    uninstall_cockpit_mod
    uninstall_zsh_mod
    uninstall_minikube_mod
    uninstall_dev_tui_mod
    uninstall_shutdown_mod
    uninstall_pm_mod
    uninstall_deskflow_mod
    uninstall_bbr_mod
    uninstall_swap_mod
    uninstall_nvm_mod
    uninstall_safe_rm_mod
    uninstall_clash_mod
    uninstall_multinet_mod
    uninstall_docker_image_mod
    uninstall_essential_mod
    uninstall_dev_enhance_mod
    uninstall_modern_cli_mod
    uninstall_sys_cmd_mod
    uninstall_upftp_mod
    uninstall_opencode_mod
    uninstall_ollama_mod
    uninstall_bun_mod
    uninstall_pi_mod
    uninstall_deno_mod
    uninstall_pnpm_mod
    uninstall_go_mod
    uninstall_rust_mod
    uninstall_dev_mirror_mod
    echo
    success "全部卸载流程结束。"
}

show_usage() {
    cat <<EOF
用法: $0 [选项] [模块名]

选项:
  -h, --help    显示本帮助
  --all         卸载全部已安装项（需二次确认）

模块名:
  node_exporter | ddns-go | wireguard | tailscale | docker |
  fail2ban | openlist | uptime-kuma | cockpit | docker-image |
  essential-pkgs | zsh | minikube | dev-tui | bun | deno | pnpm |
  go | rust | dev-mirror | dev-enhance | modern-cli |
  opencode | ollama | pi |
  deskflow | bbr | swap | nvm | safe-rm | clash | multi-net |
  sys-cmd | upftp | shutdown_timer | process_manager

示例:
  $0                  # 逐项交互询问
  $0 docker           # 仅卸载 docker
  $0 --all            # 卸载全部
EOF
}

dispatch() {
    local name="$1"
    case "$name" in
        node_exporter|nodeexporter) ask_and_uninstall "Node Exporter" uninstall_node_exporter_mod ;;
        ddns-go|ddnsgo|ddns)        ask_and_uninstall "DDNS-GO"       uninstall_ddns_mod ;;
        wireguard|wg)               ask_and_uninstall "WireGuard"     uninstall_wireguard_mod ;;
        tailscale|ts)               ask_and_uninstall "Tailscale"     uninstall_tailscale_mod ;;
        docker)                     ask_and_uninstall "Docker"        uninstall_docker_mod ;;
        fail2ban|f2b)               ask_and_uninstall "Fail2ban"      uninstall_fail2ban_mod ;;
        openlist)                    ask_and_uninstall "OpenList"      uninstall_openlist_mod ;;
        uptime-kuma|uptime_kuma)    ask_and_uninstall "Uptime Kuma"   uninstall_uptime_kuma_mod ;;
        cockpit)                    ask_and_uninstall "Cockpit"       uninstall_cockpit_mod ;;
        zsh)                        ask_and_uninstall "Zsh"           uninstall_zsh_mod ;;
        minikube)                   ask_and_uninstall "minikube"      uninstall_minikube_mod ;;
        dev-tui|dev_tui|tui)        ask_and_uninstall "终端 TUI"      uninstall_dev_tui_mod ;;
        shutdown|shutdown_timer)    uninstall_shutdown_mod ;;
        process_manager|pm)         ask_and_uninstall "进程管理工具"  uninstall_pm_mod ;;
        deskflow)                   ask_and_uninstall "Deskflow"      uninstall_deskflow_mod ;;
        bbr)                        ask_and_uninstall "BBR"           uninstall_bbr_mod ;;
        swap)                       ask_and_uninstall "Swap"          uninstall_swap_mod ;;
        nvm)                        ask_and_uninstall "nvm"           uninstall_nvm_mod ;;
        safe-rm|safe_rm)            ask_and_uninstall "safe-rm"       uninstall_safe_rm_mod ;;
        clash|mihomo)               ask_and_uninstall "Clash"         uninstall_clash_mod ;;
        multi-net|multinet)         ask_and_uninstall "多网卡路由"    uninstall_multinet_mod ;;
        opencode)                   ask_and_uninstall "OpenCode"      uninstall_opencode_mod ;;
        ollama)                     ask_and_uninstall "Ollama"        uninstall_ollama_mod ;;
        bun)                        ask_and_uninstall "Bun"           uninstall_bun_mod ;;
        pi)                         ask_and_uninstall "Pi"            uninstall_pi_mod ;;
        deno)                       ask_and_uninstall "Deno"          uninstall_deno_mod ;;
        pnpm)                       ask_and_uninstall "pnpm"          uninstall_pnpm_mod ;;
        go|golang)                  ask_and_uninstall "Go"            uninstall_go_mod ;;
        rust|rustup)                ask_and_uninstall "Rust"          uninstall_rust_mod ;;
        dev-mirror|dev_mirror)      ask_and_uninstall "dev-mirror"    uninstall_dev_mirror_mod ;;
        docker-image|docker_image)  ask_and_uninstall "Docker 镜像导出" uninstall_docker_image_mod ;;
        essential-pkgs|essential)   ask_and_uninstall "装机必备"      uninstall_essential_mod ;;
        dev-enhance)                ask_and_uninstall "开发工具增强"  uninstall_dev_enhance_mod ;;
        modern-cli|modern_cli)      ask_and_uninstall "现代 CLI"      uninstall_modern_cli_mod ;;
        sys-cmd|sys_cmd)            ask_and_uninstall "系统诊断命令"  uninstall_sys_cmd_mod ;;
        upftp)                      ask_and_uninstall "upftp"         uninstall_upftp_mod ;;
        *) error "未知模块: $name"; show_usage; exit 1 ;;
    esac
}

# 交互式逐项询问（按分类展示）
interactive_all() {
    detect_os
    header "🗑️  一键卸载（逐项询问）"
    echo "========================================"
    echo

    echo "--- 服务 ---"
    ask_and_uninstall "Node Exporter" uninstall_node_exporter_mod
    ask_and_uninstall "DDNS-GO"       uninstall_ddns_mod
    ask_and_uninstall "WireGuard"     uninstall_wireguard_mod
    ask_and_uninstall "Tailscale"     uninstall_tailscale_mod
    ask_and_uninstall "Docker"        uninstall_docker_mod
    ask_and_uninstall "Fail2ban"      uninstall_fail2ban_mod
    ask_and_uninstall "OpenList"      uninstall_openlist_mod
    ask_and_uninstall "Uptime Kuma"   uninstall_uptime_kuma_mod
    ask_and_uninstall "Cockpit"       uninstall_cockpit_mod
    ask_and_uninstall "Docker 镜像导出" uninstall_docker_image_mod

    echo "--- 开发环境 ---"
    ask_and_uninstall "Zsh"           uninstall_zsh_mod
    ask_and_uninstall "minikube"      uninstall_minikube_mod
    ask_and_uninstall "终端 TUI"      uninstall_dev_tui_mod
    ask_and_uninstall "Bun"           uninstall_bun_mod
    ask_and_uninstall "Deno"          uninstall_deno_mod
    ask_and_uninstall "pnpm"          uninstall_pnpm_mod
    ask_and_uninstall "Go"            uninstall_go_mod
    ask_and_uninstall "Rust"          uninstall_rust_mod
    ask_and_uninstall "dev-mirror"    uninstall_dev_mirror_mod
    ask_and_uninstall "开发工具增强"  uninstall_dev_enhance_mod
    ask_and_uninstall "现代 CLI"      uninstall_modern_cli_mod

    echo "--- AI 工具 ---"
    ask_and_uninstall "OpenCode"      uninstall_opencode_mod
    ask_and_uninstall "Ollama"        uninstall_ollama_mod
    ask_and_uninstall "Pi"            uninstall_pi_mod

    echo "--- 系统工具 ---"
    ask_and_uninstall "Deskflow"      uninstall_deskflow_mod
    ask_and_uninstall "BBR"           uninstall_bbr_mod
    ask_and_uninstall "Swap"          uninstall_swap_mod
    ask_and_uninstall "nvm"           uninstall_nvm_mod
    ask_and_uninstall "safe-rm"       uninstall_safe_rm_mod
    ask_and_uninstall "Clash"         uninstall_clash_mod
    ask_and_uninstall "多网卡路由"    uninstall_multinet_mod
    ask_and_uninstall "系统诊断命令"  uninstall_sys_cmd_mod
    ask_and_uninstall "upftp"         uninstall_upftp_mod
    uninstall_shutdown_mod
    ask_and_uninstall "进程管理工具"  uninstall_pm_mod

    echo
    success "卸载流程结束。"
}

main() {
    detect_os
    if [[ $# -eq 0 ]]; then
        interactive_all
        exit 0
    fi
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        --all)     uninstall_all ;;
        -*) error "未知选项: $1"; show_usage; exit 1 ;;
        *)         dispatch "$1" ;;
    esac
}

main "$@"
