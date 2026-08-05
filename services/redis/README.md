# Redis 一键安装

封装 Redis 内存数据库的安装、卸载与状态检查。

## 支持平台

| 平台 | 安装包 | 服务管理 |
|------|--------|----------|
| Linux (apt) | `redis-server` | systemd `redis-server` |
| Linux (dnf/yum) | `redis` | systemd `redis` |
| macOS | `redis` (Homebrew) | `brew services start redis` |

## 安装

```bash
chmod +x redis/install.sh
./redis/install.sh            # 安装（默认动作）
./redis/install.sh install    # 显式安装
```

## 验证

```bash
redis-cli ping          # 返回 PONG 表示正常
redis-cli info          # 查看服务器信息
redis-cli --version     # 查看版本
```

## 端口与配置

| 项目 | 值 |
|------|-----|
| 默认端口 | 6379 |
| 配置文件 (apt) | `/etc/redis/redis.conf` |
| 配置文件 (dnf/yum) | `/etc/redis.conf` |
| 配置文件 (macOS brew) | `/usr/local/etc/redis.conf` |

## 卸载

```bash
./redis/install.sh uninstall
```

卸载会停止服务并移除软件包。

## 状态

```bash
./redis/install.sh status
```
