#!/usr/bin/env bash
#
# dev-mirror/install.sh
#
# 开发语言生态换源加速：npm / Go / Rust / Python(pip) 一键配置国内镜像。
# - npm  : npm config set registry（+ yarn v1/v2+ / pnpm）
# - Go   : go env -w GOPROXY
# - Rust : ~/.cargo/config.toml 的 [source.crates-io] replace-with
# - pip  : pip config set global.index-url
#
# Linux + macOS。配置写入用户级（家目录），无需 sudo。
#
# 子命令: install [ecosystem] [source] | uninstall [ecosystem] | status | help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 生态清单
ECOSYSTEMS="npm go rust python"

# ============================================================
# 通用：源解析（每生态一组 case，兼容 macOS bash 3.2）
# ============================================================

# 解析源 key/url -> URL；失败返回 1。
# 用法: resolve_source <ecosystem> <key-or-url>
resolve_source() {
    local eco="$1" key="$2"
    case "$eco" in
        npm)
            case "$key" in
                taobao)  echo "https://registry.npmmirror.com" ;;
                tencent) echo "https://mirrors.cloud.tencent.com/npm/" ;;
                huawei)  echo "https://mirrors.huaweicloud.com/repository/npm/" ;;
                npm|official) echo "https://registry.npmjs.org/" ;;
                https*)  echo "$key" ;;
                *) return 1 ;;
            esac
            ;;
        go)
            case "$key" in
                goproxy-cn) echo "https://goproxy.cn,direct" ;;
                aliyun)     echo "https://mirrors.aliyun.com/goproxy/,direct" ;;
                goproxy-io) echo "https://goproxy.io,direct" ;;
                official)   echo "https://proxy.golang.org,direct" ;;
                https*)     echo "$key,direct" ;;
                *) return 1 ;;
            esac
            ;;
        rust)
            case "$key" in
                tuna)     echo "https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/" ;;
                ustc)     echo "https://mirrors.ustc.edu.cn/crates.io-index/" ;;
                sjtu)     echo "https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/" ;;
                rsproxy)  echo "https://rsproxy.cn/index/" ;;
                official) echo "OFFICIAL" ;;  # 特殊标记：还原=移除配置块
                https*)   echo "$key" ;;
                *) return 1 ;;
            esac
            ;;
        python)
            case "$key" in
                tuna)     echo "https://pypi.tuna.tsinghua.edu.cn/simple" ;;
                aliyun)   echo "https://mirrors.aliyun.com/pypi/simple/" ;;
                ustc)     echo "https://pypi.mirrors.ustc.edu.cn/simple/" ;;
                tencent)  echo "https://mirrors.cloud.tencent.com/pypi/simple" ;;
                official) echo "https://pypi.org/simple" ;;
                https*)   echo "$key" ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# 默认推荐源 key（每生态）
default_source_key() {
    case "$1" in
        npm) echo "taobao" ;;
        go)  echo "goproxy-cn" ;;
        rust) echo "tuna" ;;
        python) echo "tuna" ;;
    esac
}

# 源 key -> 友好名称
label_source() {
    local eco="$1" key="$2"
    case "$eco:$key" in
        npm:taobao)   echo "淘宝 npmmirror" ;;
        npm:tencent)  echo "腾讯云" ;;
        npm:huawei)   echo "华为云" ;;
        npm:official|npm:npm) echo "官方 npm" ;;
        go:goproxy-cn)  echo "goproxy.cn (七牛)" ;;
        go:aliyun)      echo "阿里云" ;;
        go:goproxy-io)  echo "goproxy.io" ;;
        go:official)    echo "官方 proxy.golang.org" ;;
        rust:tuna)    echo "清华 TUNA" ;;
        rust:ustc)    echo "中科大 USTC" ;;
        rust:sjtu)    echo "上海交大 SJTU" ;;
        rust:rsproxy) echo "字节 rsproxy" ;;
        rust:official) echo "官方 crates.io" ;;
        python:tuna)     echo "清华 TUNA" ;;
        python:aliyun)   echo "阿里云" ;;
        python:ustc)     echo "中科大 USTC" ;;
        python:tencent)  echo "腾讯云" ;;
        python:official) echo "官方 PyPI" ;;
        *:https*) echo "自定义" ;;
        *) echo "未知" ;;
    esac
}

# 生态友好名
label_eco() {
    case "$1" in
        npm) echo "npm/yarn/pnpm" ;;
        go)  echo "Go (GOPROXY)" ;;
        rust) echo "Rust (cargo)" ;;
        python) echo "Python (pip)" ;;
    esac
}

# ============================================================
# 前置检查
# ============================================================

# 检测某生态的工具是否已安装；已装返回 0。
ecosystem_available() {
    case "$1" in
        npm)
            command_exists npm || command_exists yarn || command_exists pnpm
            ;;
        go)    command_exists go ;;
        rust)  command_exists cargo ;;
        python) command_exists pip3 || command_exists pip ;;
        *)     return 1 ;;   # 未知生态一律视为不可用
    esac
}

# 至少一个生态可用，否则报错退出
preflight_any() {
    local eco has_any=false
    for eco in $ECOSYSTEMS; do
        if ecosystem_available "$eco"; then has_any=true; break; fi
    done
    if ! $has_any; then
        error "未检测到任何目标工具链（npm/go/cargo/pip）。"
        error "请先安装对应运行时再运行本模块。"
        exit 1
    fi
}

# 指定生态不可用时报错退出
require_ecosystem() {
    local eco="$1"
    if ! ecosystem_available "$eco"; then
        error "$(label_eco "$eco") 工具链未安装，跳过。"
        exit 1
    fi
}

# nrm/cnpm 冲突提示（仅 npm 生态）
check_npm_conflict() {
    if command_exists nrm; then
        warn "检测到 nrm（NPM registry 管理器），它可能覆盖本模块写入的 registry。"
        warn "建议二选一：要么只用 nrm，要么卸载 nrm 后用本模块。"
    fi
    if command_exists cnpm; then
        info "检测到 cnpm（自带淘宝源），通常无需为 npm 换源。"
    fi
}

# ============================================================
# npm 生态（迁移自 npm-mirror）
# ============================================================
config_npm() {
    local url="$1"
    command_exists npm && {
        npm config set registry "$url" --location=user
        success "npm    → $url"
    }
    if command_exists yarn; then
        local major
        major=$(yarn --version 2>/dev/null | cut -d. -f1 || echo "1")
        if [[ "$major" -ge 2 ]]; then
            yarn config set npmRegistryServer "$url" >/dev/null 2>&1 || true
            success "yarn v${major} → $url"
        else
            yarn config set registry "$url" >/dev/null 2>&1 || true
            success "yarn v1  → $url"
        fi
    fi
    command_exists pnpm && {
        pnpm config set registry "$url" >/dev/null 2>&1 || true
        success "pnpm   → $url"
    }
}

status_npm() {
    if command_exists npm; then
        printf "  %-8s %s\n" "npm:" "$(npm config get registry 2>/dev/null || echo 未知)"
    else
        printf "  %-8s %s\n" "npm:" "未安装"
    fi
    if command_exists yarn; then
        local yver reg
        yver=$(yarn --version 2>/dev/null | cut -d. -f1 || echo "1")
        if [[ "$yver" -ge 2 ]]; then
            reg=$(yarn config get npmRegistryServer 2>/dev/null || echo 未知)
        else
            reg=$(yarn config get registry 2>/dev/null || echo 未知)
        fi
        printf "  %-8s %s\n" "yarn:" "$reg"
    else
        printf "  %-8s %s\n" "yarn:" "未安装"
    fi
    if command_exists pnpm; then
        printf "  %-8s %s\n" "pnpm:" "$(pnpm config get registry 2>/dev/null || echo 未知)"
    else
        printf "  %-8s %s\n" "pnpm:" "未安装"
    fi
}

# ============================================================
# Go 生态
# ============================================================
config_go() {
    local url="$1"
    require_ecosystem go
    # go 1.13+ 支持 go env -w；检测版本
    local ver_major
    ver_major=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | head -1 | sed 's/go//;s/\..*//')
    if [[ "${ver_major:-0}" -ge 1 ]] && go env -w GOPROXY="$url" 2>/dev/null; then
        success "go     → $url"
    else
        # fallback: 写 shell 配置（兼容老版本 go）
        warn "go 版本较低或 go env -w 不可用，回退到写 ~/.bashrc 环境变量"
        local line="export GOPROXY=\"$url\""
        local f
        for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [[ -f "$f" ]] || continue
            if grep -q 'export GOPROXY=' "$f"; then
                sed -i.bak "s|export GOPROXY=.*|$line|" "$f"
            else
                printf '\n# dev-mirror: Go proxy\n%s\n' "$line" >> "$f"
            fi
        done
        success "go     → $url (写入 ~/.bashrc / ~/.zshrc，需 source 生效)"
    fi
}

status_go() {
    if command_exists go; then
        printf "  %-8s %s\n" "GOPROXY:" "$(go env GOPROXY 2>/dev/null || echo 未知)"
    else
        printf "  %-8s %s\n" "go:" "未安装"
    fi
}

# ============================================================
# Rust 生态（cargo config.toml，标记段 + 原子重写）
# ============================================================
CARGO_CFG="$HOME/.cargo/config.toml"
CARGO_CFG_LEGACY="$HOME/.cargo/config"
MIRROR_BEGIN="# >>> dev-mirror (cargo) >>>"
MIRROR_END="# <<< dev-mirror (cargo) <<<"

# 写入 cargo 镜像段（url 为实际镜像 URL）
config_rust() {
    local url="$1"
    require_ecosystem rust
    mkdir -p "$HOME/.cargo"
    # 选择目标配置文件：优先 config.toml；若仅有旧 config 则用它
    local cfg="$CARGO_CFG"
    if [[ ! -f "$cfg" && -f "$CARGO_CFG_LEGACY" ]]; then
        cfg="$CARGO_CFG_LEGACY"
    fi

    # 读取标记段之外的内容（保留用户其他配置）
    local other=""
    if [[ -f "$cfg" ]]; then
        other=$(awk -v b="$MIRROR_BEGIN" -v e="$MIRROR_END" '
            $0==b {inblk=1; next}
            $0==e {inblk=0; next}
            !inblk {print}
        ' "$cfg")
    fi

    # 拼接：用户配置 + 本模块标记段
    local block
    block=$(printf '%s\n[source.crates-io]\nreplace-with = "dev-mirror"\n\n[source.dev-mirror]\nregistry = "sparse+%s"\n%s\n' \
        "$MIRROR_BEGIN" "$url" "$MIRROR_END")

    # 原子写入：先写临时文件再 mv
    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    {
        [[ -n "$other" ]] && printf '%s\n\n' "$other"
        printf '%s\n' "$block"
    } > "$tmp"
    mv "$tmp" "$cfg"
    success "cargo  → $url"
}

# 移除 cargo 镜像段（还原官方）
uninstall_rust() {
    require_ecosystem rust
    local cfg
    for cfg in "$CARGO_CFG" "$CARGO_CFG_LEGACY"; do
        [[ -f "$cfg" ]] || continue
        if grep -qF "$MIRROR_BEGIN" "$cfg"; then
            local tmp
            tmp=$(mktemp)
            trap 'rm -f "$tmp"' EXIT
            awk -v b="$MIRROR_BEGIN" -v e="$MIRROR_END" '
                $0==b {inblk=1; next}
                $0==e {inblk=0; next}
                !inblk {print}
            ' "$cfg" > "$tmp"
            mv "$tmp" "$cfg"
            success "cargo  → 已还原官方 crates.io"
        fi
    done
}

status_rust() {
    if command_exists cargo; then
        local reg="未知"
        if [[ -f "$CARGO_CFG" ]]; then
            reg=$(grep -A1 '\[source.dev-mirror\]' "$CARGO_CFG" 2>/dev/null \
                  | grep 'registry' | sed -E 's/.*"(.*)".*/\1/' | head -1)
        fi
        [[ -z "$reg" ]] && reg="官方 crates.io"
        printf "  %-8s %s\n" "cargo:" "$reg"
    else
        printf "  %-8s %s\n" "cargo:" "未安装"
    fi
}

# ============================================================
# Python 生态（pip config）
# ============================================================
config_python() {
    local url="$1"
    require_ecosystem python
    local pip_cmd="pip3"
    command_exists pip3 || pip_cmd="pip"
    if "$pip_cmd" config set global.index-url "$url" >/dev/null 2>&1; then
        success "pip    → $url"
    else
        # fallback: 手写 ~/.config/pip/pip.conf
        warn "pip config 命令不可用，回退到手写配置文件"
        local cfg_dir="$HOME/.config/pip"
        mkdir -p "$cfg_dir"
        local cfg="$cfg_dir/pip.conf"
        if [[ -f "$cfg" ]] && grep -q '^index-url' "$cfg"; then
            sed -i.bak "s|^index-url=.*|index-url = $url|" "$cfg"
        else
            {
                echo "[global]"
                echo "index-url = $url"
            } >> "$cfg"
        fi
        success "pip    → $url (写入 $cfg)"
    fi
}

status_python() {
    local pip_cmd=""
    command_exists pip3 && pip_cmd="pip3"
    [[ -z "$pip_cmd" ]] && command_exists pip && pip_cmd="pip"
    if [[ -n "$pip_cmd" ]]; then
        local reg
        reg=$("$pip_cmd" config get global.index-url 2>/dev/null || echo "官方 PyPI")
        printf "  %-8s %s\n" "pip:" "$reg"
    else
        printf "  %-8s %s\n" "pip:" "未安装"
    fi
}

# ============================================================
# 调度：对某生态执行配置/还原
# ============================================================

# apply_source <ecosystem> <url>
apply_source() {
    local eco="$1" url="$2"
    case "$eco" in
        npm)    config_npm "$url" ;;
        go)     config_go "$url" ;;
        rust)
            if [[ "$url" == "OFFICIAL" ]]; then
                uninstall_rust
            else
                config_rust "$url"
            fi
            ;;
        python) config_python "$url" ;;
    esac
}

# 交互式选择生态；输出选中的生态到 stdout
prompt_ecosystem() {
    while true; do
        echo
        menu "请选择要配置的生态："
        local idx=1
        local eco avail_list=()
        for eco in $ECOSYSTEMS; do
            local mark=""
            ecosystem_available "$eco" || mark="(未安装，将跳过)"
            echo "  $idx) $(label_eco "$eco") $mark"
            avail_list+=("$eco")
            idx=$((idx + 1))
        done
        echo "  $idx) 全部（逐个已安装的生态）"
        echo "  0) 取消"
        read -r -p "请输入选项 [0-$idx]: " opt
        case "$opt" in
            1|2|3|4) echo "${avail_list[$((opt - 1))]}"; return 0 ;;
            5) echo "all"; return 0 ;;
            0) info "已取消"; exit 0 ;;
            *) error "无效选项"; sleep 1 ;;
        esac
    done
}

# 交互式选源；输出选中的 url 到 stdout。
# prompt_source <ecosystem>
prompt_source() {
    local eco="$1"
    while true; do
        echo
        menu "请选择 $(label_eco "$eco") 的源："
        case "$eco" in
            npm)
                echo "  1) 淘宝 npmmirror   https://registry.npmmirror.com        [默认/推荐]"
                echo "  2) 腾讯云           https://mirrors.cloud.tencent.com/npm/"
                echo "  3) 华为云           https://mirrors.huaweicloud.com/repository/npm/"
                echo "  4) 官方 npm         https://registry.npmjs.org/          (还原)"
                ;;
            go)
                echo "  1) goproxy.cn (七牛) https://goproxy.cn,direct          [默认/推荐]"
                echo "  2) 阿里云            https://mirrors.aliyun.com/goproxy/,direct"
                echo "  3) goproxy.io        https://goproxy.io,direct"
                echo "  4) 官方              https://proxy.golang.org,direct     (还原)"
                ;;
            rust)
                echo "  1) 清华 TUNA   https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/  [默认/推荐]"
                echo "  2) 中科大 USTC https://mirrors.ustc.edu.cn/crates.io-index/"
                echo "  3) 上交 SJTU   https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/"
                echo "  4) 字节 rsproxy https://rsproxy.cn/index/"
                echo "  5) 官方 crates.io                                       (还原)"
                ;;
            python)
                echo "  1) 清华 TUNA   https://pypi.tuna.tsinghua.edu.cn/simple  [默认/推荐]"
                echo "  2) 阿里云      https://mirrors.aliyun.com/pypi/simple/"
                echo "  3) 中科大 USTC https://pypi.mirrors.ustc.edu.cn/simple/"
                echo "  4) 腾讯云      https://mirrors.cloud.tencent.com/pypi/simple"
                echo "  5) 官方 PyPI   https://pypi.org/simple                  (还原)"
                ;;
        esac
        local max_opt=4
        [[ "$eco" == "rust" || "$eco" == "python" ]] && max_opt=5
        echo "  $((max_opt + 1))) 自定义输入 URL"
        echo "  0) 取消"
        read -r -p "请输入选项 [0-$((max_opt + 1))]，默认 1: " sopt
        sopt="${sopt:-1}"
        local key=""
        case "$eco:$sopt" in
            npm:1|go:1|rust:1|python:1) key="$(default_source_key "$eco")" ;;
            npm:2) key="tencent" ;;
            npm:3) key="huawei" ;;
            npm:4) key="official" ;;
            go:2) key="aliyun" ;;
            go:3) key="goproxy-io" ;;
            go:4) key="official" ;;
            rust:2) key="ustc" ;;
            rust:3) key="sjtu" ;;
            rust:4) key="rsproxy" ;;
            rust:5) key="official" ;;
            python:2) key="aliyun" ;;
            python:3) key="ustc" ;;
            python:4) key="tencent" ;;
            python:5) key="official" ;;
            *:$((max_opt + 1)))
                local custom
                read -r -p "请输入 URL (http(s)://): " custom
                if [[ "$custom" =~ ^https?:// ]]; then
                    resolve_source "$eco" "$custom" && return 0
                fi
                error "URL 非法，需以 http:// 或 https:// 开头"
                continue
                ;;
            *:0) info "已取消"; exit 0 ;;
            *) error "无效选项"; sleep 1; continue ;;
        esac
        resolve_source "$eco" "$key" && return 0
    done
}

# ============================================================
# 子命令
# ============================================================
do_install() {
    preflight_any
    local eco="${1:-}"
    local src="${2:-}"

    # 无生态参数：交互选
    if [[ -z "$eco" ]]; then
        eco=$(prompt_ecosystem)
    fi

    # 校验生态名（all 除外）
    if [[ "$eco" != "all" ]]; then
        local _valid=false _e
        for _e in $ECOSYSTEMS; do [[ "$_e" == "$eco" ]] && _valid=true; done
        if ! $_valid; then
            error "未知生态: $eco（可选: $ECOSYSTEMS | all）"
            exit 1
        fi
    fi

    # 解析源（交互或参数）
    local url
    if [[ "$eco" == "all" ]]; then
        if [[ -z "$src" ]]; then
            # 交互：逐个生态选源
            local e
            for e in $ECOSYSTEMS; do
                ecosystem_available "$e" || continue
                echo
                info "=== $(label_eco "$e") ==="
                url=$(prompt_source "$e")
                info "目标: $url ($(label_source "$e" "$(src_key_or_url "$e" "$url")"))"
                [[ "$e" == "npm" ]] && check_npm_conflict
                apply_source "$e" "$url"
            done
        else
            # 非交互：用每生态默认推荐源批量
            local e
            for e in $ECOSYSTEMS; do
                ecosystem_available "$e" || continue
                url=$(resolve_source "$e" "$(default_source_key "$e")")
                info "$(label_eco "$e"): $url ($(label_source "$e" "$(default_source_key "$e")"))"
                apply_source "$e" "$url"
            done
        fi
    else
        require_ecosystem "$eco"
        if [[ -z "$src" ]]; then
            url=$(prompt_source "$eco")
        else
            if ! url=$(resolve_source "$eco" "$src"); then
                error "无法识别的源标识: $src (生态: $eco)"
                exit 1
            fi
        fi
        info "$(label_eco "$eco") 目标: $url"
        [[ "$eco" == "npm" ]] && check_npm_conflict
        echo
        apply_source "$eco" "$url"
    fi
    echo
    success "换源完成！"
}

# 由 url 反推 source key（用于展示 label）；找不到则当 URL 处理
src_key_or_url() {
    local eco="$1" url="$2"
    local k
    for k in taobao tencent huawei npm official \
             goproxy-cn aliyun goproxy-io \
             tuna ustc sjtu rsproxy; do
        if [[ "$(resolve_source "$eco" "$k" 2>/dev/null)" == "$url" ]]; then
            echo "$k"; return 0
        fi
    done
    echo "$url"
}

do_uninstall() {
    preflight_any
    local eco="${1:-}"
    if [[ -z "$eco" ]]; then
        eco=$(prompt_ecosystem)
    fi
    # 校验生态名（all 除外）
    if [[ "$eco" != "all" ]]; then
        local _valid=false _e
        for _e in $ECOSYSTEMS; do [[ "$_e" == "$eco" ]] && _valid=true; done
        if ! $_valid; then
            error "未知生态: $eco（可选: $ECOSYSTEMS | all）"
            exit 1
        fi
    fi
    if [[ "$eco" == "all" ]]; then
        warn "将把所有已安装的生态还原为官方源（npm/Go/Rust/Python）"
    else
        warn "将把以下生态还原为官方源：$(label_eco "$eco")"
    fi
    if ! yes_no "确认还原？"; then
        info "已取消"; return 0
    fi
    echo
    if [[ "$eco" == "all" ]]; then
        local e
        for e in $ECOSYSTEMS; do
            ecosystem_available "$e" || continue
            apply_source "$e" "$(resolve_source "$e" official)"
        done
    else
        require_ecosystem "$eco"
        apply_source "$eco" "$(resolve_source "$eco" official)"
    fi
    echo
    success "已还原为官方源"
}

do_status() {
    detect_os
    echo
    info "npm/yarn/pnpm:"
    status_npm
    info "Go:"
    status_go
    info "Rust:"
    status_rust
    info "Python:"
    status_python
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help} [ecosystem] [source]

开发语言生态换源加速（npm / Go / Rust / Python）。

  install [ecosystem] [source]   换源
    ecosystem: npm | go | rust | python | all（缺省=交互选择）
    source:    各生态内置源 key（见下）或完整 URL（缺省=交互选择）
  uninstall [ecosystem]          还原官方源
  status                         查看各生态当前镜像
  help                           显示本帮助

内置源 key：
  npm     : taobao(默认) | tencent | huawei | npm/official
  go      : goproxy-cn(默认) | aliyun | goproxy-io | official
  rust    : tuna(默认) | ustc | sjtu | rsproxy | official
  python  : tuna(默认) | aliyun | ustc | tencent | official

示例:
  $0 install                       # 交互：先选生态，再选源
  $0 install go goproxy-cn         # 直接为 Go 配置 goproxy.cn
  $0 install all                   # 交互逐个生态选源
  $0 install npm https://my.com/   # 自定义 URL
  $0 uninstall rust                # 还原 cargo 官方源
EOF
}

main() {
    local action="${1:-help}"
    detect_os
    case "$action" in
        install)
            shift || true
            do_install "${1:-}" "${2:-}"
            ;;
        uninstall)
            shift || true
            do_uninstall "${1:-}"
            ;;
        status)    do_status ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

main "$@"
