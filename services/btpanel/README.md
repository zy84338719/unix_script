# 宝塔面板一键安装（仅 Linux）

[宝塔面板](https://www.bt.cn/new/download.html) 是国内主流的 Linux 服务器运维面板，
通过浏览器管理网站（LNMP/LAMP）、数据库、FTP、SSL、计划任务、文件与防火墙等。
`en` 子命令可安装其国际版 [aaPanel](https://www.aapanel.com/)（英文界面）。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux (CentOS/Ubuntu/Debian 等，systemd) | ✅（官方脚本） |
| macOS | ❌（不适用） |

## 安装

```bash
./services/btpanel/install.sh            # 安装国内版（默认动作）
./services/btpanel/install.sh en         # 安装国际版 aaPanel
# 或经框架：./install.sh btpanel
```

安装会：
1. 下载并执行官方 `install_lts.sh`（国内版）或 `install_7.0_en.sh`（aaPanel）。
2. 交互终端下按官方脚本提示操作；非交互（管道/CI）环境自动应答 `y`。
3. 面板约 2 分钟装完，装在 `/www/server/panel`。

**注意**：宝塔官方要求在「纯净系统」上安装（无既有 Apache/Nginx/MySQL/PHP）。
本模块安装前会自动检测这些环境，命中时提示并要求二次确认，避免端口冲突。

## 常用命令

```bash
sudo bt default           # 面板地址/安全入口/默认密码（首次登录必查）
sudo bt                   # 面板管理菜单（重启/改端口/改密码等）
sudo /etc/init.d/bt start|stop|restart
```

首次访问 `http://服务器IP:面板端口/安全入口`（以 `bt default` 输出为准），
登录后务必立即修改默认账号密码。云服务器还需在安全组放行面板端口。

## 卸载

```bash
./services/btpanel/install.sh uninstall
```

默认停止面板并删除 `/etc/init.d/bt`、`bt` 命令与 `/www/server/panel`；
站点数据 `/www/wwwroot`、日志与数据库目录保留，二次确认后可选整体删除 `/www`。

## 说明
- 官方脚本会对面板端口与安全入口做随机化，请以 `sudo bt default` 输出为准。
- 面板依赖 LNMP 环境的安装/升级均在面板内操作，本模块只负责面板本身。
- 国内外官方源（download.bt.cn / aapanel.com）直连，无需镜像。
