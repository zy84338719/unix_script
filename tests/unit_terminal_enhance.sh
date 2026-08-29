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

# ---------- ② modern-cli 扩展 ----------
MODERN_SH="$REPO_DIR/dev-tools/modern-cli/install.sh"
t_true "modern-cli: 安装脚本含 tealdeer/direnv" \
    "grep -q 'tealdeer' '$MODERN_SH' && grep -q 'direnv' '$MODERN_SH'"
t_true "modern-cli: status 检查含 tldr/direnv" "grep -q 'tldr direnv' '$MODERN_SH'"
t_true "modern-cli: 存在 extras 标记块（向后兼容老 rc）" "grep -q 'modern-cli extras' '$MODERN_SH'"

# ---------- ④ nerd-font ----------
NF_MANIFEST="$REPO_DIR/dev-tools/nerd-font/.manifest"
NF_SH="$REPO_DIR/dev-tools/nerd-font/install.sh"
t_true "nerd-font: 模块文件存在且可执行" "[[ -f '$NF_MANIFEST' && -x '$NF_SH' ]]"
t_true "nerd-font: manifest EXPORTABLE=fonts" "grep -q '^EXPORTABLE=fonts$' '$NF_MANIFEST'"
t_true "nerd-font: 语法通过" "bash -n '$NF_SH'"
t_true "nerd-font: 映射表用正确的 Cascadia cask 名(-nf)" "grep -q 'font-cascadia-code-nf' '$NF_SH'"

# ---------- ③ atuin ----------
ATUIN_SH="$REPO_DIR/dev-tools/atuin/install.sh"
t_true "atuin: 模块文件存在且可执行" "[[ -x '$ATUIN_SH' ]]"

printf '#!/bin/sh\necho "atuin 18.0.0"\n' > "$FAKE/atuin"; chmod +x "$FAKE/atuin"
out=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" UXS_STATUS_MODE=machine bash "$ATUIN_SH" status </dev/null 2>/dev/null)
t_eq "atuin: 已装无 rc 集成 → STATE=installed + EXTRA sync=off" \
    "installed off" \
    "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1) $(printf '%s' "$out" | sed -n 's/^EXTRA=sync=//p')"
t_true "atuin: 导入子命令为 import auto（空格形式）" "grep -q 'import auto' '$ATUIN_SH'"
t_true "atuin: manifest EXPORTABLE=sync" "grep -q '^EXPORTABLE=sync$' '$REPO_DIR/dev-tools/atuin/.manifest'"

# ---------- ⑤ terminal 编排 ----------
TERM_MANIFEST="$REPO_DIR/dev-tools/terminal/.manifest"
TERM_SH="$REPO_DIR/dev-tools/terminal/install.sh"
t_true "terminal: 模块文件存在且可执行" "[[ -f '$TERM_MANIFEST' && -x '$TERM_SH' ]]"
t_true "terminal: manifest 无 EXPORTABLE（子模块自治声明）" \
    "grep -q '^DESC=' '$TERM_MANIFEST' && ! grep -q '^EXPORTABLE=' '$TERM_MANIFEST'"

# EXCLUDE 全排除 → install 幂等完成 rc=0，不触发任何子模块安装
HOME="$FAKE/home" UXS_CONFIG_EXCLUDE="zsh,zsh_setup,modern-cli,nerd-font,atuin" \
    bash "$TERM_SH" install </dev/null >/dev/null 2>&1
t_eq "terminal: EXCLUDE 全排除 install rc=0" "0" "$?"

out=$(PATH="$FAKE:$PATH" HOME="$FAKE/home" UXS_STATUS_MODE=machine bash "$TERM_SH" status </dev/null 2>/dev/null)
t_eq "terminal: 全缺 → STATE=not_installed" "not_installed" "$(printf '%s' "$out" | sed -n 's/^STATE=//p' | head -1)"
t_true "terminal: EXTRA=missing 含 modern-cli（桩无该命令）" "printf '%s' \"\$out\" | grep -q 'missing=.*modern-cli'"

echo
echo "通过: $PASS / 失败: $FAIL"
[[ $FAIL -eq 0 ]]
