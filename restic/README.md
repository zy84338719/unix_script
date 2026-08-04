# Restic 备份工具

基于 [Restic](https://restic.net/) 封装，提供安装、卸载、状态检查。

## 支持平台

| 平台 | 方式 | 备选 |
|------|------|------|
| macOS | Homebrew `restic` | -- |
| Linux (apt/dnf/yum) | 系统包管理器 `restic` | GitHub 二进制下载 |
| Linux (其他) | GitHub 二进制下载 (`restic/restic`) | -- |

## 安装

```bash
chmod +x restic/install.sh
./restic/install.sh            # 安装（默认动作）
./restic/install.sh install    # 显式安装
```

## 快速上手

```bash
# 初始化本地备份仓库
restic init --repo /path/to/backup-repo

# 备份目录
restic -r /path/to/backup-repo backup /home/user/docs

# 查看备份快照
restic -r /path/to/backup-repo snapshots

# 恢复文件
restic -r /path/to/backup-repo restore latest --target /tmp/restore

# 初始化远程仓库（S3 示例）
export AWS_ACCESS_KEY_ID="xxx"
export AWS_SECRET_ACCESS_KEY="xxx"
restic -r s3:s3.amazonaws.com/bucket-name init
restic -r s3:s3.amazonaws.com/bucket-name backup /home/user/docs
```

## 常用命令

```bash
restic version                            # 查看版本
restic -r <repo> init                     # 初始化仓库
restic -r <repo> backup <path>            # 备份
restic -r <repo> snapshots                # 列出快照
restic -r <repo> restore latest --target <dir>  # 恢复
restic -r <repo> check                    # 检查仓库完整性
restic -r <repo> forget --keep-last 7     # 保留最近7个快照
restic -r <repo> prune                    # 清理旧数据
```

## 卸载

```bash
./restic/install.sh uninstall
```

## 说明

- Restic 是纯 CLI 工具，无后台服务，不需要 systemctl 或 launchd。
- 支持多种后端：本地目录、SFTP、S3、Azure、GCS、B2 等。
- 官方文档：https://restic.readthedocs.io/
