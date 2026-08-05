# 终端 TUI 开发工具（lazydocker + lazygit）

安装两款流行的终端 TUI 开发工具，提升命令行下的 Docker/Git 操作体验：

- [lazydocker](https://github.com/jesseduffield/lazydocker) —— Docker 终端 UI
- [lazygit](https://github.com/jesseduffield/lazygit) —— Git 终端 UI

## 支持平台

| 平台 | 架构 | 支持 |
|------|------|:----:|
| Linux | x86_64 / ARM64 / ARMv7 | ✅ |
| macOS | x86_64 / ARM64 | ✅ |

## 安装

```bash
chmod +x dev-tui/install.sh
./dev-tui/install.sh            # 安装（默认动作）
./dev-tui/install.sh install    # 显式安装
```

下载官方 Go 二进制到 `~/.local/bin/`（纯用户态，无需 sudo）。

## PATH 配置

若 `~/.local/bin` 不在 PATH 中，添加到 shell 配置：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## 使用

```bash
lazydocker      # 进入 Docker TUI（查看容器/镜像/日志/资源）
lazygit         # 进入 Git TUI（提交/分支/合并/rebase）
```

## 卸载

```bash
./dev-tui/install.sh uninstall
```

## 说明
- 纯用户态安装，最稳定，CI 上 Linux + macOS 均可验证。
- 版本通过 GitHub API 获取，CI 中带 `GH_TOKEN` 认证规避速率限制。
