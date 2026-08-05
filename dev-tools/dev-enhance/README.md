# 开发工具增强（Neovim + git + tmux）

一站式增强开发工具：Neovim（+LazyVim）、git 全局配置（+delta diff 高亮）、tmux 配置（+tpm 插件）。

## 功能

### Neovim + LazyVim
- 安装 Neovim（macOS brew / Linux 包管理器 / AppImage 兜底）
- 安装 [LazyVim](https://github.com/LazyVim/starter) 配置模板到 `~/.config/nvim`（首次启动自动装插件）

### git 增强
- 全局配置：默认分支 main、颜色、编辑器、pull 策略
- 实用别名：`git st`(status)、`git co`(checkout)、`git lg`(彩色日志树)
- [delta](https://github.com/dandavison/delta) diff 高亮：集成到 git pager

### tmux 配置
- 前缀键改为 `Ctrl+a`
- 鼠标支持、true color、vim 风格窗格切换
- `|` 水平分屏、`-` 垂直分屏（更直观）
- [tpm](https://github.com/tmux-plugins/tpm) 插件管理 + tmux-resurrect（会话持久化）

## 安装

```bash
chmod +x dev-enhance/install.sh
./dev-enhance/install.sh            # 一键全部安装
```

## 使用

```bash
nvim                    # 启动 Neovim（首次自动装 LazyVim 插件）
git lg                  # 彩色日志树
tmux                    # 启动 tmux
# tmux 内：Ctrl+a | 水平分屏，Ctrl+a - 垂直分屏，Ctrl+a I 装 tpm 插件
```

## 状态与卸载

```bash
./dev-enhance/install.sh status      # 查看状态
./dev-enhance/install.sh uninstall   # 显示卸载说明
```
