# Netcore N30Pro OpenWrt 自编译指南（校园网特化）

> 面向中国爱好者，尤其是**校园网环境**下的学生用户，仅供学习研究。
> 本仓库提供一键拉取/配置脚本 + 校园网突围说明 + 构建指令，帮助你从**官方 OpenWrt 最新稳定版**快速编译出适用于 **Netcore N30Pro** 的固件。

⚠️ **注意：拉取源码、下载内核与依赖需要科学上网。**

---

## 📦 仓库内容

| 文件              | 说明                                                                                         |
| ----------------- | -------------------------------------------------------------------------------------------- |
| `openwrt_pull.sh` | 一键脚本：克隆 OpenWrt 稳定分支、打 DTS 补丁、拉取插件、内置 Clash Meta 内核、生成 `.config` |
| `build.sh`        | 编译脚本：先单独编译 `llvm-bpf`（省运行内存，否则内存不够用），再全量编译并记录日志          |
| `README.md`       | 本文件（含文末的校园网突围指南）                                                             |

---

## 🎯 项目定位

- 目标设备：**Netcore N30Pro**（MediaTek Filogic，aarch64_cortex-a53）
- 基线：**OpenWrt 官方稳定分支 `openwrt-25.12`**（脚本自动跟踪最新稳定 tag）
- 场景：**校园网**（深澜认证、多设备检测、TTL/UA/IPID 特征检测、DNS 泄露检测）
- 原则：尽量使用官方源码 + 少量必要补丁，避免臃肿，方便复现与升级（也是因为我经常有破坏性改动导致依赖乱成一锅粥，需要快速恢复）

---

## 🔧 关于 N30Pro DTS 补丁（重要）

官方 OpenWrt 源码中 **Netcore N30Pro 的设备树（DTS）尚不完整**，直接编译会出现两个问题：

1. **USB 供电异常**：USB 接口供电相关节点缺失，导致外接 U 盘、USB 网卡等设备无法正常识别或供电不足。
2. **4 网口无法完整识别**：设备有 4 个网口，但原厂 DTS 中交换机/PHY 端口映射不完整，编译后只能识别部分网口（通常只能识别 3 个），无法使用全部 4 个网口。

因此 `openwrt_pull.sh` 中会拉取并 `git apply` 来自 [bfdeh/openwrt](https://github.com/bfdeh/openwrt) 的 DTS 补丁（commit `3af12a2`），**修复 USB 供电问题 + 补全 4 网口识别**，并把改动提交为一次 commit：

    curl -fsSL https://github.com/bfdeh/openwrt/commit/3af12a2d67e0db51c7a5ded10bddfa9ce0c4944c.patch -o /tmp/n30pro.patch
    git apply --3way /tmp/n30pro.patch
    git add -A && git commit -m "mediatek: filogic: add support Netcore N30PRO/NX35U"

> 如果你的设备是 N30Pro / NX35U，**这个补丁是必须的**，否则 USB 与 4 网口无法正常工作。

---

## 🚀 快速开始

### 1. 环境准备（Linux，推荐 Ubuntu/Debian）

    sudo apt update
    sudo apt install -y build-essential clang flex bison g++ gawk \
      gcc-multilib g++-multilib gettext git libncurses5-dev libncursesw5-dev \
      zlib1g-dev python3 python3-setuptools python3-pip rsync unzip wget \
      file libssl-dev libelf-dev

> **磁盘空闲空间建议 > 70GB**（编译完成后目录约占用 65GB）；**运行内存建议 > 6GB**（8GB 更稳，多多益善，内存不足请开启 swap）。

### 2. 拉取与配置

    git clone <本仓库地址> openwrt_build
    cd openwrt_build
    chmod +x openwrt_pull.sh build.sh
    ./openwrt_pull.sh

脚本会：

1. `git clone -b openwrt-25.12` 官方源码并创建分支 `netcore-n30pro`
2. 打 **N30Pro DTS 补丁**（修复 USB 供电 + 补全 4 网口识别）
3. 拉取插件并 `feeds update/install`
4. 下载 **mihomo（Clash Meta）最新稳定版 arm64 内核**放入 `files/etc/openclash/core/clash_meta`
5. 生成 `.config`（目标平台 + 插件 + 内核模块）

### 3. 编译（使用 build.sh）

    cd openwrt
    ../build.sh

`build.sh` 内容：

    make tools/llvm-bpf/compile -j1 V=s 2>&1 | tee llvm-bpf.log
    make -j$(nproc) V=s 2>&1 | tee build.log
    grep -n -B 50 "ERROR: package/.*failed to build" build.log

说明：

- **先 `-j1` 单独编译 `tools/llvm-bpf`**：目的是**节省运行内存**（并行编译该工具链极易吃满内存导致 OOM/失败），单独串行最稳。
- 再 `make -j$(nproc)` 全速编译，日志写入 `build.log`。
- 最后 `grep` 自动定位编译失败包的前 50 行上下文，方便排查。

产物：`bin/targets/mediatek/filogic/` 下的 `*sysupgrade.itb` 等。

### 4. 刷机

- 首次从原厂固件刷入：使用 **factory** 镜像（按 N30Pro 官方刷机方式）
- 后续升级：使用 **sysupgrade** 镜像，保留配置
- 推荐刷入**Yuzhii0718 的 `bl-mt798x-dhcpd` 系列 U-Boot**，带有DHCP功能无需配置静态IP，也有WebUI界面方便刷写

---

# 一、固件内置特性（编译进固件，开箱即用）

> 以下能力在 `openwrt_pull.sh` 生成的 `.config` 中已勾选，**刷机后无需额外安装**即可使用。

### 核心插件

- `luci-app-openclash` + 内置 **mihomo (Clash Meta)** 内核（`files/etc/openclash/core/clash_meta`）
- `luci-app-mwan3`（多 WAN 负载/故障切换）
- `luci-app-pbr`（策略路由）
- `luci-app-samba4`（文件共享）
- `luci-app-wol`（网络唤醒）
- `luci-app-sqm` + `sqm-scripts`（**智能队列，降低高占用/高延迟触发校园网系统检测的风险**，缓解 bufferbloat）
- `luci-app-https-dns-proxy`（DoH 加密 DNS）
- `luci-app-harbor-file`（Web 文件管理）
- `luci-theme-argon`（Argon 主题）

### 校园网 / 伪装相关

- `UA-MASK` （UA 伪装，实测 `UA3F` 非常卡不建议启用）
- `kmod-rkp-ipid`（IPID 递增伪装，内核模块已内置）
- `smart-srun`（深澜校园网自动登录）
- `iptables-nft` / `kmod-nft-compat`（兼容层）
- `ebtables-legacy` + `kmod-ebtables-*` + `kmod-nft-bridge`（切断 STP 等二层特征所需模块已内置）

### USB / 存储

- USB2/3、UAS、SCSI、`kmod-usb-net-*`（asix / ax88179 / rtl8152 / cdc-ether / rndis）
- `block-mount`、`kmod-fs-autofs4`
- 文件系统：ext4 / vfat / exfat / ntfs3 / isofs / loop / nls-cp437 / nls-utf8
- **配合 DTS 补丁后，USB 供电正常、4 网口全部可用**

### 网络与系统

- `uhttpd` + LuCI 全套模块
- `kmod-wireguard`（**VPN 服务器能力已内置**，可直接在 LuCI/SSH 搭建 WireGuard 服务端，无需重编）
- **`tcpdump`（已集成进固件，开箱即用）**：可直接在 SSH 中对 WAN/LAN/桥接口抓包，配合 `kmod-nft-*`、`iptables-nft` 兼容层与 bridge 模块分析校园网认证与特征检测流量（电脑端可以使用`WireShark`连接获得更好体验）
- `openssh-sftp-server`（SFTP服务器，ssh连接时传文件更便捷）
- `acl`、`shadow-useradd`（用于samba4用户管理）
- 中文语言包（zh_Hans / zh_Hant）

> 脚本中已规避 `weechat` 系列循环依赖。

---

# 二、刷机后手动配置特性（需执行启动脚本 / SSH 命令生效）

> 以下能力**不在固件编译范围内**，而是刷机后按下方 SSH 配置生效。二者请勿混淆。

1. **IPID 全局伪装（nftables 打标）**
   启动脚本用 `nft` 新建 `ipid_change` 表，在 `postrouting` 排除内网与 DHCP 后统一 `meta mark or 0x10`，配合已内置的 `rkp-ipid` 内核模块实现 IPID 递增伪装。

2. **TTL / Hop Limit 强制 128**
   通过 `/usr/share/nftables.d/chain-post/mangle_postrouting/99-set-ttl.nft` 注入：IPv4 TTL 设 128；IPv6 排除 NDP（133–136）后 hoplimit 设 128，避免破坏邻居发现。

3. **切断校园网 STP 二层特征**
   `ebtables` 规则丢弃 `01:80:c2:00:00:00`（STP/BPDU）在 `eth1` 与 `phy1-sta0` 的 FORWARD 双向流量，降低被交换机识别为"路由器"的概率（依赖固件已内置的 ebtables 模块）。

4. **NTP 强制重定向到路由器**
   `system.ntp` 启用 LAN 服务端 + 国内 NTP 源；防火墙 DNAT 将 LAN 侧 UDP/123 重定向到 `192.168.1.1:123`，统一时间源、减少外联特征。

5. **DNS 劫持 + DoH 加密上游**

   - `https-dns-proxy` 关闭 `force_dns`，批量配置 6 个 DoH（阿里/腾讯/360/腾讯国密/Quad9/Cloudflare），监听 5053–5058
   - `/etc/hosts` 写入 DoH 域名→IP 的 Bootstrap 覆盖
   - `dnsmasq` 上游固定为 `127.0.0.1#5053~5058`，`noresolv=1`
   - nftables `dstnat` 预链将 `br-lan` 进入的 53/udp、53/tcp 全部 `redirect to :53`，防止明文 DNS 泄露

6. **关闭 Flow Offloading**
   强制 `flow_offloading=0` / `flow_offloading_hw=0`，否则上述 TTL/DNS/IPID 规则会被硬件/软件加速绕过。

7. **内网信息防泄露（nftables forward 预链）**
   `99-block-leak.nft`：LAN→LAN 放行；封杀离开 LAN 的 IPv4 组播/广播、IPv6 链路本地组播、NetBIOS(137/138/139)、UPnP(1900/2869)，防止 SSDP/LLMNR 等发现协议泄露到 WAN。

8. **Samba 入站放行**
   新增 `Allow-Samba-LAN` 规则，允许 LAN （内网）访问路由器 137–139/445。

9. **主机名 / 设备名统一伪装**
   `hostname`、`network.wan.hostname`、Samba `NAME/DESCRIPTION/WORKGROUP` 统一为 `MasterChen` / `Windows File Sharing` / `WORKGROUP`。

10. **MAC 地址伪装（最后执行，避免 SSH 断连）**
    `network.wan.macaddr`、`wireless.radio0/radio1.macaddr` 统一设置为指定值，并在重启网络前完成备份（`/root/mac_backup.txt`、`network.bak_mac`、`wireless.bak_mac`）。

11. **软件源切换中科大镜像**
    `distfeeds.list` 中 `downloads.openwrt.org` → `mirrors.ustc.edu.cn/openwrt`，`apk update` 加速。

12. **配置备份**
    首次 SSH 执行会备份 `network` / `wireless` / `nftables.d` 到 `/root`，便于回滚。

---

## 

## 🛠 构建指令速查

    # 进入源码
    cd openwrt
    
    # 可选：菜单调整
    make menuconfig
    
    # 推荐：先单独串行编译 llvm-bpf（省运行内存，见 build.sh）
    make tools/llvm-bpf/compile -j1 V=s 2>&1 | tee llvm-bpf.log
    
    # 全量编译
    make -j$(nproc) V=s 2>&1 | tee build.log
    
    # 失败排查：定位失败包前 50 行
    grep -n -B 50 "ERROR: package/.*failed to build" build.log
    
    # 只编译某个包
    make package/luci-app-openclash/compile V=s
    
    # 清理
    make clean          # 清产物
    make dirclean       # 清工具链

产物目录：`bin/targets/mediatek/filogic/`

---

## ⚠️ 注意事项

- **需要科学上网**：GitHub、mihomo release、feeds 拉取均需稳定网络。
- 磁盘空闲建议 **> 70GB**（编译后约 65GB），运行内存建议 **> 6GB**，不足请开 swap。
- 脚本中 `sed` 修补 `rkp-ipid.c` 与 `UA-Mask` Makefile 的路径按个人环境写死（忘记有没有了，如果编译失败就自己调或问可靠点的AI），**请按自己路径调整**（或改为相对 `$(TOPDIR)`）。
- 首次刷机后**务必到 LuCI → 系统 → 系统 → 通用设置 同步时间**，否则 DoH/TLS 可能失败。
- MAC 修改在脚本最后执行并重启网络，SSH 可能短暂断开，属正常现象。
- `tcpdump` 已内置固件，无需 `apk` 安装即可抓包。
- 本项目为个人校园网使用配置，**请遵守所在学校网络管理规定**，仅供学习与研究。

---

# 三、校园网突围指南

> 本项目最初就是为校园网环境（深澜认证、多设备/特征检测）而做。以下配置用于**降低被校园网系统识别为"路由器/多设备共享"的风险**，并减少明文特征泄露。请遵守学校网络管理规定，仅供学习与研究。

校园网常见检测手段与本方案对应处理：

| 检测手段      | 特征                                | 本方案处理                                                        |
| ------------- | ----------------------------------- | ----------------------------------------------------------------- |
| TTL 检测      | 经路由器转发后 TTL 递减（如 64→63） | nftables 强制 TTL/Hop Limit 为 128                                |
| UA 检测       | 非浏览器 UA / 多设备不同 UA         | UA3F + UA-Mask 统一伪装为 Chrome                                  |
| IPID 检测     | 多设备 IPID 不连续/随机             | `rkp-ipid` 内核模块 + nftables 打标，伪装为递增                   |
| 时间/外联检测 | 设备各自外联 NTP                    | 强制 NTP 重定向到路由器统一时间源                                 |
| DNS 泄露      | 明文 DNS 暴露查询特征               | 全局 53 劫持 + 6 路 DoH 加密上游                                  |
| 二层特征      | STP/BPDU、组播/广播发现协议         | ebtables 丢弃 STP；nftables 封杀离开 LAN 的组播/广播/NetBIOS/UPnP |
| 高占用/高延迟 | 大流量、bufferbloat 触发风控        | SQM 智能队列整形                                                  |

---

## 3.1 第一步：填写和配置 UA

进入 LuCI → **服务 → UA MASK**，按下表填写：

### 常规设置

- **User-Agent 标识** 修改为：

  ```UA
  Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36
  ```

- **匹配规则**：修改所有流量（强制）

- **网络与防火墙：绕过目标 IP**：`192.168.1.0/24`

### 保存并应用

点击「保存并应用」后生效。UA3F 由固件内置，负责对经过路由器的 HTTP/HTTPS 流量做 UA 改写；UA-Mask 提供 LuCI 规则管理。

> 注意：本方法仅在编译/使用本仓库脚本布置环境所编译的固件中可用（UA3F + `kmod-nft-queue` 已内置）。

---

## 3.2 第二步：编辑启动脚本

进入 LuCI → **系统 → 启动项 → 本地启动脚本**，在 `exit 0` 之前加入以下内容（IPID 打标 + 切断 STP）：

```bash
# IPID 伪装全局标记（排除局域网和 DHCP）
nft add table ip ipid_change
nft add chain ip ipid_change postrouting { type filter hook postrouting priority 0\; policy accept\; }
# 1. 排除内网互访
nft add rule ip ipid_change postrouting ip daddr 192.168.1.0/24 return
# 2. 排除 DHCP 客户端请求和回复（极其关键）
nft add rule ip ipid_change postrouting udp sport 68 udp dport 67 return
nft add rule ip ipid_change postrouting udp sport 67 udp dport 68 return
# 3. 剩下的才打标
nft add rule ip ipid_change postrouting meta mark set meta mark or 0x10

# 切断校园网 STP 往来
ebtables -A FORWARD -i eth1 -d 01:80:c2:00:00:00 -j DROP
ebtables -A FORWARD -o eth1 -d 01:80:c2:00:00:00 -j DROP
ebtables -A FORWARD -i phy1-sta0 -d 01:80:c2:00:00:00 -j DROP
ebtables -A FORWARD -o phy1-sta0 -d 01:80:c2:00:00:00 -j DROP
exit 0
```

> 只保留一个 `exit 0`，放在最后。保存后重启路由器或重启相关服务使启动脚本生效。

---

## 3.3 第三步：执行 SSH（推荐使用开源的 Tabby）

使用开源 SSH 工具 **Tabby**（或其他任意 SSH 客户端）连接路由器（默认 `192.168.1.1`，root 登录），**将下面代码框内容一次性粘贴执行**。

该脚本按顺序完成：

1. 备份 network / wireless / nftables 配置与 MAC 信息
2. TTL / Hop Limit 强制 128
3. 关闭 Flow Offloading
4. NTP 服务端 + 强制重定向
5. 配置 6 路 DoH 加密 DNS + hosts Bootstrap 覆盖
6. dnsmasq 上游固定到 6 个 DoH 端口
7. 全局 53 端口劫持
8. 主机名 / 设备名伪装
9. 内网信息防泄露 + Samba 入站放行
10. 软件源切换中科大镜像
11. MAC 伪装（最后执行，避免 SSH 断连）
12. 重启网络

执行完成后：

- **务必前往 LuCI → 系统 → 系统 → 通用设置 同步时间**，否则 DoH/TLS 可能失败。

- MAC 修改会导致 SSH 短暂断开，属正常现象，重连即可。

  #### 首次启动后 SSH 执行（完整命令，一次复制）

  > 使用 Tabby / 任意 SSH 工具连接路由器后，**将下面整个代码框内容一次性粘贴执行**。默认 LAN 为 `192.168.1.0/24`、路由器 `192.168.1.1`，如不同请先全局替换。
  >
  > 关键代码**AI零信任**原则，坚决不使用AI优化。
  >
  > 屎山代码请见谅，关键是能跑，实测能用。

  ```bash
  # 备份网络和无线配置
  cp /etc/config/network /etc/config/network.bak_mac
  cp /etc/config/wireless /etc/config/wireless.bak_mac
  # 顺便把当前的规则也备份一下
  cp -r /usr/share/nftables.d /root/nftables.d.bak
  echo "=== 当前配置的 MAC 备份 ($(date)) ===" > /root/mac_backup.txt
  echo "--- 网络接口 (WAN) ---" >> /root/mac_backup.txt
  uci get network.wan.macaddr 2>/dev/null >> /root/mac_backup.txt || echo "未设置(使用默认)" >> /root/mac_backup.txt
  echo "--- 无线中继 (WWAN) ---" >> /root/mac_backup.txt
  # 查找所有绑定了客户端模式的接口
  for i in $(uci show wireless | grep "mode='sta'" | cut -d. -f2 | cut -d= -f1); do
      echo "接口 $i: $(uci get wireless.$i.macaddr 2>/dev/null || echo '未设置')" >> /root/mac_backup.txt
  done
  # 显示备份内容
  cat /root/mac_backup.txt
  
  mkdir -p /usr/share/nftables.d/chain-post/mangle_postrouting/
  # 写入 TTL 伪装规则（文件内容只需写规则本身，无需 table/chain 声明）
  cat << 'EOF' > /usr/share/nftables.d/chain-post/mangle_postrouting/99-set-ttl.nft
  ip ttl set 128
  # 非 ICMPv6 的普通流量：设为 128
  ip6 nexthdr != icmpv6 ip6 hoplimit set 128
  # ICMPv6 中排除 NDP 类型（133-136）后，剩余流量设为 128
  ip6 nexthdr icmpv6 icmpv6 type != { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } ip6 hoplimit set 128
  EOF
  # 重载防火墙，使规则自动合并生效
  fw4 reload
  
  # 关闭 Flow Offloading
  uci set firewall.@defaults[0].flow_offloading='0'
  uci set firewall.@defaults[0].flow_offloading_hw='0'
  uci commit firewall
  # 添加防火墙重定向规则（假设路由器 LAN IP 是 192.168.1.1）
  uci set system.ntp.enable_server='1'
  uci set system.ntp.interface='lan'
  uci -q delete system.ntp.server
  uci add_list system.ntp.server='ntp.ntsc.ac.cn'
  uci add_list system.ntp.server='ntp.tencent.com'
  uci add_list system.ntp.server='time1.cloud.tencent.com'
  uci add_list system.ntp.server='ntp.aliyun.com'
  uci add_list system.ntp.server='ntp1.nim.ac.cn'
  uci add_list system.ntp.server='ntp.aliyun.com'
  uci add_list system.ntp.server='pool.ntp.org'
  uci set system.@system[0].timezone='CST-8'
  uci set system.@system[0].zonename='Asia/Shanghai'
  uci commit system
  /etc/init.d/sysntpd restart
  
  # 添加有状态 DNAT 重定向规则（ntp服务器）
  uci add firewall redirect
  uci set firewall.@redirect[-1].name='Force-NTP-to-Router'
  uci set firewall.@redirect[-1].src='lan'
  uci set firewall.@redirect[-1].src_dport='123'
  uci set firewall.@redirect[-1].proto='udp'
  uci set firewall.@redirect[-1].target='DNAT'
  uci set firewall.@redirect[-1].dest_ip='192.168.1.1'
  uci set firewall.@redirect[-1].dest_port='123'
  uci set firewall.@redirect[-1].family='ipv4'
  uci commit firewall
  /etc/init.d/firewall restart
  
  # dns劫持，降低被检测出异常dns流量特征的概率
   # 把 https-dns-proxy 的 force_dns 关掉
  uci set https-dns-proxy.config.force_dns='0' 
  uci commit https-dns-proxy
  /etc/init.d/https-dns-proxy restart
  echo "=== 2. 清理旧的 DoH 实例并批量添加 6 个全新的加密 DNS ==="
  uci show https-dns-proxy | grep "@https-dns-proxy\[" | cut -d. -f2 | cut -d= -f1 | while read cfg; do
      uci delete https-dns-proxy.$cfg 2>/dev/null
  done
  # 1. 阿里 DoH (国内主力)
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://dns.alidns.com/dns-query'
  uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='223.5.5.5,223.6.6.6'
  uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5053'
  # 2. 腾讯 DoH (国内主力)
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://doh.pub/dns-query'
  uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='119.29.29.29,119.28.28.28'
  uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5054'
  # 3. 360 安全 DoH (国内拦截恶意网站)
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://doh.360.cn/dns-query'
  uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='101.226.4.6,218.30.118.6'
  uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5055'
  # 4. 腾讯国密 DoH (极安全)
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://sm2.doh.pub/dns-query'
  uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='119.29.29.29,119.28.28.28'
  uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5056'
  # 5. Quad9 (国际防污染)
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://dns.quad9.net/dns-query'
  uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='9.9.9.9,149.112.112.112'
  uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5057'
  # 6. Cloudflare (国际隐私极速)
  uci add https-dns-proxy https-dns-proxy
  uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://cloudflare-dns.com/dns-query'
  uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='1.1.1.1,1.0.0.1'
  uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5058'
  uci commit https-dns-proxy
  
  cp /etc/hosts /etc/hosts.bak
  # 2. 将 6 个 DoH 服务器的域名和对应的 IP 写入 hosts
  cat << 'EOF' >> /etc/hosts
  127.0.0.1 localhost
  
  ::1     localhost ip6-localhost ip6-loopback
  ff02::1 ip6-allnodes
  ff02::2 ip6-allrouters
  
  # --- DoH Bootstrap Overrides ---
  223.5.5.5 dns.alidns.com
  119.29.29.29 doh.pub
  119.29.29.29 sm2.doh.pub
  101.226.4.6 doh.360.cn
  9.9.9.9 dns.quad9.net
  1.1.1.1 cloudflare-dns.com
  EOF
  
  # 3. 重启 dnsmasq 和 https-dns-proxy
  /etc/init.d/dnsmasq restart
  /etc/init.d/https-dns-proxy restart
  
  echo "=== 3. 固定 dnsmasq 上游至这 6 个加密端口 ==="
  uci -q delete dhcp.@dnsmasq[0].server
  uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5053'
  uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5054'
  uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5055'
  uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5056'
  uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5057'
  uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5058'
  uci set dhcp.@dnsmasq[0].noresolv='1'
  uci commit dhcp
  /etc/init.d/dnsmasq restart 
  
  
  #全局53端口劫持
  echo "=== 写入自定义 nftables 防火墙重定向规则 ==="
  # 创建自定义规则目录（如果不存在）
  mkdir -p /usr/share/nftables.d/chain-pre/dstnat/
  # 写入规则：排除 lo 回环接口，强制拦截 br-lan 进入的 53 端口明文请求
  cat << 'EOF' > /usr/share/nftables.d/chain-pre/dstnat/00-force-dns.nft
  iifname != "lo" iifname "br-lan" udp dport 53 counter redirect to :53
  iifname != "lo" iifname "br-lan" tcp dport 53 counter redirect to :53
  EOF
  echo "=== 强行关闭 Flow Offloading（必须，否则规则被绕过） ==="
  uci set firewall.@defaults[0].flow_offloading='0'
  uci set firewall.@defaults[0].flow_offloading_hw='0'
  uci commit firewall
  echo "=== 重启服务并加载防火墙规则 ==="
  /etc/init.d/dnsmasq restart
  fw4 reload
  echo "=== 配置完成 ==="
  echo "请执行以下命令检查规则是否生效："
  echo "nft list chain inet fw4 dstnat_lan | grep -A 3 '53'"
  
  # 修改主机名
  uci set system.@system[0].hostname='MasterChen'
  uci commit system
  /etc/init.d/system reload
  uci set network.wan.hostname='MasterChen'
  uci commit network
  uci set samba4.@samba[0].NAME='MasterChen'
  uci set samba4.@samba[0].DESCRIPTION='Windows File Sharing'
  uci set samba4.@samba[0].WORKGROUP='WORKGROUP'
  uci commit samba4
  /etc/init.d/samba4 restart 2>/dev/null || service samba4 restart 2>/dev/null
  
  # 修改MAC,网络服务重启在最后，避免ssh断连
  uci set network.wan.macaddr='A0:36:BC:1F:4A:8B'
  uci commit network
  uci set wireless.radio1.macaddr='A0:36:BC:8F:2D:4C'
  uci set wireless.radio0.macaddr='D8:5D:4C:7A:3E:91'
  uci commit wireless
  wifi reload
  mkdir -p /usr/share/nftables.d/chain-pre/forward/
  # 保护内网设备的信息与安全
  cat << 'EOF' > /usr/share/nftables.d/chain-pre/forward/99-block-leak.nft
  # 内网互通优先放行（Samba、文件共享、发现协议在 LAN 内正常走）
  iifname "br-lan" oifname "br-lan" accept
  # 允许路由器本机向 LAN 发送的组播通知（SSDP/NetBIOS）通过
  ip saddr 192.168.1.1 oifname "br-lan" accept
  # 封杀试图离开 LAN 的 IPv4 组播（SSDP/LLMNR 等发现协议不会泄露到 WAN）
  iifname "br-lan" oifname != "br-lan" ip daddr 224.0.0.0/4 drop
  # 封杀试图离开 LAN 的 IPv4 广播（255.255.255.255 和子网广播）
  iifname "br-lan" oifname != "br-lan" ip daddr 255.255.255.255 drop
  iifname "br-lan" oifname != "br-lan" ip daddr 192.168.1.255 drop
  # 封杀试图离开 LAN 的 IPv6 链路本地组播
  iifname "br-lan" oifname != "br-lan" ip6 daddr ff02::/16 drop
  # 封杀 NetBIOS/UPnP 泄漏到 LAN 以外（但 LAN 内已由第一条 accept 放行）
  iifname "br-lan" oifname != "br-lan" udp dport { 137, 138 } drop
  iifname "br-lan" oifname != "br-lan" tcp dport 139 drop
  iifname "br-lan" oifname != "br-lan" udp dport 1900 drop
  iifname "br-lan" oifname != "br-lan" tcp dport 2869 drop
  # 入站方向：从非 LAN 进入 LAN 的 IPv4 组播
  iifname != "br-lan" oifname "br-lan" ip daddr 224.0.0.0/4 drop
  # 入站方向：从非 LAN 进入 LAN 的 IPv4 广播
  iifname != "br-lan" oifname "br-lan" ip daddr 255.255.255.255 drop
  # 入站方向：从非 LAN 进入 LAN 的 IPv6 链路本地组播
  iifname != "br-lan" oifname "br-lan" ip6 daddr ff02::/16 drop
  EOF
  echo "=== 放行 Samba 入站（路由器对外提供 Samba 服务） ==="
  # 允许 LAN 侧访问路由器的 Samba（137-139, 445）
  uci -q delete firewall.samba_lan
  uci set firewall.samba_lan="rule"
  uci set firewall.samba_lan.name="Allow-Samba-LAN"
  uci set firewall.samba_lan.src="lan"
  uci set firewall.samba_lan.proto="tcp udp"
  uci set firewall.samba_lan.dest_port="137-139 445"
  uci set firewall.samba_lan.target="ACCEPT"
  uci commit firewall
  echo "=== 重载防火墙 ==="
  fw4 reload
  
  #修改软件源确保能够正常加包
  cp /etc/apk/repositories.d/distfeeds.list /etc/apk/repositories.d/distfeeds.list.bak
  # 统一替换为中科大源
  sed -i 's|downloads.openwrt.org|mirrors.ustc.edu.cn/openwrt|g' /etc/apk/repositories.d/distfeeds.list
  # 查看修改后的源列表，确认替换正确
  cat /etc/apk/repositories.d/distfeeds.list
  # 刷新软件源索引
  apk update
  
  echo "务必要前往管理界面的 系统>系统>通用设置 同步时间！！！"
  /etc/init.d/network restart
  ```

---

# 四、抗校园网检测维度分析

本表按**严格校园网检测机制**逐维度列出：项目做了什么、没做什么（含修补难度）、该维度在校园网检测中的权重、涉及主动数据包探测时的隐私合规性、以及最终露馅风险。权重与风险为经验性评估，不同学校检测强度差异较大。

| 检测维度                    | 项目做法（或缺失 + 难度）                                                                                                                          | 校园网检测权重                                 | 主动探测维度隐私合规性                                                                                                                         | 露馅风险                                                     |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| TTL / Hop Limit             | ✅ 已做：nftables 强制 IPv4 TTL=128，IPv6 排除 NDP 后 hoplimit=128                                                                                  | 高（锐捷等明确检测）                           | 被动字段，不涉及主动探测，合规                                                                                                                 | 低（已覆盖）                                                 |
| IPID                        | ✅ 已做：`rkp-ipid` 内核模块 + nftables 打标，伪装递增，排除内网与 DHCP                                                                             | 高（防共享核心判据之一）                       | 被动字段，合规                                                                                                                                 | 低（已覆盖）                                                 |
| UA（明文 HTTP）             | ✅ 已做：UA3F + UA-Mask 统一为 Chrome                                                                                                               | 中低（HTTPS 下失效，检测方仅在明文 HTTP 有效） | 被动字段，合规                                                                                                                                 | 中（HTTPS 流量无法改 UA）                                    |
| NTP 外联                    | ✅ 已做：LAN 侧 UDP/123 DNAT 到路由器，统一时间源                                                                                                   | 中（多设备各自外联 NTP 是共享信号）            | 被动重定向，合规                                                                                                                               | 低（已覆盖）                                                 |
| DNS 明文泄露                | ✅ 已做：全局 53 劫持 + 6 路 DoH 加密上游 + hosts Bootstrap 覆盖                                                                                    | 中高（明文 DNS 特征明显）                      | 被动加密，合规                                                                                                                                 | 低到中（6 个 DoH 会话本身可能异常，见下）                    |
| 二层 STP/BPDU               | ✅ 已做：ebtables 丢弃 `01:80:c2:00:00:00` 在 eth1 / phy1-sta0 双向 FORWARD                                                                         | 中（交换机侧可识别路由器）                     | 被动二层过滤，合规                                                                                                                             | 低（已覆盖）                                                 |
| 出站组播/广播/NetBIOS/UPnP  | ✅ 已做：nftables forward 封杀离开 LAN 的组播/广播/137-139/1900/2869                                                                                | 中（SSDP/LLMNR 泄露设备发现）                  | 被动过滤，合规                                                                                                                                 | 低（已覆盖）                                                 |
| 入站组播/广播               | ✅ 已修补：nftables 反向 drop（`iifname != "br-lan" oifname "br-lan"`）                                                                             | 中低（主动探测手段之一）                       | **主动探测相关**：拦截入站探测包属于被动防御，不主动回包，合规                                                                                 | 低到中（修补后降低）                                         |
| Flow Offloading             | ✅ 已做：强制关闭，避免规则被加速绕过                                                                                                               | —（前置条件）                                  | 不涉及                                                                                                                                         | 低                                                           |
| 主机名 / 设备名             | ✅ 已做：hostname / WAN hostname / Samba NAME 统一伪装                                                                                              | 低（辅助指纹）                                 | 被动字段，合规                                                                                                                                 | 低                                                           |
| MAC 地址                    | ✅ 已做：WAN + 无线 radio0/1 指定 MAC                                                                                                               | 低到中（MAC 厂商前缀可聚类）                   | 被动字段，合规                                                                                                                                 | 低                                                           |
| SQM 智能队列                | ✅ 已做：降低高占用/高延迟触发风控                                                                                                                  | 低到中（大流量/bufferbloat 触发风控）          | 不涉及                                                                                                                                         | 低                                                           |
| **TCP Window Size / Scale** | ❌ 未做。难度：**高**（需 eBPF 改写或用户态代理，性能代价大）                                                                                       | **高**（Windows/iOS/Android 强区分特征）       | 被动字段，合规                                                                                                                                 | **高**（多 OS 混合时 WS 跳变直接暴露）                       |
| **TCP Timestamp**           | ❌ 未做。难度：**中高**（可关闭但有性能代价，统一频率需内核干预）                                                                                   | 高（OS 识别 + 时钟频率估算）                   | 被动字段，合规                                                                                                                                 | **高**（不同设备 TS 行为差异持续泄露）                       |
| **TCP 源端口序列**          | ❌ 未做。难度：**中**（需改 NAT 端口分配策略，可能影响应用）                                                                                        | **高**（锐捷明确检测多组递增序列）             | 被动字段，合规                                                                                                                                 | **高**（NAT 后仍可能呈可聚类模式）                           |
| **TOS / DSCP / IP 选项**    | ❌ 未做。难度：**低**（nftables 可改，但收益有限）                                                                                                  | 低（辅助指纹）                                 | 被动字段，合规                                                                                                                                 | 中低                                                         |
| **DHCP 客户端指纹**         | ❌ 已放弃。难度：**中高且已验证失败**（udhcpc 框架下 Bootp flags / Option 57 / Option 55 改不动；OpenWrt 25.12 的 Option 61 回归可能导致拿不到 IP） | 中（DHCP 请求特征可识别路由器）                | 主动 DHCP 交互，合规（用户主动请求地址）                                                                                                       | 中（拿不到 IP 的风险高于露馅风险）                           |
| **并发连接数 / 新建速率**   | ❌ 未做。难度：**高**（需连接数整形，影响正常使用）                                                                                                 | 高（推断背后设备数量）                         | 被动统计，合规                                                                                                                                 | **高**（多设备并发峰值单设备不可能达到）                     |
| **独立 TLS 会话数**         | ❌ 未做。难度：**高**（路由器无法合并终端 TLS 会话）                                                                                                | 高（每台设备维持独立长连接）                   | 被动统计，合规                                                                                                                                 | **高**（会话数直接反映设备数）                               |
| **应用层心跳聚类**          | ❌ 不可行。路由器无法干预终端应用层行为                                                                                                             | 高（微信/QQ 心跳周期可聚类）                   | 被动统计，合规                                                                                                                                 | **高**（基本无解）                                           |
| **DoH 上游会话数**          | ⚠️ 已做但可能反效果：配置 6 个 DoH 上游，出口侧可见单 IP 同时连 6 个 DoH 端点                                                                       | 低到中（单设备通常只用 1 个 DoH）              | 被动观察，合规                                                                                                                                 | 中（建议收敛到 1-2 个上游）                                  |
| **主动 TCP SYN 探测**       | ❌ 未做，且**不建议做**。难度：**极高**（需对任意探测端口返回 SYN-ACK 并模拟终端，极易被识别为异常）                                                | 高（专利 CN101800681A 明确描述）               | **主动探测**：检测方向用户 IP 发 SYN，用户侧不响应/回 RST 即被标记。模拟终端响应属于**对抗性伪装**，在多数校园网协议中构成违规规避，合规性存疑 | **极高**（RST 或超时都会被标记为疑似路由器；模拟响应更危险） |
| **时钟频率方差**            | ❌ 不可行。路由器无法控制终端 TCP timestamp 频率                                                                                                    | 中高（学术研究用于设备识别）                   | 被动统计，合规                                                                                                                                 | 高（多设备混合时方差增大）                                   |
| **Cookie / 会话关联**       | ❌ 未做。难度：**不可行**（需 DPI 能力与跨会话关联，路由器层无法干预）                                                                              | 中（依赖检测方 DPI 能力）                      | 被动分析，合规                                                                                                                                 | 中高（取决于检测方能力）                                     |
| **入站主动探测响应**        | ⚠️ 部分：已拦截入站组播/广播，但**不响应**任何主动探测                                                                                              | 中高                                           | **主动探测**：不响应属于被动防御，合规；若模拟终端响应则属对抗性伪装                                                                           | 中高（不响应会被标记，响应更危险）                           |

---

## 5.1 表格读法说明

- **✅ 已做**：项目当前已覆盖，露馅风险低。
- **⚠️ 部分/有反效果**：做了但可能引入新信号，或只覆盖了部分方向。
- **❌ 未做**：明确缺失，标注了修补难度与露馅风险。
- **难度分级**：低 = nftables/UCI 可完成；中 = 需改 NAT 策略或脚本；高 = 需 eBPF/内核态/用户态代理；极高 = 不建议尝试。
- **隐私合规性**：被动字段观察与过滤属于合规的自我防护；**主动模拟终端响应（如对 SYN 探测回 SYN-ACK）属于对抗性伪装**，在多数校园网用户协议中构成违规规避，合规性存疑。

---

## 5.2 关键结论

1. **已覆盖的维度**集中在“单包字段”层面（TTL、IPID、UA、NTP、DNS、二层 STP、组播出站/入站），这些在单规则检测下有效。

2. **未覆盖的维度**集中在“协议栈深层指纹”（TCP WS/TS/端口序列）与“行为统计”（连接数、TLS 会话数、心跳聚类），这些是多维度联合判定的核心，**修补难度高或不可行**。

3. **主动探测维度**：项目选择“不响应 + 拦截入站组播”，属于被动防御，合规且风险可控；**不建议**模拟终端响应，那会从“自我防护”变成“对抗性伪装”，合规性与安全性双输。

4. **DHCP 伪装已验证失败**，从方案中移除是正确的；OpenWrt 25.12 的 Option 61 回归意味着继续折腾 DHCP 可能连 IP 都拿不到。

5. **DoH 上游 6 个可能反效果**，建议收敛到 1-2 个，牺牲冗余换取更低的会话数异常。

6. **最根本的结构性事实**：NAT 后面有多台设备的统计画像无法通过改包头字段消除。项目在“已知单点规则”上做得还算可以，在“严格联合检测 + 主动探测”下仍有明确露馅路径。

   ## 📄 许可

   脚本与文档以 MIT 许可发布；所引用的第三方项目（OpenWrt、UA3F、UA-Mask、OpenClash、mihomo、smart-srun、argon 等）版权归各自作者所有，请遵循其许可证。
   本项目仅供学习研究，请遵守相关规定。

   ## 🙏 致谢

   - [OpenWrt](https://github.com/openwrt/openwrt)
   - [bfdeh/openwrt](https://github.com/bfdeh/openwrt)（N30Pro DTS 补丁：修复 USB 供电 + 补全 4 网口识别）
   - [SunBK201/UA3F](https://github.com/SunBK201/UA3F)
   - [Zesuy/UA-Mask](https://github.com/Zesuy/UA-Mask)
   - [vernesong/OpenClash](https://github.com/vernesong/OpenClash)
   - [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
   - [CHN-beta/rkp-ipid](https://github.com/CHN-beta/rkp-ipid)
   - [matthewlu070111/smart-srun](https://github.com/matthewlu070111/smart-srun)
   - [jerrykuku/luci-theme-argon](https://github.com/jerrykuku/luci-theme-argon)
   - [destan19/luci-app-harbor-file](https://github.com/destan19/luci-app-harbor-file)

   ---

   > 如果这个项目帮到你，欢迎 Star ⭐ 与提交 Issue / PR 改进脚本路径兼容性。
