# MongoDB

文档型数据库（mongodb-org 8.0）。仅 Linux——官方 GPG key + TUNA 镜像仓库安装
（国内可达），服务自动 enable-now。

- Deb 系支持代号：jammy / noble / bookworm / trixie（其他代号报错列出支持列表）
- RHEL 系走 `el$releasever`
- 客户端 shell `mongosh` 随 mongodb-org 一并安装

```bash
./install.sh mongodb           # 安装
mongosh                        # 连接
```
