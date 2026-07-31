#!/usr/bin/env bash
#
# bootstrap.sh
#
# 一键安装引导脚本：无需手动 git clone，一行命令拉起 install.sh。
#
# 用法（终端粘贴即可）：
#   curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- docker
#   curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- --help
#
# 行为：
#   1. 检查 git/bash/curl 依赖
#   2. 克隆仓库到固定目录（~/.local/share/unix_script）；已存在则 git pull 更新
#   3. 启动 install.sh，透传所有参数
#
# 可用环境变量覆盖默认值：
#   UNIX_SCRIPT_INSTALL_DIR  安装目录（默认 ~/.local/share/unix_script）
#   UNIX_SCRIPT_REPO_URL     仓库地址（默认 HTTPS）
#

set -u

# ---------------- 配置 ----------------
REPO_URL="${UNIX_SCRIPT_REPO_URL:-https://github.com/zy84338719/unix_script.git}"
INSTALL_DIR="${UNIX_SCRIPT_INSTALL_DIR:-$HOME/.local/share/unix_script}"

# ---------------- 颜色 / 打印 ----------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi
b_info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
b_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
b_warn()    { printf "${YELLOW}[WARNING]${NC} %s\n" "$*"; }
b_error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
b_header()  { printf "${CYAN}%s${NC}\n" "$*"; }

# ---------------- 依赖检查 ----------------
check_deps() {
    local missing=()
    command -v bash  >/dev/null 2>&1 || missing+=(bash)
    command -v git   >/dev/null 2>&1 || missing+=(git)
    command -v curl  >/dev/null 2>&1 || missing+=(curl)
    if ((${#missing[@]} > 0)); then
        b_error "缺少必要命令：${missing[*]}"
        b_error "请先安装后再运行本脚本。"
        exit 1
    fi
}

# ---------------- 克隆或更新仓库 ----------------
clone_or_update() {
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        # 已存在：尝试更新
        b_info "发现已有安装：$INSTALL_DIR"
        b_info "拉取最新更新..."
        if git -C "$INSTALL_DIR" pull --ff-only origin 2>/dev/null; then
            b_success "已更新到最新版本"
        else
            b_warn "自动更新失败（可能有本地改动或网络问题）。"
            b_warn "可手动进入目录处理：cd \"$INSTALL_DIR\" && git pull"
            b_warn "继续使用当前本地版本..."
        fi
    elif [[ -e "$INSTALL_DIR" ]]; then
        # 目录存在但不是 git 仓库
        b_error "目标目录已存在且不是 git 仓库：$INSTALL_DIR"
        b_error "请备份/删除该目录后重试：rm -rf \"$INSTALL_DIR\""
        exit 1
    else
        # 全新克隆（浅克隆省流量）
        b_info "克隆仓库到：$INSTALL_DIR"
        b_info "（使用 --depth 1 浅克隆以节省流量）"
        local parent_dir
        parent_dir="$(dirname "$INSTALL_DIR")"
        mkdir -p "$parent_dir" || { b_error "无法创建父目录：$parent_dir"; exit 1; }
        if ! git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
            b_error "克隆失败：$REPO_URL"
            b_error "请检查网络连接，或手动克隆：git clone $REPO_URL \"$INSTALL_DIR\""
            exit 1
        fi
        b_success "克隆完成"
    fi
}

# ---------------- 启动安装 ----------------
run_install() {
    local install_script="$INSTALL_DIR/install.sh"
    if [[ ! -f "$install_script" ]]; then
        b_error "未找到安装脚本：$install_script"
        exit 1
    fi
    # 透传所有参数给 install.sh
    b_header "🚀 启动安装..."
    cd "$INSTALL_DIR" || { b_error "无法进入目录：$INSTALL_DIR"; exit 1; }
    bash "$install_script" "$@"
}

# ---------------- 提示别名 ----------------
show_alias_hint() {
    local bin_link="$HOME/.local/bin/unix_script"
    echo
    b_info "提示：为方便日后使用，可创建一个全局命令别名："
    echo "    mkdir -p ~/.local/bin && ln -sf \"$INSTALL_DIR/install.sh\" \"$bin_link\""
    echo "    # 确保 ~/.local/bin 在你的 PATH 中（多数发行版默认已包含）"
    echo "    # 之后即可直接：unix_script docker   或   unix_script --status"
}

# ---------------- 主函数 ----------------
main() {
    b_header "📦 unix_script 一键安装"
    echo "───────────────────────────────"
    check_deps
    clone_or_update
    run_install "$@"
    # 安装脚本退出码非 0 时不显示别名提示（避免干扰错误信息）
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        show_alias_hint
    fi
    exit $rc
}

main "$@"
