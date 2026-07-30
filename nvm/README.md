# nvm（Node 版本管理）

安装 [nvm](https://github.com/nvm-sh/nvm)（Node Version Manager），用于管理多个 Node.js 版本。Linux + macOS。

## 用法

```bash
chmod +x nvm/install.sh
./nvm/install.sh install     # 安装 nvm 最新版并配置 shell
./nvm/install.sh status      # 查看安装状态
./nvm/install.sh uninstall   # 卸载 nvm
```

## 安装后

nvm 安装到 `~/.nvm`，并自动为 `~/.bashrc`、`~/.zshrc`、`~/.profile` 添加激活配置。重新加载 shell 后即可使用：

```bash
source ~/.bashrc        # 或重新打开终端
nvm install --lts       # 安装最新 LTS 版 Node
nvm install 20          # 安装指定版本
nvm use 20
nvm ls
```

## 说明
- 通过 GitHub API 取最新版本，CI 中带 `GH_TOKEN` 认证规避速率限制。
- 卸载会删除 `~/.nvm` 并清理 shell 配置文件中的 nvm 相关行（保留 `.bak` 备份）。
