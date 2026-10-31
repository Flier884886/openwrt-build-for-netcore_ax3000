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
  # 保护内网设备的信息与安全（拦截离开指定接口集合的组播广播）
mkdir -p /usr/share/nftables.d/table-pre/ /usr/share/nftables.d/chain-pre/forward/
cat << 'EOF' > /usr/share/nftables.d/table-pre/00-lan-ifs-set.nft
set lan_ifs {
    type ifname
    flags constant
    elements = { "br-lan", "VPN", "wireguard-VPN" }
}
EOF
cat << 'EOF' > /usr/share/nftables.d/chain-pre/forward/99-block-leak.nft
iifname @lan_ifs oifname @lan_ifs accept
ip saddr 192.168.1.1 oifname @lan_ifs accept
iifname @lan_ifs oifname != @lan_ifs ip daddr 224.0.0.0/4 drop
iifname @lan_ifs oifname != @lan_ifs ip daddr 255.255.255.255 drop
iifname @lan_ifs oifname != @lan_ifs ip daddr 192.168.1.255 drop
iifname @lan_ifs oifname != @lan_ifs ip6 daddr ff00::/8 drop
iifname @lan_ifs oifname != @lan_ifs udp dport { 137, 138 } drop
iifname @lan_ifs oifname != @lan_ifs tcp dport 139 drop
iifname @lan_ifs oifname != @lan_ifs udp dport 1900 drop
iifname @lan_ifs oifname != @lan_ifs tcp dport 2869 drop
iifname != @lan_ifs oifname @lan_ifs ip daddr 224.0.0.0/4 drop
iifname != @lan_ifs oifname @lan_ifs ip daddr 255.255.255.255 drop
iifname != @lan_ifs oifname @lan_ifs ip6 daddr ff00::/8 drop
iifname != @lan_ifs oifname @lan_ifs udp dport { 137, 138 } drop
iifname != @lan_ifs oifname @lan_ifs tcp dport 139 drop
iifname != @lan_ifs oifname @lan_ifs udp dport 1900 drop
iifname != @lan_ifs oifname @lan_ifs tcp dport 2869 drop
EOF
fw4 reload
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
