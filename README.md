# unix_script

[![CI](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml/badge.svg)](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**macOS / Linux 服务与环境一键管理脚本库** — 54 个模块，统一子命令接口，覆盖服务部署、系统初始化、开发环境、AI 工具、系统运维全场景。支持 **x86_64 / ARM64 / ARMv7** 三大架构，适配银河麒麟 / 统信 UOS 等国产发行版。

> 当前版本：[VERSION](VERSION)（v1.14.0） · 更新日志：[CHANGELOG.md](CHANGELOG.md) · AI 接口说明：[AGENTS.md](AGENTS.md)

---

## ✨ 核心特性

- **一行安装**：无需 clone，`curl | bash` 即可拉起任意模块
- **54 个模块**：服务 / 装机必备 / 开发环境 / AI 工具 / 系统工具，5 大分类全覆盖
- **统一接口**：所有模块遵循 `install / uninstall / status / help` 约定
- **注册表驱动**：模块自带 `.manifest` 元数据，自动发现、自动排序、自动别名
- **AI / 脚本友好**：`--status-json`、`--list-modules`、`--list-categories` 三种机器可读输出
- **交互 + 非交互双模**：终端用户用菜单，AI / CI 用参数透传
- **全局命令 `uxs`**：装一次，任意目录可用
- **Tab 补全**：bash / zsh 自动补全模块名与子命令
- **预览模式 `--dry-run`**：只打印不执行，安全审计
- **环境诊断 `doctor`**：一键检查运行前提
- **模块脚手架 `scaffold`**：一行命令生成新模块模板
- **安全自更新**：`update` 自动检查 + 确认 + `git pull`
- **国产化适配**：银河麒麟 / 统信 UOS / openEuler / deepin / openKylin 的发行版与桌面环境自动识别
- **多发行版 CI**：Ubuntu / macOS 实机 + 主流发行版容器 + 国产化容器矩阵验证

---

## 🚀 快速开始

### 方式一：一行安装（推荐新手）

```bash
# 启动交互式菜单（首次自动 clone，之后自动 git pull 更新）
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash

# 非交互：直接安装指定模块
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- docker
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- tailscale
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- --status-json

# 子命令透传
curl -fsSL .../bootstrap.sh | bash -s -- bun mirror
curl -fsSL .../bootstrap.sh | bash -s -- clash start
```

### 方式二：本地 clone（完整功能）

```bash
git clone https://github.com/zy84338719/unix_script.git && cd unix_script
./install.sh                  # 交互式主菜单
./install.sh docker           # 非交互安装
./install.sh tailscale        # 非交互安装
./install.sh bun mirror       # 模块子命令透传
./install.sh sys-setup all    # 一次性执行所有系统初始化
```

---

## 🧰 全部命令与选项

### 日常使用

| 命令 | 说明 |
|------|------|
| `./install.sh` | 进入交互式主菜单 |
| `./install.sh <模块>` | 非交互安装该模块（默认动作） |
| `./install.sh <模块> <子命令>` | 透传子命令到模块（如 `clash start`） |
| `./install.sh -s` / `--status` | 查看所有模块安装状态 |

### 信息查询

| 命令 | 说明 |
|------|------|
| `./install.sh -h` / `--help` | 显示帮助（含所有模块名） |
| `./install.sh -v` / `--version` | 显示版本 |
| `./install.sh --list` | 列出所有模块名（空格分隔，适合脚本） |
| `./install.sh --list-modules` | TSV：模块名 + 支持的子命令 + 描述（AI / 脚本友好） |
| `./install.sh --list-categories` | 按分类分组列出模块 |
| `./install.sh search <关键字>` | 搜索模块（名称/别名/描述，多关键字 AND；无匹配退出 1） |
| `./install.sh --status-json` | key:value 状态（无颜色无 emoji，AI 友好） |

### 工具链命令

| 命令 | 说明 |
|------|------|
| `./install.sh doctor` | 环境诊断：Bash 版本 / 必要工具 / 包管理器 / 磁盘 / 网络 / sudo |
| `./install.sh check-update` | 检查远端是否有新版本（不修改本地） |
| `./install.sh update` | 安全检查 + 确认后 `git pull` 更新 |
| `./install.sh --dry-run <模块>` | 预览模式：只打印将执行的操作，不实际执行 |
| `./install.sh --no-deps <模块>` | 安装但跳过依赖自动安装 |
| `./install.sh export [文件]` | 导出已装模块+配置为 profile（默认 `~/.config/unix_script/profile.txt`） |
| `./install.sh apply [文件] [--force\|--dry-run]` | 从 profile 复现安装（已装跳过；`--force` 重装） |
| `./install.sh cli` | 安装全局命令 `uxs` 到 `~/.tools/bin` |
| `./install.sh uninstall-cli` | 卸载全局命令 `uxs` |
| `./install.sh completions` | 安装 Tab 自动补全到当前 shell 配置 |
| `./install.sh scaffold <名称> [选项]` | 生成新模块脚手架 |

#### `scaffold` 选项

```bash
./install.sh scaffold my-module --category 服务 --label "我的服务"
# 在 services/ 下创建 my-module/install.sh + .manifest + README.md
# category 取值：服务 / 装机必备 / 开发环境 / AI工具 / 系统工具
```

---

## 🤖 机器可读输出（AI / 脚本 / CI 友好）

专为 AI agent 与自动化脚本设计，三种格式覆盖所有场景：

```bash
# 1) 模块名 + 子命令 + 描述（TSV，解析最方便；第 3 列为 DESC 描述）
$ ./install.sh --list-modules
node_exporter  install uninstall status help  Prometheus 系统指标收集器
bun            install mirror unmirror uninstall status help  Bun 运行时（含国内镜像加速）
clash          install uninstall status start stop restart enable disable help  代理核心 + TUN 透明代理（mihomo）

# 2) 当前安装状态（key:value，无颜色无 emoji；首 3 行为框架元数据 os/arch/version）
$ ./install.sh --status-json
os:darwin
arch:ARM64
version:1.14.0
node_exporter:not_installed
docker:installed:running
bun:installed:v1.3.14

# 3) 按分类分组（人类可读）
$ ./install.sh --list-categories
[服务] docker nginx redis ...
[装机必备] sys-setup nvm brew ...
```

**去除颜色**（管道 / 日志场景）：

```bash
NO_COLOR=1 ./install.sh --status    # 强制无颜色
./install.sh --status-json          # --status-json 始终无颜色
```

> AI agent 的典型工作流详见 [AGENTS.md](AGENTS.md)。

---

## 🖥️ 交互式菜单

无参数运行 `./install.sh` 进入交互菜单。根据环境自动选择模式（`UXS_MENU=fzf|bash` 强制指定）：

**fzf 模式**（检测到 [fzf](https://github.com/junegunn/fzf) 时自动启用）
- 输入关键字模糊搜索模块（模块名 / 名称 / 中文描述）
- `TAB` 勾选多个模块，回车批量执行默认动作（install 依赖自动先装）
- 右侧预览窗格显示模块 README（fzf ≥ 0.20）

**bash 分类菜单**（无 fzf 时自动降级）
- 首页选分类（服务 / 装机必备 / 开发环境 / AI工具 / 系统工具，附「已装/总数」），再进模块列表
- 每行含状态图标与中文描述：`✓` 已安装 · 空白 未安装 · `·` 本平台不适用
- 支持一次多选：输入 `1,3,5-8`（逗号/区间可混合）
- 输入 `/关键字` 过滤当前分类（匹配模块名/名称/描述），单独输入 `/` 清空过滤
- `b` 返回上级；首页：`s` 状态总览 · `u` 卸载 · `c` 检查更新 · `f` 刷新状态缓存 · `q` 退出

菜单内的安装状态来自并行查询的跨进程缓存：默认缓存 300 秒（`UXS_STATUS_CACHE_TTL` 调整，`0` 禁用），并发度 `UXS_STATUS_JOBS`（默认 8）。

---

## 📦 全部 54 个模块

> 平台：✅ 支持 · ❌ 不适用 · ✅* 引导安装。带「别名」的模块可用别名调用，如 `./install.sh pg` = postgres。

### 🌐 服务（17 个）

| 模块 | 说明 | 别名 | Linux | macOS |
|------|------|------|:-----:|:-----:|
| [docker](services/docker) | 容器引擎（Engine / Desktop） | — | ✅ | ✅* |
| [nginx](services/nginx) | Web 服务器 / 反向代理 | — | ✅ | ✅ |
| [caddy](services/caddy) | 现代 Web 服务器（自动 HTTPS） | — | ✅ | ✅ |
| [redis](services/redis) | 内存数据库 / 缓存 | — | ✅ | ✅ |
| [postgres](services/postgres) | PostgreSQL 数据库 | postgresql, pg | ✅ | ✅ |
| [prometheus](services/prometheus) | 监控系统（时间序列数据库） | — | ✅ | ✅ |
| [grafana](services/grafana) | 监控可视化面板 | — | ✅ | ✅ |
| [node_exporter](services/node_exporter) | Prometheus 系统指标收集器 | nodeexporter | ✅ | ✅ |
| [uptime-kuma](services/uptime-kuma) | 服务可用性监控面板（Docker） | uptime_kuma | ✅ | ✅ |
| [gitea](services/gitea) | 自托管 Git 服务 | — | ✅ | ✅ |
| [openlist](services/openlist) | 文件列表 / 网盘聚合（原 Alist） | — | ✅ | ✅ |
| [ddns-go](services/ddns-go) | 动态域名解析服务 | ddnsgo, ddns | ✅ | ✅ |
| [certbot](services/certbot) | Let's Encrypt 免费 SSL 证书 | letsencrypt | ✅ | ✅ |
| [fail2ban](services/fail2ban) | SSH 暴力破解防护 | f2b | ✅ | ❌ |
| [cockpit](services/cockpit) | Linux Web 管理面板 | — | ✅ | ❌ |
| [tailscale](services/tailscale) | 免公网 IP 的组网 VPN | ts | ✅ | ✅ |
| [wireguard](services/wireguard) | 现代、快速、安全的 VPN | wg | ✅ | ✅ |

### 🧱 装机必备（6 个）

| 模块 | 说明 | 别名 | Linux | macOS |
|------|------|------|:-----:|:-----:|
| [essential-pkgs](essentials/essential-pkgs) | curl/git/vim/htop/tmux/jq 等一键装齐 | essential, essential_pkgs | ✅ | ✅ |
| [sys-setup](essentials/sys-setup) | 换源/时区/NTP/优化/SSH 加固/自动更新 | sys_setup | ✅ | ✅ |
| [nvm](essentials/nvm) | Node.js 多版本管理 | — | ✅ | ✅ |
| [brew](essentials/brew) | Homebrew 包管理器 | homebrew | ❌ | ✅ |
| [swap](essentials/swap) | 创建 / 调整 swap 虚拟内存 | — | ✅ | ❌ |
| [bbr](essentials/bbr) | TCP BBR 拥塞控制加速 | — | ✅ | ❌ |

### 👨‍💻 开发环境（12 个）

| 模块 | 说明 | 别名 | Linux | macOS |
|------|------|------|:-----:|:-----:|
| [bun](dev-tools/bun) | Bun 运行时（含国内镜像加速） | — | ✅ | ✅ |
| [deno](dev-tools/deno) | Deno 运行时 | — | ✅ | ✅ |
| [go](dev-tools/go) | Go 语言环境 | golang | ✅ | ✅ |
| [rust](dev-tools/rust) | Rust 语言环境 | rustup | ✅ | ✅ |
| [pnpm](dev-tools/pnpm) | Node.js 包管理器 | — | ✅ | ✅ |
| [dev-mirror](dev-tools/dev-mirror) | 开发换源加速（npm/Go/Rust/pip） | dev_mirror, devmirror | ✅ | ✅ |
| [dev-enhance](dev-tools/dev-enhance) | Neovim+LazyVim / git delta / tmux 配置 | — | ✅ | ✅ |
| [dev-tui](dev-tools/dev-tui) | lazydocker + lazygit | dev_tui, tui | ✅ | ✅ |
| [modern-cli](dev-tools/modern-cli) | bat/eza/ripgrep/fd/fzf/zoxide/starship | modern_cli, moderncli | ✅ | ✅ |
| [zsh_setup](dev-tools/zsh_setup) | Zsh + Oh My Zsh + 插件配置 | zsh | ✅ | ✅ |
| [code-lint](dev-tools/code-lint) | 代码分析工具集 | codelint, code_lint, lint-tools | ✅ | ✅ |
| [minikube](dev-tools/minikube) | 本地 Kubernetes 开发环境 | — | ✅ | ✅ |

### 🤖 AI 工具（3 个）

| 模块 | 说明 | 别名 | Linux | macOS |
|------|------|------|:-----:|:-----:|
| [ollama](ai-tools/ollama) | 本地大模型运行时 | — | ✅ | ✅ |
| [opencode](ai-tools/opencode) | 终端 AI 编程助手 | — | ✅ | ✅ |
| [pi](ai-tools/pi) | Pi AI 编程代理框架 | — | ✅ | ✅ |

### 🛠️ 系统工具（16 个）

| 模块 | 说明 | 别名 | Linux | macOS |
|------|------|------|:-----:|:-----:|
| [clash](sys-tools/clash) | 代理核心 + TUN 透明代理（mihomo） | mihomo | ✅ | ✅ |
| [sys-cmd](sys-tools/sys-cmd) | 系统诊断命令集（cpu/mem/port/disk/net） | sys_cmd, syscmd | ✅ | ✅ |
| [disk-usage](sys-tools/disk-usage) | 磁盘空间管理（top 大目录下钻 / 监控 / 清理） | du, disk_usage | ✅ | ✅ |
| [disk](sys-tools/disk) | 磁盘管理工具箱：分区/格式化/挂载/SMART 体检/坏块扫描/擦除 | — | ✅ | ❌ |
| [ops-kit](sys-tools/ops-kit) | 运维工具箱：一键巡检/日志运维/systemd 服务/安全基线 | ops, opskit | ✅ | ❌ |
| [docker-image](sys-tools/docker-image) | 镜像导出为 .tar.gz（离线分发） | docker_image, dockerimage | ✅ | ✅ |
| [process_manager_tool](sys-tools/process_manager_tool) | 智能搜索和管理系统进程 | process_manager, pm | ✅ | ✅ |
| [shutdown_timer](sys-tools/shutdown_timer) | 定时 / 倒计时关机管理 | shutdown | ✅ | ✅ |
| [safe-rm](sys-tools/safe-rm) | 安全删除替代 rm，防误删 | safe_rm, safesrm | ✅ | ✅ |
| [nat](sys-tools/nat) | NAT 端口转发 | port-forward, forward, nat-manager | ✅ | ✅ |
| [multi-net](sys-tools/multi-net) | 多网卡策略路由 | multinet, multi_net | ✅ | ❌ |
| [ufw](sys-tools/ufw) | UFW 防火墙管理 | firewall | ✅ | ❌ |
| [restic](sys-tools/restic) | 增量加密备份工具 | — | ✅ | ✅ |
| [deskflow](sys-tools/deskflow) | 键鼠共享（Flatpak / Homebrew） | — | ✅ | ✅ |
| [k7s](sys-tools/k7s) | k7s 工具 | — | ✅ | ✅ |
| [upftp](sys-tools/upftp) | 轻量级 FTP 文件分享工具 | — | ✅ | ✅ |

\* macOS 上引导安装 Docker Desktop。

---

## 📋 统一子命令接口

所有模块遵循同一套约定，学习一个即可用全部：

```bash
./install.sh <模块> install     # 安装 / 配置（默认动作）
./install.sh <模块> uninstall   # 卸载
./install.sh <模块> status      # 查看状态（输出一行结论，退出 0，用于探测）
./install.sh <模块> help        # 用法说明
```

### 模块扩展子命令

部分模块提供额外子命令（用 `--list-modules` 查询完整列表）：

```bash
# 开发环境 —— 国内镜像加速
./install.sh bun mirror              # Bun 切国内镜像源
./install.sh bun unmirror            # 恢复官方源
./install.sh dev-mirror all          # npm/Go/Rust/pip 全部换源

# 代理与网络
./install.sh clash start             # 启动 mihomo
./install.sh clash stop              # 停止
./install.sh clash restart           # 重启
./install.sh clash enable            # 开机自启
./install.sh clash disable           # 禁用自启

# 磁盘空间分析
./install.sh disk-usage top --depth 2    # 多层大目录下钻（交互终端可序号下钻）
./install.sh disk-usage clean            # 一键清理

# 运维工具箱（仅 Linux）
./install.sh ops-kit inspect             # 一键巡检报告（默认动作，只读）
./install.sh ops-kit inspect --json      # 机器可读巡检结果
./install.sh ops-kit svc failed          # systemd 失败单元排查
./install.sh ops-kit audit all           # SSH 基线/公网端口/待更新自查

# 系统初始化（一次性全套）
./install.sh sys-setup all           # 换源 + 时区 + NTP + 内核优化 + SSH 加固 + 自动更新
./install.sh sys-setup mirror        # 仅换源
./install.sh sys-setup ssh           # 仅 SSH 加固
./install.sh sys-setup optimize      # 仅内核参数优化
./install.sh sys-setup ntp           # 仅配置 NTP
./install.sh sys-setup timezone      # 仅设时区
./install.sh sys-setup unattended    # 仅配置自动更新

# 直接调用（绕过 install.sh，进入子菜单）
./dev-tools/dev-mirror/install.sh install all default
./sys-tools/multi-net/install.sh list
./sys-tools/sys-cmd/install.sh menu
./sys-tools/docker-image/install.sh save
./sys-tools/disk/install.sh wizard    # 新盘一键上线：分区→格式化→挂载→fstab（仅 Linux）
./essentials/bbr/install.sh enable
```

### 别名机制

每个模块在 `.manifest` 中可声明 `ALIASES`，支持简写调用：

```bash
./install.sh pg           # = postgres
./install.sh ts           # = tailscale
./install.sh wg           # = wireguard
./install.sh f2b          # = fail2ban
./install.sh du           # = disk-usage
./install.sh pm           # = process_manager_tool
./install.sh homebrew     # = brew
./install.sh zsh          # = zsh_setup
```

---

## 🌍 全局命令 `uxs`

安装一次后，任意目录都可调用：

```bash
./install.sh cli                  # 安装 uxs 到 ~/.tools/bin（自动配置 PATH）
uxs docker                        # 任意目录安装 docker
uxs bun mirror                    # 任意目录换源
uxs --status-json                 # 任意目录查状态
uxs doctor                        # 任意目录环境诊断
uxs uninstall-cli                 # 卸载 uxs 自身
```

支持 bash / zsh / fish 的 PATH 配置，自动备份 shell rc 文件。

### Tab 自动补全

```bash
./install.sh completions          # 一键安装到 shell 配置（自动检测 bash/zsh）
source completions/uxs.bash       # 或手动 source（bash）
source completions/uxs.zsh        # 或手动 source（zsh）
# 之后输入 uxs <Tab> 即可补全模块名与子命令
```

---

## 🧪 预览与环境诊断

### `--dry-run` 预览模式

只打印将执行的操作，不实际改动系统，适合审计与 CI：

```bash
./install.sh --dry-run docker            # 预览 docker 安装流程
./install.sh --dry-run sys-setup all     # 预览系统初始化
```

### `doctor` 环境诊断

一键检查运行 unix_script 的所有前提条件：

```bash
./install.sh doctor
# 检查项：Bash 版本 / curl/tar/git/sudo / shellcheck/jq /
#         操作系统 / CPU 架构 / 包管理器 / 磁盘空间 / 网络连通 / sudo 权限
# 返回值 = 发现的问题数（0 = 一切就绪）
```

---

## 🗑️ 卸载

```bash
./uninstall.sh                  # 交互式逐项询问
./uninstall.sh docker           # 仅卸载指定模块
./uninstall.sh --all            # 卸载全部（需二次确认）
./uninstall.sh -h               # 帮助
```

卸载入口同样注册表驱动，自动发现所有 `.manifest` 模块。

---

<!-- SUPPORT-MATRIX:START（由 scripts/support_matrix.sh 自动生成，勿手改） -->
## 🖥️ 支持的操作系统与 CI 状态

> 状态列 = main 分支最近一次完成的 CI run 中对应 job 的结论，由 `support-matrix` 任务自动刷新。

| 分类 | 系统 | 镜像 / 版本 | 包管理 | CI |
|------|------|-------------|--------|:--:|
| 实机 | Ubuntu（runner 内置） | ubuntu-latest | apt | ✅ |
| 实机 | macOS（runner 内置） | macos-latest | brew | ✅ |
| 容器 | Ubuntu 26.04 | `ubuntu:26.04` | apt | ✅ |
| 容器 | Ubuntu 24.04 | `ubuntu:24.04` | apt | ✅ |
| 容器 | Debian 12 | `debian:12` | apt | ✅ |
| 容器 | Debian 13 | `debian:13` | apt | ✅ |
| 容器 | Fedora | `fedora:latest` | dnf/yum | ✅ |
| 容器 | CentOS Stream 9 | `quay.io/centos/centos:stream9` | dnf/yum | ✅ |
| 容器 | AlmaLinux 9 | `almalinux:9` | dnf/yum | ✅ |
| 容器 | Rocky Linux 9 | `rockylinux:9` | dnf/yum | ✅ |
| 容器 | openSUSE Leap 15.6 | `opensuse/leap:15.6` | zypper | ❌ |
| 容器 | Arch Linux | `archlinux:latest` | pacman | ✅ |
| 容器 | Alpine Linux | `alpine:latest` | apk | ✅ |
| 国产化* | 银河麒麟 V10 SP3 | `docker.io/macrosan/kylin:v10-sp3-2403` | dnf/yum | ✅ |
| 国产化* | 统信 UOS V20 | `docker.io/macrosan/uos:v20-1070` | dnf/yum | ✅ |
| 国产化* | openEuler 24.03 LTS | `docker.io/openeuler/openeuler:24.03-lts` | dnf/yum | ✅ |
| 国产化* | deepin 23 | `docker.io/linuxdeepin/deepin:latest` | apt | ✅ |
| 国产化* | openKylin | `docker.io/openkylin/openkylin:latest` | apt | ✅ |

> \* 国产化社区镜像为尽力而为（continue-on-error）：结果记入报告，不阻塞质量门禁。
