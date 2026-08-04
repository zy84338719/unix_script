# AGENTS.md

本文件供 AI agent（Claude Code / Cursor / Copilot / opencode / Pi 等）阅读，说明如何使用 unix_script 脚本库。

## 这是什么

unix_script 是一个 macOS/Linux 脚本库，提供 47 个模块的安装、配置与管理。每个模块支持统一的子命令接口。

## 快速调用（AI agent 友好）

### 列出所有模块

```bash
./install.sh --list
# 输出：空格分隔的模块名
# node_exporter ddns-go wireguard tailscale docker ...
```

### 机器可读的模块清单（含子命令）

```bash
./install.sh --list-modules
# 输出 TSV：模块名\t支持子命令
# node_exporter  install uninstall status help
# bun            install mirror unmirror uninstall status help
```

### 按分类列出模块

```bash
./install.sh --list-categories
# 输出：按分类分组的模块列表（服务/网络/系统/开发环境/AI工具）
```

### 机器可读状态

```bash
./install.sh --status-json
# 输出 key:value（每行一个，无颜色无 emoji）
# node_exporter:not_installed
# docker:installed:running
# bun:installed:v1.3.14
```

### 安装/操作模块

```bash
# 非交互安装某模块（AI 推荐方式）
./install.sh <模块名>           # 默认动作（通常=install）
./install.sh <模块名> install   # 显式安装
./install.sh bun mirror         # 模块子命令透传

# 示例
./install.sh docker             # 安装 Docker
./install.sh fail2ban           # 安装 Fail2ban
./install.sh sys-setup all      # 全部系统初始化配置
./install.sh bun mirror         # Bun 换国内镜像源
```

### 去除颜色（管道/日志场景）

所有输出支持 `NO_COLOR=1` 环境变量（或管道自动检测）：

```bash
NO_COLOR=1 ./install.sh --status
./install.sh --status-json       # --status-json 始终无颜色
```

## 模块子命令约定

所有可执行模块遵循统一接口：

| 子命令 | 说明 |
|--------|------|
| `install` | 安装/配置（默认动作） |
| `uninstall` | 卸载 |
| `status` | 查看状态（输出一行结论） |
| `help` | 用法说明 |

部分模块有额外子命令（如 `bun mirror`、`clash start`、`sys-setup all`），用 `--list-modules` 查询。

## 直接调用模块（绕过 install.sh）

```bash
./<模块目录>/install.sh <子命令>
# 例：./bun/install.sh status
#     ./clash/install.sh start
```

## 一行安装（bootstrap）

```bash
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- <模块名> [子命令]
```

## AI agent 典型工作流

1. `./install.sh --status-json` → 了解当前已装/未装
2. `./install.sh --list-modules` → 了解可用模块及子命令
3. `./install.sh <需要的模块>` → 安装
4. `./install.sh <模块> status` → 确认结果

## 注意事项

- `install` 类操作可能需要 sudo（脚本内部处理 `require_sudo`）
- 某些模块仅 Linux（macOS 会输出"不适用"并退出 0）
- 状态子命令始终退出 0（用于探测），安装子命令失败退出非 0
- 输出为中文，子命令名和模块名为英文
