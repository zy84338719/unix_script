# Zsh & Oh My Zsh

一键配置 Zsh + [Oh My Zsh](https://ohmyz.sh/) + 常用插件（zsh-autosuggestions、zsh-syntax-highlighting）。Linux + macOS。

## 支持平台

| 平台 | 安装方式 |
|------|----------|
| Linux (apt/yum) | 包管理器安装 Zsh |
| macOS | Homebrew 安装 Zsh（macOS 自带 Zsh 但版本较旧） |

## 安装

```bash
chmod +x zsh_setup/install.sh
./zsh_setup/install.sh            # 安装（默认动作）
./zsh_setup/install.sh install    # 显式安装
```

安装内容：
1. Zsh（如未安装）
2. Oh My Zsh（装到 `~/.oh-my-zsh`）
3. 插件：`zsh-autosuggestions`（命令建议）、`zsh-syntax-highlighting`（语法高亮）
4. 自动配置 `~/.zshrc` 启用上述插件
5. 可选：将 Zsh 设为默认 shell

## 状态与卸载

```bash
./zsh_setup/install.sh status      # 查看安装状态
./zsh_setup/install.sh uninstall   # 显示卸载说明（手动执行）
```

## 说明

- 需要 `git` 和 `curl`，脚本会自动检测。
- Oh My Zsh 安装器会备份已有的 `~/.zshrc`。
- 更换默认 shell 后需重新登录生效。
- Oh My Zsh 官方卸载命令：`uninstall_oh_my_zsh`
- 切回 bash：`chsh -s /bin/bash`
- 官方文档：https://ohmyz.sh/docs
