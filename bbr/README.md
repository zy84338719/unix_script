# TCP BBR 网络加速

开启 Google TCP BBR 拥塞控制算法，提升网络吞吐，尤其适合高延迟/丢包链路（国内服务器、跨境链路）。仅 Linux，需内核 ≥ 4.9。

## 用法

```bash
chmod +x bbr/install.sh
./bbr/install.sh enable    # 开启 BBR
./bbr/install.sh status    # 查看当前拥塞控制算法
./bbr/install.sh disable   # 关闭 BBR（恢复默认）
```

## 原理
写入 `/etc/sysctl.d/99-bbr.conf`：
```
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```
然后 `sysctl --system` 生效。

## 说明
- 现代 Linux 内核（4.9+）已内置 BBR，无需额外编译。
- 开启后用 `sysctl net.ipv4.tcp_congestion_control` 确认显示 `bbr` 即成功。
- 关闭时恢复为 `cubic`（大多数发行版默认算法）。
