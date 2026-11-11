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

set -euo pipefail

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
                # 特殊标记：还原=移除配置块
                official) echo "OFFICIAL" ;;
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
        npm:taobao)   printf '%s\n' "$(_t 'Taobao npmmirror')" ;;
        npm:tencent)  printf '%s\n' "$(_t 'Tencent Cloud')" ;;
        npm:huawei)   printf '%s\n' "$(_t 'Huawei Cloud')" ;;
        npm:official|npm:npm) printf '%s\n' "$(_t 'Official npm')" ;;
        go:goproxy-cn)  echo "goproxy.cn ($(_t 'Qiniu)')" ;;
        go:aliyun)      printf '%s\n' "$(_t 'Alibaba Cloud')" ;;
        go:goproxy-io)  echo "goproxy.io" ;;
        go:official)    printf '%s\n' "$(_t 'Official proxy.golang.org')" ;;
        rust:tuna)    printf '%s\n' "$(_t 'Tsinghua TUNA')" ;;
        rust:ustc)    printf '%s\n' "$(_t 'USTC')" ;;
        rust:sjtu)    printf '%s\n' "$(_t 'Shanghai Jiao Tong SJTU')" ;;
        rust:rsproxy) printf '%s\n' "$(_t 'ByteDance rsproxy')" ;;
        rust:official) printf '%s\n' "$(_t 'Official crates.io')" ;;
        python:tuna)     printf '%s\n' "$(_t 'Tsinghua TUNA')" ;;
        python:aliyun)   printf '%s\n' "$(_t 'Alibaba Cloud')" ;;
        python:ustc)     printf '%s\n' "$(_t 'USTC')" ;;
        python:tencent)  printf '%s\n' "$(_t 'Tencent Cloud')" ;;
        python:official) printf '%s\n' "$(_t 'Official PyPI')" ;;
        *:https*) printf '%s\n' "$(_t 'Custom')" ;;
        *) printf '%s\n' "$(_t 'Unknown')" ;;
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
        # 未知生态一律视为不可用
        *)     return 1 ;;
    esac
}

# 至少一个生态可用，否则报错退出
preflight_any() {
    local eco has_any=false
    for eco in $ECOSYSTEMS; do
        if ecosystem_available "$eco"; then has_any=true; break; fi
    done
    if ! $has_any; then
        error "$(_t 'No target toolchain detected (npm/go/cargo/pip).')"
        error "$(_t 'Please install the corresponding runtime before running this module.')"
        exit 1
    fi
}

# 指定生态不可用时报错退出
require_ecosystem() {
    local eco="$1"
    if ! ecosystem_available "$eco"; then
        error "$(label_eco "$eco") $(_t 'Toolchain not installed, skipping.')"
        exit 1
    fi
}

# nrm/cnpm 冲突提示（仅 npm 生态）
check_npm_conflict() {
    if command_exists nrm; then
        warn "$(_t 'nrm (NPM registry manager) detected, it may override the registry written by this module.')"
        warn "$(_t 'Recommendation: either use only nrm, or uninstall nrm and then use this module.')"
    fi
    if command_exists cnpm; then
        info "$(_t 'cnpm detected (ships with the Taobao mirror), usually no need to switch the npm mirror.')"
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
        printf "  %-8s %s\n" "npm:" "$(npm config get registry 2>/dev/null || _t 'Unknown')"
    else
        printf "  %-8s %s\n" "npm:" "$(_t 'Not installed')"
    fi
    if command_exists yarn; then
        local yver reg
        yver=$(yarn --version 2>/dev/null | cut -d. -f1 || echo "1")
        if [[ "$yver" -ge 2 ]]; then
            reg=$(yarn config get npmRegistryServer 2>/dev/null || _t 'Unknown')
        else
            reg=$(yarn config get registry 2>/dev/null || _t 'Unknown')
        fi
        printf "  %-8s %s\n" "yarn:" "$reg"
    else
        printf "  %-8s %s\n" "yarn:" "$(_t 'Not installed')"
    fi
    if command_exists pnpm; then
        printf "  %-8s %s\n" "pnpm:" "$(pnpm config get registry 2>/dev/null || _t 'Unknown')"
    else
        printf "  %-8s %s\n" "pnpm:" "$(_t 'Not installed')"
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
    # 不用 `| head -1`：head 命中即退会给上游 SIGPIPE，pipefail 下整条管道非 0。
    # 用 sed 取首行（sed 读完整个输入才退出，不会打断上游）。
    ver_major=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | sed -n '1{s/go//;s/\..*//;p;}' || true)
    if [[ "${ver_major:-0}" -ge 1 ]] && go env -w GOPROXY="$url" 2>/dev/null; then
        success "go     → $url"
    else
        # fallback: 写 shell 配置（兼容老版本 go）
        warn "go $(_t 'version is too old or go env -w is unavailable, falling back to writing the ~/.bashrc environment variable')"
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
        success "go     $(_tf '→ %s (written to ~/.bashrc / ~/.zshrc, run source to take effect)' "$url")"
    fi
}

status_go() {
    if command_exists go; then
        printf "  %-8s %s\n" "GOPROXY:" "$(go env GOPROXY 2>/dev/null || _t 'Unknown')"
    else
        printf "  %-8s %s\n" "go:" "$(_t 'Not installed')"
    fi
}

# ============================================================
# Rust 生态（cargo config.toml，标记段 + 原子重写）
# ============================================================
CARGO_CFG="$HOME/.cargo/config.toml"
CARGO_CFG_LEGACY="$HOME/.cargo/config"
# 结束标记的 '<<<' 用变量拼出：源码里直接写裸 '<<<' 会被只认 '<<' 的解析器
# 误判成 heredoc 起始，导致后面的行全被当成 heredoc 正文。取值与原来逐字相同。
_MIRROR_END_TAG='<<<'
MIRROR_BEGIN="# >>> dev-mirror (cargo) >>>"
MIRROR_END="# ${_MIRROR_END_TAG} dev-mirror (cargo) ${_MIRROR_END_TAG}"

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
            success "cargo  $(_t '→ restored to official crates.io')"
        fi
    done
}

# 从 cargo 配置里读 [source.dev-mirror] 段的 registry URL；读不到输出空串。
# 不用 `grep -A1 ... | head -1`：grep 无匹配时退出 1，pipefail 下整条管道非 0，
# set -e 会让 status 子命令整体中止（违反「状态子命令恒 0」契约）；
# head 命中即退还会给上游 SIGPIPE（141）。
cargo_mirror_registry() {
    local cfg="$1"
    [[ -f "$cfg" ]] || return 0
    awk '
        /^\[source\.dev-mirror\]/ { inblk = 1; next }
        /^\[/ { inblk = 0 }
        inblk && /^[[:space:]]*registry[[:space:]]*=/ {
            if (match($0, /"[^"]*"/)) { print substr($0, RSTART + 1, RLENGTH - 2); exit }
        }
    ' "$cfg" 2>/dev/null || true
}

status_rust() {
    if command_exists cargo; then
        local reg
        reg="$(_t 'Unknown')"
        if [[ -f "$CARGO_CFG" ]]; then
            reg=$(cargo_mirror_registry "$CARGO_CFG")
        fi
        [[ -z "$reg" ]] && reg="$(_t 'Official crates.io')"
        printf "  %-8s %s\n" "cargo:" "$reg"
    else
        printf "  %-8s %s\n" "cargo:" "$(_t 'Not installed')"
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
        warn "pip config $(_t 'pip config command unavailable, falling back to writing the config file by hand')"
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
        success "pip    $(_tf '→ %s (written to %s)' "$url" "$cfg")"
    fi
}

status_python() {
    local pip_cmd=""
    command_exists pip3 && pip_cmd="pip3"
    [[ -z "$pip_cmd" ]] && command_exists pip && pip_cmd="pip"
    if [[ -n "$pip_cmd" ]]; then
        local reg
        reg=$("$pip_cmd" config get global.index-url 2>/dev/null || _t 'Official PyPI')
        printf "  %-8s %s\n" "pip:" "$reg"
    else
        printf "  %-8s %s\n" "pip:" "$(_t 'Not installed')"
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
        menu "$(_t 'Please select the ecosystem to configure:')"
        local idx=1
        local eco avail_list=()
        for eco in $ECOSYSTEMS; do
            local mark=""
            ecosystem_available "$eco" || mark="($(_t 'Not installed, will skip)')"
            echo "  $idx) $(label_eco "$eco") $mark"
            avail_list+=("$eco")
            idx=$((idx + 1))
        done
        echo "  $idx) $(_t 'All (one by one for each installed ecosystem)')"
        echo "  0) $(_t 'Cancel')"
        read -r -p "$(_tf 'Enter option [0-%s]:' "$idx") " opt
        case "$opt" in
            1|2|3|4) echo "${avail_list[$((opt - 1))]}"; return 0 ;;
            5) echo "all"; return 0 ;;
            0) info "$(_t 'Cancelled')"; exit 0 ;;
            *) error "$(_t 'Invalid option')"; sleep 1 ;;
        esac
    done
}

# 交互式选源；输出选中的 url 到 stdout。
# prompt_source <ecosystem>
prompt_source() {
    local eco="$1"
    while true; do
        echo
        menu "$(_t 'Please select') $(label_eco "$eco") $(_t 'the source:')"
        case "$eco" in
            npm)
                echo "  1) $(_t 'Taobao npmmirror   https://registry.npmmirror.com        [Default/Recommended]')"
                echo "  2) $(_t 'Tencent Cloud           https://mirrors.cloud.tencent.com/npm/')"
                echo "  3) $(_t 'Huawei Cloud           https://mirrors.huaweicloud.com/repository/npm/')"
                echo "  4) $(_t 'Official npm         https://registry.npmjs.org/          (restore)')"
                ;;
            go)
                echo "  1) goproxy.cn ($(_t 'Qiniu) https://goproxy.cn,direct          [Default/Recommended]')"
                echo "  2) $(_t 'Alibaba Cloud            https://mirrors.aliyun.com/goproxy/,direct')"
                echo "  3) goproxy.io        https://goproxy.io,direct"
                echo "  4) $(_t 'Official              https://proxy.golang.org,direct     (restore)')"
                ;;
            rust)
                echo "  1) $(_t 'Tsinghua TUNA   https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/  [Default/Recommended]')"
                echo "  2) $(_t 'USTC https://mirrors.ustc.edu.cn/crates.io-index/')"
                echo "  3) $(_t 'SJTU   https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/')"
                echo "  4) $(_t 'ByteDance rsproxy https://rsproxy.cn/index/')"
                echo "  5) $(_t 'Official crates.io                                       (restore)')"
                ;;
            python)
                echo "  1) $(_t 'Tsinghua TUNA   https://pypi.tuna.tsinghua.edu.cn/simple  [Default/Recommended]')"
                echo "  2) $(_t 'Alibaba Cloud      https://mirrors.aliyun.com/pypi/simple/')"
                echo "  3) $(_t 'USTC https://pypi.mirrors.ustc.edu.cn/simple/')"
                echo "  4) $(_t 'Tencent Cloud      https://mirrors.cloud.tencent.com/pypi/simple')"
                echo "  5) $(_t 'Official PyPI   https://pypi.org/simple                  (restore)')"
                ;;
        esac
        local max_opt=4
        [[ "$eco" == "rust" || "$eco" == "python" ]] && max_opt=5
        local max_range=$((max_opt + 1))
        echo "  ${max_range}) $(_t 'Custom URL input')"
        echo "  0) $(_t 'Cancel')"
        read -r -p "$(_tf 'Enter option [0-%s], default 1:' "${max_range}") " sopt
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
                read -r -p "$(_t 'Enter URL (http(s)://):') " custom
                if [[ "$custom" =~ ^https?:// ]]; then
                    resolve_source "$eco" "$custom" && return 0
                fi
                error "URL $(_t 'is invalid, must start with http:// or https://')"
                continue
                ;;
            *:0) info "$(_t 'Cancelled')"; exit 0 ;;
            *) error "$(_t 'Invalid option')"; sleep 1; continue ;;
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
            error "$(_tf 'Unknown ecosystem: %s (available: %s | all)' "${eco}" "$ECOSYSTEMS")"
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
                info "$(_t 'Target'): $url ($(label_source "$e" "$(src_key_or_url "$e" "$url")"))"
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
                error "$(_tf 'Unrecognized source identifier: %s (ecosystem: %s)' "$src" "$eco")"
                exit 1
            fi
        fi
        info "$(label_eco "$eco") $(_tf 'Target: %s' "$url")"
        [[ "$eco" == "npm" ]] && check_npm_conflict
        echo
        apply_source "$eco" "$url"
    fi
    echo
    success "$(_t 'Mirror switch completed!')"
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
            error "$(_tf 'Unknown ecosystem: %s (available: %s | all)' "${eco}" "$ECOSYSTEMS")"
            exit 1
        fi
    fi
    if [[ "$eco" == "all" ]]; then
        warn "$(_t 'All installed ecosystems will be restored to the official mirror (npm/Go/Rust/Python)')"
    else
        warn "$(_t 'The following ecosystems will be restored to the official mirror:')$(label_eco "$eco")"
    fi
    if ! yes_no "$(_t 'Confirm restore?')"; then
        info "$(_t 'Cancelled')"; return 0
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
    success "$(_t 'Restored to the official mirror')"
}

do_status() {
    detect_os

    # ---- 先计算各生态的镜像状态（不输出），用于聚合并 emit STATE= 首行 ----
    # 每个生态：installed=true/false；mirrored=true/false；value=当前源（用于 EXTRA）
    local npm_installed=false npm_mirrored=false npm_val=""
    if command_exists npm; then
        npm_installed=true
        npm_val=$(npm config get registry 2>/dev/null || _t 'Unknown')
        # 官方源判定：含 registry.npmjs.org 视为未换源
        [[ "$npm_val" == *"registry.npmjs.org"* ]] || npm_mirrored=true
    fi

    local go_installed=false go_mirrored=false go_val=""
    if command_exists go; then
        go_installed=true
        go_val=$(go env GOPROXY 2>/dev/null || _t 'Unknown')
        # 官方源判定：含 proxy.golang.org 视为未换源
        [[ "$go_val" == *"proxy.golang.org"* ]] || go_mirrored=true
    fi

    local rust_installed=false rust_mirrored=false rust_val
    rust_val="$(_t 'Official crates.io')"
    if command_exists cargo; then
        rust_installed=true
        local _reg=""
        if [[ -f "$CARGO_CFG" ]]; then
            _reg=$(cargo_mirror_registry "$CARGO_CFG")
        fi
        if [[ -z "$_reg" ]] && [[ -f "$CARGO_CFG_LEGACY" ]]; then
            _reg=$(cargo_mirror_registry "$CARGO_CFG_LEGACY")
        fi
        if [[ -n "$_reg" ]]; then
            rust_val="$_reg"
            rust_mirrored=true
        fi
    fi

    local py_installed=false py_mirrored=false py_val
    py_val="$(_t 'Official PyPI')"
    local pip_cmd=""
    command_exists pip3 && pip_cmd="pip3"
    [[ -z "$pip_cmd" ]] && command_exists pip && pip_cmd="pip"
    if [[ -n "$pip_cmd" ]]; then
        py_installed=true
        py_val=$("$pip_cmd" config get global.index-url 2>/dev/null || _t 'Official PyPI')
        # 官方源判定：含 pypi.org 视为未换源
        [[ "$py_val" == *"pypi.org"* ]] || py_mirrored=true
    fi

    # ---- 聚合主状态 ----
    # installed_count：已装语言数；mirrored_count：已换源语言数
    # 用 if 包裹（而非顶层 && 链）：set -e 下，$var=false 的顶层命令会以 1 退出导致脚本中止。
    local installed_count=0 mirrored_count=0
    if $npm_installed;  then installed_count=$((installed_count + 1)); $npm_mirrored  && mirrored_count=$((mirrored_count + 1)); fi
    if $go_installed;   then installed_count=$((installed_count + 1)); $go_mirrored   && mirrored_count=$((mirrored_count + 1)); fi
    if $rust_installed; then installed_count=$((installed_count + 1)); $rust_mirrored && mirrored_count=$((mirrored_count + 1)); fi
    if $py_installed;   then installed_count=$((installed_count + 1)); $py_mirrored   && mirrored_count=$((mirrored_count + 1)); fi

    local agg_state agg_msg
    if [[ $installed_count -eq 0 ]]; then
        # 无已装语言工具链：n/a 保留给「平台不适用」；此处用 not_configured（0/0 视为未配置）
        agg_state="not_configured"
        agg_msg="${YELLOW}$(_t 'No installed language toolchain')${NC}"
    elif [[ $mirrored_count -eq $installed_count ]]; then
        agg_state="configured"
        agg_msg="${GREEN}$(_tf 'All installed languages have switched mirrors (%s/%s)' "$mirrored_count" "${installed_count}")${NC}"
    elif [[ $mirrored_count -gt 0 ]]; then
        agg_state="not_configured"
        agg_msg="${YELLOW}$(_tf 'Some languages have switched mirrors (%s/%s)' "$mirrored_count" "${installed_count}")${NC}"
    else
        agg_state="not_configured"
        agg_msg="${RED}$(_tf 'No language has switched mirrors (0/%s)' "${installed_count}")${NC}"
    fi
    emit_status "$agg_state" "$agg_msg"

    # ---- 每语言 EXTRA（key=value）----
    if $npm_installed; then
        emit_extra "npm=$npm_val"
    fi
    if $go_installed; then
        emit_extra "go=$go_val"
    fi
    if $rust_installed; then
        emit_extra "rust=$rust_val"
    fi
    if $py_installed; then
        emit_extra "python=$py_val"
    fi

    # ---- 人类模式：逐语言详情表（调用既有 status_* 函数）----
    if ! uxs_is_machine_mode; then
        echo
        info "npm/yarn/pnpm:"
        status_npm
        info "Go:"
        status_go
        info "Rust:"
        status_rust
        info "Python:"
        status_python
    fi
}

usage() {
    cat <<EOF
用法: $0 {install|uninstall|status|help} [ecosystem] [source]

$(_t 'Development language ecosystem mirror acceleration (npm / Go / Rust / Python).')

  install [ecosystem] [source]   $(_t 'Switch mirror')
    ecosystem: npm | go | rust | python | all$(_t '(default = interactive selection)')
    source:    $(_t 'Built-in source key for each ecosystem (see below) or a full URL (default = interactive selection)')
  uninstall [ecosystem]          $(_t 'Restore the official mirror')
  status                         $(_t 'Show the current mirror of each ecosystem')
  help                           $(_t 'Show this help')

$(_t 'Built-in source keys:')
  npm     : taobao($(_t 'Default) | tencent | huawei | npm/official')
  go      : goproxy-cn($(_t 'Default) | aliyun | goproxy-io | official')
  rust    : tuna($(_t 'Default) | ustc | sjtu | rsproxy | official')
  python  : tuna($(_t 'Default) | aliyun | ustc | tencent | official')

$(_t 'Examples:')
  $0 install                       $(_t '# Interactive: first choose the ecosystem, then the source')
  $0 install go goproxy-cn         $(_t '# Configure goproxy.cn for Go directly')
  $0 install all                   $(_t '# Interactively choose a source for each ecosystem')
  $0 install npm https://my.com/   $(_t '# Custom URL')
  $0 uninstall rust                $(_t '# Restore the official cargo mirror')
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
        status)
            # 状态子命令恒退出 0（AGENTS.md 契约：用于探测，退出码只表示"能不能测"，
            # 不表示"测出来是什么"）。do_status 放 || true 里，
            # 顺带把函数体内的 errexit 一并挂起，内部任何一步失败都不应让探测失败。
            do_status || true
            exit 0
            ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

main "$@"
