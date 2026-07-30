# macOS/Linux 一键安装脚本集合

[![CI](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml/badge.svg)](https://github.com/zy84338719/unix_script/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

一个跨平台的服务与环境安装脚本库，支持在 macOS 和 Linux 上一键安装、配置、卸载各种常用服务。

> 当前版本：见 [VERSION](VERSION) ｜ 更新日志：[CHANGELOG.md](CHANGELOG.md)

## 🌟 特性

- **跨平台支持**：同时支持 macOS 和 Linux
- **多架构兼容**：支持 x86_64、ARM64、ARMv7 等架构
- **智能检测**：自动检测操作系统、CPU 架构与包管理器
- **统一入口**：`install.sh` 交互式菜单，也支持非交互命令行
- **一键卸载**：`uninstall.sh` 逐项或全量卸载
- **公共函数库**：`lib/common.sh` 统一打印、检测、服务管理
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
| [Zsh & Oh My Zsh](zsh_setup) | Shell 环境与插件配置 | ✅ | ✅ | - |
| [自动关机管理](shutdown_timer) | 临时或每日定时关机 | ✅ | ✅ | - |
| [进程管理工具](process_manager_tool) | 智能搜索和管理系统进程 | ✅ | ✅ | - |

\* macOS 上引导安装 Docker Desktop。

## 🚀 快速开始

### 交互式安装（推荐）

```bash
git clone <repository-url>
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
```

可用模块名：`node_exporter | ddns-go | wireguard | tailscale | docker | fail2ban | zsh | shutdown_timer | process_manager`

### 单独安装某模块

每个模块目录下都有独立的 `install.sh`，可直接运行：

```bash
./node_exporter/install.sh
./tailscale/install.sh install      # 显式子命令
./fail2ban/install.sh uninstall     # 卸载
```

通用子命令：`install | uninstall | status | help`

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

| 操作系统 | 架构 | Node Exporter | DDNS-GO | WireGuard | Tailscale | Docker | Fail2ban |
|---------|------|:---:|:---:|:---:|:---:|:---:|:---:|
| Linux | x86_64 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Linux | ARM64 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Linux | ARMv7 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| macOS | Intel (x86_64) | ✅ | ✅ | ✅ | ✅ | ✅* | ❌ |
| macOS | Apple Silicon (ARM64) | ✅ | ✅ | ✅ | ✅ | ✅* | ❌ |

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

**注意**：这些脚本会修改系统配置并安装服务，请在生产环境使用前充分测试。
