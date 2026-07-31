# 多网卡策略路由

让指定的服务（按用户/端口）走指定的网卡出网。仅 Linux，基于策略路由（policy routing）+ fwmark + iptables。

## 原理
为每张网卡建独立路由表，用 `ip rule` + `iptables fwmark` 把目标流量打标记并导到对应表，实现按网卡分流。对被路由的服务完全透明（无需服务自身支持代理）。

## 子命令

| 子命令 | 说明 |
|--------|------|
| `setup <网卡>` | 为网卡初始化独立路由表（默认网关、脱离主路由表） |
| `route-user <用户> <网卡>` | 让某用户的所有流量走指定网卡 |
| `route-port <端口> <网卡>` | 让访问指定目的端口的流量走指定网卡 |
| `list` | 查看当前策略路由规则 |
| `clear` | 清除本脚本添加的所有规则 |
| `status` | 总览 |

## 示例

```bash
# 场景：服务器有 eth0(主) 和 eth1(备用)，想让 www-data 服务的流量走 eth1
./multi-net/install.sh setup eth1                       # 初始化 eth1 策略路由
./multi-net/install.sh route-user www-data eth1         # www-data 走 eth1
./multi-net/install.sh route-port 443 eth1              # 所有 443 流量走 eth1

# 验证：以 www-data 身份请求，应显示 eth1 的公网 IP
sudo -u www-data curl ifconfig.me

./multi-net/install.sh list                             # 查看规则
./multi-net/install.sh clear                            # 清除所有规则
```

## 说明
- 每张网卡自动分配唯一 table id（100-250 区间）与 fwmark，互不冲突。
- `route-user` 基于 `iptables -m owner --uid-owner`，按 Linux 用户 UID 标记流量。
- `route-port` 按目的端口标记（TCP），适合让特定服务（如只让 HTTPS）走某网卡。
- `clear` 清除规则但保留路由表登记（可重新 `setup` 复用）。
- 需 `iproute2` 与 `iptables`（多数 Linux 默认有；Alpine 需 `apk add iproute2 iptables`）。
