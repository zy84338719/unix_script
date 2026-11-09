#!/usr/bin/env bash
#
# 采集 unix_script 的确定性输出，作为重构前后的行为基线。
#
# 只采「同一台机器上多次运行结果一致」的输出：模块清单类。
# --status-json / 各模块 status 依赖本机安装状态，跨机器必然不同，
# 那两项改成结构判据（见 tools/check_status_shape.sh），不做逐字基线。
#
# 基线按 <os>-<arch> 分目录存放：模块清单受平台可见性过滤影响
# （PLATFORMS=linux 的模块在 macOS 上不出现，反之亦然），
# 跨平台共用一份基线必然误报。
#
# 用法：
#   bash tools/snapshot.sh            # 写入 tests/snapshot/<os>-<arch>/
#   bash tools/snapshot.sh /tmp/out   # 写入指定目录
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
OUT_DIR="${1:-$ROOT/tests/snapshot/${OS}-${ARCH}}"

# LC_ALL=C：目录 glob 的排序受 locale 影响，不固定就会在不同机器上排出不同顺序，
# 基线随之漂移 —— 那是环境差异，不是行为变化。
export LC_ALL=C

# NO_COLOR=1：install.sh 按「stdout 是否 TTY」决定是否输出颜色码。
# 采集时 stdout 已重定向到文件（非 TTY），颜色本就会被清掉；这里显式写死，
# 让基线的确定性来自「明确设置」而不是「碰巧重定向」。
export NO_COLOR=1

# UNIX_SCRIPT_NO_UPDATE_CHECK=1：install.sh 启动时可能查远端版本并打印更新提示。
# 该检查同样被 TTY/CI 环境变量挡住，但显式关掉可保证基线不依赖网络与提示文案。
export UNIX_SCRIPT_NO_UPDATE_CHECK=1

mkdir -p "$OUT_DIR"

cd "$ROOT"
for __spec in "list:--list" "list-modules:--list-modules" "list-categories:--list-categories"; do
  __name="${__spec%%:*}"
  __args="${__spec#*:}"
  # shellcheck disable=SC2086
  ./install.sh $__args >"$OUT_DIR/$__name.txt"
  printf 'snapshot: %s -> %s\n' "$__name" "$OUT_DIR/$__name.txt" >&2
done
