# 更新日志

本文件记录 unix_script 项目的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)。

## [1.1.0] - 2026-07-30

### 新增
- **公共函数库** `lib/common.sh`：统一颜色、打印函数（`info/success/warn/error/header/menu`）、平台/架构检测、包管理器检测、权限检查、依赖检查、IP/版本号获取、服务管理封装（systemd/launchd）。
- **新服务模块**：
  - `tailscale/`：基于官方安装脚本封装，支持 Linux（apt/yum/dnf）与 macOS（Homebrew）。
  - `docker/`：Linux 用 get.docker.com 一键安装，可选加入 docker 组；macOS 引导安装 Docker Desktop。
  - `fail2ban/`：仅 Linux，安装并写入保护 sshd 的默认 `jail.local`。
- **一键卸载入口** `uninstall.sh`：支持逐项交互、`--all` 全量卸载、单模块卸载。
- **文档**：`VERSION`、`CHANGELOG.md`、`CONTRIBUTING.md`。
- **`.gitignore`**：忽略 `.DS_Store`、备份文件、`.tools/`、临时下载产物等。

### 变更
- 重写 `check_issues.sh`：优先使用系统 shellcheck 做真实静态检查（与 CI 一致），并对所有脚本做 `bash -n` 语法检查；shellcheck 缺失时回退到 grep 启发式并给出安装指引。
- 重构 `install.sh`（主菜单）：
  - 接入 3 个新模块，菜单编号改为连续（1-9）。
  - 新增非交互命令行：`--help`、`--version`、`--status`、`--list`、`<模块名>` 直接安装。
  - 修复 `manage_process_tool` 用递归改为 `while` 循环，并在每轮重新检测安装状态。
  - 子目录脚本调用改用子 shell `( cd ... && bash ... )`，避免 `set -e` 下工作目录被污染。
  - 卸载菜单新增 Tailscale/Docker/Fail2ban 项，并修复 Zsh 卸载项实际调用 `uninstall_zsh_omz`（此前为死代码）。
- 现有模块（`node_exporter`、`ddns-go`、`wireguard`、`zsh_setup`、`shutdown_timer`）改为 `source lib/common.sh`，统一打印函数命名与颜色码（修复 zsh_setup 中颜色码缺失 ESC 转义的缺陷）。

### 修复
- `install.sh` 主菜单从选项 6 跳到 8 的编号空缺（无选项 7）。
- `install.sh` 中 `uninstall_zsh_omz()` 函数从未被调用的死代码。
- `zsh_setup/install.sh` 颜色码 `[0;31m` 缺少 `\033` 转义前缀。

## [1.0.0] - 2025
- 初始版本：Node Exporter、DDNS-GO、WireGuard、Zsh & Oh My Zsh、自动关机、进程管理工具。
- 统一安装菜单 `install.sh`、ShellCheck CI、快捷访问脚本。
