#!/bin/bash
# ============================================================
# custom-packages.sh —— 自定义包注入（在 feeds update 之前执行）
# 模式：VIKINGYFY/OpenWRT-CI 清单驱动，移植自 bpi-r4-openwrt-builder diy-part1.sh
#   一、代理四源 src-git 注入（passwall_packages/passwall/passwall2/helloworld）
#   二、CLONE_LIST 清单驱动 git clone 到 package/custom/（并发 8 限流）
#   三、逐包 Makefile 校验（clone 失败/缺 Makefile 即报错退出）
#
# 添加新自定义包的标准三步：
#   ① 本脚本 CLONE_LIST 加一行：目录名|仓库URL|分支（分支留空=上游默认分支）
#   ② configs/my_defconfig-wired-universal 加 CONFIG_PACKAGE_<包名>=y
#   ③ scripts/custom-packages.list 加一行包名（builder 在 defconfig 后校验选入）
#
# 执行环境：当前目录为 OpenWrt 源码根目录
# ============================================================
set -e

# ============================================================
# 一、代理 feeds 注入（src-git：feeds update 时从上游 clone 最新版）
#
#   passwall_packages: 代理核心（xray-core/sing-box/hysteria/
#                       shadowsocks-rust/naiveproxy/shadow-tls/chinadns-ng 等）
#   passwall:          luci-app-passwall
#   passwall2:         luci-app-passwall2（独立仓库，main 分支仅含此包）
#   helloworld:        luci-app-ssr-plus + chinadns-ng + 额外核心（分支 dev）
#
#   同名包由 feeds install 按声明顺序去重，先声明者优先；
#   package/custom/ 下的包优先级高于 feeds（防顶替）。
# ============================================================
sed -i '/passwall_packages/d; /openwrt-passwall-packages/d; /src-git passwall /d; /src-git passwall2/d; /Openwrt-Passwall\/openwrt-passwall/d; /src-git helloworld/d; /fw876\/helloworld/d' feeds.conf.default
echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' >> feeds.conf.default
echo 'src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall.git;main' >> feeds.conf.default
echo 'src-git passwall2 https://github.com/Openwrt-Passwall/openwrt-passwall2.git;main' >> feeds.conf.default
echo 'src-git helloworld https://github.com/fw876/helloworld.git;dev' >> feeds.conf.default

# ============================================================
# 二、自定义包（编译时逐仓库 clone 最新版到 package/custom/）
#
# 克隆清单格式：目录名|仓库URL|分支（分支留空 = 上游默认分支）
# OpenWrt 25.12 包扫描深度为 5 层（include/scan.mk SCAN_DEPTH=5），
# 整仓库 clone 到 package/custom/ 下即可被自动发现，无需移动子目录。
# ============================================================
rm -rf package/custom
mkdir -p package/custom

CLONE_LIST="
# --- sing-box 管理器 nikki（含 luci-app-nikki + nikki + mihomo）---
OpenWrt-nikki|https://github.com/nikkinikki-org/OpenWrt-nikki.git|main
# --- homeproxy（社区修复版，仓库自带 sing-box 打包）---
luci-app-homeproxy|https://github.com/XiaoHaiSly/luci-app-homeproxy.git|main
# --- DNS 加速管理界面（smartdns 本体由官方 packages feed 提供）---
luci-app-smartdns|https://github.com/pymumu/luci-app-smartdns.git|master
"

# 并行克隆（并发 8：控制与 GitHub 的连接数，避免限流；失败不中断，
# 由下方校验步骤统一报告缺失项）
MAX_JOBS=8
while IFS='|' read -r dir url branch; do
  case "$dir" in ''|'#'*) continue ;; esac
  (
    if [ -n "$branch" ]; then
      git clone -q --depth 1 --single-branch --branch "$branch" "$url" "package/custom/$dir" \
        && echo "  OK $dir ($branch)" \
        || echo "  FAIL $dir 克隆失败"
    else
      git clone -q --depth 1 "$url" "package/custom/$dir" \
        && echo "  OK $dir (默认分支)" \
        || echo "  FAIL $dir 克隆失败"
    fi
  ) &
  # 并发限流：达到上限时等待任一任务结束
  while [ "$(jobs -rp | wc -l)" -ge "$MAX_JOBS" ]; do
    sleep 0.3
  done
done <<< "$CLONE_LIST"
wait || true

# ============================================================
# 三、克隆结果校验（逐包必须含有效 Makefile，缺失即失败）
# ============================================================
check_pkg() {
  find "package/custom/$1" -maxdepth 3 -name Makefile -print -quit 2>/dev/null | grep -q .
}

FAILED=""
while IFS='|' read -r dir url branch; do
  case "$dir" in ''|'#'*) continue ;; esac
  check_pkg "$dir" || FAILED="$FAILED $dir"
done <<< "$CLONE_LIST"

if [ -n "$FAILED" ]; then
  echo "ERROR: 以下包 clone 失败，未发现有效 Makefile:$FAILED"
  exit 1
fi

echo "===== package/custom Makefile 扫描结果 ====="
find package/custom -maxdepth 3 -name Makefile -not -path '*/.git/*' | wc -l \
  | xargs -I{} echo "共发现 {} 个 Makefile"
echo "custom-packages: 代理源注入 + 编译时 clone 完成"
