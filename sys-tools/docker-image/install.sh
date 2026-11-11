#!/usr/bin/env bash
#
# docker-image/install.sh
#
# 从公网拉取 Docker 镜像并导出为本地压缩文件（.tar.gz），便于离线分发/备份。
#
# 交互流程：镜像名 →（本地已有时询问是否重拉）→ 导出目录 → 文件名 →
#          docker pull → docker save | gzip → 显示摘要 → 是否继续下一个。
#
# Linux + macOS。要求本机已安装并运行 Docker。
#
# 子命令：save | status | help
#   save    拉取并导出镜像（默认交互；支持参数：save <镜像名>）
#   status  检查 Docker 是否可用
#   help    显示帮助
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 默认导出目录（用户可覆盖）
DEFAULT_OUT_DIR="."

# ---------------- 前置检查 ----------------
preflight() {
    detect_os
    if ! os_has_cmd docker; then
        error "$(_t 'The docker command was not found. Install Docker first: ./install.sh docker')"
        exit 1
    fi
    # docker daemon 必须在运行（docker info 失败说明未启动）
    if ! docker info >/dev/null 2>&1; then
        error "Docker $(_t 'The daemon is not running. Start Docker first:')"
        error "  Linux: sudo systemctl start docker"
        error "  macOS: $(_t 'Start the Docker Desktop app')"
        exit 1
    fi
}

# 规范化镜像名：无 tag 时补 :latest
normalize_image() {
    local img="$1"
    # 含冒号且冒号后非空 → 已有 tag；否则补 latest
    # 注意 registry:5000/myimg 这种含端口号的情况：仅当最后一段无冒号或冒号后为空才补
    local last_part
    last_part="${img##*/}"
    if [[ "$last_part" != *:* ]]; then
        img="${img}:latest"
    fi
    echo "$img"
}

# 由镜像名生成安全的默认文件名（/ : 转为 _，加 .tar.gz 后缀）
default_filename() {
    local img="$1"
    local name
    name="${img//\//_}"     # / → _
    name="${name//:/_}"     # : → _
    echo "${name}.tar.gz"
}

# 校验文件名合法（不含路径分隔符 / 与空字符，非空）
valid_filename() {
    local name="$1"
    [[ -n "$name" && "$name" != *"/"* && "$name" != *$'\n'* ]]
}

# 问镜像名（返回到 stdout；用户直接回车则返回空表示结束）
prompt_image() {
    local img
    read -r -p "$(_t 'Enter the image name to pull (e.g. nginx:1.25, press Enter to finish):') " img
    echo "$img"
}

# 问导出目录（默认 DEFAULT_OUT_DIR，校验存在且可写）
prompt_out_dir() {
    local dir
    read -r -p "$(_tf 'Enter the export directory (default %s):' "$PWD") " dir
    dir="${dir:-$DEFAULT_OUT_DIR}"
    if [[ ! -d "$dir" ]]; then
        warn "$(_tf 'The directory does not exist: %s' "$dir")"
        if yes_no "$(_t 'Create it?')"; then
            mkdir -p "$dir" || { error "$(_tf 'Cannot create the directory: %s' "$dir")"; return 1; }
        else
            error "$(_t 'Cancelled')"
            return 1
        fi
    fi
    if [[ ! -w "$dir" ]]; then
        error "$(_tf 'The directory is not writable: %s' "$dir")"
        return 1
    fi
    echo "$dir"
}

# 问文件名（默认 default_filename，校验合法；文件已存在则询问覆盖）
prompt_filename() {
    local img="$1"
    local out_dir="$2"
    local default_fname
    default_fname=$(default_filename "$img")
    local fname
    read -r -p "$(_tf 'Enter the export file name (default %s):' "${default_fname}") " fname
    fname="${fname:-$default_fname}"
    if ! valid_filename "$fname"; then
        error "$(_tf 'Invalid file name (it must not contain / and must not be empty): %s' "$fname")"
        return 1
    fi
    local target="${out_dir}/${fname}"
    if [[ -e "$target" ]]; then
        warn "$(_tf 'The file already exists: %s' "$target")"
        if ! yes_no "$(_t 'Overwrite it?')"; then
            error "$(_t 'Cancelled')"
            return 1
        fi
    fi
    echo "$fname"
}

# 拉取单个镜像（含本地已有时询问）。
# 返回 0 表示继续导出，1 表示跳过。
pull_one() {
    local img="$1"
    # 检查本地是否已有
    if docker image inspect "$img" >/dev/null 2>&1; then
        success "$(_tf 'The image is already present locally: %s' "$img")"
        if ! yes_no "$(_t 'Pull it again from the public registry (overwriting the local one)?')"; then
            info "$(_t 'Skipped the pull, using the local image')"
            return 0
        fi
    fi
    info "$(_tf 'Pulling the image: %s' "$img")"
    if ! docker pull "$img"; then
        error "$(_tf 'Pull failed: %s (wrong image name or network problem)' "${img}")"
        return 1
    fi
    success "$(_t 'Pull complete')"
    return 0
}

# 导出单个镜像为 gzip 压缩文件，并打印摘要。
# 参数：镜像名 导出目录 文件名
export_one() {
    local img="$1"
    local out_dir="$2"
    local fname="$3"
    local target="${out_dir}/${fname}"

    info "$(_tf 'Export the image → %s (gzip compressed)' "$target")"
    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    # docker save 输出未压缩 tar 流，管道给 gzip 压缩写盘
    if ! docker save "$img" | gzip > "$target"; then
        error "$(_tf 'Export failed: %s' "$img")"
        rm -f "$target" 2>/dev/null || true
        return 1
    fi
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))

    # 文件大小（人类可读）
    local size
    if [[ "$OS_TYPE" == "darwin" ]]; then
        # macOS：用 stat 取字节数再转换
        local bytes
        bytes=$(stat -f%z "$target" 2>/dev/null || echo 0)
        size=$(human_size "$bytes")
    else
        size=$(du -h "$target" | cut -f1)
    fi

    # 镜像 digest（可能为多个，取第一个）
    local digest
    digest=$(docker image inspect "$img" --format '{{index .RepoDigests 0}}' 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
    if [[ "$digest" == "$(_t 'Unknown')" ]]; then
        digest=$(docker image inspect "$img" --format '{{.Id}}' 2>/dev/null || printf '%s\n' "$(_t 'Unknown')")
    fi

    echo
    header "$(_t '📦 Export summary')"
    echo "  $(_tf 'Image:   %s' "$img")"
    echo "  digest: $digest"
    echo "  $(_tf 'File:   %s' "$target")"
    echo "  $(_tf 'Size:   %s' "$size")"
    echo "  $(_tf 'Elapsed:   %ss' "${elapsed}")"
    return 0
}

# 字节数 → 人类可读（KB/MB/GB），纯整数运算，兼容 bash 3.2
human_size() {
    local bytes="$1"
    if [[ -z "$bytes" || "$bytes" -le 0 ]] 2>/dev/null; then
        echo "0B"
        return
    fi
    local unit="B"
    local size="$bytes"
    # 依次除以 1024 直到不足 1024 或到达 GB
    if (( size >= 1024 )); then
        size=$(( size / 1024 )); unit="KB"
    fi
    if (( size >= 1024 )); then
        size=$(( size / 1024 )); unit="MB"
    fi
    if (( size >= 1024 )); then
        size=$(( size / 1024 )); unit="GB"
    fi
    echo "${size}${unit}"
}

# 记录本次会话成功导出的文件（用于最终汇总）
EXPORTED_FILES=()

# ---------------- 主流程：拉取并导出一个镜像（循环）----------------
do_save_one() {
    local img
    img=$(prompt_image)
    img="${img%$'\n'}"
    if [[ -z "${img// /}" ]]; then
        info "$(_t 'No image name entered, exiting')"
        return 1
    fi
    img=$(normalize_image "$img")
    info "$(_tf 'Target image: %s' "$img")"
    echo

    # 拉取
    if ! pull_one "$img"; then
        return 1
    fi

    # 导出目录
    local out_dir
    if ! out_dir=$(prompt_out_dir); then
        return 1
    fi

    # 文件名
    local fname
    if ! fname=$(prompt_filename "$img" "$out_dir"); then
        return 1
    fi
    echo

    # 导出
    if export_one "$img" "$out_dir" "$fname"; then
        EXPORTED_FILES+=("${out_dir}/${fname}")
        return 0
    fi
    return 1
}

do_save() {
    preflight
    header "$(_t '📦 Docker image pull and export')"
    echo "───────────────────────────────"

    # 支持命令行直接传镜像名（跳过第一个交互问询）
    if [[ $# -ge 1 && "$1" != "" ]]; then
        local img
        img=$(normalize_image "$1")
        info "$(_tf 'Target image (command line argument): %s' "$img")"
        echo
        local out_dir fname
        if pull_one "$img" \
            && out_dir=$(prompt_out_dir) \
            && fname=$(prompt_filename "$img" "$out_dir"); then
            echo
            if export_one "$img" "$out_dir" "$fname"; then
                EXPORTED_FILES+=("${out_dir}/${fname}")
            fi
        fi
    else
        # 纯交互：循环逐个处理
        while true; do
            echo
            if ! do_save_one; then
                # 单个失败/取消，继续问是否下一个
                :
            fi
            if ! yes_no "$(_t 'Continue pulling and exporting the next image?')"; then
                break
            fi
        done
    fi

    # 最终汇总
    echo
    header "$(_t '📋 Export summary of this run')"
    if ((${#EXPORTED_FILES[@]} == 0)); then
        warn "$(_t 'No file was exported')"
    else
        local f
        for f in "${EXPORTED_FILES[@]}"; do
            success "$f"
        done
        echo
        info "$(_tf '%s file(s) exported in total' "${#EXPORTED_FILES[@]}")"
        info "$(_t 'How to restore: docker load < <file> (or gunzip -c <file> | docker load)')"
    fi
}

do_status() {
    detect_os
    local state human_msg ver=""
    if os_has_cmd docker; then
        ver=$(docker --version 2>/dev/null || echo "")
        # docker info 在守护进程挂起时实测可阻塞 90s+（黑洞地址实测 93.3s），
        # 套 5s 超时护栏（同 services/docker）：超时按未运行降级
        if run_timeout 5 docker info >/dev/null 2>&1; then
            state="installed:running"
            human_msg="${GREEN}[SUCCESS]${NC} Docker $(_t 'Installed and currently running')"
        else
            state="installed:stopped"
            human_msg="${YELLOW}[WARNING]${NC} Docker $(_t 'Installed but the daemon is not running')"
        fi
    else
        state="not_installed"
        human_msg="${RED}[ERROR]${NC} Docker $(_t 'Not installed')"
    fi
    if ! uxs_is_machine_mode; then
        # 保留原始首行空行
        echo
    fi
    uxs_emit_status "$state" "$human_msg"
    [[ -n "$ver" ]] && uxs_emit_version "$ver"
    if ! uxs_is_machine_mode; then
        # 人类模式：运行态额外打印 docker --version（success 消息已由 uxs_emit_status 输出）
        if [[ "$state" == "installed:running" ]] && [[ -n "$ver" ]]; then
            echo "$ver"
        fi
    fi
}

usage() {
    cat <<EOF
用法: $0 {save|status|help} [镜像名]

  save [$(_t 'Image name]   Pull and export the image as .tar.gz (interactive by default; pass an image name to skip the first prompt)')
  status          $(_t 'Check whether Docker is installed and running')
  help            $(_t 'Show this help')

$(_t 'Examples:')
  $0 save                      $(_t '# Interactive: ask for the image name, the directory and the file name step by step')
  $0 save nginx:1.25           $(_t '# Give the image directly, still ask for the directory and the file name')
  $0 status

$(_t 'The exported file is a gzip-compressed tar, restore command:')
  docker load < xxx.tar.gz
EOF
}

main() {
    local action="${1:-help}"
    case "$action" in
        save)    shift || true; do_save "$@" ;;
        status)  do_status ;;
        # 本模块仅「导出」镜像为 .tar.gz 产物，不安装任何持久组件/服务/配置；
        # 导出的文件由用户保留（可用于 docker load 恢复），故 uninstall 为文档化 no-op。
        uninstall) info "docker-image $(_t 'This module only exports image artifacts and installs no persistent component; delete the exported .tar.gz files manually when they are no longer needed')" ;;
        help|--help|-h) usage ;;
        *) error "$(_tf 'Unknown action: %s' "$action")"; usage; exit 1 ;;
    esac
}

main "$@"
