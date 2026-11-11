#!/usr/bin/env bash
#
# harbor/install.sh
#
# 安装 Harbor —— 自托管 Docker 镜像仓库（CNCF 毕业项目，offline installer）。
# 仅 Linux（PLATFORMS=linux）；运行依赖 docker + compose 插件（框架自动先装 docker）。
#
# 用法: $0 {install|uninstall|status|help}
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

REPO="goharbor/harbor"
HARBOR_DIR="/opt/harbor"

preflight() {
    detect_os
    detect_arch
    check_commands curl tar
    if ! command_exists docker; then
        error "Harbor $(_t 'The docker runtime is required, run this first: ./install.sh docker')"
        exit 1
    fi
}

# 本机主 IP（配置 hostname 用）
primary_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

gen_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

do_install() {
    preflight
    if [[ -d "$HARBOR_DIR" ]]; then
        yes_no "$(_tf '%s detected (Harbor may already be installed), reinstall?' "${HARBOR_DIR}")" || { info "$(_t 'Cancelled')"; exit 0; }
    fi
    info "$(_t 'Fetching the latest Harbor version (GitHub API)...')"
    local ver
    ver=$(github_latest_tag "$REPO")
    [[ -n "$ver" ]] || { error "$(_t 'Cannot fetch the version (GitHub is unreachable or rate limited), set GH_TOKEN and retry')"; exit 1; }
    local url="https://github.com/${REPO}/releases/download/v${ver}/harbor-offline-installer-v${ver}.tgz"
    warn "Harbor $(_t 'The offline installer is about 600MB+, the download time depends on the network')"
    info "$(_tf 'Downloading %s ...' "$url")"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    curl -fSL "$url" -o "$tmpdir/harbor.tgz" || { error "$(_t 'Download failed (GitHub large files are slow, you can retry)')"; exit 1; }
    info "$(_tf 'Extracting to %s ...' "$HARBOR_DIR")"
    sudo mkdir -p "$HARBOR_DIR"
    sudo tar -xzf "$tmpdir/harbor.tgz" -C "$(dirname "$HARBOR_DIR")"

    # 生成 harbor.yml：hostname 取本机主 IP，http 80；密码交互输入、非 TTY 随机生成
    local admin_pwd
    if [[ -t 0 ]]; then
        read -r -p "$(_t 'Set the Harbor admin password (press Enter to generate a random one):') " admin_pwd || true
    fi
    [[ -n "${admin_pwd:-}" ]] || admin_pwd=$(gen_password)
    local ip
    ip=$(primary_ip)
    [[ -n "$ip" ]] || ip="reg.example.com"
    sudo cp "$HARBOR_DIR/harbor.yml.tmpl" "$HARBOR_DIR/harbor.yml"
    sudo sed -i "s/^hostname: .*/hostname: $ip/" "$HARBOR_DIR/harbor.yml"
    sudo sed -i "s/^harbor_admin_password: .*/harbor_admin_password: $admin_pwd/" "$HARBOR_DIR/harbor.yml"
    # 默认注释 https 段会校验失败？模板 http/https 均含——关掉 https 以便纯内网 http 可用
    sudo sed -i 's/^https:/#https:/; s/^  port: 443/#  port: 443/; s/^  certificate: .#/#  certificate:/; s/^  private_key: .#/#  private_key:/' "$HARBOR_DIR/harbor.yml" || true

    info "$(_t 'Running the official install orchestration (prepare and compose up, it takes several minutes)...')"
    (cd "$HARBOR_DIR" && sudo ./install.sh) || { error "Harbor $(_tf 'The orchestrated install failed, check %s for the details' "$HARBOR_DIR")"; exit 1; }
    echo
    success "Harbor v$ver $(_tf 'Installation complete: http://%s' "$ip")"
    warn "admin $(_tf 'Password: %s (store it safely, it is shown only once)' "${admin_pwd}")"
    info "Docker $(_t 'A client using this registry needs insecure-registries (for plain http), see the README')"
}

do_uninstall() {
    preflight
    if [[ ! -d "$HARBOR_DIR" ]]; then
        warn "Harbor $(_tf 'Not installed (%s not found)' "${HARBOR_DIR}")"
        exit 0
    fi
    yes_no "$(_t 'Confirm uninstall of Harbor (stop and remove all the containers)?')" || { info "$(_t 'Cancelled')"; exit 0; }
    (cd "$HARBOR_DIR" && sudo docker compose down 2>/dev/null) \
        || (cd "$HARBOR_DIR" && sudo docker-compose down 2>/dev/null) \
        || warn "compose down $(_tf 'failed, run it manually in %s' "$HARBOR_DIR")"
    sudo rm -rf "$HARBOR_DIR"
    success "Harbor $(_t 'Uninstalled')"
    if [[ -d /data ]]; then
        if yes_no "$(_t 'Delete the Harbor data directory /data (images/database/certificates, irreversible)?')"; then
            sudo rm -rf /data/harbor 2>/dev/null || sudo rm -rf /data && success "$(_t 'Data deleted')"
        else
            info "$(_t 'Keeping the data')"
        fi
    fi
}

do_status() {
    # status 可能独立于 install 调用，先补平台变量（其他子命令走 preflight）
    detect_os
    if [[ ! -d "$HARBOR_DIR" ]]; then
        emit_status "not_installed" "$(_t '❌ Harbor not installed')"
        return 0
    fi
    if sudo docker ps --format '{{.Image}}' 2>/dev/null | grep -q "^goharbor/harbor-core"; then
        emit_status "installed:running" "$(_t '✅ Harbor containers are running')"
    else
        emit_status "installed:stopped" "$(_t '⚠️ Harbor installed but the containers are not running')"
    fi
}

do_help() {
    cat <<EOF
Harbor $(_t '— Self-hosted Docker image registry (Linux only, requires docker)')

用法: install.sh {install|uninstall|status|help}

  install    $(_t 'Download the offline installer to /opt/harbor and install it with the official orchestration (http mode)')
  uninstall  $(_t 'Stop the containers and uninstall (the /data is kept by default, deletion needs a second confirmation)')
  status     $(_t 'View the install status (supports UXS_STATUS_MODE=machine)')
  help       $(_t 'This help')

$(_t 'Note: the admin password is set during the install (random in non-interactive mode, shown once); http is the default,')
Docker $(_t 'a client has to add the registry address to insecure-registries in daemon.json.')
EOF
}

case "${1:-install}" in
    install)        do_install ;;
    uninstall)      do_uninstall ;;
    status)         do_status ;;
    help|--help|-h) do_help ;;
    *)              error "$(_tf 'Unknown subcommand: %s' "$1")"; do_help; exit 1 ;;
esac
