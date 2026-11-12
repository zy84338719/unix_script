#!/usr/bin/env bash
#
# tools/pi_sync.sh —— 把本仓当前提交同步到 Pi500 的部署副本（Mac 侧执行）
#
# 为什么存在：Pi 部署原本是手工文件树，scp 在烂网络下反复超时（实测 886ms RTT +
# 丢包，同一文件 scp 超时而 ssh stdin 单流能过）。改成 git 化副本后，同步 = 一个
# bundle 走 ssh stdin + Pi 端 checkout，且 Pi 上永远是「某个真实提交的干净检出」。
#
# 用法：
#   bash tools/pi_sync.sh                    # 同步到默认目标 root@10.10.40.247
#   PI_SSH=pi bash tools/pi_sync.sh          # 换目标（也接受第 1 个位置参数）
#   PI_REMOTE_DIR=/path bash tools/pi_sync.sh # 换远端目录
#
# 远端动作（幂等，重复跑安全）：
#   1) git init（首次）+ git fetch 本地 bundle 到 refs/remotes/origin/*
#   2) git checkout -f -B main origin/main   —— 强制对齐，覆盖已跟踪文件的本地漂移
#   3) chown 回 zhangyi；打印 git status 残留（未跟踪文件不删，报告出来给人看）
#
# 注意：checkout -f 会丢弃远端副本里对**已跟踪文件**的本地修改（部署镜像的语义
# 就是「永远等于某个提交」）；未跟踪文件保留并在输出里列出。
set -euo pipefail

PI="${1:-${PI_SSH:-root@10.10.40.247}}"
REMOTE_DIR="${PI_REMOTE_DIR:-/home/zhangyi/unix_script}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bundle="$(mktemp "${TMPDIR:-/tmp}/uxs-sync.XXXXXX.bundle")"
trap 'rm -f "$bundle"' EXIT

echo ">> 生成 bundle（HEAD: $(git log --oneline -1)）"
git bundle create "$bundle" --all >/dev/null

echo ">> 经 ssh stdin 传输到 $PI（scp 会超时的网络，单流 stdin 能过）"
ssh "${SSH_OPTS[@]}" "$PI" 'cat > /tmp/uxs-sync.bundle && wc -c < /tmp/uxs-sync.bundle' < "$bundle"

echo ">> Pi 端 fetch + 强制对齐 + 归属 zhangyi"
# 引号 heredoc：远端脚本不在客户端展开；远端目录经位置参数传入
# shellcheck disable=SC2029  # $REMOTE_DIR 客户端展开是有意的（自有变量，传给远端作 $1）
ssh "${SSH_OPTS[@]}" "$PI" "bash -s '$REMOTE_DIR'" <<'REMOTE'
set -euo pipefail
d="${1:?remote dir required}"
git config --global --add safe.directory "$d"
if [ ! -d "$d/.git" ]; then
  mkdir -p "$d"
  git -C "$d" init -q
fi
git -C "$d" fetch -q /tmp/uxs-sync.bundle '+refs/heads/*:refs/remotes/origin/*'
git -C "$d" checkout -q -f -B main origin/main
chown -R zhangyi:zhangyi "$d"
rm -f /tmp/uxs-sync.bundle
echo "远端 HEAD: $(git -C "$d" log --oneline -1)"
echo "远端版本: $(bash "$d/install.sh" --version)"
left="$(git -C "$d" status --short | head -5 || true)"
if [ -n "$left" ]; then
  echo "残留（未跟踪/已修改，未删除）:"
  echo "$left"
else
  echo "工作树: clean"
fi
REMOTE

echo ">> 同步完成"
