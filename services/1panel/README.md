# 1Panel 一键安装（仅 Linux）

[1Panel](https://1panel.cn/) 是 FIT2CLOUD 开源的新一代 Linux 服务器运维管理面板
（本模块安装 v2），通过浏览器管理网站、数据库、容器、计划任务、文件与防火墙等。

## 支持平台

| 平台 | 支持情况 |
|------|----------|
| Linux (apt/dnf/yum，systemd) | ✅（官方支持 Ubuntu/Debian/CentOS/openEuler 等） |
| macOS | ❌（不适用） |

## 安装

```bash
./services/1panel/install.sh            # 安装（默认动作）
./services/1panel/install.sh install    # 显式安装
# 或经框架：./install.sh 1panel
```

安装会：
1. 下载并执行官方 `quick_start.sh`（v2，来自 resource.fit2cloud.com）。
2. 按交互提示选择安装目录（默认 /opt）、端口、安全入口与账号密码。

### 非交互安装（AI / 脚本友好）

透传官方 `PANEL_*` 环境变量即可跳过全部交互：

```bash
PANEL_NON_INTERACTIVE=true PANEL_LANG=zh \
PANEL_PORT=18080 PANEL_ENTRANCE=entrance PANEL_USERNAME=admin \
PANEL_PASSWORD='ChangeMe_123456' \
./services/1panel/install.sh install
```

完整参数见[官方文档](https://1panel.cn/docs/v2/installation/online_installation/)；
`PANEL_INSTALL_DOCKER=y` 可让 1Panel 顺带安装 Docker（默认不装）。

## 常用命令

```bash
sudo 1pctl user-info      # 面板地址/安全入口/账号
sudo 1pctl status         # 服务状态
sudo 1pctl restart        # 重启面板
./services/1panel/install.sh update   # 升级（1pctl update）
```

## 卸载

```bash
./services/1panel/install.sh uninstall
```

卸载保留数据目录（默认 `/opt/1panel`），站点与镜像数据不受影响。

## 说明
- 面板端口与安全入口安装时生成，忘记时用 `sudo 1pctl user-info` 查询。
- 1Panel 的应用商店功能依赖 Docker，可在面板内或通过本库 `docker` 模块安装。
