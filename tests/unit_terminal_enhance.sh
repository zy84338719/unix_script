#!/usr/bin/env bash
#
# tests/unit_terminal_enhance.sh — 终端配置增强批次 单测
# 覆盖：zsh_setup install 子命令 / modern-cli 扩展 / nerd-font / atuin / terminal 编排
# 独立运行：bash tests/unit_terminal_enhance.sh（退出码 0=全过）
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

# 共享桩目录：假二进制 + 假 HOME（后续任务用例复用）
FAKE=$(mktemp -d)
mkdir -p "$FAKE/home"

# ---------- ① zsh_setup install 子命令 ----------
ZSH_SETUP_SH="$REPO_DIR/dev-tools/zsh_setup/install.sh"

# 桩 PATH：假 zsh 让 status 走到框架检测
printf '#!/bin/sh\necho "zsh 5.9 (x86_64)"\n' > "$FAKE/zsh"
chmod +x "$FAKE/zsh"

out=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" UXS_STATUS_MODE=machine bash "$ZSH_SETUP_SH" status </dev/null 2>/dev/null)
t_eq "zsh_setup: status 机器模式输出 STATE=" "1" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1 | wc -l | tr -d ' ')"

# install 子命令存在：桩 curl 失败的场景下，错误不应是"未知命令: install"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/curl"; chmod +x "$FAKE/curl"
err=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" bash "$ZSH_SETUP_SH" install </dev/null 2>&1 || true)
t_true "zsh_setup: install 不再报未知命令" "! printf '%s' \"\$err\" | grep -q '未知命令'"

t_true "zsh_setup: manifest 声明 EXPORTABLE=framework,theme" \
    "grep -q '^EXPORTABLE=framework,theme$' '$REPO_DIR/dev-tools/zsh_setup/.manifest'"

echo
echo "通过: $PASS / 失败: $FAIL"
[[ $FAIL -eq 0 ]]
