# PostgreSQL 一键安装

封装 PostgreSQL 关系型数据库的安装、卸载与状态检查。

## 支持平台

| 平台 | 安装包 | 服务管理 |
|------|--------|----------|
| Linux (apt) | `postgresql postgresql-contrib` | systemd `postgresql` |
| Linux (dnf/yum) | `postgresql-server postgresql-contrib` | systemd `postgresql`（需先 initdb） |
| macOS | `postgresql@16` (Homebrew) | `brew services start postgresql@16` |

## 安装

```bash
chmod +x postgres/install.sh
./postgres/install.sh            # 安装（默认动作）
./postgres/install.sh install    # 显式安装
```

dnf/yum 平台会自动执行 `postgresql-setup --initdb` 初始化数据库集群。

## 验证

```bash
pg_isready             # 检查服务是否就绪
psql --version         # 查看版本
```

## 端口与配置

| 项目 | 值 |
|------|-----|
| 默认端口 | 5432 |
| 配置目录 (apt) | `/etc/postgresql/<版本>/main/` |
| 配置目录 (dnf/yum) | `/var/lib/pgsql/data/` |
| 数据目录 (macOS brew) | `/usr/local/var/postgres/` |

## 快速开始

```bash
# Linux: 使用 postgres 系统用户登录
sudo -u postgres psql

# 创建用户和数据库
sudo -u postgres createuser --interactive
sudo -u postgres createdb <数据库名>

# macOS: 直接连接（brew 安装时已创建当前用户）
psql postgres
```

## 卸载

```bash
./postgres/install.sh uninstall
```

卸载会停止服务并移除软件包，但会提示数据目录位置，需手动清理。

## 状态

```bash
./postgres/install.sh status
```
