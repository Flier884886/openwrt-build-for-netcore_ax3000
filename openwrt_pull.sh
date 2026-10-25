#!/bin/bash
echo "拉取 OpenWrt 主体"
# 拉取 OpenWrt 主体，跟踪最新稳定分支（当前为 openwrt-25.12)
git clone -b openwrt-25.12 https://github.com/openwrt/openwrt.git openwrt
ls -la
cd openwrt

echo "创建自己的工作分支"
# 创建自己的工作分支
git switch -c netcore-n30pro

# 动态获取当前检出的稳定版 tag（去掉前缀 v）
STABLE_VER=$(git describe --tags --abbrev=0 | sed 's/^v//')
if [ -z "$STABLE_VER" ]; then
    echo "错误: 无法获取稳定版 tag" >&2
    exit 1
fi
echo "当前稳定版: $STABLE_VER"

# 记录克隆时间和版本信息
{
  echo "clone_time=$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "branch=$(git rev-parse --abbrev-ref HEAD)"
  echo "describe=$(git describe --tags --always 2>/dev/null || echo 'unknown')"
  echo "commit=$(git rev-parse HEAD)"
  echo "remote=$(git remote get-url origin)"
} > clone-info.txt
echo "已写入 $(pwd)/clone-info.txt"

# 打dts补丁
curl -fsSL https://github.com/bfdeh/openwrt/commit/3af12a2d67e0db51c7a5ded10bddfa9ce0c4944c.patch -o /tmp/n30pro.patch
if ! git apply --3way /tmp/n30pro.patch; then
    echo "警告：三路合并仍失败，请手动处理" >&2
    exit 1
fi
# 把改动提交成一次 commit
git add -A && git commit -m "mediatek: filogic: add support Netcore N30PRO/NX35U"

# 添加包
echo "克隆UA3F"
git clone --depth=1 https://github.com/SunBK201/UA3F.git package/UA3F
echo "克隆argon主题"
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
echo "克隆openclash"
git clone --depth=1 https://github.com/vernesong/OpenClash.git package/luci-app-openclash
echo "克隆ipid内核模块"
git clone https://github.com/CHN-beta/rkp-ipid.git package/rkp-ipid
# 修补ipid的编译错误
sed -i 's/unsigned int hook_funcion/static unsigned int hook_funcion/' $(find /run/media/masterchen/openwrt_build/openwrt -name "rkp-ipid.c" 2>/dev/null | head -1)
echo "克隆UA-Mask"
git clone --depth=1 https://github.com/Zesuy/UA-Mask.git package/luci/UA-Mask
# echo "显示参数预编译UA-Mask"
# make package/luci/UA-Mask/openwrt/package/compile V=0 \
#   UAMASK_SOURCE_DIR=/run/media/masterchen/openwrt_build/openwrt/package/luci/UA-Mask \
#   2>&1 | tee uamask_build.log
sed -i 's|^UAMASK_SOURCE_DIR:=.*|UAMASK_SOURCE_DIR:=$(TOPDIR)/package/luci/UA-Mask|' package/luci/UA-Mask/openwrt/package/Makefile
echo "克隆 bitsrunlogin-go"
git clone --depth 1 --filter=blob:none --sparse https://github.com/immortalwrt/packages.git temp-packages00/packages
cd temp-packages00/packages
git sparse-checkout set net/bitsrunlogin-go
cd ../..
echo "克隆 luci-app-bitsrunlogin-go"
git clone --depth 1 --filter=blob:none --sparse https://github.com/immortalwrt/luci.git temp-packages00/luci
cd temp-packages00/luci
git sparse-checkout set applications/luci-app-bitsrunlogin-go
cd ../..
# 直接复制到 package/ 下(平级存放)
echo "复制包到 package/"
cp -r temp-packages00/packages/net/bitsrunlogin-go package/
cp -r temp-packages00/luci/applications/luci-app-bitsrunlogin-go package/
echo "清理临时目录 temp-packages00"
rm -rf temp-packages00
# 修补依赖路径错误
cp package/luci-app-bitsrunlogin-go/Makefile package/luci-app-bitsrunlogin-go/Makefile.bak
sed -i 's|^include[[:space:]]\+\.\./\.\./luci\.mk|include $(TOPDIR)/feeds/luci/luci.mk|' package/luci-app-bitsrunlogin-go/Makefile
sed -i 's|^include[[:space:]]\+\.\./\.\./lang/golang/golang-package\.mk|include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|' package/bitsrunlogin-go/Makefile
# 清tmp让修改生效
rm -rf tmp
./scripts/feeds update -a
./scripts/feeds install -a



# ===== 下载并内置 Clash Meta 内核（最新稳定版）=====
echo "下载clash内核"
CLASH_CORE_DIR="files/etc/openclash/core"
mkdir -p "$CLASH_CORE_DIR"

# 获取 mihomo 最新稳定版版本号
META_VER=$(curl -fsSL https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')
if [ -z "$META_VER" ]; then
    echo "错误: 无法获取 mihomo 最新版本号" >&2
    exit 1
fi

META_URL="https://github.com/MetaCubeX/mihomo/releases/download/v${META_VER}/mihomo-linux-arm64-v${META_VER}.gz"
echo "下载 mihomo 内核: v${META_VER}"

if ! wget -qO /tmp/clash_meta.gz "$META_URL"; then
    echo "错误: 下载失败，URL: $META_URL" >&2
    exit 1
fi

gunzip -f /tmp/clash_meta.gz
mv /tmp/clash_meta "$CLASH_CORE_DIR/clash_meta"
chmod 0755 "$CLASH_CORE_DIR/clash_meta"
echo "Clash Meta 内核 v${META_VER} 已放入: $(pwd)/$CLASH_CORE_DIR/clash_meta"


cat >> .config <<'EOF'

# ===== 目标平台（必须在最前）=====
CONFIG_MODULES=y
CONFIG_HAVE_DOT_CONFIG=y
CONFIG_HOST_OS_LINUX=y
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_netcore_n30pro=y
CONFIG_HAS_SUBTARGETS=y
CONFIG_HAS_DEVICES=y
CONFIG_TARGET_BOARD="mediatek"
CONFIG_TARGET_SUBTARGET="filogic"
CONFIG_TARGET_PROFILE="DEVICE_netcore_n30pro"
CONFIG_TARGET_ARCH_PACKAGES="aarch64_cortex-a53"
CONFIG_DEFAULT_TARGET_OPTIMIZATION="-Os -pipe -mcpu=cortex-a53"
CONFIG_CPU_TYPE="cortex-a53"

# 仓库路径
CONFIG_IMAGEOPT=y
CONFIG_VERSIONOPT=y
CONFIG_VERSION_NUMBER="$STABLE_VER"
CONFIG_VERSION_REPO="https://downloads.openwrt.org/releases/$STABLE_VER"

# ===== 核心插件 =====
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-mwan3=y
CONFIG_PACKAGE_luci-app-pbr=y
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_luci-app-wol=y

# ===== USB 基础与存储 =====
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y
CONFIG_PACKAGE_kmod-scsi-core=y

# ===== USB 网卡 =====
CONFIG_PACKAGE_kmod-usb-net=y
CONFIG_PACKAGE_kmod-usb-net-asix=y
CONFIG_PACKAGE_kmod-usb-net-asix-ax88179=y
CONFIG_PACKAGE_kmod-usb-net-rtl8152=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-net-rndis=y

# ===== 自动挂载 =====
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_kmod-fs-autofs4=y

# ===== 文件系统支持 =====
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
CONFIG_PACKAGE_kmod-fs-isofs=y
CONFIG_PACKAGE_kmod-loop=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-utf8=y

# ===== Web 管理界面核心 =====
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-mod-admin-full=y
CONFIG_PACKAGE_luci-mod-network=y
CONFIG_PACKAGE_luci-mod-status=y
CONFIG_PACKAGE_luci-mod-system=y
CONFIG_PACKAGE_luci-app-firewall=y

# ===== UA3F =====
CONFIG_PACKAGE_ua3f=y
CONFIG_PACKAGE_kmod-nft-queue=y
CONFIG_PACKAGE_libubox-lua=y
CONFIG_PACKAGE_kmod-rkp-ipid=y

# ===== UA-Mask =====
CONFIG_PACKAGE_UAmask=y

# ===== bitsrunlogin-go =====
CONFIG_PACKAGE_bitsrunlogin-go=y
CONFIG_PACKAGE_luci-app-bitsrunlogin-go=y

# ===== dns-proxy =====
CONFIG_PACKAGE_https-dns-proxy=y
CONFIG_PACKAGE_luci-app-https-dns-proxy=y

# ===== iptables 兼容层（25.12 使用 iptables-nft）=====
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_kmod-ipt-core=y
CONFIG_PACKAGE_kmod-nft-compat=y

CONFIG_PACKAGE_openssh-sftp-server=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_LUCI_LANG_zh_Hant=y
EOF

#规避循环依赖错误
echo "# CONFIG_PACKAGE_luci-app-weechat is not set" >> .config
echo "# CONFIG_PACKAGE_weechat-full is not set" >> .config
echo "# CONFIG_PACKAGE_weechat-minimal is not set" >> .config
# 让 defconfig 补全所有缺失的依赖和默认值，生成完整 .config
make defconfig
make download V=0 2>&1 | tee download.log
echo "完成"
read #暂停窗口以便查看
