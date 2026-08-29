# CasaOS 一键安装（仅 Linux）

[CasaOS](https://www.casaos.io/) 是开源的家庭云/NAS 轻量面板：内置 Docker 应用商店、
文件管理、系统监控，把一台 Linux 机器变成家庭私有云。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux (Debian/Ubuntu/RHEL 等，systemd) | ✅（官方脚本） |
| macOS | ❌（不适用） |

## 安装

```bash
./services/casaos/install.sh            # 安装（默认动作）
./services/casaos/install.sh install    # 显式安装
# 或经框架：./install.sh casaos
```

安装会：
1. 下载并执行官方安装脚本（get.casaos.io，会按需安装 Docker 组件，耗时数分钟）。
2. **执行前探测 80 端口**：CasaOS 默认占用 80 端口，与 nginx/caddy 等冲突时
   会提示并要求二次确认。

## 访问

浏览器打开 `http://your-ip`（80 端口），首次访问创建本地管理员账号（仅存本机）。
端口冲突时可登录后在「设置 → 常规 → 端口」修改。

## 常用命令

```bash
sudo systemctl status casaos
sudo systemctl restart casaos
```

## 卸载

```bash
./services/casaos/install.sh uninstall
```

走官方卸载脚本，移除 casaos 全家桶服务；已创建的 Docker 应用容器与数据默认保留。

## 说明
- CasaOS 面向家庭/居家服务器场景；若做公网业务面板，建议用 1Panel/宝塔（见同目录）。
- 应用商店需要 Docker；官方脚本会自动处理，也可用本库 `docker` 模块预装。
