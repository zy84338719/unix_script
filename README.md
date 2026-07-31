# macOS/Linux 一键安装脚本集合

[![CI](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml/badge.svg)](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

一个跨平台的服务与环境安装脚本库，支持在 macOS 和 Linux 上一键安装、配置、卸载各种常用服务。

> 当前版本：见 [VERSION](VERSION) ｜ 更新日志：[CHANGELOG.md](CHANGELOG.md)

## 🌟 特性

- **跨平台支持**：同时支持 macOS 和 Linux
- **多架构兼容**：支持 x86_64、ARM64、ARMv7 等架构
- **智能检测**：自动检测操作系统、CPU 架构与包管理器
- **统一入口**：`install.sh` 交互式菜单（26+ 模块），也支持非交互命令行
- **一键卸载**：`uninstall.sh` 逐项或全量卸载
- **公共函数库**：`lib/common.sh` 统一打印、检测、服务管理
- **自动更新检查**：运行时自动检测远端新版本并提示（详见 [自动更新检查](#-自动更新检查)）
- **错误处理**：完善的依赖检查与回滚提示

## 📦 支持的服务

| 模块 | 说明 | Linux | macOS | 默认端口 |
|------|------|:-----:|:-----:|:--------:|
| [Node Exporter](node_exporter) | Prometheus 系统监控数据收集器 | ✅ | ✅ | 9100 |
| [DDNS-GO](ddns-go) | 动态域名解析服务 | ✅ | ✅ | 9876 |
| [WireGuard](wireguard) | 现代、快速、安全的 VPN | ✅ | ✅ | - |
| [Tailscale](tailscale) | 免公网 IP 的组网 VPN | ✅ | ✅ | - |
| [Docker](docker) | 容器引擎 (Engine / Desktop) | ✅ | ✅* | - |
| [Fail2ban](fail2ban) | SSH 暴力破解防护 | ✅ | ❌ | - |
| [OpenList](openlist) | 文件列表 / 网盘聚合（原 Alist） | ✅ | ✅ | 5244 |
| [Uptime Kuma](uptime-kuma) | 服务可用性监控面板 (Docker) | ✅ | ✅ | 3001 |
| [Cockpit](cockpit) | Linux Web 管理面板 | ✅ | ❌ | 9090 |
| [装机必备工具包](essential-pkgs) | curl/wget/git/vim/htop/tmux/jq 等一键装齐 | ✅ | ✅ | - |
| [系统初始化配置](sys-setup) | 换源/时区/系统优化/SSH 加固/自动安全更新 | ✅ | ✅ | - |
| [Swap 虚拟内存](swap) | 创建/调整 swap（小内存 VPS 必备） | ✅ | ❌ | - |
| [BBR 网络加速](bbr) | 开启 TCP BBR 拥塞控制 | ✅ | ❌ | - |
| [nvm](nvm) | Node.js 多版本管理 | ✅ | ✅ | - |
| [dev-mirror](dev-mirror) | 开发换源加速（npm/Go/Rust/Python） | ✅ | ✅ | - |
| [Zsh & Oh My Zsh](zsh_setup) | Shell 环境与插件配置 | ✅ | ✅ | - |
| [minikube](minikube) | 本地 Kubernetes 开发环境 (kubectl + minikube) | ✅ | ✅ | - |
| [终端 TUI 工具](dev-tui) | lazydocker + lazygit | ✅ | ✅ | - |
| [OpenCode](opencode) | 终端 AI 编程助手 (sst/opencode) | ✅ | ✅ | - |
| [Ollama](ollama) | 本地大模型运行时（跑 Llama/Qwen/DeepSeek） | ✅ | ✅ | 11434 |
| [自动关机管理](shutdown_timer) | 临时或每日定时关机 | ✅ | ✅ | - |
| [进程管理工具](process_manager_tool) | 智能搜索和管理系统进程 | ✅ | ✅ | - |
| [Deskflow](deskflow) | 键鼠共享 (Flatpak) | ✅ | ❌ | - |
| [safe-rm 回收站](safe-rm) | 安全删除替代 rm，防误删灾难 | ✅ | ✅ | - |
| [Clash (mihomo)](clash) | 代理核心 + 快速配置 + TUN 透明代理 | ✅ | ✅ | 7890 |
| [多网卡策略路由](multi-net) | 指定服务/用户/端口走指定网卡 | ✅ | ❌ | - |
| [Docker 镜像导出](docker-image) | 拉取公网镜像并导出为 .tar.gz（离线分发/备份） | ✅ | ✅ | - |

\* macOS 上引导安装 Docker Desktop。

## 🚀 快速开始

### 一键安装（推荐）

无需手动 clone，终端粘贴一行命令即可（自动下载并启动安装菜单）：

```bash
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash
```

也可直接安装指定模块或执行子命令（参数透传给 `install.sh`）：

```bash
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- docker
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash -s -- --status
```

> 引导脚本会将仓库克隆到 `~/.local/share/unix_script`；再次运行会自动 `git pull` 更新。详见 [bootstrap.sh](bootstrap.sh)。

### 📌 日常使用（幂等：一条命令通吃首次与更新）

**无论首次安装还是日后更新，都用同一条 `curl|bash` 命令**——它会自动检测：未安装则克隆，已安装则 `git pull` 更新到最新版。

```bash
# 首次安装 / 日后更新（同一条命令）
curl -fsSL https://raw.githubusercontent.com/zy84338719/unix_script/main/bootstrap.sh | bash
```

**常用非交互参数**（通过 `bash -s --` 透传，适合脚本/CI，无需进入菜单）：

```bash
curl -fsSL .../bootstrap.sh | bash -s -- --status      # 查看所有模块安装状态
curl -fsSL .../bootstrap.sh | bash -s -- --list        # 列出可用模块名
curl -fsSL .../bootstrap.sh | bash -s -- docker        # 直接安装指定模块
curl -fsSL .../bootstrap.sh | bash -s -- dev-mirror    # 开发换源（npm/Go/Rust/pip）
curl -fsSL .../bootstrap.sh | bash -s -- update        # 更新到最新版本（需确认）
```

> ⚠️ **注意**：`curl|bash` 管道模式下**无法进入交互式菜单**（标准输入被管道占用）。若要使用交互菜单，请先 [手动 clone](#交互式安装手动-clone) 后在终端直接运行 `./install.sh`。

**已克隆到本地后**，也可直接在仓库目录运行（支持完整交互菜单）：

```bash
cd ~/.local/share/unix_script   # bootstrap 的默认安装目录
./install.sh                    # 交互式主菜单
./install.sh update             # 更新到最新版本（需确认）
```

### 交互式安装（手动 clone）

```bash
git clone https://github.com/zy84338719/unix_script.git
cd unix_script
chmod +x install.sh
./install.sh
```

### 非交互式安装

```bash
./install.sh docker         # 直接安装 docker
./install.sh tailscale      # 直接安装 tailscale
./install.sh --status       # 查看所有模块安装状态
./install.sh --list         # 列出可用模块名
./install.sh --help         # 查看帮助
./install.sh --version      # 查看版本
./install.sh check-update   # 检查远端是否有新版本
./install.sh update         # 安全检查 + 确认后 git pull 更新
```

可用模块名：`node_exporter | ddns-go | wireguard | tailscale | docker | fail2ban | openlist | uptime-kuma | cockpit | essential-pkgs | sys-setup | swap | bbr | nvm | dev-mirror | zsh | minikube | dev-tui | opencode | ollama | deskflow | shutdown_timer | process_manager | safe-rm | clash | multi-net`

### 单独安装某模块

每个模块目录下都有独立的 `install.sh`，可直接运行：

```bash
./node_exporter/install.sh
./tailscale/install.sh install      # 显式子命令
./fail2ban/install.sh uninstall     # 卸载
```

通用子命令：`install | uninstall | status | help`

### 🔄 自动更新检查

运行 `install.sh` 时会自动（仅提示，不自动改动）检查 GitHub 是否发布了新版本，有更新会在顶部提示。也可手动检查或更新：

```bash
./install.sh check-update   # 检查是否有新版本
./install.sh update         # 安全检查 + 确认后 git pull 更新（需 git clone 来源）
```

> 环境变量 `UNIX_SCRIPT_NO_UPDATE_CHECK=1` 可关闭启动时的自动检查（CI / 离线场景适用）。

### ⌨️ 安装为全局命令（uxs）

安装后可在**任意目录**直接用 `uxs` 调用，免去每次进目录或敲长路径：

```bash
./install.sh cli            # 安装全局命令 uxs 到 ~/.tools/bin（自动配置 PATH）
uxs --version               # 之后任意目录可直接用
uxs docker-image            # 等价于 ./install.sh docker-image
uxs --status                # 等价于 ./install.sh --status

./install.sh uninstall-cli  # 卸载全局命令 uxs
```

> 安装会写入 shell 的 rc 文件（自动检测 bash/zsh/fish），将 `~/.tools/bin` 加入 PATH。需 `source ~/.zshrc`（或重开终端）后生效。

## 🗑️ 卸载

```bash
./uninstall.sh             # 逐项交互询问
./uninstall.sh docker      # 仅卸载 docker
./uninstall.sh --all       # 卸载全部（需二次确认）
```

> Zsh & Oh My Zsh 属敏感操作，未自动卸载，请参考文末说明手动处理。

## 💻 系统要求

- **操作系统**：macOS 10.12+ 或 Linux（任意主流发行版）
- **权限**：多数服务需要 sudo 权限
- **网络**：安装时需要互联网连接
- **依赖工具**：脚本会自动检查 `curl`、`tar` 等；macOS 服务通常需要 [Homebrew](https://brew.sh/)

## 📋 支持的平台与架构

| 操作系统 | 架构 | 服务安装 | 装机配置 | 开发环境 | AI 工具 |
|---------|------|:---:|:---:|:---:|:---:|
| Linux | x86_64 | ✅ | ✅ | ✅ | ✅ |
| Linux | ARM64 | ✅ | ✅ | ✅ | ✅ |
| Linux | ARMv7 | ✅ | ✅ | ✅ | ✅ |
| macOS | Intel (x86_64) | ✅* | ✅ | ✅ | ✅ |
| macOS | Apple Silicon (ARM64) | ✅* | ✅ | ✅ | ✅ |

\* 部分 Linux 专属服务（Fail2ban、Cockpit、Swap、BBR、Deskflow、多网卡策略路由）在 macOS 不可用，详见上方 [支持的服务](#-支持的服务) 表。

## 🔧 安装后配置

### Node Exporter
监听端口 9100：状态页面 `http://your-ip:9100`，指标 `http://your-ip:9100/metrics`。

```bash
# Linux
sudo systemctl status node_exporter
sudo journalctl -u node_exporter -f
# macOS
sudo launchctl list | grep node_exporter
tail -f /var/log/node_exporter.log
```

### DDNS-GO
Web 界面 `http://your-ip:9876`，首次访问需设置管理员密码并配置 DNS 服务商。

### WireGuard
需要配置文件才能启动：
- Linux：`/etc/wireguard/wg0.conf`
- macOS：`/usr/local/etc/wireguard/wg0.conf`

```bash
sudo systemctl status wg-quick@wg0       # Linux
sudo wg                                  # 查看状态
```

### Tailscale
安装后需登录：`sudo tailscale up`，详见 [tailscale/README.md](tailscale/README.md)。

### Docker
```bash
docker --version
sudo systemctl status docker             # Linux
sudo docker run hello-world              # 测试
```
安装时会询问是否将当前用户加入 `docker` 组（免 sudo，需重新登录生效）。

### Fail2ban（仅 Linux）
```bash
sudo fail2ban-client status              # 总览
sudo fail2ban-client status sshd         # sshd jail 详情
sudo tail -f /var/log/fail2ban.log
```
默认策略：封禁 1 小时、10 分钟内失败 5 次即封；本机与内网不封。调整请编辑 `/etc/fail2ban/jail.local`。

### OpenList（原 Alist）
Web 界面 `http://your-ip:5244`，详见 [openlist/README.md](openlist/README.md)。

### Uptime Kuma
基于 Docker 部署，Web 界面 `http://your-ip:3001`，详见 [uptime-kuma/README.md](uptime-kuma/README.md)。

### Cockpit（仅 Linux）
Web 管理面板 `http://your-ip:9090`，详见 [cockpit/README.md](cockpit/README.md)。

### Ollama
本地大模型运行时，API 端口 11434。安装后拉取模型：`ollama run llama3`，详见 [ollama/README.md](ollama/README.md)。

### Clash (mihomo)
代理端口 7890（HTTP/SOCKS），控制面板 9090。详见 [clash/README.md](clash/README.md)。

### Zsh & Oh My Zsh
自动安装 Zsh、Oh My Zsh 及 `zsh-autosuggestions`、`zsh-syntax-highlighting` 插件，并提示是否设为默认 Shell。安装后请**重启终端**。

## 🐛 故障排除

### 权限错误
```bash
sudo -v   # 测试 sudo 权限
```

### 网络问题
```bash
curl -I https://api.github.com
```

### 服务启动失败
```bash
# Linux
sudo systemctl status <service>
sudo journalctl -u <service> -f
# macOS
sudo launchctl list | grep <service>
tail -f /var/log/<service>.log
```

### 端口冲突
```bash
sudo ss -tlnp | grep :9100      # Linux
sudo lsof -i :9100              # macOS
```

## 🔍 本地质量检查

```bash
./check_issues.sh              # bash -n 语法检查 + shellcheck（若已安装）
./check_issues.sh --strict     # 不排除 SC2164 的严格模式
./check_issues.sh install.sh   # 仅检查指定文件
```

CI 驱动脚本也可本地复现：

```bash
./tests/ci_run.sh --phase static     # 静态检查（bash -n + shellcheck）
./tests/ci_run.sh --phase routing    # CLI 路由与子命令测试
./tests/ci_run.sh --phase install    # 实装测试（fail2ban / node_exporter / 进程管理工具）
```

## 🤖 持续集成 (CI)

[CI 工作流](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml) 在多个操作系统/发行版上验证脚本库，每次 push/PR 自动运行，结果通过顶部徽章实时反映。

**测试矩阵与分级**（设计原则：CI 的 pass/fail 只反映脚本质量，不因 CI 环境限制而误报）：

| 阶段 | 覆盖环境 | 内容 |
|------|----------|------|
| 静态检查 | ubuntu-latest, macos-latest | `bash -n` + `shellcheck`（全量脚本） |
| 路由测试 | ubuntu-latest, macos-latest | `lib/common.sh` source、`install.sh --version/--list/--status`、各模块 `status/help` |
| 实装测试 | ubuntu-latest VM（完整 systemd） + Debian/Fedora/CentOS 容器（包名解析） | Fail2ban、Node Exporter、进程管理工具真实安装/验证/卸载 |

**降级项**（CI 环境限制，不做完整实装，避免误报）：
- Docker (macOS)：runner 无嵌套虚拟化，Docker Desktop 无法安装 → 只测 Linux 分支
- WireGuard：runner 缺 `CAP_NET_ADMIN`/内核模块 → 只测包安装与卸载路由
- Tailscale：需真实登录认证 → 只测 status/help/包路由
- DDNS-GO：需真实 DNS 配置与端口 → 只测下载解压逻辑

每次运行会生成一份 **Markdown 测试报告**（`ci-report`），可在对应 Action 运行页面的 Artifacts 区下载；报告摘要也会显示在 commit/PR 的检查摘要中。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！贡献约定详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

新增模块要点：创建 `<name>/install.sh`（`source lib/common.sh`，实现 install/uninstall/status 子命令）+ `<name>/README.md`，并接入 `install.sh` 的主菜单/卸载菜单/状态页与 `uninstall.sh`。

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE)。

## 🙏 致谢

- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
- [DDNS-GO](https://github.com/jeessy2/ddns-go)
- [WireGuard](https://www.wireguard.com/)
- [Tailscale](https://tailscale.com/)
- [Docker](https://www.docker.com/)
- [Fail2ban](https://github.com/fail2ban/fail2ban)
- [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) / [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)

---
