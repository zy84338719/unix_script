# minikube 安装工具

这是一个用于在 macOS 和 Linux 系统上安装和管理 minikube Kubernetes 开发环境的工具集。

## 功能特性

- ✅ 自动检测操作系统和架构
- ✅ 下载并安装最新版本的 kubectl 和 minikube
- ✅ 配置环境变量和 PATH
- ✅ 创建便捷的管理脚本
- ✅ 提供完整的状态检查
- ✅ 支持简单卸载

## 系统要求

### 支持的系统
- macOS (Intel/Apple Silicon)
- Linux (x86_64/ARM64)

### 依赖项
- `curl` 或 `wget` (用于下载)
- `docker` (推荐，作为 minikube 驱动)

## 安装方法

### 1. 直接运行安装脚本

```bash
# 进入 minikube 目录
cd /path/to/macos_script/minikube

# 运行安装脚本
./install.sh
```

### 2. 从主安装菜单

```bash
# 运行主安装脚本
cd /path/to/macos_script
./install.sh

# 选择 minikube 安装选项
```

## 安装位置

所有文件将安装到: `$HOME/.tools/minikube/`

```
~/.tools/minikube/
├── bin/
│   ├── kubectl          # Kubernetes 命令行工具
│   └── minikube         # minikube 二进制文件
├── config/              # 配置文件目录
├── start-minikube.sh    # 集群启动脚本
├── check-status.sh      # 状态检查脚本
└── uninstall.sh         # 卸载脚本
```

## 使用方法

### 启动 minikube 集群

```bash
# 方法1: 使用便捷脚本
~/.tools/minikube/start-minikube.sh

# 方法2: 直接使用 minikube
minikube start

# 方法3: 自定义配置启动
minikube start --cpus=4 --memory=8192 --disk-size=50g
```

### 检查状态

```bash
# 使用状态检查脚本
~/.tools/minikube/check-status.sh

# 或者使用本工具的检查脚本
./check_minikube.sh

# 直接检查 minikube 状态
minikube status
```

### 访问 Kubernetes 仪表板

```bash
minikube dashboard
```

### 停止集群

```bash
minikube stop
```

### 删除集群

```bash
minikube delete
```

## 常用 kubectl 命令

```bash
# 查看集群信息
kubectl cluster-info

# 查看节点
kubectl get nodes

# 查看所有 Pod
kubectl get pods --all-namespaces

# 查看服务
kubectl get services

# 创建示例部署
kubectl create deployment hello-minikube --image=k8s.gcr.io/echoserver:1.4
kubectl expose deployment hello-minikube --type=NodePort --port=8080
```

## 故障排除

### 1. 命令未找到

如果 `kubectl` 或 `minikube` 命令未找到：

```bash
# 重新加载环境变量
source ~/.zshrc    # 对于 zsh
source ~/.bashrc   # 对于 bash

# 或者手动添加到 PATH
export PATH="$HOME/.tools/minikube/bin:$PATH"
```

### 2. minikube 启动失败

```bash
# 检查 Docker 是否运行
docker info

# 使用其他驱动
minikube start --driver=hyperkit    # macOS
minikube start --driver=kvm2        # Linux

# 查看详细日志
minikube start --alsologtostderr -v=7
```

### 3. 清理并重新开始

```bash
# 删除现有集群
minikube delete

# 清理 minikube 配置
rm -rf ~/.minikube

# 重新启动
minikube start
```

## 卸载

运行卸载脚本：

```bash
~/.tools/minikube/uninstall.sh
```

或者手动卸载：

1. 停止并删除集群：`minikube delete`
2. 删除安装目录：`rm -rf ~/.tools/minikube`
3. 从 shell 配置文件中删除 PATH 配置

## 版本信息

此工具会自动下载最新版本的：
- kubectl (从 Kubernetes 官方仓库)
- minikube (从 GitHub releases)

## 支持

如果遇到问题：

1. 运行 `./check_minikube.sh` 检查环境状态
2. 查看 minikube 日志：`minikube logs`
3. 访问 [minikube 官方文档](https://minikube.sigs.k8s.io/docs/)
4. 访问 [kubectl 官方文档](https://kubernetes.io/docs/reference/kubectl/)

## 许可证

本项目遵循 MIT 许可证。
