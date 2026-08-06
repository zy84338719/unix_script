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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

# 默认导出目录（用户可覆盖）
DEFAULT_OUT_DIR="."

# ---------------- 前置检查 ----------------
preflight() {
    detect_os
    if ! command_exists docker; then
        error "未检测到 docker 命令。请先安装 Docker：./install.sh docker"
        exit 1
    fi
    # docker daemon 必须在运行（docker info 失败说明未启动）
    if ! docker info >/dev/null 2>&1; then
        error "Docker 守护进程未运行。请先启动 Docker："
        error "  Linux: sudo systemctl start docker"
        error "  macOS: 启动 Docker Desktop 应用"
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
    read -r -p "请输入要拉取的镜像名（如 nginx:1.25，回车结束）: " img
    echo "$img"
}

# 问导出目录（默认 DEFAULT_OUT_DIR，校验存在且可写）
prompt_out_dir() {
    local dir
    read -r -p "请输入导出目录（默认 $(pwd)）: " dir
    dir="${dir:-$DEFAULT_OUT_DIR}"
    if [[ ! -d "$dir" ]]; then
        warn "目录不存在：$dir"
        if yes_no "是否创建该目录？"; then
            mkdir -p "$dir" || { error "无法创建目录：$dir"; return 1; }
        else
            error "已取消"
            return 1
        fi
    fi
    if [[ ! -w "$dir" ]]; then
        error "目录不可写：$dir"
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
    read -r -p "请输入导出文件名（默认 $default_fname）: " fname
    fname="${fname:-$default_fname}"
    if ! valid_filename "$fname"; then
        error "文件名非法（不能含 / 或为空）: $fname"
        return 1
    fi
    local target="${out_dir}/${fname}"
    if [[ -e "$target" ]]; then
        warn "文件已存在：$target"
        if ! yes_no "是否覆盖？"; then
            error "已取消"
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
        success "本地已有镜像：$img"
        if ! yes_no "是否重新从公网拉取（覆盖本地）？"; then
            info "跳过拉取，使用本地已有镜像"
            return 0
        fi
    fi
    info "拉取镜像：$img"
    if ! docker pull "$img"; then
        error "拉取失败：$img（镜像名错误或网络问题）"
        return 1
    fi
    success "拉取完成"
    return 0
}

# 导出单个镜像为 gzip 压缩文件，并打印摘要。
# 参数：镜像名 导出目录 文件名
export_one() {
    local img="$1"
    local out_dir="$2"
    local fname="$3"
    local target="${out_dir}/${fname}"

    info "导出镜像 → $target （gzip 压缩）"
    local start_ts end_ts elapsed
    start_ts=$(date +%s)
    # docker save 输出未压缩 tar 流，管道给 gzip 压缩写盘
    if ! docker save "$img" | gzip > "$target"; then
        error "导出失败：$img"
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
    digest=$(docker image inspect "$img" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo "未知")
    if [[ "$digest" == "未知" ]]; then
        digest=$(docker image inspect "$img" --format '{{.Id}}' 2>/dev/null || echo "未知")
    fi

    echo
    header "📦 导出摘要"
    echo "  镜像:   $img"
    echo "  digest: $digest"
    echo "  文件:   $target"
    echo "  大小:   $size"
    echo "  耗时:   ${elapsed}s"
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
        info "未输入镜像名，结束"
        return 1
    fi
    img=$(normalize_image "$img")
    info "目标镜像：$img"
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
    header "📦 Docker 镜像拉取与导出"
    echo "───────────────────────────────"

    # 支持命令行直接传镜像名（跳过第一个交互问询）
    if [[ $# -ge 1 && "$1" != "" ]]; then
        local img
        img=$(normalize_image "$1")
        info "目标镜像（命令行参数）：$img"
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
                : # 单个失败/取消，继续问是否下一个
            fi
            if ! yes_no "是否继续拉取并导出下一个镜像？"; then
                break
            fi
        done
    fi

    # 最终汇总
    echo
    header "📋 本次导出汇总"
    if ((${#EXPORTED_FILES[@]} == 0)); then
        warn "未导出任何文件"
    else
        local f
        for f in "${EXPORTED_FILES[@]}"; do
            success "$f"
        done
        echo
        info "共导出 ${#EXPORTED_FILES[@]} 个文件"
        info "恢复方式：docker load < <文件> （或 gunzip -c <文件> | docker load）"
    fi
}

do_status() {
    detect_os
    local state human_msg ver=""
    if command_exists docker; then
        ver=$(docker --version 2>/dev/null || echo "")
        if docker info >/dev/null 2>&1; then
            state="installed:running"
            human_msg="${GREEN}[SUCCESS]${NC} Docker 已安装且正在运行"
        else
            state="installed:stopped"
            human_msg="${YELLOW}[WARNING]${NC} Docker 已安装但守护进程未运行"
        fi
    else
        state="not_installed"
        human_msg="${RED}[ERROR]${NC} Docker 未安装"
    fi
    if ! uxs_is_machine_mode; then
        echo   # 保留原始首行空行
    fi
    emit_status "$state" "$human_msg"
    [[ -n "$ver" ]] && emit_version "$ver"
    if ! uxs_is_machine_mode; then
        # 人类模式：运行态额外打印 docker --version（success 消息已由 emit_status 输出）
        if [[ "$state" == "installed:running" ]] && [[ -n "$ver" ]]; then
            echo "$ver"
        fi
    fi
}

usage() {
    cat <<EOF
用法: $0 {save|status|help} [镜像名]

  save [镜像名]   拉取并导出镜像为 .tar.gz（默认交互；可传入镜像名跳过首问）
  status          检查 Docker 是否已安装并运行
  help            显示本帮助

示例:
  $0 save                      # 交互式：逐步问镜像名/目录/文件名
  $0 save nginx:1.25           # 直接指定镜像，仍问目录与文件名
  $0 status

导出文件为 gzip 压缩的 tar，恢复命令：
  docker load < xxx.tar.gz
EOF
}

main() {
    local action="${1:-help}"
    case "$action" in
        save)    shift || true; do_save "$@" ;;
        status)  do_status ;;
        help|--help|-h) usage ;;
        *) error "未知操作: $action"; usage; exit 1 ;;
    esac
}

main "$@"
