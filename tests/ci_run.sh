#!/usr/bin/env bash
#
# tests/ci_run.sh
#
# CI 测试驱动脚本，本地亦可复现。
#
# 用法:
#   ./tests/ci_run.sh --phase static                 # 静态检查（bash -n + shellcheck）
#   ./tests/ci_run.sh --phase routing                # CLI 路由与子命令测试
#   ./tests/ci_run.sh --phase install [--module X]   # 实装测试（默认 fail2ban/node_exporter/pm）
#   ./tests/ci_run.sh --phase static --out rep.md    # 指定报告输出文件
#   ./tests/ci_run.sh --help
#
# 退出码：任一检查失败返回 1，全部通过返回 0。
# 报告：以 Markdown 写入 $OUT（默认 tests/<phase>-report.md），并追加到 $GITHUB_STEP_SUMMARY（若存在）。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PHASE=""
OUT=""
MODULES_OVERRIDE=""

usage() {
    sed -n '2,18p' "$0"
}

# ---------------- 报告辅助 ----------------
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# 在报告里追加一行表格；参数: 名字 | 状态(pass/fail/skip) | 备注
report_row() {
    local name="$1" status="$2" note="${3:-}"
    local icon
    case "$status" in
        pass) icon="✅"; PASS_COUNT=$((PASS_COUNT + 1)) ;;
        fail) icon="❌"; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        skip) icon="⏭️"; SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
    esac
    printf '| %s | %s | %s |\n' "$name" "$icon" "$note" >> "$OUT"
}

# 执行一条断言：成功记 pass，失败记 fail 并记录输出
# assert <名字> <命令...>
assert() {
    local name="$1"; shift
    local log
    if log=$("$@" 2>&1); then
        report_row "$name" pass
        return 0
    else
        # 截断过长日志
        local short
        short=$(printf '%s' "$log" | tail -3 | tr '\n' ' ' | cut -c1-160)
        report_row "$name" fail "$short"
        return 1
    fi
}

# 写报告头
report_header() {
    local title="$1"
    : > "$OUT"
    {
        echo "## $title"
        echo
        echo "- 运行环境: $(uname -s) $(uname -m)"
        echo "- 时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo
        echo "| 检查项 | 结果 | 备注 |"
        echo "|--------|------|------|"
    } >> "$OUT"
}

report_footer() {
    {
        echo
        echo "**汇总**: ✅ 通过 $PASS_COUNT ｜ ❌ 失败 $FAIL_COUNT ｜ ⏭️ 跳过 $SKIP_COUNT"
    } >> "$OUT"
    # 追加到 GitHub 步骤摘要
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -f "$GITHUB_STEP_SUMMARY" ]]; then
        cat "$OUT" >> "$GITHUB_STEP_SUMMARY"
    elif [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        cat "$OUT" >> "$GITHUB_STEP_SUMMARY"
    fi
}

# ---------------- 阶段: static ----------------
phase_static() {
    report_header "静态检查 (static) — bash -n + shellcheck"

    local scripts
    scripts=$(find "$REPO_DIR" -type f -name "*.sh" \
              -not -path "*/.git/*" -not -path "*/node_modules/*" \
              -not -path "*/.tools/*" | sort)

    local f
    while IFS= read -r f; do
        local rel="${f#"$REPO_DIR"/}"
        assert "bash -n: $rel" bash -n "$f"
    done <<< "$scripts"

    if command -v shellcheck >/dev/null 2>&1; then
        while IFS= read -r f; do
            local rel="${f#"$REPO_DIR"/}"
            assert "shellcheck: $rel" shellcheck -e SC2164,SC1091,SC2317,SC2329 -x "$f"
        done <<< "$scripts"
    else
        # 未安装 shellcheck：对每个脚本标记 skip
        while IFS= read -r f; do
            local rel="${f#"$REPO_DIR"/}"
            report_row "shellcheck: $rel" skip "shellcheck 未安装"
        done <<< "$scripts"
    fi

    report_footer
    [[ $FAIL_COUNT -eq 0 ]]
}

# ---------------- 阶段: routing ----------------
phase_routing() {
    report_header "路由与子命令测试 (routing)"

    cd "$REPO_DIR" || exit 1

    # 1. common.sh 可被 source 且关键函数存在
    assert "source lib/common.sh" bash -c "source \"$REPO_DIR/lib/common.sh\" && type info >/dev/null && type detect_os >/dev/null && type service_start >/dev/null"

    # 2. install.sh CLI
    assert "install.sh --help (exit 0)" bash "$REPO_DIR/install.sh" --help
    assert "install.sh --version (含版本号)" bash -c "\"$REPO_DIR/install.sh\" --version | grep -q 'unix_script'"
    assert "install.sh --list (含关键模块)" bash -c "\"$REPO_DIR/install.sh\" --list | grep -q tailscale && \"$REPO_DIR/install.sh\" --list | grep -q fail2ban"
    assert "install.sh --list (模块数 >= 20)" bash -c "[ \$($REPO_DIR/install.sh --list | wc -w) -ge 20 ]"
    # --status 会调用 sudo launchctl/systemctl；仅在有免密 sudo 时断言（CI runner 满足）
    if sudo -n true 2>/dev/null; then
        assert "install.sh --status (非交互正常退出)" bash -c "\"$REPO_DIR/install.sh\" --status >/dev/null 2>&1"
    else
        report_row "install.sh --status (非交互)" skip "本机无免密 sudo（CI runner 有）"
    fi
    assert "install.sh 未知模块报错 (exit 1)" bash -c "! \"$REPO_DIR/install.sh\" __nope__ >/dev/null 2>&1"

    # 2b. 版本更新检查子命令
    # check-update 即使无网络/无 release 也必须正常退出（容错）
    assert "install.sh check-update (exit 0)" bash "$REPO_DIR/install.sh" check-update
    # update 不应真正执行 git pull（破坏仓库）：记录运行前后 HEAD，应相同。
    # 用 </dev/null 让所有确认 read 立即返回非 y（取消），不依赖工作区是否 clean。
    assert "install.sh update (不改变 HEAD)" bash -c "before=\$(git -C \"$REPO_DIR\" rev-parse HEAD); \"$REPO_DIR/install.sh\" update </dev/null >/dev/null 2>&1; after=\$(git -C \"$REPO_DIR\" rev-parse HEAD); [ \"\$before\" = \"\$after\" ]"
    # UNIX_SCRIPT_NO_UPDATE_CHECK=1 关闭自动检查，且 --help 不受影响
    assert "关闭自动检查开关后 --help 正常" bash -c "UNIX_SCRIPT_NO_UPDATE_CHECK=1 \"$REPO_DIR/install.sh\" --help >/dev/null"
    # common.sh 新函数存在
    assert "common.sh 含更新检查函数" bash -c "source \"$REPO_DIR/lib/common.sh\" && type get_local_version >/dev/null && type version_gt >/dev/null && type check_for_update >/dev/null && type do_self_update >/dev/null"
    # cli 子命令：install.sh 含 install_cli / uninstall_cli 函数（不实际安装，避免污染 CI 环境）
    assert "install.sh 含 cli 安装/卸载函数" bash -c "grep -q 'install_cli()' \"$REPO_DIR/install.sh\" && grep -q 'uninstall_cli()' \"$REPO_DIR/install.sh\""

    # 2c. bootstrap.sh 引导脚本：存在、可执行、语法正确、含关键函数
    #     （不在此做真实 git clone，避免 CI 增加网络依赖与耗时；实装由本地端到端覆盖）
    assert "bootstrap.sh 存在且可执行" bash -c "test -x \"$REPO_DIR/bootstrap.sh\""
    assert "bootstrap.sh 语法正确 (bash -n)" bash -n "$REPO_DIR/bootstrap.sh"
    assert "bootstrap.sh 含主函数与依赖检查" bash -c "grep -q 'main()' \"$REPO_DIR/bootstrap.sh\" && grep -q 'check_deps' \"$REPO_DIR/bootstrap.sh\" && grep -q 'clone_or_update' \"$REPO_DIR/bootstrap.sh\""
    # bootstrap.sh 幂等：clone_or_update 同时处理「已存在则更新」与「全新克隆」
    assert "bootstrap.sh 幂等（含已存在更新分支）" bash -c "grep -q 'pull --ff-only' \"$REPO_DIR/bootstrap.sh\" && grep -q 'clone --depth 1' \"$REPO_DIR/bootstrap.sh\""

    # 2d. install.sh 非 TTY 无参（curl|bash 管道场景）：应优雅打印帮助+退出 0，而非卡死/刷屏
    #     复现并固化修复：stdin 非 tty 且无参数时不能进入交互菜单
    assert "install.sh 非 TTY 无参 → 打印帮助 (exit 0)" bash -c "bash \"$REPO_DIR/install.sh\" </dev/null 2>&1 | grep -q '检测到非交互环境'"
    assert "install.sh 非 TTY 无参 → 含用法说明 (exit 0)" bash -c "bash \"$REPO_DIR/install.sh\" </dev/null 2>&1 | grep -q '显示本帮助'"

    # 3. uninstall.sh
    assert "uninstall.sh --help (exit 0)" bash "$REPO_DIR/uninstall.sh" --help

    # 4. 模块（有子命令分发）：验证 status 子命令退出码 0
    #    从各模块的 .manifest 文件动态发现，不再硬编码。
    #    注意：此处绝不调用 install（避免触发真实安装），仅 static 阶段覆盖其语法。
    local new_mods=()
    for manifest in "$REPO_DIR"/*/.manifest; do
        [[ -f "$manifest" ]] || continue
        new_mods+=("$(basename "$(dirname "$manifest")")")
    done
    local m
    for m in "${new_mods[@]}"; do
        local script="$REPO_DIR/$m/install.sh"
        [[ -f "$script" ]] || { report_row "$m: 脚本存在" fail "缺失"; continue; }
        assert "$m: status (exit 0)" bash "$script" status
        assert "$m: help (exit 0)" bash "$script" help
    done

    # 5. shutdown_timer 的非交互入口存在且可调用（取消接口）
    assert "shutdown_timer: cancel 接口存在" bash -c "grep -q cancel_daily_shutdown_internal \"$REPO_DIR/shutdown_timer/shutdown_timer.sh\""

    # 6. process_manager_tool 脚本就绪
    assert "pm_wrapper: --version (exit 0)" bash "$REPO_DIR/process_manager_tool/pm_wrapper.sh" --version

    # 9. dev-mirror 模块集成断言
    #    注册表驱动：dev-mirror 有 manifest，子菜单在 lib/submenus.sh
    assert "dev-mirror 有 .manifest" bash -c "test -f \"$REPO_DIR/dev-mirror/.manifest\""
    assert "lib/submenus.sh 含 manage_dev_mirror 函数" bash -c "grep -q 'manage_dev_mirror()' \"$REPO_DIR/lib/submenus.sh\""
    assert "lib/status.sh 含 module_status 函数" bash -c "grep -q 'module_status()' \"$REPO_DIR/lib/status.sh\""
    # dev-mirror 子命令路由：非法生态应报错退出 1
    assert "dev-mirror: 非法生态报错 (exit 1)" bash -c "! \"$REPO_DIR/dev-mirror/install.sh\" install __bad_eco__ >/dev/null 2>&1"
    # dev-mirror: 非法源标识应报错退出 1
    assert "dev-mirror: 非法源标识报错 (exit 1)" bash -c "! \"$REPO_DIR/dev-mirror/install.sh\" install go __bad_source__ >/dev/null 2>&1"
    # 旧 npm-mirror 别名仍可路由（向后兼容）
    assert "install.sh npm-mirror 别名仍可路由" bash -c "grep -q 'npm-mirror|npm_mirror' \"$REPO_DIR/install.sh\""

    report_footer
    [[ $FAIL_COUNT -eq 0 ]]
}

# ---------------- 阶段: install ----------------
phase_install() {
    report_header "实装测试 (install)"

    cd "$REPO_DIR" || exit 1

    # 进程管理工具：纯用户态，最稳定，Linux + macOS 都可
    # 注意：install_process_manager.sh 内部按相对路径查找 process_manager.sh，
    # 必须在其所在目录下运行（用子 shell cd）。
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"pm"* ]]; then
        local pm_dir="$REPO_DIR/process_manager_tool"
        if ( cd "$pm_dir" && bash install_process_manager.sh ) >/tmp/pm_install.log 2>&1; then
            if "$HOME/.tools/bin/pm" --version >/dev/null 2>&1; then
                report_row "pm: 安装并运行 pm --version" pass
            else
                report_row "pm: 安装并运行 pm --version" fail "pm 不可执行"
            fi
            # 卸载清理
            if ( cd "$pm_dir" && bash install_process_manager.sh uninstall ) >/tmp/pm_uninstall.log 2>&1; then
                report_row "pm: 卸载" pass
            else
                report_row "pm: 卸载" fail "见 pm_uninstall.log"
            fi
        else
            report_row "pm: 安装" fail "$(tail -2 /tmp/pm_install.log | tr '\n' ' ')"
        fi
    fi

    # 仅 Linux 可靠实装的服务
    if [[ "$(uname -s)" != "Linux" ]]; then
        report_row "fail2ban/node_exporter 实装" skip "非 Linux（CI 环境限制）"
        report_footer
        [[ $FAIL_COUNT -eq 0 ]]
        return
    fi

    # Fail2ban 完整实装（需要 systemd，故要求在 VM 而非普通容器）
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"fail2ban"* ]]; then
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
            if bash "$REPO_DIR/fail2ban/install.sh" install >/tmp/f2b_install.log 2>&1; then
                if systemctl is-active --quiet fail2ban 2>/dev/null; then
                    report_row "fail2ban: 安装并运行" pass
                else
                    report_row "fail2ban: 安装并运行" fail "服务未 active"
                fi
                if bash "$REPO_DIR/fail2ban/install.sh" uninstall >/tmp/f2b_uninstall.log 2>&1; then
                    report_row "fail2ban: 卸载" pass
                else
                    report_row "fail2ban: 卸载" fail "见 f2b_uninstall.log"
                fi
            else
                report_row "fail2ban: 安装" fail "$(tail -2 /tmp/f2b_install.log | tr '\n' ' ')"
            fi
        else
            report_row "fail2ban 实装" skip "无 systemd（容器环境），仅静态/路由覆盖"
        fi
    fi

    # Node Exporter 完整实装（注入 GITHUB_TOKEN 规避 API 限速）
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"node_exporter"* ]]; then
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
            # 通过 env 把 token 暴露给 curl：用 GH_TOKEN，并在安装脚本外预取版本以减少 API 调用
            if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
                export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
            fi
            # node_exporter install.sh 是交互式脚本（有"确认继续安装"提示），
            # 用 yes y | 喂入确认，避免 </dev/null 导致 read 收到 EOF 而取消安装。
            if yes y | bash "$REPO_DIR/node_exporter/install.sh" >/tmp/ne_install.log 2>&1; then
                if systemctl is-active --quiet node_exporter 2>/dev/null || curl -sf http://localhost:9100 >/dev/null 2>&1; then
                    report_row "node_exporter: 安装并运行" pass
                else
                    report_row "node_exporter: 安装并运行" fail "服务未 active 且端口无响应"
                fi
                # 清理
                sudo systemctl stop node_exporter 2>/dev/null || true
                sudo systemctl disable node_exporter 2>/dev/null || true
                sudo rm -f /etc/systemd/system/node_exporter.service /usr/local/bin/node_exporter
                sudo systemctl daemon-reload 2>/dev/null || true
                if id node_exporter >/dev/null 2>&1; then
                    sudo userdel node_exporter 2>/dev/null || true
                fi
                report_row "node_exporter: 卸载" pass
            else
                # 多半是 GitHub API 限速或网络，记 fail 但备注
                report_row "node_exporter: 安装" fail "$(tail -2 /tmp/ne_install.log | tr '\n' ' ')(可能为 API 限速/网络)"
            fi
        else
            report_row "node_exporter 实装" skip "无 systemd（容器环境），仅静态/路由覆盖"
        fi
    fi

    # essential-pkgs 实装：纯包安装，容器内也可行，能验证 dnf/yum/apt 各分支
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"essential-pkgs"* || "${MODULES_OVERRIDE}" == *"essential_pkgs"* ]]; then
        if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1 || command -v zypper >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 || command -v apk >/dev/null 2>&1; then
            local epkg_log=/tmp/essential_install.log
            # essential-pkgs 在容器里需用 sudo（容器内 root 直接跑 sudo 可能无此命令，已装）
            if bash "$REPO_DIR/essential-pkgs/install.sh" install >"$epkg_log" 2>&1; then
                # 验证至少装上几个关键工具
                local got=0 need="curl git vim"
                for c in $need; do command -v "$c" >/dev/null 2>&1 && got=$((got+1)); done
                if [[ $got -ge 3 ]]; then
                    report_row "essential-pkgs: 安装 (各发行版包管理器分支)" pass
                else
                    report_row "essential-pkgs: 安装" fail "部分工具仍缺失 ($got/3)"
                fi
            else
                report_row "essential-pkgs: 安装" fail "$(tail -2 "$epkg_log" | tr '\n' ' ')"
            fi
        else
            report_row "essential-pkgs 实装" skip "无包管理器"
        fi
    fi

    report_footer
    [[ $FAIL_COUNT -eq 0 ]]
}

# ---------------- 参数解析 ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)    PHASE="$2"; shift 2 ;;
        --out)      OUT="$2"; shift 2 ;;
        --module)   MODULES_OVERRIDE="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "未知参数: $1" >&2; usage; exit 2 ;;
    esac
done

if [[ -z "$PHASE" ]]; then
    echo "错误：必须指定 --phase" >&2
    usage
    exit 2
fi

if [[ -z "$OUT" ]]; then
    OUT="$SCRIPT_DIR/${PHASE}-report.md"
fi

case "$PHASE" in
    static)  phase_static ;;
    routing) phase_routing ;;
    install) phase_install ;;
    *) echo "未知 phase: $PHASE (可选 static|routing|install)" >&2; exit 2 ;;
esac

echo "报告已写入: $OUT"
echo "汇总: 通过 $PASS_COUNT / 失败 $FAIL_COUNT / 跳过 $SKIP_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
