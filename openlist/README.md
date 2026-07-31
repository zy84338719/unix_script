# OpenList 一键安装（原 Alist）

[OpenList](https://github.com/OpenListTeam/OpenList)（原 Alist，2024 年更名）是一个文件列表程序，支持聚合多种存储后端（本地、网盘、对象存储等），并提供 WebDAV 访问。

## 支持平台

| 平台 | 架构 | 支持 |
|------|------|:----:|
| Linux | x86_64 / ARM64 / ARMv7 | ✅ |
| macOS | x86_64 / ARM64 | ✅ |

## 安装

```bash
chmod +x openlist/install.sh
./openlist/install.sh            # 安装（默认动作）
./openlist/install.sh install    # 显式安装
```

安装会：下载官方二进制到 `/opt/openlist/`，配置 systemd（Linux）或 launchd（macOS）开机自启，默认监听 **5244** 端口。

## 首次登录

- 访问 `http://your-ip:5244`
- 默认管理员账号：**admin**
- 初始随机密码见安装日志；可用以下命令重设：

```bash
sudo /opt/openlist/openlist admin set NEW_PASSWORD
```

## 常用命令

```bash
# Linux
sudo systemctl status openlist
sudo journalctl -u openlist -f

# macOS
sudo launchctl list | grep openlist
tail -f /var/log/openlist.log
```

## 卸载

```bash
./openlist/install.sh uninstall
```

卸载时会询问是否删除 `/opt/openlist`（含配置与数据库）。

## 说明
- OpenList 通过 GitHub API 取版本，CI 中通过 `GH_TOKEN` 规避速率限制。
- 更名说明：Alist 项目于 2024 年迁移并更名为 OpenList（仓库 `OpenListTeam/OpenList`），本模块已跟进。
- 详细存储后端配置请参考 [OpenList 文档](https://openlist.bio/)。
