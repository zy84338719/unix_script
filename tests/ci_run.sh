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
# 报告：以 Markdown 写入 ${OUT}（默认 tests/<phase>-report.md），并追加到 ${GITHUB_STEP_SUMMARY}（若存在）。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PHASE=""
OUT=""
MODULES_OVERRIDE=""

usage() {
    sed -n '2,18p' "$0"
}

# ---------------- 模块路径解析 ----------------
# 分类目录列表
CATEGORY_DIRS="services essentials dev-tools ai-tools sys-tools"

# 解析模块名到物理相对路径（如 "docker" → "services/docker"）
resolve_module_path() {
    local mod="$1"
    local cat_dir
    for cat_dir in $CATEGORY_DIRS; do
        if [[ -d "$REPO_DIR/$cat_dir/$mod" ]]; then
            echo "$cat_dir/$mod"
            return 0
        fi
    done
    echo "$mod"
    return 1
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

    local scripts f rel
    scripts=$(find "$REPO_DIR" -type f -name "*.sh" \
              -not -path "*/.git/*" -not -path "*/node_modules/*" \
              -not -path "*/.tools/*" | sort)

    while IFS= read -r f; do
        rel="${f#"$REPO_DIR"/}"
        assert "bash -n: $rel" bash -n "$f"
    done <<< "$scripts"

    if command -v shellcheck >/dev/null 2>&1; then
        while IFS= read -r f; do
            rel="${f#"$REPO_DIR"/}"
            assert "shellcheck: $rel" shellcheck -e SC2164,SC1091,SC2317,SC2329 -x "$f"
        done <<< "$scripts"
    else
        # 未安装 shellcheck：对每个脚本标记 skip
        while IFS= read -r f; do
            rel="${f#"$REPO_DIR"/}"
            report_row "shellcheck: $rel" skip "shellcheck 未安装"
        done <<< "$scripts"
    fi

    report_footer
    [[ $FAIL_COUNT -eq 0 ]]
}

# ---------------- status 契约校验 ----------------
# 每个模块在 UXS_STATUS_MODE=machine 下首行必须是 STATE= 且值在有限集内。
# 复用 ci_run.sh 既有的报告 helper：report_row <name> <pass|fail|skip> [short]
check_status_contract() {
    local valid=" not_installed installed:running installed:stopped installed configured not_configured n/a "
    local cat_dirs="services essentials dev-tools ai-tools sys-tools"
    local cat_dir mod_dir mod first state
    for cat_dir in $cat_dirs; do
        [[ -d "$REPO_DIR/$cat_dir" ]] || continue
        for mod_dir in "$REPO_DIR/$cat_dir"/*/; do
            [[ -d "$mod_dir" ]] || continue
            mod=$(basename "$mod_dir")
            [[ -f "$mod_dir/install.sh" ]] || continue   # P5 模块无 install.sh，跳过
            first=$(UXS_STATUS_MODE=machine bash "$mod_dir/install.sh" status 2>/dev/null | head -1)
            if [[ "$first" != STATE=* ]]; then
                report_row "status 契约: $mod" fail "首行非 STATE=（实际: '$first'）"
                continue
            fi
            state="${first#STATE=}"
            if [[ " $valid " != *" $state "* ]]; then
                report_row "status 契约: $mod" fail "状态码 '$state' 不在有限集"
                continue
            fi
            report_row "status 契约: $mod" pass
        done
    done

    # shutdown_timer / process_manager_tool 历史上是「特殊模块」（ENTRY_SCRIPT 非 install.sh，
    # 状态逻辑曾硬编码在 lib/status.sh）。现已去特判化，二者与普通模块一样经入口脚本 status
    # 输出 STATE=。此处保留断言作为回归守卫：确保去特判后它们仍输出合法状态码。
    local p5_mod
    for p5_mod in shutdown_timer process_manager_tool; do
        # 从 --status-json 提取该模块的状态行
        state=$("$REPO_DIR/install.sh" --status-json 2>/dev/null \
                 | sed -n "s/^${p5_mod}://p" | head -1)
        # 状态行可能含 version 后缀（如 installed:running:1.2.3），取第一个字段
        state="${state%%:*}"
        if [[ -z "$state" || "$state" == "unknown" ]]; then
            report_row "status 契约: $p5_mod (P5)" fail "状态为 '$state'（应为合法码）"
        elif [[ " $valid " != *" $state "* ]]; then
            report_row "status 契约: $p5_mod (P5)" fail "状态码 '$state' 不在有限集"
        else
            report_row "status 契约: $p5_mod (P5)" pass
        fi
    done
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
    # cli 子命令：lib/uxs_cli.sh 含 install_cli / uninstall_cli 函数（不实际安装，避免污染 CI 环境）
    assert "lib/uxs_cli.sh 含 cli 安装/卸载函数" bash -c "grep -q 'install_cli()' \"$REPO_DIR/lib/uxs_cli.sh\" && grep -q 'uninstall_cli()' \"$REPO_DIR/lib/uxs_cli.sh\""

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
    #    从各分类子目录的 .manifest 文件动态发现，不再硬编码。
    #    注意：此处绝不调用 install（避免触发真实安装），仅 static 阶段覆盖其语法。
    local new_mods=()
    local cat_dir
    for cat_dir in $CATEGORY_DIRS; do
        for manifest in "$REPO_DIR/$cat_dir"/*/.manifest; do
            [[ -f "$manifest" ]] || continue
            new_mods+=("$(basename "$(dirname "$manifest")")")
        done
    done
    local m entry_script script mod_path
    for m in "${new_mods[@]}"; do
        mod_path=$(resolve_module_path "$m")
        # 从 manifest 读取入口脚本名（默认 install.sh）
        entry_script="install.sh"
        if grep -q '^ENTRY_SCRIPT=' "$REPO_DIR/$mod_path/.manifest" 2>/dev/null; then
            entry_script=$(grep '^ENTRY_SCRIPT=' "$REPO_DIR/$mod_path/.manifest" | head -1 | cut -d= -f2)
        fi
        script="$REPO_DIR/$mod_path/$entry_script"
        [[ -f "$script" ]] || { report_row "$m: 脚本存在 ($entry_script)" fail "缺失"; continue; }
        # 契约：每个模块入口脚本必须提供 install/uninstall/status/help 四子命令分发。
        # uninstall 多为破坏性操作，无法在 CI 行为测试，故校验 case 分支存在（grep 结构断言）。
        # shellcheck disable=SC2016 # $1 故意不在外层展开（交给内层 bash -c 求值）
        assert "$m: uninstall 子命令存在" bash -c 'grep -qE "uninstall[[:space:]]*\)" "$1"' _ "$script"
        assert "$m: status (exit 0)" bash "$script" status
        assert "$m: help (exit 0)" bash "$script" help
        # 永久门禁：强制 nounset 跑一遍，确保模块未引入未定义变量引用
        # （模块自身已 set -euo pipefail；此断言防止有人删掉 set -u 后静默回退）
        assert "$m: status (set -u)" bash -u "$script" status
        assert "$m: help (set -u)" bash -u "$script" help
    done

    # 5. shutdown_timer 的非交互入口存在且可调用（取消接口）
    local st_path
    st_path=$(resolve_module_path shutdown_timer)
    assert "shutdown_timer: cancel 接口存在" bash -c "grep -q cancel_daily_shutdown_internal \"$REPO_DIR/$st_path/shutdown_timer.sh\""

    # 6. process_manager_tool 脚本就绪
    local pm_path
    pm_path=$(resolve_module_path process_manager_tool)
    assert "pm_wrapper: --version (exit 0)" bash "$REPO_DIR/$pm_path/pm_wrapper.sh" --version

    # 9. dev-mirror 模块集成断言
    #    注册表驱动：dev-mirror 有 manifest，子菜单在 lib/submenus.sh
    local dm_path
    dm_path=$(resolve_module_path dev-mirror)
    assert "dev-mirror 有 .manifest" bash -c "test -f \"$REPO_DIR/$dm_path/.manifest\""
    assert "lib/submenus.sh 含 manage_dev-mirror 函数" bash -c "grep -q 'manage_dev-mirror()' \"$REPO_DIR/lib/submenus.sh\""
    # 菜单按 "manage_${HAS_SUBMENU}" 动态分发：每个声明 HAS_SUBMENU 的模块都必须有同名入口
    # shellcheck disable=SC2016 # $1/$() 故意交给内层 bash -c 求值
    assert "子菜单入口: 所有 HAS_SUBMENU 均有 manage_<名>() 对应" bash -c '
        for m in "$1"/*/*/.manifest; do
            v=$(grep -h "^HAS_SUBMENU=" "$m" 2>/dev/null | cut -d= -f2)
            [ -z "$v" ] && continue
            grep -q "manage_${v}()" "$1/lib/submenus.sh" || { echo "缺少 manage_${v}()"; exit 1; }
        done' _ "$REPO_DIR"
    assert "lib/status.sh 含 module_status 函数" bash -c "grep -q 'module_status()' \"$REPO_DIR/lib/status.sh\""
    # dev-mirror 子命令路由：非法生态应报错退出 1
    assert "dev-mirror: 非法生态报错 (exit 1)" bash -c "! \"$REPO_DIR/$dm_path/install.sh\" install __bad_eco__ >/dev/null 2>&1"
    # dev-mirror: 非法源标识应报错退出 1
    assert "dev-mirror: 非法源标识报错 (exit 1)" bash -c "! \"$REPO_DIR/$dm_path/install.sh\" install go __bad_source__ >/dev/null 2>&1"

    # 9c. sys-setup：apt 换源需感知 deb822（Ubuntu 24.04+ 发行版源在 sources.list.d/*.sources）
    local ss_path
    ss_path=$(resolve_module_path sys-setup)
    assert "sys-setup: mirror 重写 deb822 ubuntu.sources" bash -c "grep -q 'sources.list.d/ubuntu.sources' \"$REPO_DIR/$ss_path/install.sh\""
    assert "sys-setup: 停用残留源逻辑存在" bash -c "grep -q '_apt_disable_distro_sources()' \"$REPO_DIR/$ss_path/install.sh\""
    assert "sys-setup: status 镜像检测覆盖 sources.list.d" bash -c "grep -qF '/etc/apt/sources.list.d/*.sources' \"$REPO_DIR/$ss_path/install.sh\""

    # 4b. status 契约：machine 模式下每个模块首行必须是合法 STATE=
    check_status_contract

    # 10. 阶段 E：模块依赖图（lib/deps.sh）
    assert "依赖图: lib/deps.sh 存在" bash -c "test -f \"$REPO_DIR/lib/deps.sh\""
    assert "依赖图: minikube .manifest 含 REQUIRES=docker" bash -c "grep -q '^REQUIRES=docker' \"$REPO_DIR/dev-tools/minikube/.manifest\""
    # shellcheck disable=SC2016 # $1/$() 故意交给内层 bash -c 求值
    assert "依赖图: resolve_deps(minikube)=docker" bash -c \
        'cd "$1" && SCRIPT_DIR=. && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/deps.sh >/dev/null 2>&1
         detect_os >/dev/null 2>&1; registry_scan
         [ "$(resolve_deps minikube)" = "docker" ]' _ "$REPO_DIR"
    # shellcheck disable=SC2016 # 同上
    assert "依赖图: topo_sort_all 中 docker 先于 minikube" bash -c \
        'cd "$1" && SCRIPT_DIR=. && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/deps.sh >/dev/null 2>&1
         detect_os >/dev/null 2>&1; registry_scan
         order=$(topo_sort_all)
         di=$(echo "$order" | tr " " "\n" | grep -n "^docker$" | cut -d: -f1)
         mi=$(echo "$order" | tr " " "\n" | grep -n "^minikube$" | cut -d: -f1)
         [ -n "$di" ] && [ -n "$mi" ] && [ "$di" -lt "$mi" ]' _ "$REPO_DIR"
    # 循环检测：注入 docker→minikube（minikube 已→docker）形成环，resolve_deps 内部 exit 1，
    # 用子 shell 捕获：检测到环 → 本断言通过（exit 0）
    # shellcheck disable=SC2016 # 同上
    assert "依赖图: 循环依赖检测（遇环退出非0）" bash -c \
        'cd "$1" && SCRIPT_DIR=. && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/deps.sh >/dev/null 2>&1
         detect_os >/dev/null 2>&1; registry_scan
         eval "_REG_REQUIRES_docker=minikube"
         if ( resolve_deps minikube ) >/dev/null 2>&1; then exit 1; else exit 0; fi' _ "$REPO_DIR"
    # --list-modules 对 minikube 输出 requires:docker
    assert "依赖图: --list-modules 含 minikube requires:docker" bash -c \
        "\"$REPO_DIR/install.sh\" --list-modules | grep '^minikube' | grep -q 'requires:docker'"
    # --no-deps 解析（无模块参数 → 显示用法 exit 0）
    # shellcheck disable=SC2016 # $1 故意交给内层 bash -c 求值
    assert "依赖图: --no-deps 解析正常" bash -c \
        'UNIX_SCRIPT_NO_UPDATE_CHECK=1 "$1/install.sh" --no-deps </dev/null >/dev/null 2>&1' _ "$REPO_DIR"

    # 11. 阶段 D：profile 导出/应用（lib/profile.sh）
    assert "profile: lib/profile.sh 存在" bash -c "test -f \"$REPO_DIR/lib/profile.sh\""
    assert "profile: 含 export_profile/apply_profile" bash -c \
        "grep -q 'export_profile()' \"$REPO_DIR/lib/profile.sh\" && grep -q 'apply_profile()' \"$REPO_DIR/lib/profile.sh\""
    assert "profile: bun .manifest 含 EXPORTABLE=registry" bash -c \
        "grep -q '^EXPORTABLE=registry' \"$REPO_DIR/dev-tools/bun/.manifest\""
    assert "profile: install.sh 路由 export/apply" bash -c \
        "grep -q 'export|export-profile)' \"$REPO_DIR/install.sh\" && grep -q 'apply|apply-profile)' \"$REPO_DIR/install.sh\""
    # export → 产出合法 profile（含头部 + 用法提示）
    local prof_dir prof synth
    prof_dir="$(mktemp -d)"
    prof="$prof_dir/uxs_test_profile.txt"
    # shellcheck disable=SC2016 # $1/$2 故意交给内层 bash -c 求值
    assert "profile: export 产出文件" bash -c \
        'UNIX_SCRIPT_NO_UPDATE_CHECK=1 "$1/install.sh" export "$2" >/dev/null 2>&1 && grep -q "# unix_script profile" "$2"' _ "$REPO_DIR" "$prof"
    # apply --dry-run 对导出的 profile 不报错（已装模块全跳过）
    # shellcheck disable=SC2016
    assert "profile: apply --dry-run 正常退出" bash -c \
        'UNIX_SCRIPT_NO_UPDATE_CHECK=1 "$1/install.sh" apply "$2" --dry-run </dev/null >/dev/null 2>&1' _ "$REPO_DIR" "$prof"
    # 配置透传解析：合成一个含 key=value 的 profile（bun 未装时会被 dry-run「应用」并回显配置）
    synth="$prof_dir/synth.txt"
    printf '# synthetic\nbun registry=https://example.test/\n' > "$synth"
    # shellcheck disable=SC2016
    assert "profile: 解析 key=value 配置并注入" bash -c \
        'UNIX_SCRIPT_NO_UPDATE_CHECK=1 "$1/install.sh" apply "$2" --dry-run </dev/null 2>&1 | grep -q "UXS_CONFIG_registry="' _ "$REPO_DIR" "$synth"
    rm -rf "$prof_dir"

    # 12. 行为测试：别名解析 + 畸形 manifest 容错
    # shellcheck disable=SC2016 # $1/$() 故意交给内层 bash -c 求值
    assert "行为: 别名解析（pm/shutdown/未知）" bash -c \
        'cd "$1" && SCRIPT_DIR=. && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/deps.sh >/dev/null 2>&1
         detect_os >/dev/null 2>&1; registry_scan
         [ "$(registry_resolve_alias pm)" = "process_manager_tool" ] &&
         [ "$(registry_resolve_alias shutdown)" = "shutdown_timer" ] &&
         [ "$(registry_resolve_alias __no_such_alias__)" = "__no_such_alias__" ]' _ "$REPO_DIR"
    # 畸形 manifest（缺必填 LABEL）应被 _parse_manifest 拒绝（return 1）且不进 _REGISTRY_MODULES
    # shellcheck disable=SC2016
    assert "行为: 畸形 manifest（缺 LABEL）被跳过" bash -c \
        'cd "$1" && SCRIPT_DIR=. && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/deps.sh >/dev/null 2>&1
         detect_os >/dev/null 2>&1; registry_scan
         tmp=$(mktemp); printf "CATEGORY=服务\n" > "$tmp"
         if _parse_manifest __uxs_fake__ "$tmp" >/dev/null 2>&1; then rc=0; else rc=1; fi
         rm -f "$tmp"
         [ "$rc" -eq 1 ] && ! echo "$_REGISTRY_MODULES" | grep -qw __uxs_fake__' _ "$REPO_DIR"

    # 13. DESC 数据完整性：--list-modules 三列且第 3 列（描述）非空
    local desc_bad
    desc_bad=$("$REPO_DIR/install.sh" --list-modules 2>/dev/null | awk -F'\t' 'NF<3 || $3==""')
    if [[ -z "$desc_bad" ]]; then
        report_row "DESC: --list-modules 三列非空" pass
    else
        report_row "DESC: --list-modules 三列非空" fail "缺描述: $(printf '%s' "$desc_bad" | head -3 | tr '\n' ' ')"
    fi
    # shellcheck disable=SC2016
    assert "DESC: registry_desc(docker) 非空" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh
         registry_scan; [ -n "$(registry_desc docker)" ]' _ "$REPO_DIR"
    assert "DESC: scaffold 模板含 DESC 占位" bash -c "grep -q 'DESC=' '$REPO_DIR/lib/scaffold.sh'"

    # 14. did-you-mean：未知模块给出建议且不再倾倒 usage
    # shellcheck disable=SC2016
    assert "容错: doker → 建议 docker (exit 1)" bash -c \
        'out=$("$1/install.sh" doker 2>&1); rc=$?; [ "$rc" -eq 1 ] && printf "%s" "$out" | grep -q "docker"' _ "$REPO_DIR"
    # shellcheck disable=SC2016
    assert "容错: 无相近候选时不倾倒 usage" bash -c \
        'out=$("$1/install.sh" zzzqqq 2>&1); rc=$?; [ "$rc" -eq 1 ] && printf "%s" "$out" | grep -q "list-categories" && ! printf "%s" "$out" | grep -q "^用法:"' _ "$REPO_DIR"
    # shellcheck disable=SC2016
    assert "容错: usage 按分类分组（含描述）" bash -c \
        '"$1/install.sh" --help | grep -q "\[服务\]" && "$1/install.sh" --help | grep -q "容器引擎"' _ "$REPO_DIR"

    # 15. 网络超时：common.sh 所有 curl 均带超时参数
    # shellcheck disable=SC2016
    assert "超时: common.sh 定义 UXS_CURL_TIMEOUT_ARGS" bash -c \
        'source "$1/lib/common.sh" && [ "${#UXS_CURL_TIMEOUT_ARGS[@]}" -eq 4 ]' _ "$REPO_DIR"
    local bare_curls
    bare_curls=$(grep -n 'curl ' "$REPO_DIR/lib/common.sh" | grep -v 'UXS_CURL_TIMEOUT_ARGS' | grep -v ':[[:space:]]*#' || true)
    if [[ -z "$bare_curls" ]]; then
        report_row "超时: 全部 curl 带超时参数" pass
    else
        report_row "超时: 全部 curl 带超时参数" fail "$(printf '%s' "$bare_curls" | head -2 | tr '\n' ' ')"
    fi

    # 16. 状态缓存与图标（lib/status.sh）
    # shellcheck disable=SC2016
    assert "状态: status_icon 映射" bash -c \
        'source "$1/lib/common.sh" && source "$1/lib/registry.sh" && source "$1/lib/status.sh"
         [ "$(status_icon installed)" = "✓" ] && [ "$(status_icon installed:running)" = "✓" ] && \
         [ "$(status_icon configured)" = "✓" ] && [ "$(status_icon not_installed)" = " " ] && \
         [ "$(status_icon n/a)" = "·" ] && [ "$(status_icon unknown)" = "?" ]' _ "$REPO_DIR"
    local sc_dir
    sc_dir=$(mktemp -d)
    # shellcheck disable=SC2016
    assert "状态: 并行批查 + 缓存写入 + 命中" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/status.sh
         registry_scan
         UXS_STATUS_CACHE_DIR="$2" UXS_STATUS_CACHE_TTL=60 status_batch_query docker redis
         [ -n "$(UXS_STATUS_CACHE_DIR="$2" status_state_get docker)" ] && \
         [ -n "$(UXS_STATUS_CACHE_DIR="$2" status_state_get redis)" ]
         UXS_STATUS_CACHE_DIR="$2" status_cache_save
         UXS_STATUS_CACHE_DIR="$2" status_cache_load' _ "$REPO_DIR" "$sc_dir"
    # shellcheck disable=SC2016
    assert "状态: TTL=0 禁用缓存（load 必 miss）" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/status.sh
         if UXS_STATUS_CACHE_DIR="$2" UXS_STATUS_CACHE_TTL=0 status_cache_load; then exit 1; else exit 0; fi' _ "$REPO_DIR" "$sc_dir"
    rm -rf "$sc_dir"

    # 17. 菜单：模式解析与渲染纯函数（交互循环不自动化）
    # shellcheck disable=SC2016
    assert "菜单: UXS_MENU=bash 强制 bash 模式" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh
         registry_scan
         [ "$(UXS_MENU=bash resolve_menu_mode)" = "bash" ]' _ "$REPO_DIR"
    # shellcheck disable=SC2016
    assert "菜单: category_items 过滤（vpn → tailscale+wireguard）" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh
         registry_scan
         items=$(category_items 服务 vpn)
         echo "$items" | grep -q tailscale && echo "$items" | grep -q wireguard && \
         [ "$(echo "$items" | wc -w)" -eq 2 ]' _ "$REPO_DIR"
    # shellcheck disable=SC2016
    assert "菜单: render_category_page 含状态列与描述" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh
         registry_scan
         render_category_page 服务 "" 2>/dev/null | grep -q "容器引擎" && \
         render_category_page 服务 "" 2>/dev/null | grep -q "docker"' _ "$REPO_DIR"

    # 18. fzf 菜单：源码结构与降级
    assert "fzf 菜单: lib/menu_fzf.sh 存在" bash -c "test -f '$REPO_DIR/lib/menu_fzf.sh'"
    assert "fzf 菜单: install.sh 已 source menu_fzf.sh" bash -c "grep -q 'lib/menu_fzf.sh' '$REPO_DIR/install.sh'"
    # shellcheck disable=SC2016
    assert "fzf 菜单: 无 fzf 时 resolve_menu_mode=auto → bash" bash -c \
        'cd "$1" && SCRIPT_DIR=$PWD && source ./lib/common.sh && source ./lib/registry.sh && source ./lib/suggest.sh && source ./lib/status.sh && source ./lib/menu.sh && source ./lib/menu_fzf.sh
         registry_scan
         if command -v fzf >/dev/null 2>&1; then
            [ "$(UXS_MENU=bash resolve_menu_mode)" = "bash" ]
         else
            [ "$(resolve_menu_mode)" = "bash" ]
         fi' _ "$REPO_DIR"

    # 19. 补全：注册表驱动（与 --list 同源）
    # shellcheck disable=SC2016
    assert "补全: bash 模块清单与注册表一致" bash -c '
        COMP_WORDS=(uxs ""); COMP_CWORD=1
        source "$1/completions/uxs.bash"
        _uxs_completions
        # 不用 diff：极简容器（arch/RHEL 系）可能无 diffutils；sort+字符串比较仅依赖 POSIX 基础工具
        comp_list=$(printf "%s\n" "${COMPREPLY[@]}" | grep -vE "^(--.*|apply|check-update|cli|completions|doctor|export|scaffold|uninstall-cli|update)$" | sort)
        reg_list=$("$1/install.sh" --list | tr " " "\n" | grep -v "^$" | sort)
        [ "$comp_list" = "$reg_list" ]' _ "$REPO_DIR"
    if command -v zsh >/dev/null 2>&1; then
        assert "补全: uxs.zsh 语法正确" zsh -n "$REPO_DIR/completions/uxs.zsh"
    else
        report_row "补全: uxs.zsh 语法" skip "zsh 未安装"
    fi
    assert "补全: uxs.zsh manifest 驱动（无硬编码清单）" bash -c \
        "! grep -q 'bbr:BBR' '$REPO_DIR/completions/uxs.zsh' && grep -q 'manifest' '$REPO_DIR/completions/uxs.zsh'"
    assert "补全: uxs.bash manifest 驱动" bash -c \
        "! grep -q 'bbr brew bun clash' '$REPO_DIR/completions/uxs.bash' && grep -q 'manifest' '$REPO_DIR/completions/uxs.bash'"

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
    local pm_path
    pm_path=$(resolve_module_path process_manager_tool)
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"pm"* ]]; then
        local pm_dir="$REPO_DIR/$pm_path"
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
    local f2b_path
    f2b_path=$(resolve_module_path fail2ban)
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"fail2ban"* ]]; then
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
            if bash "$REPO_DIR/$f2b_path/install.sh" install >/tmp/f2b_install.log 2>&1; then
                if systemctl is-active --quiet fail2ban 2>/dev/null; then
                    report_row "fail2ban: 安装并运行" pass
                else
                    report_row "fail2ban: 安装并运行" fail "服务未 active"
                fi
                if bash "$REPO_DIR/$f2b_path/install.sh" uninstall >/tmp/f2b_uninstall.log 2>&1; then
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
    local ne_path
    ne_path=$(resolve_module_path node_exporter)
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"node_exporter"* ]]; then
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
            # 通过 env 把 token 暴露给 curl：用 GH_TOKEN，并在安装脚本外预取版本以减少 API 调用
            if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
                export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
            fi
            # node_exporter install.sh 是交互式脚本（有"确认继续安装"提示），
            # 用 yes y | 喂入确认，避免 </dev/null 导致 read 收到 EOF 而取消安装。
            if yes y | bash "$REPO_DIR/$ne_path/install.sh" >/tmp/ne_install.log 2>&1; then
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
    local epkg_path
    epkg_path=$(resolve_module_path essential-pkgs)
    if [[ "${MODULES_OVERRIDE}" == "" || "${MODULES_OVERRIDE}" == *"essential-pkgs"* || "${MODULES_OVERRIDE}" == *"essential_pkgs"* ]]; then
        if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1 || command -v zypper >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 || command -v apk >/dev/null 2>&1; then
            local epkg_log=/tmp/essential_install.log
            # essential-pkgs 在容器里需用 sudo（容器内 root 直接跑 sudo 可能无此命令，已装）
            if bash "$REPO_DIR/$epkg_path/install.sh" install >"$epkg_log" 2>&1; then
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
