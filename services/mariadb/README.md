# MariaDB

MySQL 兼容分支数据库，各大发行版仓库的默认关系型数据库。Linux 走系统仓库（服务自动
enable-now），macOS 走 brew。检测到已装 MySQL 时警告 3306 端口冲突。

```bash
./install.sh mariadb                    # 安装
mariadb-secure-installation             # 安全加固
```

要 MySQL 8 官方版用 `./install.sh mysql`。
