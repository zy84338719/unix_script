# Deskflow 一键安装（Linux / macOS）

[Deskflow](https://github.com/deskflow/deskflow) 是跨计算机共享键盘与鼠标的开源工具（Synergy 的分支）。

- **Linux**：通过 Flatpak 安装（需图形环境）
- **macOS**：通过 Homebrew 官方 tap 安装（`deskflow/tap` cask，装到 `/Applications/Deskflow.app`）

## 支持平台

| 平台 | 支持情况 | 安装方式 |
|------|----------|----------|
| Linux（apt/dnf/yum，图形环境） | ✅ | Flatpak |
| macOS | ✅ | Homebrew cask |

## 安装

```bash
./sys-tools/deskflow/install.sh            # 安装（默认动作）
./sys-tools/deskflow/install.sh install    # 显式安装
```

### Linux（Flatpak）安装步骤

1. 通过包管理器安装 `flatpak` 与 `curl`。
2. 添加 Flathub 仓库（在线失败时回退离线添加）。
3. `flatpak install flathub org.deskflow.deskflow`。
4. 在 `~/.profile` 中配置 `XDG_DATA_DIRS` 以集成桌面菜单。

启动：
```bash
source ~/.profile            # 或注销/重启会话
flatpak run org.deskflow.deskflow
```

### macOS（Homebrew）安装步骤

1. 添加官方 tap：`brew tap deskflow/tap`（已存在则跳过）。
2. 安装 cask：`brew install --cask deskflow`。
3. 清除 quarantine 属性（兼容新版 macOS 启动限制）。

启动：
```bash
open -a Deskflow
```

> 若启动被 macOS 阻止（未签名提示），到「系统设置 → 隐私与安全性」点击「仍要打开」。

## 子命令

| 子命令 | 说明 |
|--------|------|
| `install` | 安装（默认动作） |
| `uninstall` | 卸载 |
| `status` | 查看安装状态 |
| `help` | 帮助信息 |

## 状态与卸载

```bash
./sys-tools/deskflow/install.sh status      # 查看是否已安装
./sys-tools/deskflow/install.sh uninstall   # 卸载
```

## 说明

- Linux 需要 sudo 权限（安装系统级 Flatpak 与包）；macOS 不需要 sudo（brew cask 用户级安装）。
- macOS 需先安装 Homebrew（可用 `./install.sh brew` 安装）。
