# Swap 虚拟内存配置

创建/调整 swap 交换文件，适合小内存 VPS 装机。仅 Linux。

## 用法

```bash
chmod +x swap/install.sh
./swap/install.sh install              # 自动按内存计算大小创建 swap
./swap/install.sh install --size 4     # 创建 4GB swap
./swap/install.sh status               # 查看 swap 状态
./swap/install.sh uninstall            # 禁用并删除 swap
```

## 行为
- 默认路径 `/swapfile`。
- 未指定大小时按物理内存自动建议：≤2G 内存给 2 倍，否则给等量（上限 8G）。
- 优先用 `fallocate`（快），不支持时回退 `dd`。
- 写入 `/etc/fstab` 实现开机自动挂载。
- 设置 `vm.swappiness=10`（倾向少用 swap，避免频繁交换拖慢性能）。

## 说明
- 仅在已有 swap 时会提示是否重建。
- 卸载会从 `/etc/fstab` 移除对应行并删除配置文件。
