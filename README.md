# unix_script

[![CI](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml/badge.svg)](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

macOS / Linux 服务与环境一键管理脚本库 — 52 个模块，统一子命令接口，支持 x86_64 / ARM64 / ARMv7。

> 版本：[VERSION](VERSION) · 更新日志：[CHANGELOG.md](CHANGELOG.md)

## 快速开始

```bash
# 一行安装（自动下载并启动菜单；已安装则 git pull 更新）
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash

# 非交互：直接安装指定模块
curl -fsSL .../bootstrap.sh | bash -s -- docker
curl -fsSL .../bootstrap.sh | bash -s -- --status
```

本地 clone 后可使用完整交互菜单：

```bash
git clone https://github.com/zy84338719/unix_script.git && cd unix_script
./install.sh                  # 交互式主菜单
./install.sh docker           # 非交互安装
./install.sh bun mirror       # 模块子命令透传
./install.sh --status         # 查看所有模块状态
./install.sh --list           # 列出可用模块名
./install.sh --version        # 查看版本
./install.sh update           # 更新到最新版
```

### 全局命令 `uxs`

```bash
./install.sh cli              # 安装 uxs 到 ~/.tools/bin
uxs docker                    # 任意目录可用
uxs --status
```

### 开发者工具

```bash
# 模块脚手架：一键生成新模块模板
./install.sh scaffold my-module --category 服务 --label "我的服务"

# 环境诊断：检查运行前提条件
./install.sh doctor

# Tab 补全（bash / zsh）
./install.sh completions       # 一键安装到 shell 配置
source completions/uxs.bash    # 或手动 source（bash）
source completions/uxs.zsh     # 或手动 source（zsh）
```

## 模块列表

| 分类 | 模块 | 说明 | Linux | macOS |
|------|------|------|:-----:|:-----:|
| **服务** | [node_exporter](services/node_exporter) | Prometheus 系统监控数据收集器 | ✅ | ✅ |
| | [ddns-go](services/ddns-go) | 动态域名解析服务 | ✅ | ✅ |
| | [docker](services/docker) | 容器引擎 (Engine / Desktop) | ✅ | ✅* |
| | [fail2ban](services/fail2ban) | SSH 暴力破解防护 | ✅ | ❌ |
| | [openlist](services/openlist) | 文件列表 / 网盘聚合（原 Alist） | ✅ | ✅ |
| | [uptime-kuma](services/uptime-kuma) | 服务可用性监控面板 (Docker) | ✅ | ✅ |
| | [cockpit](services/cockpit) | Linux Web 管理面板 | ✅ | ❌ |
| | [nginx](services/nginx) | Web 服务器 / 反向代理 | ✅ | ✅ |
| | [caddy](services/caddy) | 现代 Web 服务器（自动 HTTPS） | ✅ | ✅ |
| | [certbot](services/certbot) | Let's Encrypt 免费 SSL 证书 | ✅ | ✅ |
| | [redis](services/redis) | 内存数据库 / 缓存 | ✅ | ✅ |
| | [postgres](services/postgres) | PostgreSQL 数据库 | ✅ | ✅ |
| | [prometheus](services/prometheus) | 监控系统（时间序列数据库） | ✅ | ✅ |
| | [grafana](services/grafana) | 监控可视化面板 | ✅ | ✅ |
| | [gitea](services/gitea) | 自托管 Git 服务 | ✅ | ✅ |
| | [tailscale](services/tailscale) | 免公网 IP 的组网 VPN | ✅ | ✅ |
| | [wireguard](services/wireguard) | 现代、快速、安全的 VPN | ✅ | ✅ |
| **装机必备** | [essential-pkgs](essentials/essential-pkgs) | curl/git/vim/htop/tmux/jq 等一键装齐 | ✅ | ✅ |
| | [sys-setup](essentials/sys-setup) | 换源/时区/NTP/优化/SSH 加固/自动更新 | ✅ | ✅ |
| | [nvm](essentials/nvm) | Node.js 多版本管理 | ✅ | ✅ |
| | [brew](essentials/brew) | Homebrew 包管理器 | ❌ | ✅ |
| | [swap](essentials/swap) | 创建/调整 swap 虚拟内存 | ✅ | ❌ |
| | [bbr](essentials/bbr) | TCP BBR 拥塞控制加速 | ✅ | ❌ |
| **开发环境** | [bun](dev-tools/bun) | Bun 运行时（含国内镜像加速） | ✅ | ✅ |
| | [deno](dev-tools/deno) | Deno 运行时 | ✅ | ✅ |
| | [go](dev-tools/go) | Go 语言环境 | ✅ | ✅ |
| | [rust](dev-tools/rust) | Rust 语言环境 | ✅ | ✅ |
| | [pnpm](dev-tools/pnpm) | Node.js 包管理器 | ✅ | ✅ |
| | [dev-mirror](dev-tools/dev-mirror) | 开发换源加速（npm/Go/Rust/pip） | ✅ | ✅ |
| | [dev-enhance](dev-tools/dev-enhance) | Neovim+LazyVim / git delta / tmux 配置 | ✅ | ✅ |
| | [dev-tui](dev-tools/dev-tui) | lazydocker + lazygit | ✅ | ✅ |
| | [modern-cli](dev-tools/modern-cli) | bat/eza/ripgrep/fd/fzf/zoxide/starship | ✅ | ✅ |
| | [minikube](dev-tools/minikube) | 本地 Kubernetes 开发环境 | ✅ | ✅ |
| | [zsh_setup](dev-tools/zsh_setup) | Zsh + Oh My Zsh + 插件配置 | ✅ | ✅ |
| | [code-lint](dev-tools/code-lint) | 代码分析工具集 | ✅ | ✅ |
| **AI 工具** | [ollama](ai-tools/ollama) | 本地大模型运行时 | ✅ | ✅ |
| | [opencode](ai-tools/opencode) | 终端 AI 编程助手 | ✅ | ✅ |
| | [pi](ai-tools/pi) | Pi AI 编程代理框架 | ✅ | ✅ |
| **系统工具** | [docker-image](sys-tools/docker-image) | 镜像导出为 .tar.gz（离线分发） | ✅ | ✅ |
| | [clash](sys-tools/clash) | 代理核心 + TUN 透明代理 (mihomo) | ✅ | ✅ |
| | [multi-net](sys-tools/multi-net) | 多网卡策略路由 | ✅ | ❌ |
| | [nat](sys-tools/nat) | NAT 端口转发 | ✅ | ✅ |
| | [sys-cmd](sys-tools/sys-cmd) | 系统诊断命令集（cpu/mem/port/disk/net） | ✅ | ✅ |
| | [safe-rm](sys-tools/safe-rm) | 安全删除替代 rm，防误删 | ✅ | ✅ |
| | [shutdown_timer](sys-tools/shutdown_timer) | 定时/倒计时关机管理 | ✅ | ✅ |
| | [process_manager_tool](sys-tools/process_manager_tool) | 智能搜索和管理系统进程 | ✅ | ✅ |
| | [ufw](sys-tools/ufw) | UFW 防火墙管理 | ✅ | ❌ |
| | [restic](sys-tools/restic) | 增量加密备份工具 | ✅ | ✅ |
| | [deskflow](sys-tools/deskflow) | 键鼠共享 (Flatpak) | ✅ | ❌ |
| | [disk-usage](sys-tools/disk-usage) | 磁盘空间管理 | ✅ | ✅ |
| | [k7s](sys-tools/k7s) | k7s 工具 | ✅ | ✅ |
| | [upftp](sys-tools/upftp) | 轻量级 FTP 文件分享工具 | ✅ | ✅ |

\* macOS 上引导安装 Docker Desktop。

## 通用子命令

所有模块遵循统一接口：

```bash
./install.sh <模块> install     # 安装（默认动作）
./install.sh <模块> uninstall   # 卸载
./install.sh <模块> status      # 查看状态
./install.sh <模块> help        # 用法说明
```

部分模块有额外子命令（如 `bun mirror`、`clash start`、`sys-setup all`），用 `--list-modules` 查询。

## 机器可读输出（AI / 脚本友好）

```bash
./install.sh --list-modules     # TSV：模块名\t子命令列表
./install.sh --list-categories  # 按分类列出模块
./install.sh --status-json      # key:value 状态（无颜色无 emoji）
NO_COLOR=1 ./install.sh --status  # 去除颜色
```

详见 [AGENTS.md](AGENTS.md)。

## 卸载

```bash
./uninstall.sh                  # 逐项交互询问
./uninstall.sh docker           # 仅卸载指定模块
./uninstall.sh --all            # 卸载全部（需二次确认）
```

## 系统要求

- **操作系统**：macOS 10.12+ 或 Linux（任意主流发行版）
- **权限**：多数服务需要 sudo（脚本内部处理）
- **网络**：安装时需要互联网连接
- **依赖**：脚本自动检查 `curl`、`tar` 等；macOS 服务通常需要 [Homebrew](https://brew.sh/)

## 本地质量检查

```bash
./scripts/check_issues.sh                  # bash -n + shellcheck
./scripts/check_issues.sh --strict         # 严格模式
./tests/ci_run.sh --phase static   # 静态检查
./tests/ci_run.sh --phase routing  # CLI 路由测试
```

## CI

[CI 工作流](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml) 在 Ubuntu / macOS / Debian / Fedora / CentOS 上验证脚本，每次 push/PR 自动运行。测试报告可在 Action 页面 Artifacts 区下载。

## 贡献

欢迎 Issue 和 PR！详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

新增模块：在对应分类目录下创建 `<分类>/<name>/install.sh`（`source ../../lib/common.sh`，实现 install/uninstall/status）+ `<分类>/<name>/.manifest`，并接入主菜单与卸载菜单。

## 架构

```
install.sh                 # 入口骨架
bootstrap.sh               # 一行安装引导
uninstall.sh               # 卸载入口
lib/
  common.sh                # 共享函数库（打印/检测/包管理）
  core.sh                  # 框架核心（run_in_dir / run_submenu）
  registry.sh              # 模块注册表（.manifest 扫描/查询）
  status.sh                # 状态检查
  submenus.sh              # 子菜单回调
  uxs_cli.sh               # 全局命令 uxs 管理
  menu.sh                  # 主菜单 / 交互循环 / 机器可读输出
  scaffold.sh              # 模块脚手架（生成新模块模板）
  doctor.sh                # 环境诊断
services/                  # 服务类模块（17 个）
essentials/                # 装机必备模块（6 个）
dev-tools/                 # 开发环境模块（12 个）
ai-tools/                  # AI 工具模块（3 个）
sys-tools/                 # 系统工具模块（14 个）
  <模块名>/
    install.sh             # 模块入口
    .manifest              # 元数据（名称/分类/子命令/默认动作）
    README.md              # 模块文档
completions/
  uxs.bash                 # Bash 自动补全
  uxs.zsh                  # Zsh 自动补全
scripts/                   # 辅助脚本
tests/                     # CI 测试
docs/                      # 文档
```

## 许可证

[MIT](LICENSE)
