# Nerd Font（终端图标字体）

安装 Nerd Font 图标字体，是 Powerlevel10k / starship / `eza --icons` 等工具图标正常显示的前提。

**核心约束：字体由终端模拟器（客户端）渲染**——SSH 远程机上装字体对远程会话无效，请在本地终端机执行本模块。

## 支持平台

- ✅ macOS（brew cask，装到本机）
- ✅ Linux 桌面（`~/.local/share/fonts/NerdFonts/` + fc-cache；远程/无头机 install 会提示跳过）

## 可安装字体

JetBrainsMono（默认）/ FiraCode / Hack / CascadiaCode

```bash
./install.sh nerd-font                                  # 默认 JetBrainsMono
UXS_CONFIG_FONTS="JetBrainsMono,FiraCode" ./install.sh nerd-font
./install.sh nerd-font list                             # 可安装清单
```

## 子命令

| 子命令 | 说明 |
|--------|------|
| `install` | 安装（默认动作） |
| `list` | 列出可安装字体 |
| `uninstall` | 卸载 |
| `status` | 查看状态 |
| `help` | 帮助信息 |

## 说明

- macOS cask 名映射：JetBrainsMono→`font-jetbrains-mono-nerd-font`、FiraCode→`font-fira-code-nerd-font`、Hack→`font-hack-nerd-font`、CascadiaCode→`font-cascadia-code-nf`（新版 cask 命名为 `-nf` 后缀）。
- Linux 从 nerd-fonts GitHub release 下载 `<FontName>.tar.xz`（v3.5.1 实测资产名）。
- 安装后需在终端模拟器的字体设置里选择对应的 Nerd Font 字体才会生效。
