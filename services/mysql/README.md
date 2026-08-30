# MySQL

MySQL 数据库服务端——库内数据库补齐（此前只有 postgres/redis）。Linux 走发行版仓库
（Ubuntu `mysql-server` / Debian `default-mysql-server` / RHEL 系 AppStream
`mysql-server`），服务自动 enable-now；macOS 走 brew。

- Deb 系 root 走 auth_socket：`sudo mysql` 直登
- RHEL 系首次 root 临时密码在 `/var/log/mysqld.log`
- 装完建议跑 `mysql_secure_installation`
- 需要 MariaDB 的可直接用系统仓库 `mariadb-server`（本模块不封装）

```bash
./install.sh mysql           # 安装并启动
./install.sh mysql status    # 状态
```
