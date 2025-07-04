# 进程管理工具快速上手指南

## 🚀 5分钟快速开始

### 1. 系统检查（推荐）

在安装前，建议先检查系统兼容性：

```bash
./check_dependencies.sh
```

### 2. 一键安装

运行自动安装脚本：

```bash
./install_process_manager.sh
```

安装程序会：
- ✅ 自动检测您的系统（macOS/Linux）和Shell（Bash/Zsh/Fish）
- ✅ 创建 `~/.tools/bin` 目录
- ✅ 安装所有必要文件
- ✅ 自动配置环境变量和别名
- ✅ 可选创建全局命令链接

### 3. 重新加载配置

安装完成后，重新加载Shell配置：

```bash
# 方法1: 重新加载配置文件
source ~/.bashrc        # Bash 用户
source ~/.zshrc         # Zsh 用户  
source ~/.config/fish/config.fish  # Fish 用户

# 方法2: 重启终端（推荐）
```

### 4. 验证安装

测试工具是否正常工作：

```bash
# 检查安装状态
pm --config

# 查看帮助信息
pm --help

# 测试搜索功能
pm --version
```

## 🎯 常用操作

### 基本搜索

```bash
# 搜索进程名
pm node                 # 搜索Node.js进程
pm chrome               # 搜索Chrome浏览器
pm nginx                # 搜索Nginx服务器

# 搜索端口
pm 3000                 # 搜索使用端口3000的进程
pm 80                   # 搜索HTTP服务
pm 22                   # 搜索SSH服务

# 交互式模式
pm                      # 启动交互式界面
```

### 快捷搜索（预设别名）

```bash
pmc chrome              # 快速搜索Chrome
pmc http                # 快速搜索HTTP端口(80)
pmc https               # 快速搜索HTTPS端口(443)
pmc node                # 快速搜索Node.js
pmc mysql               # 快速搜索MySQL端口(3306)
```

### 高级用法

```bash
# 使用包装脚本查看配置
pm --config

# 直接使用主程序
process_manager node

# 运行依赖检查
./check_dependencies.sh --performance
```

## 🎯 常用场景

### 开发场景

```bash
# 开发服务器占用端口
pm 3000                 # React/Node.js开发服务器
pm 8080                 # Vue.js开发服务器
pm 4200                 # Angular开发服务器

# 数据库端口
pm 3306                 # MySQL
pm 5432                 # PostgreSQL
pm 6379                 # Redis
pm 27017                # MongoDB
```

### 系统维护

```bash
# Web服务器
pm nginx                # Nginx
pm apache               # Apache
pm httpd                # Apache (CentOS)

# 浏览器进程
pm chrome               # Chrome浏览器
pm firefox              # Firefox浏览器
pm safari               # Safari浏览器

# 开发工具
pm vscode               # VS Code
pm code                 # VS Code
pm docker               # Docker
```

## 🔧 故障排除

### 常见问题

**1. 命令未找到 (`pm: command not found`)**

```bash
# 检查安装状态
ls -la ~/.tools/bin/

# 检查PATH配置
echo $PATH | grep -o "[^:]*\.tools[^:]*"

# 手动重新加载配置
source ~/.bashrc  # 或对应的配置文件
```

**2. 没有权限终止进程**

```bash
# 使用sudo运行（谨慎使用）
sudo pm process_name

# 或者只终止自己的进程
pm process_name
```

**3. 找不到进程**

```bash
# 尝试更宽泛的搜索
pm part_of_name

# 确认进程正在运行
ps aux | grep process_name
```

### 重新安装

如果遇到问题，可以重新安装：

```bash
# 卸载
./install_process_manager.sh uninstall

# 重新安装
./install_process_manager.sh
```

## 📚 更多资源

- **详细文档**: `~/.tools/docs/process_manager_README.md`
- **配置参考**: `~/.tools/bin/process_manager_config.sh`
- **系统检查**: `./check_dependencies.sh --help`
- **安装脚本**: `./install_process_manager.sh --help`

## 🎉 开始使用

现在您可以开始使用强大的进程管理工具了！

```bash
# 搜索并终止占用端口3000的进程
pm 3000

# 搜索并管理Chrome进程
pm chrome

# 启动交互式模式
pm
```

**提示**: 使用 `pm --help` 查看所有可用选项和功能。
