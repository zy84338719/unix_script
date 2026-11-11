#!/usr/bin/env bash
#
# bun/install.sh
#
# 安装 Bun —— 快速的 JavaScript/TypeScript 运行时与工具链（打包/运行/测试）。
# Linux + macOS。包装官方安装脚本 / Homebrew。
#
# 子命令：install | uninstall | status | help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

OFFICIAL_INSTALLER="https://bun.sh/install"
BUN_DIR="$HOME/.bun"
BUNFIG="$HOME/.bunfig.toml"
# 国内镜像（淘宝 npmmirror）
MIRROR_REGISTRY="https://registry.npmmirror.com"
OFFICIAL_REGISTRY="https://registry.npmjs.org"

preflight() {
    detect_os
    check_commands curl
}

install_bun() {
    preflight
    info "$(_t '🚀 Installing Bun (the JavaScript/TypeScript runtime and toolchain)')"

    if command_exists bun; then
        local cur
        cur=$(bun --version 2>/dev/null || printf '%s\n' "$(_t 'Installed')")
        warn "$(_tf 'Detected that Bun is already installed (%s)' "${cur}")"
        if ! yes_no "$(_t 'Continue and reinstall/update it?')"; then
            info "$(_t 'Cancelled')"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "$(_t 'Installing bun via Homebrew...')"
        brew install bun
    else
        info "$(_tf 'Installing via the official script (%s)...' "${OFFICIAL_INSTALLER}")"
        # 信任模型：bun.sh/install 官方脚本会校验下载二进制的 SHA256（oven-sh/bun 发布
        # SHASUMS256.txt 且安装器内置校验），故二进制完整性已自校验。
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
            error "$(_t 'The official installation script failed, check the network or see https://bun.sh/docs/installation')"
            exit 1
        fi
    fi

    # 官方脚本装到 ~/.bun/bin/bun，可能不在当前 PATH
    if ! command_exists bun; then
        if [[ -x "$BUN_DIR/bin/bun" ]]; then
            warn "bun $(_tf 'Installed to %s/bin/bun, but it is not in the current PATH' "$BUN_DIR")"
            # shellcheck disable=SC2016  # 译文里的 $PATH 是要原样打印的字面量，不能展开
            info "$(_tf 'Add it to your shell configuration: export PATH="%s/bin:$PATH"' "$BUN_DIR")"
        else
            error "$(_t 'bun is still not found after the installation, reopen the terminal or check PATH')"
            exit 1
        fi
    fi

    # 阶段 D：apply profile 透传镜像源（UXS_CONFIG_REGISTRY 由 lib/profile.sh 注入）
    if [[ -n "${UXS_CONFIG_REGISTRY:-}" ]]; then
        info "$(_tf 'Applying the configuration: registry = %s' "${UXS_CONFIG_REGISTRY}")"
        _set_registry "$UXS_CONFIG_REGISTRY"
    fi

    success "$(_t '🎉 Bun installation complete!')"
    info "$(_t 'Quick start:')"
    echo "  bun --version           # $(_t 'View the version')"
    echo "  bun run dev             # $(_t 'Run a script (replaces npm run)')"
    echo "  bun install             # $(_t 'Install the dependencies (faster than npm)')"
    echo "  bun build ./index.ts    # $(_t 'Bundle')"
    echo "  bun test                # $(_t 'Run the tests')"
    echo
    info "$(_t 'Docs: https://bun.sh/docs')"
}

uninstall_bun() {
    preflight
    local removed=false
    # brew 安装的
    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        brew uninstall bun 2>/dev/null && removed=true
    fi
    # 官方脚本安装的（~/.bun）
    if [[ -d "$BUN_DIR" ]]; then
        if yes_no "$(_tf 'Confirm deleting %s (including the bun binary and the global cache)?' "${BUN_DIR}")"; then
            rm -rf "$BUN_DIR"
            removed=true
            success "$(_tf 'Deleted %s' "$BUN_DIR")"
        fi
    fi
    if $removed; then
        success "Bun $(_t 'Uninstalled')"
        info "$(_t 'If the shell configuration has a BUN related PATH line, delete it manually')"
    else
        warn "$(_t 'No Bun installation found (it may have been uninstalled or installed in another way)')"
    fi
}

status_bun() {
    detect_os
    # 计算版本与 registry（emit_status 之前完成，保证 STATE= 为首行）
    local installed=false ver=""
    if command_exists bun || [[ -x "$BUN_DIR/bin/bun" ]]; then
        installed=true
        ver=$(bun --version 2>/dev/null || "$BUN_DIR/bin/bun" --version 2>/dev/null || echo "")
    fi
    local cur_reg
    cur_reg="$(_t '(the default official registry)')"
    if [[ -f "$BUNFIG" ]] && grep -q "registry" "$BUNFIG" 2>/dev/null; then
        # 从 "registry = \"url\"" 提取 url（用 Parameter Expansion 避免 sed 跨平台问题）
        local reg_line
        # 不用 `| head -1`：head 命中即退会给上游 SIGPIPE(141)；grep 无匹配时退出 1。
        # 两者在 pipefail 下都会让整条管道非 0，set -e 会让 status 子命令整体中止
        # （违反「状态子命令恒 0」契约）。改用 sed 取首行（sed 读完整个输入才退出），
        # 取不到就回落成空串。
        reg_line=$(grep -E "^registry" "$BUNFIG" | sed -n '1p') || reg_line=""
        cur_reg=${reg_line#*=}
        cur_reg=${cur_reg//\"/}
        cur_reg=${cur_reg// /}
    fi

    if $installed; then
        emit_status "installed" "${GREEN}$(_t '✅ Installed')${NC} ${ver:+(v$ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}$(_t '❌ Not installed')${NC}"
    fi
    emit_extra "registry=$cur_reg"
    if ! uxs_is_machine_mode; then
        echo "   registry: $cur_reg"
    fi
}

# 跨平台设置 bunfig.toml 的 registry（兼容 macOS BSD sed 与 Linux GNU sed）。
# 重建 [install] 段：保留其他段，[install] 段只保留 registry（覆盖）。
# 参数: <registry_url>
_set_registry() {
    local reg="$1"
    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    # 备份
    [[ -f "$BUNFIG" ]] && cp -a "$BUNFIG" "$BUNFIG.bak.$(date +%s)"
    # 提取 [install] 段之外的行（即不在 [install] 段的内容），用 awk 跨平台
    if [[ -f "$BUNFIG" ]]; then
        awk -v inst=0 '
            /^\[install\]/ { inst=1; next }
            /^\[/ { inst=0 }
            inst==0 { print }
        ' "$BUNFIG" > "$tmp"
    fi
    # 追加新的 [install] 段（含 registry）
    {
        # 若提取后有内容且不以空行结尾，补一个空行
        if [[ -s "$tmp" ]]; then
            cat "$tmp"
            tail -1 "$tmp" | grep -q '.' && echo ""
        fi
        printf '[install]\nregistry = "%s"\n' "$reg"
    } > "$BUNFIG"
    rm -f "$tmp"
}

# 换国内镜像源（写入 ~/.bunfig.toml）
mirror_bun() {
    detect_os
    info "$(_tf '🌐 Configuring a domestic mirror for Bun (%s)' "${MIRROR_REGISTRY}")"
    _set_registry "$MIRROR_REGISTRY"
    success "$(_tf 'The registry = %s has been configured (written to %s)' "${MIRROR_REGISTRY}" "${BUNFIG}")"
    # 清理 bun 缓存使新源生效
    if command_exists bun; then
        info "$(_t 'Cleaning the Bun installation cache...')"
        bun pm cache rm >/dev/null 2>&1 || true
    fi
    info "$(_t 'Verification: bun install will pull from the domestic mirror')"
}

# 还原官方源
unmirror_bun() {
    detect_os
    if [[ ! -f "$BUNFIG" ]]; then
        info "$(_tf 'No %s, it is already the official registry' "${BUNFIG}")"; return 0
    fi
    info "$(_tf 'Restoring the official Bun registry (%s)' "${OFFICIAL_REGISTRY}")"
    _set_registry "$OFFICIAL_REGISTRY"
    success "$(_tf 'The registry = %s has been restored' "$OFFICIAL_REGISTRY")"
    if command_exists bun; then
        bun pm cache rm >/dev/null 2>&1 || true
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|mirror|unmirror|uninstall|status|help}

  install     $(_t 'Install Bun (the JavaScript/TypeScript runtime, default action)')
  mirror      $(_t 'Configure a domestic mirror (Taobao npmmirror, speeds up bun install)')
  unmirror    $(_t 'Restore the official registry')
  uninstall   $(_t 'Uninstall')
  status      $(_t 'View the status (including the current registry)')
EOF
}

main() {
    local action="${1:-install}"
    detect_os
    case "$action" in
        install)   install_bun ;;
        mirror)    mirror_bun ;;
        unmirror)  unmirror_bun ;;
        uninstall) uninstall_bun ;;
        status)    status_bun ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
