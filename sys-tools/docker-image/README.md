# docker-image —— Docker 镜像拉取与导出

从公网拉取 Docker 镜像，导出为本地 gzip 压缩文件（`.tar.gz`），便于离线分发、备份或迁移。

## 功能

- **交互式逐步引导**：镜像名 → 导出目录 → 文件名
- **gzip 压缩导出**：`docker save | gzip`，体积小、`docker load` 可直接读取
- **批量处理**：导完一个可继续下一个，循环直至用户结束
- **本地已有时询问**：避免重复下载
- **导出摘要**：digest、文件大小、耗时一目了然
- **安全校验**：目录可写检查、文件名合法性检查、文件已存在询问覆盖

## 前置要求

本机已安装并运行 Docker：

```bash
./install.sh docker     # 如未安装 Docker 引擎
```

## 用法

### 交互式（推荐）

```bash
./docker-image/install.sh save
```

依次询问：
1. 镜像名（如 `nginx:1.25`，无 tag 自动补 `:latest`）
2. 导出目录（默认当前目录，不存在可创建）
3. 文件名（默认 `<镜像名>.tar.gz`，可自定义）

导出完成后询问「是否继续下一个」。

### 直接指定镜像名

```bash
./docker-image/install.sh save nginx:1.25
```

跳过镜像名输入，仍询问目录与文件名。

### 检查 Docker 状态

```bash
./docker-image/install.sh status
```

## 导出文件恢复

导出的 `.tar.gz` 可直接用 `docker load` 加载：

```bash
docker load < nginx_1.25.tar.gz
# 或
gunzip -c nginx_1.25.tar.gz | docker load
```

## 示例

```
$ ./docker-image/install.sh save
📦 Docker 镜像拉取与导出
请输入要拉取的镜像名（如 nginx:1.25，回车结束）: nginx:1.25
目标镜像：nginx:1.25
...
📦 导出摘要
  镜像:   nginx:1.25
  digest: nginx@sha256:...
  文件:   ./nginx_1.25.tar.gz
  大小:   45MB
  耗时:   12s
```

## 平台支持

Linux + macOS 均可（依赖 Docker 本身的可用性）。
