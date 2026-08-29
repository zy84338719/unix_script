# Webmin 一键安装（仅 Linux）

[Webmin](https://webmin.com/) 是经典的开源 Web 系统管理面板，通过浏览器管理
用户账号、服务、cron 计划任务、文件、磁盘、防火墙与软件包等，几乎覆盖 Unix
系统管理的方方面面。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux (Debian/Ubuntu、RHEL/Alma/Rocky/Fedora、openSUSE) | ✅（官方仓库） |
| macOS | ❌（不适用） |

## 安装

```bash
./services/webmin/install.sh            # 安装（默认动作）
./services/webmin/install.sh install    # 显式安装
# 或经框架：./install.sh webmin
```

安装会：
1. 配置 Webmin 官方 APT/YUM 仓库（download.webmin.com，国内直连可达，
   不依赖 raw.githubusercontent.com）并导入官方签名密钥。
2. 通过包管理器安装 webmin（Deb 系含 `--install-recommends`）。
3. 若存在 `firewall-cmd`/`ufw`，自动放行 10000 端口。

## 访问

浏览器打开 `https://your-ip:10000`，使用**系统 root 账号与 root 密码**登录。
首次访问浏览器会提示自签证书不受信任，可忽略或后续在面板内配置正式证书。

## 常用命令

```bash
sudo systemctl status webmin
sudo systemctl restart webmin
grep ^port= /etc/webmin/miniserv.conf    # 查看实际端口（若改过）
# 忘记 root 的面板密码时重置：
sudo /usr/share/webmin/changepass.pl /etc/webmin root 新密码
```

## 卸载

```bash
./services/webmin/install.sh uninstall
```

卸载移除 webmin 包、官方仓库文件与签名密钥；`/etc/webmin` 配置目录二次确认后删除。

## 说明
- Webmin 走包管理器升级（`apt upgrade`/`dnf upgrade` 即可），无需重跑安装。
- 仅管理面板本体；系统内已有的 Nginx/MySQL 等由其「服务管理」模块纳管，无端口冲突。
