# 智能进程管理工具使用说明

## 概述

`process_manager.sh` 是一个强大的跨平台进程管理工具，支持模糊搜索进程名称或端口号，提供二次确认机制，并能智能地选择终止方式（优雅退出或强制杀死）。支持安装到用户的 `~/.tools` 目录并自动配置系统环境变量。

## 功能特性

- ✅ **模糊搜索**: 支持按进程名称模糊匹配
- ✅ **端口搜索**: 支持按端口号查找占用进程
- ✅ **PID搜索**: 支持直接通过进程ID查找
- ✅ **跨平台**: 同时支持 macOS 和 Linux
- ✅ **智能终止**: 优先使用 SIGTERM，必要时使用 SIGKILL
- ✅ **二次确认**: 防止误操作
- ✅ **详细信息**: 显示进程的详细信息和监听端口
- ✅ **交互式**: 支持命令行直接使用和交互式菜单
- ✅ **系统安装**: 支持安装到 ~/.tools 目录并配置环境变量
- ✅ **多Shell支持**: 支持 Bash、Zsh、Fish shell
- ✅ **智能包装**: 提供智能路径检测和依赖检查
- ✅ **预设配置**: 内置常用端口和进程别名

## 系统要求

### 支持的操作系统
- **macOS**: 10.12+ (Sierra 及更高版本)
- **Linux**: 主要发行版 (Ubuntu, Debian, CentOS, RHEL, Arch Linux 等)

### 必需依赖
- **基本工具**: `ps`, `grep`, `awk`, `sed`, `kill`
- **macOS**: `lsof` (系统自带)
- **Linux**: `ss` (推荐) 或 `netstat` 或 `lsof`

### 支持的Shell
- **Bash**: 4.0+ 
- **Zsh**: 5.0+
- **Fish**: 3.0+

### 权限要求
- 读取进程信息的权限
- 发送进程信号的权限
- 写入用户主目录的权限

## 安装方法

### 预检查（推荐）

在安装前，建议先检查系统兼容性：

```bash
# 检查系统依赖和兼容性
./check_dependencies.sh

# 包含性能测试的详细检查
./check_dependencies.sh --performance
```

### 方法一：自动安装到 ~/.tools 目录（推荐）

使用自动安装脚本将工具安装到 `~/.tools` 目录，这是推荐的安装方式：

```bash
# 运行安装脚本
./install_process_manager.sh

# 重新加载Shell配置（三选一）
source ~/.bashrc        # Bash用户
source ~/.zshrc         # Zsh用户
source ~/.config/fish/config.fish  # Fish用户

# 或者重启终端
```

**安装后的目录结构：**
```
~/.tools/
├── bin/
│   ├── process_manager     # 主程序
│   ├── pm                  # 智能包装脚本
│   └── process_manager_config.sh  # 配置文件
└── docs/
    ├── process_manager_README.md      # 详细文档
    └── process_manager_quickstart.md  # 快速指南
```

**自动配置的功能：**
- ✅ 创建 `~/.tools/bin` 目录
- ✅ 自动检测操作系统和Shell类型
- ✅ 添加 `~/.tools/bin` 到 PATH 环境变量
- ✅ 创建便捷别名 `pm` 和 `pmc`
- ✅ 支持全局命令链接（可选）
- ✅ 自动配置 Bash/Zsh/Fish 三种Shell

### 方法二：使用包装脚本（便携）

如果不想修改系统配置，可以使用智能包装脚本：

```bash
# 直接使用包装脚本
./pm_wrapper.sh <搜索词>

# 查看帮助和配置信息
./pm_wrapper.sh --help
./pm_wrapper.sh --config
./pm_wrapper.sh --install  # 调用安装程序
```

### 方法三：直接使用（开发/测试）

```bash
# 给脚本执行权限
chmod +x process_manager.sh

# 直接运行
./process_manager.sh <搜索词>
```

## 使用方法

### 系统安装后的使用（推荐）

安装后可以通过多种方式使用：

```bash
# 方式1: 使用智能包装脚本（推荐）
pm <搜索词>              # 搜索模式
pm                       # 交互式模式
pm --help               # 查看帮助
pm --config             # 查看配置信息

# 方式2: 使用完整命令名
process_manager <搜索词>
process_manager         # 交互式模式

# 方式3: 使用预定义快捷搜索
pmc chrome              # 搜索Chrome浏览器
pmc http                # 搜索HTTP端口(80)
pmc node                # 搜索Node.js相关进程
```

### 包装脚本使用

智能包装脚本提供了额外的功能：

```bash
# 查看系统配置和安装状态
pm --config

# 显示版本信息
pm --version

# 运行安装程序
pm --install

# 获取帮助信息
pm --help
```

### 直接使用方式

如果没有安装到系统，可以直接运行：

```bash
# 直接搜索模式
./process_manager.sh <搜索词>

# 交互式模式
./process_manager.sh

# 使用包装脚本
./pm_wrapper.sh <搜索词>
```

### 2. 搜索示例

```bash
# 按进程名搜索
pm node                 # 搜索所有包含 "node" 的进程
pm chrome               # 搜索 Chrome 浏览器进程
pm nginx                # 搜索 Nginx 服务器进程
pm python               # 搜索 Python 进程

# 按端口号搜索
pm 3000                 # 搜索使用端口 3000 的进程
pm 80                   # 搜索使用端口 80 的进程
pm 9100                 # 搜索使用端口 9100 的进程（Node Exporter）
pm 22                   # 搜索 SSH 服务进程

# 按进程ID搜索
pm 1234                 # 搜索 PID 为 1234 的进程

# 使用快捷别名（需要配置文件）
pmc chrome              # 等同于搜索 Chrome 相关进程
pmc http                # 等同于搜索端口 80
pmc https               # 等同于搜索端口 443
pmc mysql               # 等同于搜索 MySQL 相关进程
```

## 安装目录结构

系统安装后的目录结构：

```
~/.tools/
├── bin/
│   ├── process_manager              # 主程序
│   └── process_manager_config.sh    # 配置文件
└── docs/
    └── process_manager_README.md    # 使用文档
```

## 环境变量配置

安装脚本会自动配置以下内容：

### Bash/Zsh 用户
在 `~/.bashrc` 或 `~/.zshrc` 中添加：
```bash
# 添加 ~/.tools/bin 到 PATH
export PATH="$HOME/.tools/bin:$PATH"

# 进程管理工具别名
alias pm='process_manager'
alias pmc='source $HOME/.tools/bin/process_manager_config.sh && quick_search'
```

### Fish 用户
在 `~/.config/fish/config.fish` 中添加：
```fish
# 添加 ~/.tools/bin 到 PATH
set -gx PATH $HOME/.tools/bin $PATH

# 进程管理工具别名
alias pm='process_manager'
```

## 卸载方法

```bash
# 运行卸载程序
./install_process_manager.sh uninstall

# 或使用参数
./install_process_manager.sh --uninstall
./install_process_manager.sh -u
```

卸载程序会：
- 删除 `~/.tools/bin/` 中的相关文件
- 清理 Shell 配置文件中的相关配置
- 删除全局命令链接（如果存在）
- 自动备份原始配置文件

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

### 预定义别名

系统安装包含了 `process_manager_config.sh` 配置文件，提供了常用的快捷搜索：

**常用端口别名**:
- `http` → 端口 80
- `https` → 端口 443
- `ssh` → 端口 22
- `ftp` → 端口 21
- `mysql` → 端口 3306
- `postgres` → 端口 5432
- `redis` → 端口 6379
- `mongodb` → 端口 27017
- `node` → 端口 3000
- `react` → 端口 3000
- `vue` → 端口 8080
- `prometheus` → 端口 9090
- `node_exporter` → 端口 9100
- `grafana` → 端口 3000
- `ddns-go` → 端口 9876

**常用应用别名**:
- `chrome` → Google Chrome/chrome/chromium
- `firefox` → Firefox 浏览器
- `vscode` → Visual Studio Code
- `docker` → Docker 容器
- `nginx` → Nginx 服务器
- `apache` → Apache 服务器
- `mysql` → MySQL 数据库
- `postgres` → PostgreSQL 数据库
- `redis` → Redis 服务器
- `mongodb` → MongoDB 数据库
- `node` → Node.js 进程
- `python` → Python 进程
- `java` → Java 进程
- `ssh` → SSH 服务

### 使用快捷搜索

```bash
# 系统安装后可以使用 pmc 命令
pmc chrome              # 搜索 Chrome 浏览器
pmc http                # 搜索使用 HTTP 端口的进程
pmc mysql               # 搜索 MySQL 数据库进程
pmc docker              # 搜索 Docker 相关进程

# 手动加载配置（如果需要）
source ~/.tools/bin/process_manager_config.sh
quick_search nginx      # 使用 quick_search 函数
```

## ~/.tools 目录说明

### 目录结构

安装脚本会在用户主目录下创建 `~/.tools` 目录，这是一个标准的用户级工具安装位置：

```
~/.tools/
├── bin/                          # 可执行文件目录
│   ├── process_manager          # 主程序
│   ├── pm                       # 智能包装脚本
│   └── process_manager_config.sh # 配置文件
└── docs/                        # 文档目录
    ├── process_manager_README.md      # 详细文档
    └── process_manager_quickstart.md  # 快速指南
```

### 环境变量配置

安装程序会自动配置以下环境变量：

#### Bash 用户 (.bashrc 或 .bash_profile)
```bash
# 添加 ~/.tools/bin 到 PATH
export PATH="$HOME/.tools/bin:$PATH"

# 进程管理工具别名
alias pm='$HOME/.tools/bin/pm'
alias pmc='source $HOME/.tools/bin/process_manager_config.sh && quick_search'
```

#### Zsh 用户 (.zshrc)
```zsh
# 添加 ~/.tools/bin 到 PATH
export PATH="$HOME/.tools/bin:$PATH"

# 进程管理工具别名
alias pm='$HOME/.tools/bin/pm'
alias pmc='source $HOME/.tools/bin/process_manager_config.sh && quick_search'
```

#### Fish 用户 (.config/fish/config.fish)
```fish
# 添加 ~/.tools/bin 到 PATH
set -gx PATH $HOME/.tools/bin $PATH

# 进程管理工具别名
alias pm='$HOME/.tools/bin/pm'
```

### 跨平台兼容性

#### macOS 特性
- 自动检测并使用 `.bash_profile`（而非 `.bashrc`）
- 支持 Homebrew 安装的 Shell
- 兼容 iTerm2 和 Terminal.app
- 支持 macOS 系统完整性保护（SIP）

#### Linux 特性
- 支持各种发行版（Ubuntu、Debian、CentOS、Arch等）
- 自动检测包管理器和依赖
- 支持 systemd 和传统 init 系统
- 兼容各种终端模拟器

### 环境变量检查

可以使用以下命令检查环境配置：

```bash
# 检查 PATH 配置
echo $PATH | grep -o "[^:]*\.tools[^:]*"

# 检查别名配置
alias | grep pm

# 使用包装脚本检查配置
pm --config

# 检查安装状态
ls -la ~/.tools/bin/
```

### 手动配置（如果自动配置失败）

如果自动配置失败，可以手动添加以下内容到您的Shell配置文件：

```bash
# 检测Shell类型
echo $SHELL

# 编辑相应的配置文件
# Bash: ~/.bashrc (Linux) 或 ~/.bash_profile (macOS)
# Zsh:  ~/.zshrc
# Fish: ~/.config/fish/config.fish

# 添加以下内容（根据Shell语法调整）
export PATH="$HOME/.tools/bin:$PATH"
alias pm="$HOME/.tools/bin/pm"
```

然后重新加载配置：
```bash
source ~/.bashrc    # 或相应的配置文件
# 或重启终端
```

## 跨平台兼容性详情

### 平台差异和特性

#### macOS
- **进程查询**: 使用 `ps aux` 和系统自带的 `lsof`
- **端口检测**: `lsof -i :<端口>` 和 `lsof -t -i :<端口>`
- **信号发送**: 支持 SIGTERM (15) 和 SIGKILL (9)
- **特殊功能**: 支持查看进程打开的文件数和网络连接
- **权限模型**: 符合 macOS 安全策略和 SIP 保护

#### Linux
- **进程查询**: 使用 `ps aux` 和 `/proc` 文件系统
- **端口检测**: 优先使用 `ss -tulnp`，备用 `netstat -tulnp` 和 `lsof`
- **信号发送**: 支持完整的 POSIX 信号集
- **特殊功能**: 可读取 `/proc/<pid>/status` 获取详细进程状态
- **权限模型**: 基于传统 Unix 权限和 capabilities

### 依赖工具对比

| 工具 | macOS | Linux | 功能描述 |
|------|-------|-------|----------|
| `ps` | ✅ 系统自带 | ✅ 系统自带 | 进程列表查询 |
| `lsof` | ✅ 系统自带 | ⚠️ 需要安装 | 文件和网络连接查询 |
| `ss` | ❌ 不可用 | ✅ 现代工具 | 网络连接查询（推荐） |
| `netstat` | ⚠️ 基础版本 | ✅ 完整功能 | 传统网络工具 |
| `kill` | ✅ 系统自带 | ✅ 系统自带 | 进程信号发送 |

### 安装命令对比

#### macOS
```bash
# macOS 通常已预装所需工具
# 如需额外工具，使用 Homebrew:
brew install lsof        # 通常不需要，系统自带

# 检查系统工具
which lsof ps kill       # 验证工具存在
```

#### Linux
```bash
# Ubuntu/Debian
sudo apt-get install iproute2 net-tools lsof

# CentOS/RHEL
sudo yum install iproute net-tools lsof

# Fedora
sudo dnf install iproute net-tools lsof

# Arch Linux
sudo pacman -S iproute2 net-tools lsof

# openSUSE
sudo zypper install iproute2 net-tools lsof
```

### Shell 兼容性

#### Bash 兼容性
- **macOS**: Bash 3.x (系统自带) 和 Bash 5.x (Homebrew)
- **Linux**: Bash 4.x/5.x (各发行版标准)
- **特性**: 支持数组、关联数组、进程替换

#### Zsh 兼容性  
- **macOS**: Zsh 5.x (Catalina+ 默认Shell)
- **Linux**: Zsh 5.x (需要安装)
- **特性**: 完全兼容 Bash，支持更多高级特性

#### Fish 兼容性
- **macOS**: Fish 3.x (Homebrew 安装)
- **Linux**: Fish 3.x (包管理器安装)
- **特性**: 需要特殊语法处理，别名配置有差异

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

## 安装脚本详细说明

### install_process_manager.sh

这是一个智能安装脚本，支持：

#### 功能特性
- ✅ **自动检测系统**: 支持 macOS 和 Linux
- ✅ **多Shell支持**: 自动检测并配置 Bash、Zsh、Fish
- ✅ **环境变量配置**: 自动添加到 PATH 并创建别名
- ✅ **全局命令**: 可选创建全局 `pm` 命令
- ✅ **完整卸载**: 支持一键卸载并恢复配置

#### 使用方法

```bash
# 安装
./install_process_manager.sh

# 显示帮助
./install_process_manager.sh --help

# 卸载
./install_process_manager.sh uninstall
```

#### 安装过程

1. **系统检测**: 自动检测操作系统和Shell类型
2. **目录创建**: 创建 `~/.tools` 和 `~/.tools/bin` 目录
3. **文件复制**: 复制脚本和配置文件到目标位置
4. **权限设置**: 自动设置执行权限
5. **环境配置**: 自动配置环境变量和别名
6. **全局链接**: 可选创建全局命令链接
7. **安装验证**: 验证所有组件是否正确安装

#### 自动检测的Shell配置文件

| Shell | macOS | Linux |
|-------|-------|-------|
| Bash | `~/.bash_profile` | `~/.bashrc` |
| Zsh | `~/.zshrc` | `~/.zshrc` |
| Fish | `~/.config/fish/config.fish` | `~/.config/fish/config.fish` |

## 集成到主菜单

要将此工具集成到主安装脚本中，已在 `install.sh` 的主菜单中添加为第6个选项：

```bash
echo "  6) 进程管理工具     - 智能搜索和管理系统进程"
```

选择后会启动交互式进程管理界面。

## 技术实现细节

### 系统命令映射

| 功能 | macOS | Linux |
|------|-------|-------|
| 进程列表 | `ps aux` | `ps aux` |
| 端口占用 | `lsof -i :PORT` | `ss -tulnp \| grep :PORT` |
| 进程详情 | `lsof -p PID` | `/proc/PID/status` |
| 信号发送 | `kill -TERM PID` | `kill -TERM PID` |

### 信号处理策略

1. **SIGTERM (15)**: 优雅终止信号
   - 给进程10秒时间自主退出
   - 适用于大多数应用程序
   
2. **SIGKILL (9)**: 强制终止信号
   - 立即终止进程
   - 用于无响应的进程

## 常见问题解答

### Q: 安装后命令不可用？
A: 请重新加载Shell配置：`source ~/.bashrc` 或重启终端

### Q: 权限不足无法终止进程？
A: 某些系统进程需要管理员权限，可使用 `sudo pm <搜索词>`

### Q: 如何更新工具？
A: 重新运行安装脚本即可覆盖安装

### Q: Fish Shell 支持有限？
A: Fish Shell 的快捷搜索功能受限，建议使用基本的 `pm` 命令

### Q: 如何完全删除？
A: 运行 `./install_process_manager.sh uninstall` 并检查备份文件

## 开发和贡献

### 目录结构
```
.
├── process_manager.sh              # 主程序
├── process_manager_config.sh       # 配置文件
├── install_process_manager.sh      # 安装脚本
└── process_manager/
    └── README.md                   # 文档
```

### 扩展配置
可以编辑 `~/.tools/bin/process_manager_config.sh` 添加自定义别名：

```bash
# 自定义端口映射
COMMON_PORTS["custom"]="8080"

# 自定义进程模式
COMMON_PROCESSES["myapp"]="myapp|my-application"
```
