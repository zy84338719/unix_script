# Deskflow 一键安装（Linux / Flatpak）

[Deskflow](https://github.com/deskflow/deskflow) 是跨计算机共享键盘与鼠标的开源工具（Synergy 的分支）。本模块通过 Flatpak 安装。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux（apt/dnf/yum，图形环境） | ✅ |
| macOS | ❌（不适用） |

## 安装

```bash
chmod +x deskflow/install.sh
./deskflow/install.sh            # 安装（默认动作）
./deskflow/install.sh install    # 显式安装
```

安装会：

1. 通过包管理器安装 `flatpak` 与 `curl`。
2. 添加 Flathub 仓库（在线失败时回退离线添加）。
3. `flatpak install flathub org.deskflow.deskflow`。
4. 在 `~/.profile` 中配置 `XDG_DATA_DIRS` 以集成桌面菜单。

## 启动

```bash
source ~/.profile            # 或注销/重启会话
flatpak run org.deskflow.deskflow
```

## 状态与卸载

```bash
./deskflow/install.sh status      # 查看是否已安装
./deskflow/install.sh uninstall   # 卸载
```

## 说明

- 仅适用于 Linux 图形环境（需 Flatpak 与桌面会话）。
- 需要 sudo 权限（安装系统级 Flatpak 与包）。
