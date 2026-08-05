# 磁盘空间管理

查看存储概况、大文件排行、监控告警、一键清理。支持 Linux / macOS。

## 用法

```bash
# 查看存储概况（默认动作）
./disk-usage/install.sh status

# 大文件/目录排行
./disk-usage/install.sh top              # 根目录 Top 10
./disk-usage/install.sh top /home        # /home 下 Top 10
./disk-usage/install.sh top --count 20   # Top 20

# 监控告警
./disk-usage/install.sh monitor                        # 检查是否超过 90%
./disk-usage/install.sh monitor --threshold 80         # 自定义阈值
./disk-usage/install.sh monitor --install              # 写入 crontab 每天检查
./disk-usage/install.sh monitor --uninstall            # 移除定时任务

# 一键清理
./disk-usage/install.sh clean --all                    # 全部清理
./disk-usage/install.sh clean --logs --cache           # 清理日志 + 缓存
./disk-usage/install.sh clean --docker                 # 清理 Docker 垃圾
./disk-usage/install.sh clean --all --dry-run          # 预览模式
```

## 子命令

| 子命令 | 说明 |
|--------|------|
| `status` | 查看各挂载点使用率、内存、Swap 状态（默认） |
| `top [路径]` | 扫描大目录和大文件排行 |
| `monitor` | 检查使用率是否超阈值，支持 cron 定时监控 |
| `clean` | 清理日志、包管理器缓存、Docker 垃圾 |
| `help` | 显示帮助 |

## 功能详情

### status
- `df -h` 格式化输出，使用率 ≥90% 红色、≥80% 黄色、其余绿色
- 显示内存使用（Linux: `free -h`，macOS: `vm_stat`）
- 显示 Swap 状态
- 自动检测并告警使用率超 90% 的挂载点

### top
- 扫描指定路径下最大的 N 个目录（`du -sh` + `sort`）
- 额外扫描 `/var/log`、`/tmp` 等常见位置的大文件
- 可通过 `--count` 自定义显示数量

### monitor
- 检查所有物理挂载点，超过阈值输出告警
- `--install` 写入 crontab（每天 08:00 执行）
- `--uninstall` 移除定时任务
- 返回码：0=正常，1=有告警

### clean
- `--logs`：清理 journal 日志（保留 3 天）+ 截断 >100M 的日志文件
- `--cache`：清理 apt/dnf/yum/brew/pip/npm/bun 缓存
- `--docker`：`docker system prune -af --volumes`
- `--all`：全部清理
- 每项清理前显示大小并需确认
- 支持 `--dry-run` 仅预览

## 平台兼容性

| 功能 | Linux | macOS |
|------|-------|-------|
| status | ✅ 完整 | ✅ 完整 |
| top | ✅ 完整 | ✅ 完整 |
| monitor | ✅ 完整 | ✅ 完整 |
| clean --logs | ✅ journal + 大日志 | ✅ 大日志 |
| clean --cache | ✅ apt/dnf/yum + pip/npm/bun | ✅ brew + pip/npm/bun |
| clean --docker | ✅ 完整 | ✅ 完整 |
