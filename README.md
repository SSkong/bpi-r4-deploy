# BPI-R4 Wired 4GB 固件构建

基于 [woziwrt/bpi-r4-deploy](https://github.com/woziwrt/bpi-r4-deploy) 精简改造，只构建 **BPI-R4 4GB wired（无 WiFi）** 一个变体，并集成科学上网全家桶。全程 GitHub Actions 编译，无需本机环境。

## 与上游的差异

| 项目 | 上游 woziwrt | 本仓库 |
|---|---|---|
| 构建变体 | standard/wired × 4GB/8GB/PoE + Pro 8X + UniFi | 仅 wired 4GB（主设备 + lean NAND installer） |
| 构建脚本 | 2 个 builder | `builder-wired-universal.sh` |
| Release | 12+ 个 tag | 仅 `release-4gb-wired` |
| 额外包 | 无 | passwall / passwall2 / ssr-plus / homeproxy / nikki / sing-box / smartdns / chinadns-ng（代理 feeds + 编译前 git clone 清单驱动，见下方"自定义包说明"） |

固件基座不变：OpenWrt `openwrt-25.12` + MediaTek `mtk-openwrt-feeds` main，版本锁定在 **`build-versions.env`**（版本真源，两个 commit 必须成对升级）。

## 产物清单（release-4gb-wired）

| 文件 | 用途 |
|---|---|
| `bpi-r4.itb` | sysupgrade 升级固件 |
| `openwrt-...-bananapi_bpi-r4-nvme-img.bin` | NVMe 全盘安装镜像（推荐） |
| `openwrt-...-bananapi_bpi-r4-sdcard.img.gz` | SD 卡启动盘 |
| `openwrt-...-bananapi_bpi-r4-emmc-img.bin` | eMMC 安装镜像 |
| `openwrt-...-bananapi_bpi-r4-nand-snand-img.bin` | lean NAND installer（装 eMMC/NVMe 的引导步骤） |
| `bpi-r4-rescue-sdcard.img.gz` | 救援 SD 镜像 |
| `sha256sums` / `config.buildinfo` | 校验 / 完整构建配置 |

## 触发构建

1. **Actions** → **Build BPI-R4 Wired 4GB** → **Run workflow**
2. 参数（均可留空）：`repo_commit` 指定本仓库某次提交；`openwrt_commit` / `mtk_commit` 临时覆盖版本锁定
3. 约 2.5~4 小时（含全家桶 Go 编译链），完成后产物原子替换 `release-4gb-wired`（构建失败不影响现有 release）

## 安装流程（4GB wired）

完整流程与上游一致，见上游 [README](https://github.com/woziwrt/bpi-r4-deploy) Part A：

1. `bpi-r4-sdcard.img.gz` 刷入 microSD，DIP **A=1 B=1**（SD 启动），`ssh root@192.168.1.1`
2. SD 系统里执行 `/root/install-dir/install-nand.sh`，RAM 选 **1 (4GB)** → 完成后断电，DIP 改 **A=0 B=1**（NAND 启动）
3. NAND 系统里（需插 WAN）：
   - NVMe：`/root/install-dir/install-nvme.sh`，选 **2 (4GB wired)**——脚本校验 NVMe 健康度后写入并自动重启进入 NVMe 系统
   - eMMC（可选替代）：`/root/install-dir/install-emmc.sh`，选 **2 (4GB wired)**，完成后 DIP 改 **A=1 B=0**

> 安装脚本默认从 `SSkong/bpi-r4-deploy` 拉取 release；菜单里选 "Default" 直接回车即可。
> 脚本菜单中 8GB/PoE/UniFi 选项在本仓库无对应 release，误选会安全报错退出。

## 自定义包说明

采用**编译前 git clone 清单驱动**模式（移植自 VIKINGYFY/OpenWRT-CI，同 bpi-r4-openwrt-builder 仓库）：

- **代理四源**（`scripts/custom-packages.sh` 注入 src-git）：`passwall` / `passwall2` / `passwall_packages`（xray、sing-box、hysteria 等核心）/ `helloworld`（ssr-plus、chinadns-ng）
- **CLONE_LIST clone** 到 `package/custom/`（并发 8 限流 + 逐包 Makefile 校验）：`OpenWrt-nikki`（luci-app-nikki + nikki）、`luci-app-homeproxy`（XiaoHaiSly 修复版，含 sing-box 打包）、`luci-app-smartdns`；smartdns 本体由官方 packages feed 提供
- **双重校验**：clone 后检查 Makefile 存在；`make defconfig` 后按 `scripts/custom-packages.list` 逐包校验已选入 `.config`（defconfig 会静默丢弃缺失包的开关，缺失即构建失败，防止"看起来编了其实没编"）

添加新自定义包的标准三步：
1. `scripts/custom-packages.sh` 的 CLONE_LIST 加一行：`目录名|仓库URL|分支`
2. `configs/my_defconfig-wired-universal` 加 `CONFIG_PACKAGE_<包名>=y`
3. `scripts/custom-packages.list` 加一行包名

全家桶全部编入固件，**运行时只启用一个**（passwall / passwall2 / ssr-plus / homeproxy / nikki 选一），避免 DNS/端口冲突；smartdns / chinadns-ng 可作分流前置。

## 本地构建（可选）

Ubuntu 22.04 + [OpenWrt 构建依赖](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem)：

```bash
bash ./builder-wired-universal.sh
```

## 致谢

- [woziwrt/bpi-r4-deploy](https://github.com/woziwrt/bpi-r4-deploy) — BPI-R4 全套设备定义、U-Boot 补丁与安装系统
- [mediatek/mtk-openwrt-feeds](https://github.com/mediatek/mtk-openwrt-feeds) — MTK SDK feed
- [kenzok8/small-package](https://github.com/kenzok8/small-package) — 科学上网全家桶源

---

*🍌 TEAM WOZIWRT+CLAUDE（上游署名保留）*
