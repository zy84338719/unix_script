# incus

系统容器与轻量虚拟化管理（LXD 的社区分支，Linux Containers 官方项目）——一台机器上
跑带完整系统的容器和小虚拟机。仅 Linux：Deb 系走 Zabbly 稳定仓，RHEL 系走发行版/EPEL
包。

```bash
./install.sh incus                  # 安装
sudo incus admin init               # 首次初始化（存储/网络）
incus launch images:ubuntu/24.04 u1 # 起一个系统容器
```

免 sudo：`sudo usermod -aG incus-admin $USER` 后重新登录。
