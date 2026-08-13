#!/usr/bin/env bash
# unix_script / uxs Bash 自动补全
# 用法：source completions/uxs.bash
# 或复制到 /etc/bash_completion.d/uxs

_uxs_completions() {
    local cur prev modules
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # 第一个参数：模块名 + 全局选项
    if [[ $COMP_CWORD -eq 1 ]]; then
        modules="bbr brew bun clash cockpit ddns-go deno deskflow dev-enhance dev-mirror dev-tui docker docker-image essential-pkgs fail2ban go grafana gitea k7s minikube modern-cli multi-net nginx node_exporter nvm ollama opencode openlist pi pnpm postgres prometheus process_manager_tool redis restic caddy rust safe-rm shutdown_timer swap sys-cmd sys-setup tailscale ufw upftp uptime-kuma wireguard zsh_setup"
        local globals="--status --status-json --list --list-modules --list-categories --version --help update cli doctor scaffold export apply"
        COMPREPLY=( $(compgen -W "$modules $globals" -- "$cur") )
        return 0
    fi

    # 第二个参数：子命令（根据模块动态补全）
    if [[ $COMP_CWORD -eq 2 ]]; then
        local mod="${COMP_WORDS[1]}"
        local subcmds=""
        case "$mod" in
            bbr)              subcmds="enable disable status help" ;;
            brew)             subcmds="install uninstall mirror unmirror status help" ;;
            bun)              subcmds="install mirror unmirror uninstall status help" ;;
            clash)            subcmds="config example install restart start status stop tun-off tun-on uninstall" ;;
            cockpit)          subcmds="install uninstall status help" ;;
            ddns-go)          subcmds="install uninstall status help" ;;
            deno)             subcmds="install uninstall status help" ;;
            deskflow)         subcmds="install uninstall status help" ;;
            dev-enhance)      subcmds="install uninstall status help" ;;
            dev-mirror)       subcmds="install status uninstall" ;;
            dev-tui)          subcmds="install uninstall status help" ;;
            docker)           subcmds="install mirror registry uninstall status help" ;;
            docker-image)     subcmds="save status help" ;;
            essential-pkgs)   subcmds="install uninstall status help" ;;
            fail2ban)         subcmds="install uninstall status help" ;;
            go)               subcmds="install uninstall status help" ;;
            grafana)          subcmds="install uninstall status help" ;;
            gitea)            subcmds="install uninstall status help" ;;
            k7s)              subcmds="install uninstall status help" ;;
            minikube)         subcmds="install uninstall status help" ;;
            modern-cli)       subcmds="install uninstall status help" ;;
            multi-net)        subcmds="clear list route-port route-user setup status" ;;
            nginx)            subcmds="install uninstall status help" ;;
            node_exporter)    subcmds="install uninstall status help" ;;
            nvm)              subcmds="install uninstall status help" ;;
            ollama)           subcmds="install pull status uninstall help" ;;
            opencode)         subcmds="install uninstall status help" ;;
            openlist)         subcmds="install uninstall status help" ;;
            pi)               subcmds="install uninstall status help" ;;
            pnpm)             subcmds="install uninstall status help" ;;
            postgres)         subcmds="install uninstall status help" ;;
            prometheus)       subcmds="install uninstall status help" ;;
            process_manager_tool) subcmds="install uninstall status help" ;;
            redis)            subcmds="install uninstall status help" ;;
            restic)           subcmds="install uninstall status help" ;;
            caddy)            subcmds="install uninstall status help" ;;
            rust)             subcmds="install uninstall status help" ;;
            safe-rm)          subcmds="install on off status uninstall help" ;;
            shutdown_timer)   subcmds="status" ;;
            swap)             subcmds="install uninstall status help" ;;
            sys-cmd)          subcmds="all status" ;;
            sys-setup)        subcmds="mirror timezone ntp optimize ssh autoupdate all status help" ;;
            tailscale)        subcmds="install uninstall status" ;;
            ufw)              subcmds="install uninstall status help" ;;
            upftp)            subcmds="install uninstall status help" ;;
            uptime-kuma)      subcmds="install uninstall status help" ;;
            wireguard)        subcmds="install uninstall status help" ;;
            zsh_setup)        subcmds="install uninstall status help" ;;
        esac
        COMPREPLY=( $(compgen -W "$subcmds" -- "$cur") )
        return 0
    fi
}

complete -F _uxs_completions uxs
complete -F _uxs_completions ./install.sh
