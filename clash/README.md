# Clash (mihomo / clash.meta) 一键安装与配置

安装 [mihomo](https://github.com/MetaCubeX/mihomo)（clash.meta）—— 活跃维护的 clash 核心分叉，支持新协议。仅 Linux 服务器命令行场景。

> 原版 clash 已于 2023 年停更，社区主流是 mihomo（clash.meta）分叉，本模块即装 mihomo。

## 子命令

| 子命令 | 说明 |
|--------|------|
| `install` | 下载 mihomo 二进制 + 配置 systemd 服务（默认动作） |
| `config <url\|file>` | 下载订阅 URL 或复制本地文件为 `/etc/mihomo/config.yaml` |
| `example` | 生成最小示例配置（HTTP/SOCKS 混合端口 7890） |
| `tun-on` / `tun-off` | 开启/关闭 TUN 透明代理（全网卡流量走代理） |
| `start` / `stop` / `restart` | 服务管理 |
| `status` | 查看状态 |
| `uninstall` | 卸载 |

## 快速开始

```bash
chmod +x clash/install.sh
./clash/install.sh install                              # 装二进制 + systemd
./clash/install.sh config https://your-subscription.url # 放入订阅
./clash/install.sh start                                # 启动
```

## 使用代理

启动后本地提供代理端口：
```bash
# HTTP/SOCKS 混合端口 7890
curl -x http://127.0.0.1:7890 https://ifconfig.me

# 让命令行临时走代理
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890

# 管理 API（可用 yacd/metacubexd 面板）
# http://127.0.0.1:9090
```

## TUN 透明代理（全局）

让整机所有流量自动走代理（无需逐个设代理环境变量）：
```bash
./clash/install.sh tun-on       # 开启（自动开 ip_forward，需 NET_ADMIN）
./clash/install.sh restart      # 生效
./clash/install.sh tun-off      # 关闭
```

## 示例配置（无订阅时）

```bash
./clash/install.sh example      # 生成最小可用配置（直连模式，便于验证安装）
./clash/install.sh start
```

## 卸载

```bash
./clash/install.sh uninstall    # 会询问是否删除配置（订阅/节点）
```

## 说明
- 二进制装到 `/opt/mihomo/mihomo`，配置在 `/etc/mihomo/config.yaml`。
- systemd 服务配置了 `CAP_NET_ADMIN`（TUN 模式需要）。
- 优先下载 `-compatible` 变体（兼容老 CPU），失败回退标准版。
- 节点/订阅配置请遵守当地法律法规。
