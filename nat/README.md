# NAT 端口转发

管理 Linux 服务器的 NAT 规则：DNAT 端口转发 + SNAT/MASQUERADE 共享上网。

## 功能

- **DNAT 端口转发**：把外部端口的请求转发到本机或内网机器的指定端口
- **MASQUERADE 共享上网**：让内网机器通过本机访问外网（类似路由器）
- **规则持久化**：systemd service 开机自动加载规则
- **规则管理**：添加、删除、查看转发规则，支持 TCP/UDP

## 快速开始

```bash
# 安装（开启 IP forwarding + 配置 systemd 持久化）
./nat/install.sh install

# 端口转发：公网 8443 → 内网 192.168.1.100:443
./nat/install.sh forward add 8443 192.168.1.100:443

# 端口转发：外部 3306 → 本机 3307
./nat/install.sh forward add 3306 127.0.0.1:3307

# UDP 转发
./nat/install.sh forward add 5353 192.168.1.1:53 --proto udp

# 共享上网：内网网卡 eth1 的机器通过本机上网
./nat/install.sh gateway enable eth1 --source 192.168.1.0/24

# 查看状态
./nat/install.sh status
```

## 子命令

| 子命令 | 说明 |
|--------|------|
| `install` | 安装依赖、开启 IP forwarding、配置 systemd 持久化 |
| `uninstall` | 清除规则、关闭 IP forwarding、移除持久化 |
| `forward add <端口> <目标:端口> [--proto tcp\|udp]` | 添加 DNAT 转发规则 |
| `forward del <端口> [--proto tcp\|udp]` | 删除指定转发规则 |
| `forward list` | 列出所有转发规则 |
| `gateway enable <网卡> [--source CIDR]` | 开启 MASQUERADE（共享上网） |
| `gateway disable <网卡>` | 关闭 MASQUERADE |
| `status` | 总览（IP forwarding、规则数、服务状态） |
| `help` | 显示帮助 |

## 使用场景

### 场景 1：把公网端口映射到内网服务器

```bash
# 把公网 8443 映射到内网 Web 服务器
./nat/install.sh forward add 8443 192.168.1.100:443

# 把公网 80 映射到内网 HTTP 服务器
./nat/install.sh forward add 80 192.168.1.100:80
```

### 场景 2：本机端口转发（避免端口冲突）

```bash
# 把 3306 转发到本机的 3307
./nat/install.sh forward add 3306 127.0.0.1:3307
```

### 场景 3：内网共享上网

```bash
# 让连接 eth1 的内网机器通过本机上网
./nat/install.sh gateway enable eth1 --source 192.168.1.0/24
```

### 场景 4：UDP 端口转发

```bash
# DNS 转发
./nat/install.sh forward add 5353 192.168.1.1:53 --proto udp
```

## 配置文件

| 文件 | 说明 |
|------|------|
| `/etc/nat-manager/rules.conf` | DNAT 转发规则 |
| `/etc/nat-manager/gateway.conf` | MASQUERADE 网关配置 |
| `/etc/sysctl.d/99-nat-manager.conf` | IP forwarding 持久化 |
| `/etc/systemd/system/nat-manager.service` | systemd 持久化服务 |

### rules.conf 格式

```
# 格式: <外部端口> <协议> <目标IP:目标端口>
8443 tcp 192.168.1.100:443
3306 tcp 127.0.0.1:3307
5353 udp 192.168.1.1:53
```

### gateway.conf 格式

```
# 格式: <网卡> <源CIDR>（无 CIDR 则对整个网卡 MASQUERADE）
eth1 192.168.1.0/24
```

## 工作原理

1. **IP forwarding**：通过 `sysctl` 开启内核的 IP 转发功能
2. **DNAT**：使用 `iptables -t nat PREROUTING` 把外部请求重定向到目标地址
3. **MASQUERADE**：使用 `iptables -t nat POSTROUTING` 做源地址伪装
4. **FORWARD 链**：自动添加 FORWARD 规则放行转发流量
5. **持久化**：systemd service 在启动时从配置文件重建 iptables 规则

## 与其他模块的关系

| 模块 | 功能 | 区别 |
|------|------|------|
| `ufw` | 防火墙（allow/deny） | 只管放行/拒绝，不管 NAT |
| `multi-net` | 策略路由（按用户/端口分流网卡） | 管出站流量走哪张网卡 |
| `nat` | NAT 规则（DNAT + MASQUERADE） | 管端口转发和共享上网 |

## 注意事项

- 仅支持 Linux（macOS 不适用）
- 需要 sudo 权限
- 前置条件：iptables
- DNAT 规则使用 iptables comment 标记（`nat-manager:<端口>`），便于精确管理
- 卸载时可选择保留配置文件，方便下次重新安装后恢复规则

## 常见问题

### Q: 规则重启后还在吗？

A: 在。安装时会配置 systemd service，开机自动从配置文件加载规则。

### Q: 如何临时禁用所有规则？

A: 停止 systemd 服务即可：
```bash
sudo systemctl stop nat-manager.service
```
规则文件保留，下次启动自动恢复。

### Q: 如何查看当前 iptables 规则？

A: 使用系统命令：
```bash
sudo iptables -t nat -L -v -n        # 查看 NAT 表
sudo iptables -L FORWARD -v -n       # 查看 FORWARD 链
```

### Q: 支持 IPv6 吗？

A: 当前版本仅支持 IPv4（iptables）。如需 IPv6 支持，可使用 ip6tables 或后续扩展。
