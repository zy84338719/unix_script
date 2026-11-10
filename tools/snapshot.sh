#!/usr/bin/env bash
#
# 采集 unix_script 的确定性输出，作为重构前后的行为基线。
#
# 只采「同一台机器上多次运行结果一致」的输出：模块清单类。
# --status-json / 各模块 status 依赖本机安装状态，跨机器必然不同，
# 那两项改成结构判据（见 tools/check_status_shape.sh），不做逐字基线。
#
# 基线按 **OS 家族** 分目录存放（tests/snapshot/<os-family>/）：
#   · 模块清单受 PLATFORMS 可见性过滤影响（linux-only 的模块在 macOS 上不出现，反之亦然），
#     跨家族共用一份基线必然误报；
#   · 但输出与 CPU 架构、发行版版本 **无关** —— 已实测 arm64 / x86_64 与
#     ubuntu 24.04 / 25.04 的输出逐字一致，所以基线键里不再带 arch；
#     带 arch 的话，架构一漂移那条腿就会静默降级成「本机没基线」。
#
# 每次采集都会在采集目录里写一个 .collected 清单（每行一个文件名），
# 门禁据此确定「本次采集了哪些文件」—— 比较集合由采集结果决定，
# 不是由基线目录决定：基线目录里少一个文件时，门禁必须点名那个文件并判红，
# 而不是悄悄少比一个。
#
# 有意变更登记（.approved）：
#   每个基线目录里带一个 .approved，每行一条：
#     <基线文件名><TAB><该基线文件当前内容的 sha256>
#   改了行为的人必须走两步、一起提交：
#     ① bash tools/snapshot.sh          重跑采集，生成新基线
#     ② bash tools/snapshot.sh --approve  更新登记里的哈希
#   两处都进同一个 diff，评审看得见。门禁（tools/check_snapshot.sh）会核对
#   每个基线文件的 sha256 与登记是否一致：只改基线不更新登记 ⇒ 门禁红。
#
# 用法：
#   bash tools/snapshot.sh                       # 采集到 tests/snapshot/<os-family>/
#   bash tools/snapshot.sh /tmp/out              # 采集到指定目录
#   bash tools/snapshot.sh --approve [DIR]       # 重算 DIR/.approved 登记（默认当前家族基线目录）
#   bash tools/snapshot.sh --print-baseline-dir  # 打印当前家族的基线目录（stdout，纯数据）
#   bash tools/snapshot.sh --sha256 FILE         # 打印 FILE 的 sha256（stdout，纯数据）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

# LC_ALL=C：目录 glob 的排序受 locale 影响，不固定就会在不同机器上排出不同顺序，
# 基线随之漂移 —— 那是环境差异，不是行为变化。
export LC_ALL=C

# OS 家族：模块清单只随 OS 家族变化（见文件头注释），所以基线键用家族而不是 <os>-<arch>。
sk_os_family() {
  case "$(uname -s)" in
    Darwin) printf 'darwin\n' ;;
    Linux) printf 'linux\n' ;;
    *) printf '%s\n' "$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
  esac
}

# sha256：macOS 只有 shasum，Linux 一般有 sha256sum，两个都没有时退回 openssl。
# 全仓库唯一实现 —— tools/check_snapshot.sh 通过 --sha256 模式调用它，不另写一份。
sk_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    return 1
  fi
}

mode=collect
target=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --approve)
      mode=approve
      ;;
    --print-baseline-dir)
      mode=print
      ;;
    --sha256)
      mode=sha256
      ;;
    -*)
      printf 'snapshot: 未知参数：%s\n' "$1" >&2
      printf '用法：bash tools/snapshot.sh [DIR] | --approve [DIR] | --print-baseline-dir | --sha256 FILE\n' >&2
      exit 2
      ;;
    *)
      target="$1"
      ;;
  esac
  shift
done

BASE_DIR="$ROOT/tests/snapshot/$(sk_os_family)"

case "$mode" in
  print)
    printf '%s\n' "$BASE_DIR"
    exit 0
    ;;
  sha256)
    if [ -z "$target" ]; then
      printf 'snapshot: --sha256 需要一个文件参数\n' >&2
      exit 2
    fi
    if ! sk_sha256 "$target"; then
      printf 'snapshot: 无法计算 sha256（工具不可用或文件不可读）：%s\n' "$target" >&2
      exit 3
    fi
    exit 0
    ;;
esac

# 相对路径按调用方的 cwd 解析（下面会 cd 到 ROOT，先固化绝对路径）。
if [ -n "$target" ]; then
  case "$target" in
    /*) ;;
    *) target="$PWD/$target" ;;
  esac
fi

if [ "$mode" = approve ]; then
  dir="${target:-$BASE_DIR}"
  if [ ! -d "$dir" ]; then
    printf 'snapshot: 目录不存在：%s\n' "$dir" >&2
    exit 2
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/uxs-approved.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  # 只登记基线文件本身（.approved / .collected 是点文件，不算基线）。
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    h="$(sk_sha256 "$f")" || {
      printf 'snapshot: 无法计算 sha256：%s\n' "$f" >&2
      exit 3
    }
    printf '%s\t%s\n' "${f##*/}" "$h" >>"$tmp"
  done
  mv "$tmp" "$dir/.approved"
  # mktemp 落地是 0600，mv 覆盖后产物权限会与仓库里其它文件不一致（git 只记可执行位，
  # 提交内容不受影响，但本地 git status 的模式列会出现噪声）—— 归一为 0644。
  chmod 644 "$dir/.approved"
  printf 'snapshot: 已更新登记：%s\n' "$dir/.approved" >&2
  exit 0
fi

OUT_DIR="${target:-$BASE_DIR}"

# NO_COLOR=1：install.sh 按「stdout 是否 TTY」决定是否输出颜色码。
# 采集时 stdout 已重定向到文件（非 TTY），颜色本就会被清掉；这里显式写死，
# 让基线的确定性来自「明确设置」而不是「碰巧重定向」。
export NO_COLOR=1

# UNIX_SCRIPT_NO_UPDATE_CHECK=1：install.sh 启动时可能查远端版本并打印更新提示。
# 该检查同样被 TTY/CI 环境变量挡住，但显式关掉可保证基线不依赖网络与提示文案。
export UNIX_SCRIPT_NO_UPDATE_CHECK=1

mkdir -p "$OUT_DIR"

cd "$ROOT" || exit 1
: >"$OUT_DIR/.collected"
for __spec in "list:--list" "list-modules:--list-modules" "list-categories:--list-categories"; do
  __name="${__spec%%:*}"
  __args="${__spec#*:}"
  # shellcheck disable=SC2086
  ./install.sh $__args >"$OUT_DIR/$__name.txt"
  printf '%s.txt\n' "$__name" >>"$OUT_DIR/.collected"
  printf 'snapshot: %s -> %s\n' "$__name" "$OUT_DIR/$__name.txt" >&2
done
