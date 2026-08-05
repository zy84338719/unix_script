# 装机必备工具包

一键安装装机常用的基础软件工具，Linux（apt/dnf/yum）+ macOS（brew）。

## 安装的包

- **网络/传输**：curl、wget、lsof、net-tools、bind-utils(dnsutils)
- **文本/处理**：vim、jq、tree
- **压缩**：unzip、zip、tar、gzip、bzip2
- **监控/会话**：htop、tmux、screen、psmisc
- **系统**：ca-certificates、gnupg、sudo、bash-completion
- **开发**：build-essential / @development tools（gcc、make 等）

## 用法

```bash
chmod +x essential-pkgs/install.sh
./essential-pkgs/install.sh install   # 安装缺失的必备包
./essential-pkgs/install.sh status    # 检查哪些未装
```

## 说明
- 自动跳过已安装的包，只装缺失项。
- macOS 需 [Homebrew](https://brew.sh/)。
- 不建议卸载这些基础工具（其他程序可能依赖），`uninstall` 子命令会给出手动卸载命令。
