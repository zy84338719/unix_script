#!/usr/bin/env bash
#
# npm-mirror/install.sh
#
# npm / yarn / pnpm 换源加速。
# 一键为已安装的包管理器配置国内 registry（默认淘宝 npmmirror），
# 支持 npm、yarn（v1 / v2+ 自适应）、pnpm，并可随时切换或还原官方源。
#
# Linux + macOS。配置写入用户级（家目录），无需 sudo。
#
# 子命令：install | uninstall | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

OFFICIAL_REGISTRY="https://registry.npmjs.org/"

# ---------------- 内置源 ----------------
# 通过 case 分发（兼容 macOS 自带 bash 3.2，不使用关联数组）。
# 返回值打到 stdout："<name> <url>"。
registry_list() {
    cat <<'EOF'
taobao https://registry.npmmirror.com
tencent https://mirrors.cloud.tencent.com/npm/
huawei https://mirrors.huaweicloud.com/repository/npm/
npm https://registry.npmjs.org/
EOF
}

# 入参：源 key 或 URL；输出规范化 URL 到 stdout。
# 内置 key 命中则返回对应 URL；否则当 URL 原样返回（需 http(s):// 前缀）。
resolve_registry() {
    local key="$1"
    case "$key" in
        taobao)  echo "https://registry.npmmirror.com" ;;
        tencent) echo "https://mirrors.cloud.tencent.com/npm/" ;;
        huawei)  echo "https://mirrors.huaweicloud.com/repository/npm/" ;;
        npm)     echo "$OFFICIAL_REGISTRY" ;;
        *)
            if [[ "$key" =~ ^https?:// ]]; then
                echo "$key"
            else
                return 1
            fi
            ;;
    esac
}

# 源 key -> 友好名称（用于展示）
registry_label() {
    case "$1" in
        taobao)  echo "淘宝 (npmmirror)" ;;
        tencent) echo "腾讯云" ;;
        huawei)  echo "华为云" ;;
        npm)     echo "官方 npm" ;;
        https*)  echo "自定义" ;;
        *)       echo "未知" ;;
    esac
}

# ---------------- 前置检查 ----------------
preflight() {
    detect_os
    # 至少要有一个目标包管理器，否则无意义
    local has_any=false
    command_exists npm  && has_any=true
    command_exists yarn && has_any=true
    command_exists pnpm && has_any=true
    if ! $has_any; then
        error "未检测到 npm / yarn / pnpm 中的任何一个。"
        error "请先通过 nvm 安装 Node.js，再运行本模块。"
        exit 1
    fi
}

# nrm / cnpm / nvs 等源管理工具冲突检测（仅提示，不阻断）
check_nrm_conflict() {
    if command_exists nrm; then
        warn "检测到 nrm（NPM registry 管理器）。它可能覆盖本模块写入的 registry。"
        warn "如需统一管理，建议二选一：要么只用 nrm，要么卸载 nrm 后用本模块。"
    fi
    if command_exists cnpm; then
        info "检测到 cnpm（自带淘宝源客户端），通常无需为 npm 换源。"
    fi
}

# ---------------- 各包管理器配置 ----------------
config_npm() {
    local url="$1"
    npm config set registry "$url" --location=user
    success "npm  → $url"
}

config_yarn() {
    local url="$1"
    local major
    major=$(yarn --version 2>/dev/null | cut -d. -f1 || echo "1")
    if [[ "$major" -ge 2 ]]; then
        # yarn v2+ (Berry)：写 ~/.yarnrc.yml 的 npmRegistryServer
        yarn config set npmRegistryServer "$url" >/dev/null 2>&1 || {
            # 极少数旧版 v2 不支持该子命令，回退手写
            local cfg="$HOME/.yarnrc.yml"
            if grep -q '^npmRegistryServer:' "$cfg" 2>/dev/null; then
                sed -i.bak "s|^npmRegistryServer:.*|npmRegistryServer: \"$url\"|" "$cfg"
            else
                printf 'npmRegistryServer: "%s"\n' "$url" >> "$cfg"
            fi
        }
        success "yarn (v${major}) → $url"
    else
        # yarn v1：写 ~/.yarnrc
        yarn config set registry "$url" >/dev/null 2>&1 || true
        success "yarn (v1) → $url"
    fi
}

config_pnpm() {
    local url="$1"
    pnpm config set registry "$url" >/dev/null 2>&1 || true
    success "pnpm  → $url"
}

# 对所有已安装的 PM 写入 registry
apply_registry() {
    local url="$1"
    command_exists npm  && config_npm  "$url"
    command_exists yarn && config_yarn "$url"
    command_exists pnpm && config_pnpm "$url"
}

# ---------------- 交互式源选择 ----------------
# 输出选定的 URL 到 stdout（仅交互场景使用）。
prompt_registry() {
    while true; do
        echo
        menu "请选择 registry 源："
        echo "  1) 淘宝 (npmmirror)   https://registry.npmmirror.com        [默认/推荐]"
        echo "  2) 腾讯云             https://mirrors.cloud.tencent.com/npm/"
        echo "  3) 华为云             https://mirrors.huaweicloud.com/repository/npm/"
        echo "  4) 官方 npm           https://registry.npmjs.org/          (还原用)"
        echo "  5) 自定义输入 URL"
        echo "  0) 取消"
        read -r -p "请输入选项 [0-5]，默认 1: " opt
        opt="${opt:-1}"
        case "$opt" in
            1) echo "https://registry.npmmirror.com"; return 0 ;;
            2) echo "https://mirrors.cloud.tencent.com/npm/"; return 0 ;;
            3) echo "https://mirrors.huaweicloud.com/repository/npm/"; return 0 ;;
            4) echo "$OFFICIAL_REGISTRY"; return 0 ;;
            5)
                local custom
                read -r -p "请输入 registry URL (http(s)://): " custom
                if [[ "$custom" =~ ^https?:// ]]; then
                    echo "$custom"; return 0
                fi
                error "URL 非法，需以 http:// 或 https:// 开头"
                ;;
            0) info "已取消"; exit 0 ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}

# ---------------- 子命令 ----------------
do_install() {
    preflight
    local source_arg="${1:-}"
    local url label

    if [[ -z "$source_arg" ]]; then
        url=$(prompt_registry)
        label=$(registry_label "$url")
    else
        if ! url=$(resolve_registry "$source_arg"); then
            error "无法识别的源标识: $source_arg"
            error "可用内置源: taobao / tencent / huawei / npm，或传入完整 http(s):// URL"
            exit 1
        fi
        # 优先用原始 source key 标注（内置源有友好名称）；URL 则标"自定义"
        label=$(registry_label "$source_arg")
    fi

    info "目标 registry: $url ($label)"
    check_nrm_conflict
    echo
    apply_registry "$url"
    echo
    success "换源完成！"
}

do_uninstall() {
    preflight
    warn "将把已安装的 npm / yarn / pnpm 的 registry 还原为官方源："
    warn "  $OFFICIAL_REGISTRY"
    if ! yes_no "确认还原？"; then
        info "已取消"; return 0
    fi
    echo
    apply_registry "$OFFICIAL_REGISTRY"
    echo
    success "已还原为官方源"
}

do_status() {
    detect_os
    echo
    if command_exists npm; then
        local npm_reg
        npm_reg=$(npm config get registry 2>/dev/null || echo "未知")
        printf "  %-8s %s\n" "npm:" "$npm_reg"
    else
        printf "  %-8s %s\n" "npm:" "未安装"
    fi
    if command_exists yarn; then
        local yver yarn_reg
        yver=$(yarn --version 2>/dev/null | cut -d. -f1 || echo "1")
        if [[ "$yver" -ge 2 ]]; then
            yarn_reg=$(yarn config get npmRegistryServer 2>/dev/null || echo "未知")
        else
            yarn_reg=$(yarn config get registry 2>/dev/null || echo "未知")
        fi
        printf "  %-8s %s\n" "yarn:" "$yarn_reg"
    else
        printf "  %-8s %s\n" "yarn:" "未安装"
    fi
    if command_exists pnpm; then
        local pnpm_reg
        pnpm_reg=$(pnpm config get registry 2>/dev/null || echo "未知")
        printf "  %-8s %s\n" "pnpm:" "$pnpm_reg"
    else
        printf "  %-8s %s\n" "pnpm:" "未安装"
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help} [source]

  install [source]   换源（默认交互选择；source 可为内置 key 或完整 URL）
                     内置源: taobao(默认) | tencent | huawei | npm(官方)
  uninstall          还原为官方源 https://registry.npmjs.org/
  status             查看各包管理器当前 registry
  help               显示本帮助

示例:
  $0 install                  # 交互式选择（默认淘宝）
  $0 install taobao           # 直接切到淘宝源
  $0 install https://...      # 自定义 URL
  $0 uninstall                # 还原官方源
EOF
}

main() {
    local action="${1:-help}"
    detect_os
    case "$action" in
        install)   shift || true; do_install "${1:-}" ;;
        uninstall) do_uninstall ;;
        status)    do_status ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

main "$@"
