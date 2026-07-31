# npm-mirror（npm/yarn/pnpm 换源加速）

一键为已安装的 **npm / yarn / pnpm** 配置国内 registry，加速依赖安装。默认切换到淘宝源（npmmirror）。Linux + macOS。

## 用法

```bash
chmod +x npm-mirror/install.sh
./npm-mirror/install.sh install            # 交互式选择源（默认淘宝）
./npm-mirror/install.sh install taobao     # 直接切到淘宝源
./npm-mirror/install.sh install tencent    # 腾讯云
./npm-mirror/install.sh install huawei     # 华为云
./npm-mirror/install.sh install npm        # 官方源
./npm-mirror/install.sh install https://my-mirror.com/   # 自定义 URL
./npm-mirror/install.sh status             # 查看各包管理器当前 registry
./npm-mirror/install.sh uninstall          # 还原为官方源
```

## 内置源

| 名称 | URL | 说明 |
|------|-----|------|
| `taobao` | `https://registry.npmmirror.com` | **默认/推荐**，淘宝/阿里云 |
| `tencent` | `https://mirrors.cloud.tencent.com/npm/` | 腾讯云 |
| `huawei` | `https://mirrors.huaweicloud.com/repository/npm/` | 华为云 |
| `npm` | `https://registry.npmjs.org/` | 官方源（还原用） |

## 说明

- 配置写入**用户级**（`--location=user` 或家目录配置文件），无需 sudo，不污染系统全局。
- **yarn** 自动适配大版本：v1 写 `~/.yarnrc`（`registry`），v2+ (Berry) 写 `~/.yarnrc.yml`（`npmRegistryServer`）。
- 仅对已安装的包管理器生效；未安装的会被跳过并在 `status` 中标注「未安装」。
- 检测到 `nrm`/`cnpm` 等源管理工具时会给出提示，避免配置相互覆盖。
- 前置依赖：需先通过 `nvm` 模块安装 Node.js，再安装 npm/yarn/pnpm。
