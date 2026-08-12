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
    info "🚀 安装 Bun（JavaScript/TypeScript 运行时与工具链）"

    if command_exists bun; then
        local cur
        cur=$(bun --version 2>/dev/null || echo "已安装")
        warn "检测到已安装 Bun（${cur}）"
        if ! yes_no "是否继续并重新安装/更新？"; then
            info "已取消"; return 0
        fi
    fi

    if [[ "$OS_TYPE" == "darwin" ]] && command_exists brew; then
        info "通过 Homebrew 安装 bun..."
        brew install bun
    else
        info "通过官方脚本安装（${OFFICIAL_INSTALLER}）..."
        # 信任模型：bun.sh/install 官方脚本会校验下载二进制的 SHA256（oven-sh/bun 发布
        # SHASUMS256.txt 且安装器内置校验），故二进制完整性已自校验。
        if ! bash -c "$(curl -fsSL "$OFFICIAL_INSTALLER")"; then
            error "官方安装脚本执行失败，请检查网络或参考 https://bun.sh/docs/installation"
            exit 1
        fi
    fi

    # 官方脚本装到 ~/.bun/bin/bun，可能不在当前 PATH
    if ! command_exists bun; then
        if [[ -x "$BUN_DIR/bin/bun" ]]; then
            warn "bun 已装到 $BUN_DIR/bin/bun，但不在当前 PATH"
            info "请添加到 shell 配置：export PATH=\"$BUN_DIR/bin:\$PATH\""
        else
            error "安装后仍找不到 bun，请重新打开终端或检查 PATH"
            exit 1
        fi
    fi

    # 阶段 D：apply profile 透传镜像源（UXS_CONFIG_REGISTRY 由 lib/profile.sh 注入）
    if [[ -n "${UXS_CONFIG_REGISTRY:-}" ]]; then
        info "应用配置：registry = ${UXS_CONFIG_REGISTRY}"
        _set_registry "$UXS_CONFIG_REGISTRY"
    fi

    success "🎉 Bun 安装完成！"
    info "快速开始："
    echo "  bun --version           # 查看版本"
    echo "  bun run dev             # 运行脚本（替代 npm run）"
    echo "  bun install             # 安装依赖（比 npm 快）"
    echo "  bun build ./index.ts    # 打包"
    echo "  bun test                # 运行测试"
    echo
    info "文档：https://bun.sh/docs"
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
        if yes_no "确认删除 ${BUN_DIR}（含 bun 二进制与全局缓存）？"; then
            rm -rf "$BUN_DIR"
            removed=true
            success "已删除 $BUN_DIR"
        fi
    fi
    if $removed; then
        success "Bun 已卸载"
        info "若 shell 配置中有 BUN 相关的 PATH 行，请手动删除"
    else
        warn "未找到 Bun 安装（可能已卸载或通过其他方式安装）"
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
    local cur_reg="(默认官方源)"
    if [[ -f "$BUNFIG" ]] && grep -q "registry" "$BUNFIG" 2>/dev/null; then
        # 从 "registry = \"url\"" 提取 url（用 Parameter Expansion 避免 sed 跨平台问题）
        local reg_line
        reg_line=$(grep -E "^registry" "$BUNFIG" | head -1)
        cur_reg=${reg_line#*=}
        cur_reg=${cur_reg//\"/}
        cur_reg=${cur_reg// /}
    fi

    if $installed; then
        emit_status "installed" "${GREEN}✅ 已安装${NC} ${ver:+(v$ver)}"
        emit_version "$ver"
    else
        emit_status "not_installed" "${RED}❌ 未安装${NC}"
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
    info "🌐 为 Bun 配置国内镜像源（${MIRROR_REGISTRY}）"
    _set_registry "$MIRROR_REGISTRY"
    success "已配置 registry = ${MIRROR_REGISTRY}（写入 ${BUNFIG}）"
    # 清理 bun 缓存使新源生效
    if command_exists bun; then
        info "清理 Bun 安装缓存..."
        bun pm cache rm >/dev/null 2>&1 || true
    fi
    info "验证：bun install 时将从国内镜像拉取"
}

# 还原官方源
unmirror_bun() {
    detect_os
    if [[ ! -f "$BUNFIG" ]]; then
        info "无 ${BUNFIG}，已是官方源"; return 0
    fi
    info "还原 Bun 官方源（${OFFICIAL_REGISTRY}）"
    _set_registry "$OFFICIAL_REGISTRY"
    success "已还原 registry = $OFFICIAL_REGISTRY"
    if command_exists bun; then
        bun pm cache rm >/dev/null 2>&1 || true
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|mirror|unmirror|uninstall|status|help}

  install     安装 Bun（JavaScript/TypeScript 运行时，默认动作）
  mirror      配置国内镜像源（淘宝 npmmirror，加速 bun install）
  unmirror    还原官方源
  uninstall   卸载
  status      查看状态（含当前 registry）
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
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
