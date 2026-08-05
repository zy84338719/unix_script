# 现代 CLI 工具集

安装一批现代命令行工具，替代传统命令，大幅提升终端体验。Linux + macOS。

## 工具映射

| 工具 | 替代 | 说明 |
|------|------|------|
| `bat` | cat | 语法高亮 + 行号 |
| `eza` | ls | 彩色 + 图标 + git 状态 |
| `ripgrep` (rg) | grep | 超快递归搜索 |
| `fd` | find | 更友好的文件查找 |
| `fzf` | — | 模糊查找（Ctrl+R 搜历史、Ctrl+T 搜文件） |
| `zoxide` (z) | cd | 智能跳转（记录常用目录） |
| `starship` | PS1 | 跨 shell 提示符（git/语言/耗时） |

## 安装

```bash
chmod +x modern-cli/install.sh
./modern-cli/install.sh            # 一键全部安装 + shell 集成
```

安装后自动配置 shell 集成（别名 + fzf 快捷键 + zoxide 初始化 + starship 提示符）。

## 使用

```bash
bat file.py             # 替代 cat（语法高亮）
eza -la --icons         # 替代 ls（彩色+图标+git）
rg 'pattern'            # 替代 grep（超快）
fd '\.py$'              # 替代 find
Ctrl+R                  # fzf 模糊搜历史命令
z project               # zoxide 跳转到含 "project" 的常用目录
```

## 状态与卸载

```bash
./modern-cli/install.sh status      # 查看状态
./modern-cli/install.sh uninstall   # 显示卸载说明
```

## 说明
- macOS 用 `brew install`，Linux 用包管理器（starship/eza 较新，缺失时自动回退官方脚本）。
- Debian 的 `fd-find` 命令是 `fdfind`，安装后自动创建 `fd` 符号链接。
- shell 集成写入 `~/.bashrc` / `~/.zshrc`（带标记，可识别清理）。
- starship 默认配置写入 `~/.config/starship.toml`。
