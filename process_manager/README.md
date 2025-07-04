# 智能进程管理工具使用说明

## 概述

`process_manager.sh` 是一个强大的进程管理工具，支持模糊搜索进程名称或端口号，提供二次确认机制，并能智能地选择终止方式（优雅退出或强制杀死）。

## 功能特性

- ✅ **模糊搜索**: 支持按进程名称模糊匹配
- ✅ **端口搜索**: 支持按端口号查找占用进程
- ✅ **PID搜索**: 支持直接通过进程ID查找
- ✅ **跨平台**: 同时支持 macOS 和 Linux
- ✅ **智能终止**: 优先使用 SIGTERM，必要时使用 SIGKILL
- ✅ **二次确认**: 防止误操作
- ✅ **详细信息**: 显示进程的详细信息和监听端口
- ✅ **交互式**: 支持命令行直接使用和交互式菜单

## 使用方法

### 1. 基本用法

```bash
# 给脚本执行权限
chmod +x process_manager.sh

# 直接搜索模式
./process_manager.sh <搜索词>

# 交互式模式
./process_manager.sh
```

### 2. 搜索示例

```bash
# 按进程名搜索
./process_manager.sh node          # 搜索所有包含 "node" 的进程
./process_manager.sh chrome        # 搜索 Chrome 浏览器进程
./process_manager.sh nginx         # 搜索 Nginx 服务器进程

# 按端口号搜索
./process_manager.sh 3000          # 搜索使用端口 3000 的进程
./process_manager.sh 80            # 搜索使用端口 80 的进程
./process_manager.sh 9100          # 搜索使用端口 9100 的进程（Node Exporter）

# 按进程ID搜索
./process_manager.sh 1234          # 搜索 PID 为 1234 的进程
```

### 3. 交互式操作流程

1. **搜索阶段**: 输入搜索词，系统会显示匹配的进程
2. **选择阶段**: 如果找到多个进程，可以选择具体要操作的进程
3. **确认阶段**: 显示进程详细信息，确认是否要终止
4. **终止阶段**: 优先使用 SIGTERM，如果10秒内未退出，询问是否强制杀死

## 搜索结果说明

工具会显示两类搜索结果：

### 按进程名搜索
显示包含搜索词的所有进程，格式如下：
```
USER       PID  %CPU %MEM      VSZ    RSS   TT  STAT STARTED      TIME COMMAND
username  1234   0.5  1.2  5678900 123456   ??  S    10:30AM   0:01.23 /path/to/process
```

### 按端口搜索
显示占用指定端口的进程，格式如下：
```
COMMAND    PID    USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
process   1234 username   4u  IPv4 0x1234      0t0  TCP *:3000 (LISTEN)
```

## 进程终止策略

### 1. 优雅终止 (SIGTERM)
- 首先发送 SIGTERM 信号
- 等待进程自主退出（最多10秒）
- 适用于大多数应用程序

### 2. 强制终止 (SIGKILL)
- 如果 SIGTERM 无效，询问是否强制杀死
- 发送 SIGKILL 信号，立即终止进程
- 适用于无响应的进程

## 安全特性

- **二次确认**: 在终止进程前需要用户确认
- **详细信息**: 显示进程的完整信息，避免误操作
- **权限检查**: 检查是否有权限操作目标进程
- **进程验证**: 确认进程存在且可访问

## 快捷配置

使用 `process_manager_config.sh` 可以设置常用的搜索别名：

```bash
# 加载配置文件
source process_manager_config.sh

# 使用快捷搜索
quick_search chrome        # 搜索 Chrome 浏览器
quick_search http          # 搜索使用 HTTP 端口的进程
quick_search node          # 搜索 Node.js 进程
```

### 预定义别名

**常用端口**:
- `http` → 80
- `https` → 443
- `ssh` → 22
- `mysql` → 3306
- `postgres` → 5432
- `redis` → 6379
- `mongodb` → 27017
- `node` → 3000
- `prometheus` → 9090
- `node_exporter` → 9100
- `ddns-go` → 9876

**常用应用**:
- `chrome` → Google Chrome
- `firefox` → Firefox
- `vscode` → Visual Studio Code
- `docker` → Docker
- `nginx` → Nginx
- `apache` → Apache

## 平台差异

### macOS
- 使用 `lsof` 查询端口占用
- 使用 `ps aux` 列出进程
- 支持查看进程打开的文件数

### Linux
- 优先使用 `ss`，备用 `netstat` 查询端口占用
- 使用 `ps aux` 列出进程
- 支持读取 `/proc/<pid>/status` 获取进程状态

## 常见用途

1. **开发调试**: 快速终止占用端口的开发服务器
2. **系统维护**: 清理僵尸进程或异常进程
3. **服务管理**: 重启Web服务器、数据库等服务
4. **资源释放**: 终止占用过多资源的进程

## 注意事项

1. **权限要求**: 只能终止当前用户有权限的进程
2. **系统进程**: 谨慎终止系统关键进程
3. **数据安全**: 终止数据库等服务前确保数据已保存
4. **依赖关系**: 注意进程间的依赖关系，避免连锁影响

## 故障排除

### 找不到进程
- 检查进程名称拼写
- 尝试使用部分关键词
- 确认进程确实在运行

### 无法终止进程
- 检查是否有足够权限
- 尝试使用 `sudo` 运行脚本
- 确认进程不是系统保护进程

### 端口搜索无结果
- 确认端口号正确
- 检查是否安装了 `lsof`（macOS）或 `ss`/`netstat`（Linux）
- 确认端口确实被占用

## 集成到主菜单

要将此工具集成到主安装脚本中，可以在 `install.sh` 的主菜单中添加：

```bash
echo "  6) 进程管理工具        - 智能搜索和管理系统进程"
```

并在选择处理中添加：

```bash
6)
    ./process_manager.sh
    ;;
```
