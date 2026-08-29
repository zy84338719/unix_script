#!/usr/bin/env bash
#
# tests/unit_usability.sh — 易用性快修包批次① 单测
# 覆盖：uxs_with_timeout / status 批查容错 / --status-json 防截断 / doctor 无 TTY / ufw 降级链 / dry-run 副作用
# 独立运行：bash tests/unit_usability.sh（退出码 0=全过）
# 也被 tests/ci_run.sh 调用。
set -u
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

t_eq() {  # t_eq <名称> <期望> <实际>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1  期望='$2' 实际='$3'"
    fi
}

t_true() {  # t_true <名称> <条件命令>
    if eval "$2"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $1"
    fi
}

# shellcheck source=../lib/common.sh
source "$REPO_DIR/lib/common.sh"
set +e +o pipefail

# ---------- uxs_with_timeout ----------
rc=$(uxs_with_timeout 2 true; echo $?)
t_eq "timeout: 快命令透传 rc=0" "0" "$rc"

rc=$(uxs_with_timeout 2 false; echo $?)
t_eq "timeout: 失败命令透传 rc=1" "1" "$rc"

S=$SECONDS
rc=$(uxs_with_timeout 1 sleep 5 >/dev/null 2>&1; echo $?)
ELAPSED=$((SECONDS - S))
t_eq "timeout: 超时 rc=124" "124" "$rc"
t_true "timeout: 超时及时返回（实测 ${ELAPSED}s ≤ 2s）" "(( ELAPSED <= 2 ))"

# ---------- ufw 三级降级链（仅 Linux；macOS 上 ufw status=n/a）----------
if [[ "$(uname)" == "Linux" ]]; then
    UFW_SH="$REPO_DIR/sys-tools/ufw/install.sh"
    FAKE=$(mktemp -d)

    # 注入假 ufw（推荐直接注入，不依赖测试机是否装了 ufw；command_exists 需可执行位）
    printf '#!/bin/sh\nexit 0\n' > "$FAKE/ufw"
    chmod +x "$FAKE/ufw"

    # 降级1：sudo -n 成功（原语义保留）
    printf '#!/bin/sh\necho "Status: active"\n' > "$FAKE/sudo"
    chmod +x "$FAKE/sudo"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 可用 active→configured" "configured" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    printf '#!/bin/sh\necho "Status: inactive"\n' > "$FAKE/sudo"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 可用 inactive→not_configured" "not_configured" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    # 降级2：sudo -n 失败（无凭据/无 TTY），systemctl 兜底
    printf '#!/bin/sh\nexit 1\n' > "$FAKE/sudo"
    printf '#!/bin/sh\necho active\n' > "$FAKE/systemctl"
    chmod +x "$FAKE/sudo" "$FAKE/systemctl"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 失败 systemctl active→installed:running" "installed:running" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    printf '#!/bin/sh\nexit 3\n' > "$FAKE/systemctl"
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_eq "ufw: sudo 失败 systemctl inactive→installed" "installed" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"

    # 降级3：sudo 与 systemctl 全失败 → 兜底 installed，且必有输出
    out=$(PATH="$FAKE:$PATH" UXS_STATUS_MODE=machine bash "$UFW_SH" status </dev/null 2>/dev/null)
    t_true "ufw: 全失败兜底仍有 STATE= 输出" "printf '%s' \"\$out\" | grep -q '^STATE='"
    rm -rf "$FAKE"
fi

# ---------- doctor 无 TTY（管道即无 TTY，测试天然满足）----------
DOC_OUT=$(bash "$REPO_DIR/install.sh" doctor </dev/null 2>&1)
t_true "doctor: 无 TTY 时 sudo 项跳过不误报" "printf '%s' \"\$DOC_OUT\" | grep -q '无法检测 sudo'"
t_true "doctor: 无 TTY 时无 sudo 不可用误报" "! printf '%s' \"\$DOC_OUT\" | grep -q 'sudo 不可用'"
if [[ "$(uname)" == "Darwin" ]]; then
    t_true "doctor: macOS 不再把缺 os-release 计为 WARNING" "! printf '%s' \"\$DOC_OUT\" | grep -q '未能识别发行版'"
    t_true "doctor: macOS 显示已跳过" "printf '%s' \"\$DOC_OUT\" | grep -q '不适用发行版检测'"
fi
# root 环境感知：root+非 TTY 走 success 分支，上述「跳过」断言不适用
# （否则在 root 容器里套件会假失败）
if [[ $EUID -eq 0 ]]; then
    t_true "doctor: root 下显示以 root 运行" "printf '%s' \"\$DOC_OUT\" | grep -q '当前以 root 运行'"
fi

# ---------- uxs_func_with_timeout（函数级超时，批查子进程封顶用）----------
# perl exec 只能拉二进制，包不住 shell 函数——所以批查用这套 background+watchdog 实现
__usab_fast_fn() { echo "STATE=not_installed"; }
__usab_slow_fn() { sleep 8; echo "STATE=installed"; }

out=$(uxs_func_with_timeout 2 __usab_fast_fn); rc=$?
t_eq "func-timeout: 快函数透传输出" "STATE=not_installed" "$out"
t_eq "func-timeout: 快函数透传 rc=0" "0" "$rc"

S=$SECONDS
out=$(uxs_func_with_timeout 1 __usab_slow_fn); rc=$?
ELAPSED=$((SECONDS - S))
t_eq "func-timeout: 慢函数超时返回空" "" "$out"
t_eq "func-timeout: 慢函数超时 rc=143（SIGTERM）" "143" "$rc"
t_true "func-timeout: 超时及时返回（实测 ${ELAPSED}s ≤ 3s）" "(( ELAPSED <= 3 ))"

# 回归：watchdog 不得持有命令替换的管道写端（否则快函数也要等 sleep 睡满才返回）
S=$SECONDS
out=$(uxs_func_with_timeout 8 __usab_fast_fn); rc=$?
ELAPSED=$((SECONDS - S))
t_eq "func-timeout: 快函数不被 watchdog 拖住 rc=0" "0" "$rc"
t_true "func-timeout: 快函数立即返回（实测 ${ELAPSED}s ≤ 3s，防管道持有回归）" "(( ELAPSED <= 3 ))"

# ---------- --status-json 防截断 + 批查容错 ----------
# 直查 status_batch_query 需要注册表与状态层（install.sh 的 source 序：registry → status）
SCRIPT_DIR="$REPO_DIR"
# shellcheck source=../lib/registry.sh
source "$REPO_DIR/lib/registry.sh"
# shellcheck source=../lib/status.sh
source "$REPO_DIR/lib/status.sh"
# shellcheck source=../lib/menu.sh
source "$REPO_DIR/lib/menu.sh"
registry_scan

status_batch_query __no_such_mod__ 2>/dev/null
t_eq "批查: 不存在模块兜底 unknown" "unknown" "$(status_state_get __no_such_mod__)"

# 批查必须同时填充 VERSION 缓存（--status-json 版本列依赖它；菜单只用 STATE 不受影响）
if [[ "$(uname)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    status_batch_query brew
    t_eq "批查: VERSION 缓存填充（brew）" "$(brew --version 2>/dev/null | head -1)" "$(_uxs_version_get brew)"
fi

cd "$REPO_DIR"
N_LIST=$(./install.sh --list | tr ' ' '\n' | grep -c .)
N_JSON=$(./install.sh --status-json | tail -n +4 | grep -c .)
t_eq "status-json: 模块行数完整（防 ufw 式截断）" "$N_LIST" "$N_JSON"
N_META=$(./install.sh --status-json | head -3 | grep -cE '^(os|arch|version):')
t_eq "status-json: 头 3 行元数据仍在" "3" "$N_META"

# 已装 bun 时：status-json 必须保留版本列（批查改造不丢 VERSION）
if command -v bun >/dev/null 2>&1; then
    t_eq "status-json: 版本列保留（bun）" "$(./install.sh --status-json | sed -n 's/^bun:installed://p')" "$(bun --version 2>/dev/null || echo __bun_absent__)"
fi
# shellcheck disable=SC2103  # cd 回原目录：PASS/FAIL 计数器在全局，不能收进子 shell
cd - >/dev/null

# ---------- dry-run：brew auto-update 副作用压制 ----------
unset HOMEBREW_NO_AUTO_UPDATE
uxs_install_sudo_shim
t_eq "dry-run: shim 注入 HOMEBREW_NO_AUTO_UPDATE=1" "1" "${HOMEBREW_NO_AUTO_UPDATE:-}"

# ---------- NEXT_STEPS 新手引导（批次②）----------
# registry 解析 + show_next_steps 渲染（人类/机器/dry-run 三重 gate）
NS_MANIFEST=$(mktemp)
printf 'LABEL=测试模块\nCATEGORY=服务\nNEXT_STEPS=装配套甲:./install.sh foo;开箱即用无需操作\n' > "$NS_MANIFEST"
_parse_manifest __test_ns__ "$NS_MANIFEST"
t_eq "next-steps: manifest 原样存储" "装配套甲:./install.sh foo;开箱即用无需操作" "$(registry_next_steps __test_ns__)"

NS_OUT=$(show_next_steps __test_ns__)
t_eq "next-steps: 人类模式渲染 2 条" "2" "$(printf '%s' "$NS_OUT" | grep -c '•')"
t_true "next-steps: 带命令条目渲染 →" "printf '%s' \"\$NS_OUT\" | grep -q '装配套甲 → ./install.sh foo'"
t_true "next-steps: 无命令条目整句渲染" "printf '%s' \"\$NS_OUT\" | grep -q '• 开箱即用无需操作'"

t_eq "next-steps: 机器模式零输出" "" "$(UXS_STATUS_MODE=machine show_next_steps __test_ns__)"
t_eq "next-steps: dry-run 零输出" "" "$(UNIX_SCRIPT_DRY_RUN=1 show_next_steps __test_ns__)"
# 无 NEXT_STEPS 字段的模块：用临时样本（真实模块随时可能接线，不能当反例）
printf 'LABEL=测试模块乙\nCATEGORY=服务\n' > "$NS_MANIFEST"
_parse_manifest __test_ns2__ "$NS_MANIFEST"
t_eq "next-steps: 无字段的模块零输出" "" "$(show_next_steps __test_ns2__)"
rm -f "$NS_MANIFEST"

# ---------- 汇总 ----------
echo "通过 $PASS / 失败 $FAIL"
[[ "$FAIL" -eq 0 ]]
