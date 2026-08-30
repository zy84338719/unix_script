# frp

内网穿透（fatedier/frp）：`frps` 跑在有公网 IP 的服务器上，`frpc` 跑在内网机器，
把内网服务暴露出去。GitHub release 二进制安装；Linux 附 systemd unit（默认不启用）
与完整配置样例（`/etc/frp/frpc.toml`、`frps.toml`，已存在不覆盖）。

```bash
./install.sh frp                                  # 安装
sudo vim /etc/frp/frps.toml                       # 服务端：bindPort + token
sudo systemctl enable --now frps                  # 启动服务端
```

互补：动态域名 ddns-go、组网 tailscale。
