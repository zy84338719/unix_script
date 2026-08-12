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

set -euo pipefail
# 历史上不使用 set -u：curl|bash 管道模式下命令替换偶发触发 unbound variable。
# 现已将所有变量引用加 :- 默认值（old_ver/new_ver/ver/rc 等），可安全启用 nounset。
# pipefail：展示用 `... | head -N` 管道已加 `|| true` 兜底 SIGPIPE。

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
        # 已存在：尝试更新（幂等——第二次运行即更新）
        b_info "发现已有安装：$INSTALL_DIR"
        local old_ver="未知"
        old_ver=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "未知")
        b_info "当前版本：${old_ver}，拉取最新更新..."
        if git -C "$INSTALL_DIR" pull --ff-only origin 2>/dev/null; then
            local new_ver="未知"
            new_ver=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "未知")
            if [[ "$old_ver" == "$new_ver" ]]; then
                b_success "已是最新版本（${new_ver}）"
            else
                b_success "已更新：$old_ver → $new_ver"
            fi
        else
            b_warn "fast-forward 更新失败（可能有本地改动或分叉），尝试强制同步..."
            # 安全网：与 install.sh 的 do_self_update 纪律对齐——reset --hard 会丢弃本地改动，
            # 故先 stash create 备份（不改动工作区），给用户一条恢复路径。
            local dirty backup_ref=""
            dirty=$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null || true)
            if [[ -n "$dirty" ]]; then
                backup_ref=$(git -C "$INSTALL_DIR" stash create 2>/dev/null || true)
                if [[ -n "$backup_ref" ]]; then
                    b_warn "检测到本地改动，已备份为 stash：$backup_ref"
                    b_warn "  恢复：cd \"$INSTALL_DIR\" && git stash apply $backup_ref"
                else
                    b_warn "检测到本地改动但无法创建 stash 备份；强制同步将丢失这些改动"
                fi
            fi
            if git -C "$INSTALL_DIR" fetch origin 2>/dev/null && \
               git -C "$INSTALL_DIR" reset --hard origin/main 2>/dev/null; then
                local new_ver="未知"
                new_ver=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "未知")
                b_success "已强制同步：$old_ver → $new_ver"
            else
                b_error "更新失败（网络问题），请稍后重试："
                b_error "  cd \"$INSTALL_DIR\" && git fetch origin && git reset --hard origin/main"
                b_warn "继续使用当前本地版本（${old_ver}）..."
            fi
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

# ---------------- 日常使用提示 ----------------
show_alias_hint() {
    echo
    b_header "💡 日常使用"
    echo "───────────────────────────────"
    b_info "无论首次安装还是日后更新，都用同一条命令（幂等，自动检测并更新）："
    echo "    curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash"
    echo
    b_info "透传参数（非交互，适合脚本/CI）："
    echo "    curl -fsSL .../bootstrap.sh | bash -s -- --status      # 查看安装状态"
    echo "    curl -fsSL .../bootstrap.sh | bash -s -- --list        # 列出可用模块"
    echo "    curl -fsSL .../bootstrap.sh | bash -s -- docker        # 直接安装某模块"
    echo "    curl -fsSL .../bootstrap.sh | bash -s -- dev-mirror    # 开发换源（npm/Go/Rust/pip）"
    echo
    b_info "已克隆到本地后，也可直接在仓库目录运行："
    echo "    cd \"$INSTALL_DIR\""
    echo "    ./install.sh                # 交互式菜单"
    echo "    ./install.sh update         # 更新到最新版本（需确认）"
    echo
    b_info "全局命令 uxs 已安装，重新加载 shell 后可在任意目录使用："
    echo "    source ~/.zshrc 2>/dev/null || source ~/.bashrc 2>/dev/null"
    echo "    uxs --status        # 查看安装状态"
    echo "    uxs docker          # 安装某模块"
    echo "    uxs --list-modules  # 列出模块（AI 友好）"
    echo
    b_info "日后更新仍用同一条命令："
    echo "    curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash"
}

# ---------------- 安装全局命令 uxs ----------------
ensure_cli() {
    local install_script="$INSTALL_DIR/install.sh"
    if [[ ! -f "$install_script" ]]; then
        return 0
    fi
    # 检查 wrapper 文件是否存在（比 command -v 更可靠，因为 ~/.tools/bin 可能不在当前 PATH）
    local wrapper="$HOME/.tools/bin/uxs"
    if [[ -x "$wrapper" ]]; then
        return 0
    fi
    b_info "正在安装全局命令 uxs（之后可在任意目录使用 uxs）..."
    bash "$install_script" cli >/dev/null 2>&1 || true
    if [[ -x "$wrapper" ]]; then
        b_success "uxs 已安装！重新加载 shell 后即可使用"
    else
        b_info "uxs 安装到 ~/.tools/bin，请重新加载 shell：source ~/.zshrc（或 ~/.bashrc）"
    fi
}

# ---------------- 主函数 ----------------
main() {
    b_header "📦 unix_script 一键安装"
    echo "───────────────────────────────"
    check_deps
    clone_or_update

    # 无参数时：更新仓库 + 确保 uxs 已装 + 打印状态摘要（不进交互菜单）
    if [[ $# -eq 0 ]]; then
        ensure_cli
        # 打印安装状态摘要（而非进交互菜单，因为管道模式无法交互）
        local install_script="$INSTALL_DIR/install.sh"
        if [[ -f "$install_script" ]]; then
            b_info "已安装模块状态："
            if bash "$install_script" --help 2>/dev/null | grep -q '\-\-status-json'; then
                # pipefail 下 head -20 提前关管道会触发上游 SIGPIPE → 用 || true 兜底（仅展示用）
                bash "$install_script" --status-json 2>/dev/null | grep -vE '^(os|arch|version):' | head -20 || true
            else
                bash "$install_script" --status 2>/dev/null | head -20 || true
            fi
            echo "    （完整状态：uxs --status）"
            echo
            local ver
            ver=$(bash "$install_script" --version 2>/dev/null | awk '{print $2}')
            b_success "unix_script v${ver} 已就绪！"
        fi
        show_alias_hint
        exit 0
    fi

    # 有参数时：透传给 install.sh
    run_install "$@"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        show_alias_hint
    fi
    exit $rc
}

main "$@"
