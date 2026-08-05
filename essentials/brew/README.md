# Homebrew

macOS（及 Linux）上最流行的包管理器。通过官方脚本安装，支持一键配置国内镜像源加速。

## 支持平台

- ✅ macOS（推荐，含 Apple Silicon / Intel）
- ⚠️ Linux（Linuxbrew，部分 formula 不支持）

## 子命令

| 子命令 | 说明 |
|--------|------|
| `install` | 安装 Homebrew（默认动作） |
| `uninstall` | 卸载 Homebrew（交互确认） |
| `mirror` | 配置国内镜像源（清华 TUNA） |
| `unmirror` | 还原官方源 |
| `status` | 查看安装状态和当前源 |
| `help` | 帮助信息 |

## 快速开始

```bash
# 安装 Homebrew
./install.sh brew

# 查看状态
./install.sh brew status

# 配置国内镜像（加速下载）
./install.sh brew mirror

# 还原官方源
./install.sh brew unmirror

# 卸载
./install.sh brew uninstall
```

## 镜像说明

`mirror` 子命令配置以下清华 TUNA 镜像：

| 变量 | 地址 |
|------|------|
| `HOMEBREW_API_DOMAIN` | `https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api` |
| `HOMEBREW_BREW_GIT_REMOTE` | `https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git` |
| `HOMEBREW_CORE_GIT_REMOTE` | `https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git` |
| `HOMEBREW_BOTTLE_DOMAIN` | `https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles` |

配置写入 `~/.zprofile`（zsh）或 `~/.bash_profile`（bash），重新打开终端生效。

## Apple Silicon 注意事项

Apple Silicon（M1/M2/M3/M4）Mac 上，Homebrew 安装到 `/opt/homebrew`，而非 Intel 的 `/usr/local`。安装脚本会自动配置 `PATH`，无需手动处理。
