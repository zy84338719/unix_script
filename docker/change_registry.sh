#!/usr/bin/env bash
set -euo pipefail

# docker/change_registry.sh
# 用途：为 Docker 配置镜像加速/镜像源（daemon.json），支持备份、还原与无交互安装

DEFAULT_REGISTRIES=(
  "docker.io" # 默认（不变）
  "registry.cn-hangzhou.aliyuncs.com" # 阿里
  "registry.docker-cn.com" # Docker 中国官方（若可用）
  "mirrors.aliyun.com" # 作为占位
  "hub-mirror.c.163.com" # 网易
  "registry.cn-shanghai.aliyuncs.com" # 备用
)

BACKUP_DIR="/var/backups/docker_registry_$(date +%Y%m%d%H%M%S)"
DAEMON_JSON="/etc/docker/daemon.json"

usage() {
  cat <<EOF
Usage: $0 [--set <name|url>] [--list] [--backup] [--restore <backup_path>] [--apply] [--yes]

Options:
  --set <name|url>    设置镜像源，支持预置名称(aliyun|netease|dockercn)或直接 URL（例如 registry.cn-hangzhou.aliyuncs.com）
  --list              列出内置的镜像源
  --backup            备份当前 /etc/docker/daemon.json 到 $BACKUP_DIR
  --restore <path>    从指定备份恢复并重启 Docker
  --apply             仅应用当前 daemon.json（重启 Docker）
  --yes               非交互模式，默认接受所有提示
  --help              显示此帮助

示例：
  $0 --set aliyun       # 设置为阿里云镜像源并重启 Docker
  $0 --set registry.example.com --yes
  $0 --backup
  $0 --restore /var/backups/docker_registry_20230101010101/daemon.json
EOF
}

# 解析预置名称到 registry 地址
resolve_registry() {
  local key="$1"
  case "${key,,}" in
    aliyun|aliyuncnhangzhou|aliyuncn)
      echo "registry.cn-hangzhou.aliyuncs.com"
      ;;
    netease|163)
      echo "hub-mirror.c.163.com"
      ;;
    dockercn|docker-cn)
      echo "registry.docker-cn.com"
      ;;
    default|docker)
      echo "docker.io"
      ;;
    *)
      # 传入可能本身就是域名
      echo "$1"
      ;;
  esac
}

# 确认是否以 root 运行
require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "此脚本需要 root 权限，请使用 sudo 运行。"
    exit 2
  fi
}

# 备份 daemon.json
do_backup() {
  require_root
  mkdir -p "$BACKUP_DIR"
  if [[ -f "$DAEMON_JSON" ]]; then
    cp -a "$DAEMON_JSON" "$BACKUP_DIR/daemon.json"
    echo "已备份 $DAEMON_JSON 到 $BACKUP_DIR/daemon.json"
  else
    echo "未找到 $DAEMON_JSON，仍然创建空备份目录：$BACKUP_DIR"
  fi
}

# 恢复备份
do_restore() {
  require_root
  local src="$1"
  if [[ ! -f "$src" ]]; then
    echo "找不到备份文件: $src"
    exit 3
  fi
  cp -a "$src" "$DAEMON_JSON"
  echo "已从 $src 恢复到 $DAEMON_JSON"
  restart_docker
}

# 重启 Docker 服务（跨发行版尝试 systemctl 或 service）
restart_docker() {
  require_root
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl restart docker
    systemctl status docker --no-pager -l || true
  elif command -v service >/dev/null 2>&1; then
    service docker restart || true
  else
    echo "无法检测到 systemctl 或 service，Docker 是否通过其他方式管理？请手动重启 Docker。"
  fi
}

# 设置 registry
set_registry() {
  require_root
  local registry="$1"
  # 支持 registry 带端口或路径
  local mirror_entry
  # 生成 daemon.json 的镜像加速器结构（兼容多种 Docker 版本）
  cat > "$DAEMON_JSON.tmp" <<EOF
{
  "registry-mirrors": ["https://${registry}"]
}
EOF

  # 备份原文件
  if [[ -f "$DAEMON_JSON" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -a "$DAEMON_JSON" "$BACKUP_DIR/daemon.json"
    echo "已备份原始 $DAEMON_JSON 到 $BACKUP_DIR/daemon.json"
  else
    mkdir -p "$BACKUP_DIR"
  fi

  mv "$DAEMON_JSON.tmp" "$DAEMON_JSON"
  echo "已写入新配置到 $DAEMON_JSON"
  restart_docker
}

# 列出内置 registry
list_registries() {
  echo "内置镜像源："
  echo "  aliyun -> registry.cn-hangzhou.aliyuncs.com"
  echo "  netease -> hub-mirror.c.163.com"
  echo "  dockercn -> registry.docker-cn.com"
}

# 主解析
MAIN_SET=""
MAIN_BACKUP=false
MAIN_RESTORE=""
MAIN_APPLY=false
YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --set)
      MAIN_SET="$2"
      shift 2
      ;;
    --list)
      list_registries
      exit 0
      ;;
    --backup)
      MAIN_BACKUP=true
      shift
      ;;
    --restore)
      MAIN_RESTORE="$2"
      shift 2
      ;;
    --apply)
      MAIN_APPLY=true
      shift
      ;;
    --yes|-y)
      YES=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1"
      usage
      exit 1
      ;;
  esac
done

# 执行操作
if [[ "$MAIN_BACKUP" == true ]]; then
  do_backup
  exit 0
fi

if [[ -n "$MAIN_RESTORE" ]]; then
  do_restore "$MAIN_RESTORE"
  exit 0
fi

if [[ "$MAIN_APPLY" == true ]]; then
  restart_docker
  exit 0
fi

if [[ -n "$MAIN_SET" ]]; then
  REG=$(resolve_registry "$MAIN_SET")
  if [[ "$YES" != true ]]; then
    echo "将设置 Docker 镜像源为: $REG"
    read -r -p "继续吗？ [y/N]: " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "已取消"
      exit 0
    fi
  fi
  set_registry "$REG"
  exit 0
fi

# 如果没有参数则显示帮助
usage
exit 0
