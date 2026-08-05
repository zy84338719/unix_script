# dev-mirror（开发换源加速：npm / Go / Rust / Python）

一键为开发语言生态配置国内镜像，加速依赖/模块下载。覆盖 **npm（+ yarn/pnpm）、Go（GOPROXY）、Rust（cargo）、Python（pip）**。Linux + macOS。

> 取代并合并了旧的单生态 `npm-mirror` 模块（`install.sh npm-mirror` 别名仍可用，路由到本模块）。

## 用法

```bash
chmod +x dev-mirror/install.sh
./dev-mirror/install.sh install                     # 交互：先选生态，再选源
./dev-mirror/install.sh install go goproxy-cn       # 直接为 Go 配置 goproxy.cn
./dev-mirror/install.sh install npm taobao          # npm 切淘宝源
./dev-mirror/install.sh install python tuna         # pip 切清华源
./dev-mirror/install.sh install rust tuna           # cargo 切清华源
./dev-mirror/install.sh install all default         # 一键全部用各生态默认推荐源
./dev-mirror/install.sh install npm https://my.com/ # 自定义 URL
./dev-mirror/install.sh status                      # 查看各生态当前镜像
./dev-mirror/install.sh uninstall rust              # 还原 cargo 官方源
./dev-mirror/install.sh uninstall all               # 还原全部官方源
```

## 内置源清单

### npm（registry）
| key | URL | 说明 |
|-----|-----|------|
| `taobao` | `https://registry.npmmirror.com` | **默认/推荐**，淘宝/阿里云 |
| `tencent` | `https://mirrors.cloud.tencent.com/npm/` | 腾讯云 |
| `huawei` | `https://mirrors.huaweicloud.com/repository/npm/` | 华为云 |
| `official` | `https://registry.npmjs.org/` | 官方（还原用）|

### Go（GOPROXY）
| key | URL | 说明 |
|-----|-----|------|
| `goproxy-cn` | `https://goproxy.cn,direct` | **默认/推荐**，七牛 |
| `aliyun` | `https://mirrors.aliyun.com/goproxy/,direct` | 阿里云 |
| `goproxy-io` | `https://goproxy.io,direct` | goproxy.io |
| `official` | `https://proxy.golang.org,direct` | 官方（还原用）|

### Rust（cargo，sparse 稀疏索引）
| key | URL | 说明 |
|-----|-----|------|
| `tuna` | `https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/` | **默认/推荐**，清华 |
| `ustc` | `https://mirrors.ustc.edu.cn/crates.io-index/` | 中科大 |
| `sjtu` | `https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/` | 上交 |
| `rsproxy` | `https://rsproxy.cn/index/` | 字节 |
| `official` | — | 官方 crates.io（还原用，移除配置块）|

### Python（pip index-url）
| key | URL | 说明 |
|-----|-----|------|
| `tuna` | `https://pypi.tuna.tsinghua.edu.cn/simple` | **默认/推荐**，清华 |
| `aliyun` | `https://mirrors.aliyun.com/pypi/simple/` | 阿里云 |
| `ustc` | `https://pypi.mirrors.ustc.edu.cn/simple/` | 中科大 |
| `tencent` | `https://mirrors.cloud.tencent.com/pypi/simple` | 腾讯云 |
| `official` | `https://pypi.org/simple` | 官方 PyPI（还原用）|

## 说明

- 配置写入**用户级**（家目录或各工具原生 config），无需 sudo，不污染系统全局。
- **npm**：`npm config set registry`；yarn 自动适配 v1（`.yarnrc`）/ v2+（`.yarnrc.yml`）。
- **Go**：优先 `go env -w GOPROXY`（go 1.13+）；老版本回退写 `~/.bashrc` 环境变量。
- **Rust**：写 `~/.cargo/config.toml`，用 `replace-with` + `sparse+` 稀疏索引；用标记段包裹便于幂等更新与干净卸载，不破坏用户其他 cargo 配置。
- **Python**：优先 `pip config set`（pip 10+）；不可用时回退手写 `~/.config/pip/pip.conf`。
- 仅对已安装的工具链生效；未安装的生态会被跳过并在 `status` 中标注「未安装」。
- npm 生态会额外检测 `nrm`/`cnpm`，给出冲突提示。
