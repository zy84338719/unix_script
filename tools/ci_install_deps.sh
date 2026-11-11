#!/bin/sh
# CI 装依赖：带重试 + apt 备用镜像。
#
# 为什么需要它：
#   GitHub runner 与容器里的 apt 偶发「Temporary failure resolving
#   'azure.archive.ubuntu.com'」（DNS 抖动）⇒ apt-get update 只拿到警告、
#   包索引不全 ⇒ 随后的 install 直接 E: Unable to fetch some archives。
#   结果是**整批 job 变红，而与代码毫无关系**（2026-11-11 实录：静态检查、
#   实装测试、三个容器 job 全挂在这一步）。
#
# 两条对策：
#   1) 装之前挂上**备用镜像**（aliyun / 清华）—— apt 会挨个源尝试，
#      主源 DNS 挂掉时备用源顶上（apt 对单个源失败只警告，不致命）。
#   2) 整段「update + install」重试 3 次，间隔递增 —— 抖动多半是秒级的。
#
# 用法：
#   tools/ci_install_deps.sh [包管理器] [包...]
#     包管理器：auto（默认，按系统探测）/ apt / dnf / yum / zypper / pacman / apk
#     不给包名时用各包管理器的默认清单（见下）。
#
#   tools/ci_install_deps.sh --setup-mirrors      只挂备用镜像，不装东西
#     （给「跑测试时脚本内部会自己 apt-get install」的场合用：先把备用源备好，
#       模块自己那条 apt 命令就能用上备用镜像）
#
# 用 sh 而不是 bash：Alpine 容器里没有 bash（容器 job 的 shell 就是 sh）。
set -u

MAX_TRY=3

log() { printf 'ci-install-deps: %s\n' "$*" >&2; }
die() {
  log "错误：$*"
  exit 1
}

# ---- apt 备用镜像 ----------------------------------------------------------
# ubuntu 走 ubuntu 源、debian 走 debian 源；组件各 distro 不同
#（ubuntu 有 universe/multiverse，debian 是 contrib/non-free）。
apt_setup_mirrors() {
  [ -d /etc/apt ] || return 0

  _id=""
  _codename=""
  if [ -r /etc/os-release ]; then
    _id=$(sed -n 's/^ID=//p' /etc/os-release | head -1 | tr -d '"')
    _codename=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release | head -1 | tr -d '"')
  fi
  [ -n "$_codename" ] || return 0

  case "$_id" in
    ubuntu)
      _suite=ubuntu
      _comps="main restricted universe multiverse"
      ;;
    debian)
      _suite=debian
      _comps="main contrib non-free"
      ;;
    *)
      return 0
      ;;
  esac

  # ① 把**指不到的源直接换掉**（只加不减是不行的）：
  #    apt 会对解析失败的源反复重试（Ign → Ign → …），整个 update 拖到超时，
  #    备用源明明有货也轮不到它（2026-11-11 实录：aliyun 的 InRelease 明明
  #    拉下来了，update 还是超时）。
  for _f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$_f" ] || continue
    sed -i \
      -e 's|http://azure.archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' \
      -e 's|https://azure.archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' \
      -e 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' \
      -e 's|http://security.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' \
      -e 's|http://deb.debian.org/debian/|http://mirrors.aliyun.com/debian/|g' \
      -e 's|https://deb.debian.org/debian/|http://mirrors.aliyun.com/debian/|g' \
      "$_f" 2>/dev/null || true
  done

  # ★ 只**替换 URL**，不新增源文件：
  #   同一个 suite 再加一个经典格式的 .list（哪怕 URL 相同）会撞
  #   「Conflicting values set for option Signed-By」—— deb822 的 .sources
  #   已经给这个 suite 定了 Signed-By，.list 没有 ⇒ apt 直接拒绝读源列表。
  #   替换 URL 则把原来的 Signed-By / Components 一并保留。
  log "apt 源已指向备用镜像（$_suite $_codename）"
  return 0
}

# ---- 重试 ------------------------------------------------------------------
# 整段命令重试：apt 的 update 与 install 必须一起重试
#（update 失败时 install 必然失败，单独重试 install 没有意义）。
run_with_retry() {
  _n=0
  while :; do
    _n=$((_n + 1))
    if "$@"; then
      return 0
    fi
    if [ "$_n" -ge "$MAX_TRY" ]; then
      log "连续 $_n 次失败：$*"
      return 1
    fi
    _wait=$((_n * 15))
    log "第 $_n 次失败，${_wait}s 后重试：$*"
    sleep "$_wait"
  done
}

# ---- 各包管理器的安装动作 --------------------------------------------------
install_apt() {
  # 加上超时：网络被黑洞掉时 apt 可能挂住不报错（本地实测 apt-get update 会一直等），
  # 超时后返回非 0 ⇒ 交给重试逻辑换一次机会，而不是把 job 拖到超时。
  if command -v timeout >/dev/null 2>&1; then
    timeout 180 apt-get -o Acquire::Retries=3 update &&
      timeout 600 apt-get -y install "$@"
  else
    apt-get -o Acquire::Retries=3 update && apt-get -y install "$@"
  fi
}

install_dnf() {
  # 这个静态检查工具在 EPEL 仓库里：先把 epel-release 装上（没有就跳过，不致命）
  dnf install -y epel-release >/dev/null 2>&1 || true
  # --allowerasing：RHEL 系默认装的是 curl-minimal，与 curl 冲突
  #（不给这个开关 dnf 直接报「cannot install the best candidate for the job」）
  dnf install -y --allowerasing "$@"
}

install_yum() {
  yum install -y epel-release >/dev/null 2>&1 || true
  yum install -y --allowerasing "$@"
}

install_zypper() {
  zypper --non-interactive refresh && zypper --non-interactive install "$@"
}

install_pacman() {
  # ★ 必须是 -Syu（整包升级 + 安装），不能是 -Sy：
  #   pacman -Sy 只同步数据库不升级系统 ⇒ 装包时变成「部分升级」，
  #   会把 openssl 升到 4.x 而系统里的包还依赖 libcrypto.so=3 ⇒
  #   「failed to prepare transaction (could not satisfy dependencies)」
  #   （2026-11-11 实录：arch 容器 job 挂在这一步）。
  pacman -Syu --noconfirm --needed "$@"
}

install_apk() {
  apk add --no-cache "$@"
}

detect_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  elif command -v yum >/dev/null 2>&1; then
    printf 'yum'
  elif command -v zypper >/dev/null 2>&1; then
    printf 'zypper'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'pacman'
  elif command -v apk >/dev/null 2>&1; then
    printf 'apk'
  else
    printf 'none'
  fi
}

default_pkgs() {
  case "$1" in
    apt) printf 'bash sudo curl which' ;;
    dnf | yum) printf 'bash sudo curl which' ;;
    zypper) printf 'bash sudo curl which gawk findutils' ;;
    pacman) printf 'bash sudo curl which' ;;
    apk) printf 'bash sudo curl which findutils' ;;
    *) printf '' ;;
  esac
}

# ---- 入口 ------------------------------------------------------------------
case "${1:-}" in
  --setup-mirrors)
    apt_setup_mirrors
    # 顺手把包索引也刷一遍：模块脚本后面可能直接 apt-get install，
    # 索引是空的话会报「Unable to locate package」。
    if command -v apt-get >/dev/null 2>&1; then
      apt-get -qq update || log "apt-get update 没成功（脚本自己那条命令还会再试）"
    fi
    exit 0
    ;;
esac

MGR="${1:-auto}"
case "$MGR" in
  auto)
    shift || true
    MGR=$(detect_mgr)
    [ "$MGR" != "none" ] || die "认不出包管理器（apt/dnf/yum/zypper/pacman/apk 都没有）"
    ;;
  apt | dnf | yum | zypper | pacman | apk) shift || true ;;
  *) die "未知包管理器：$MGR" ;;
esac

if [ "$#" -gt 0 ]; then
  PKGS="$*"
else
  PKGS=$(default_pkgs "$MGR")
fi
[ -n "$PKGS" ] || die "没有要装的包"

# PKGS 是空格分隔的包名列表：这里**有意**分词成多个参数
# shellcheck disable=SC2086
set -- $PKGS

log "包管理器=$MGR 包=$*"
case "$MGR" in
  apt)
    apt_setup_mirrors
    run_with_retry install_apt "$@"
    ;;
  dnf) run_with_retry install_dnf "$@" ;;
  yum) run_with_retry install_yum "$@" ;;
  zypper) run_with_retry install_zypper "$@" ;;
  pacman) run_with_retry install_pacman "$@" ;;
  apk) run_with_retry install_apk "$@" ;;
esac
