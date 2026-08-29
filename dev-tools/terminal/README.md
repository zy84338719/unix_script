# 终端全家桶（terminal）

一键配好整套终端体验：`zsh → zsh_setup（Oh My Zsh + 插件/主题）→ modern-cli（9 件现代工具）→ nerd-font（图标字体）→ atuin（历史增强）`。每环节幂等跳过已装，可重跑。

## 安装

```bash
./install.sh terminal                    # 全套默认（oh-my-zsh 框架 + JetBrainsMono + 纯本地 atuin）
UXS_CONFIG_THEME=p10k ./install.sh terminal
UXS_CONFIG_EXCLUDE=atuin,nerd-font ./install.sh terminal   # 裁剪环节
```

## 可调项（经 UXS_CONFIG_* 透传给子模块）

| 环节变量 | 默认 | 说明 |
|----------|------|------|
| `UXS_CONFIG_FRAMEWORK` | oh-my-zsh | zsh 框架（prezto/zinit/sheldon 可选） |
| `UXS_CONFIG_THEME` | 框架默认 | 主题（`p10k` 走 Powerlevel10k） |
| `UXS_CONFIG_FONTS` | JetBrainsMono | 字体清单，逗号分隔 |
| `UXS_CONFIG_SYNC` | 0 | atuin 同步开关 |
| `UXS_CONFIG_EXCLUDE` | 空 | 裁剪环节名（zsh,zsh_setup,modern-cli,nerd-font,atuin） |

## 子命令

| 子命令 | 说明 |
|--------|------|
| `install` | 一键编排（默认动作） |
| `status` | 各环节就绪状态（机器模式 `EXTRA=missing=...`） |
| `help` | 帮助信息 |

## 设计说明

- **不用阶段 E REQUIRES**：REQUIRES 自动装依赖无法传递框架/字体偏好，故自编排带参调用子模块脚本；`UXS_CONFIG_*` 经进程继承自然透传。
- **EXPORTABLE 分工**：terminal 不声明；zsh_setup/nerd-font/atuin 各自声明（`framework,theme`/`fonts`/`sync`），profile 按行逐模块注入，无同键冲突，单独使用子模块时同样可复现。
- Nerd Font 装在本地终端机（字体由客户端渲染）；SSH 远程机上该环节会自动跳过并提示。
