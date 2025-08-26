#!/usr/bin/env bash
# install_deskflow.sh — Ubuntu 24.04 一键安装 Deskflow（Flatpak）

set -e

# 1. 检查 sudo 权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 或以 root 用户运行此脚本"
  exit 1
fi

echo "==== 1. 更新 apt 源并安装必要组件 ===="
apt update
apt install -y flatpak curl

echo
echo "==== 2. 添加 Flathub 仓库（如已存在则跳过） ===="
if flatpak remotes | grep -q '^flathub'; then
  echo "Flathub 已存在，跳过"
else
  # 在线添加
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    && echo "Flathub 添加成功" \
    || { echo "Flathub 添加失败，尝试离线添加…"; \
         curl -fsSL https://dl.flathub.org/repo/flathub.flatpakrepo -o /tmp/flathub.flatpakrepo && \
         flatpak remote-add --if-not-exists flathub /tmp/flathub.flatpakrepo; }
fi

echo
echo "==== 3. 安装 Deskflow ===="
flatpak install -y flathub org.deskflow.deskflow

echo
echo "==== 4. 配置桌面集成（XDG_DATA_DIRS） ===="
PROFILE="$HOME/.profile"
LINE='export XDG_DATA_DIRS=/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:$XDG_DATA_DIRS'
if grep -Fxq "$LINE" "$PROFILE"; then
  echo "$PROFILE 中已包含 XDG_DATA_DIRS 配置，跳过"
else
  echo "$LINE" >> "$PROFILE"
  echo "已追加 XDG_DATA_DIRS 到 $PROFILE"
fi

echo
echo "==== 安装完成 ===="
echo "请执行："
echo "  source \$HOME/.profile"
echo "或注销/重启会话后，即可在应用菜单中找到 Deskflow 并通过："
echo "  flatpak run org.deskflow.deskflow"
echo "来启动 Deskflow。"

exit 0
