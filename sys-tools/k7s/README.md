# k7s

[k7s](https://github.com/zy84338719/k7s) —— Kubernetes 桌面监控工具（Tauri + Rust + React），提供轻量的集群资源可视化。Linux + macOS。

## 支持平台

| 平台 | 安装方式 | 安装位置 |
|------|----------|----------|
| Linux (x86_64 / ARM64) | deb / rpm / AppImage | deb/rpm 由包管理器管理；AppImage → `~/.local/bin/k7s` |
| macOS (Intel / Apple Silicon) | .dmg | `/Applications/k7s.app` |

## 安装

```bash
chmod +x k7s/install.sh
./k7s/install.sh            # 安装（默认动作）
./k7s/install.sh install    # 显式安装
```

脚本会自动检测平台和架构，从 [GitHub Releases](https://github.com/zy84338719/k7s/releases) 下载最新版本。

## 状态与卸载

```bash
./k7s/install.sh status      # 查看安装状态
./k7s/install.sh uninstall   # 卸载
```

## 启动方式

```bash
# macOS
open -a k7s

# Linux
k7s
```

## 说明

- Linux 优先使用 deb/rpm 安装，不支持时回退到 AppImage。
- AppImage 安装到 `~/.local/bin`，需确保该目录在 PATH 中。
- 官方文档：https://github.com/zy84338719/k7s
