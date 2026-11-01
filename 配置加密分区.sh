#!/bin/sh
# deploy-luks-usb.sh
# LUKS 加密 U 盘自动化部署脚本（OpenWrt，兼容 opkg / apk）
# 除 LUKS 主密码输入外，其余步骤自动完成

set -e

# ============ 可配置参数 ============
DEV="/dev/sda1"
MAPPER="usbdata"
MOUNT_POINT="/mnt/usb/usbdata1"
KEYFILE="/etc/luks-keyfile"
FSTAB="/etc/fstab"
CRYPTTAB="/etc/crypttab"
RCLOCAL="/etc/rc.local"
# ====================================

log() { echo "[*] $*"; }
err() { echo "[!] $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || err "请以 root 运行"
[ -b "$DEV" ] || err "设备 $DEV 不存在"

# ---------- 1. 安装工具 ----------
log "检测包管理器并安装必要工具..."
if command -v apk >/dev/null 2>&1; then
    log "使用 apk"
    apk update
    apk add cryptsetup block-mount kmod-fs-ext4 e2fsprogs lsblk blkid
elif command -v opkg >/dev/null 2>&1; then
    log "使用 opkg"
    opkg update
    opkg install cryptsetup block-mount kmod-fs-ext4 e2fsprogs lsblk blkid
else
    err "未找到 opkg 或 apk，请手动安装 cryptsetup 等工具"
fi

# ---------- 2. 卸载设备 ----------
if mount | grep -q "$DEV"; then
    log "卸载 $DEV ..."
    umount "$DEV" || err "卸载失败，请手动检查"
fi

# ---------- 3. LUKS 加密（需手动输入密码） ----------
if cryptsetup isLuks "$DEV" 2>/dev/null; then
    log "$DEV 已是 LUKS 设备，跳过 luksFormat"
else
    log "即将对 $DEV 执行 LUKS 格式化，请按提示输入 YES 并设置主密码"
    cryptsetup luksFormat "$DEV"
fi

# ---------- 4. 打开加密卷并格式化 ext4 ----------
if [ ! -e "/dev/mapper/$MAPPER" ]; then
    log "打开加密卷 $MAPPER（需要输入主密码）"
    cryptsetup open "$DEV" "$MAPPER"
fi

if ! blkid "/dev/mapper/$MAPPER" | grep -q 'TYPE="ext4"'; then
    log "在 /dev/mapper/$MAPPER 上创建 ext4 文件系统..."
    mkfs.ext4 "/dev/mapper/$MAPPER"
else
    log "/dev/mapper/$MAPPER 已有 ext4 文件系统，跳过 mkfs"
fi

# ---------- 5. 创建密钥文件并加入 LUKS ----------
if [ ! -f "$KEYFILE" ]; then
    log "生成密钥文件 $KEYFILE ..."
    dd if=/dev/urandom of="$KEYFILE" bs=1024 count=4
    chmod 400 "$KEYFILE"
else
    log "密钥文件 $KEYFILE 已存在，跳过生成"
fi

if cryptsetup open --test-passphrase --key-file "$KEYFILE" "$DEV" 2>/dev/null; then
    log "密钥文件已在 LUKS 密钥槽中，跳过 luksAddKey"
else
    log "将密钥文件加入 LUKS（需要输入主密码授权）"
    cryptsetup luksAddKey "$DEV" "$KEYFILE"
fi

# ---------- 6. 获取 UUID ----------
UUID=$(blkid -s UUID -o value "$DEV")
[ -n "$UUID" ] || err "无法获取 $DEV 的 UUID"
log "设备 UUID: $UUID"

# ---------- 7. 写入 /etc/crypttab ----------
log "写入 $CRYPTTAB ..."
cat > "$CRYPTTAB" <<EOF
$MAPPER UUID=$UUID $KEYFILE luks
EOF

# ---------- 8. 写入 /etc/fstab ----------
log "创建挂载点 $MOUNT_POINT ..."
mkdir -p "$MOUNT_POINT"

if grep -q "/dev/mapper/$MAPPER" "$FSTAB" 2>/dev/null; then
    log "$FSTAB 中已存在 $MAPPER 条目，跳过"
else
    log "追加 fstab 条目..."
    cat >> "$FSTAB" <<EOF
/dev/mapper/$MAPPER $MOUNT_POINT ext4 defaults,nofail,acl 0 2
EOF
fi

# ---------- 9. 写入 /etc/rc.local ----------
log "写入 $RCLOCAL ..."
cat > "$RCLOCAL" <<EOF
# 开机自动解密并挂载 $MAPPER
if [ ! -e /dev/mapper/$MAPPER ]; then
    cryptsetup open --key-file $KEYFILE $DEV $MAPPER
fi
if [ -e /dev/mapper/$MAPPER ]; then
    mount -o acl /dev/mapper/$MAPPER $MOUNT_POINT
fi
exit 0
EOF
chmod +x "$RCLOCAL"

# ---------- 10. 测试 ----------
log "关闭映射并重新执行 rc.local 测试..."
umount "$MOUNT_POINT" 2>/dev/null || true
cryptsetup close "$MAPPER" 2>/dev/null || true
"$RCLOCAL"

if mount | grep -q "$MAPPER"; then
    log "成功：$MAPPER 已挂载到 $MOUNT_POINT"
    df -h "$MOUNT_POINT"
else
    err "自动挂载测试失败，请手动检查"
fi

# ---------- 11. 提示备份 ----------
log "部署完成。请立即备份密钥和 LUKS 头部到电脑："
echo "  base64 $KEYFILE"
echo "  cryptsetup luksHeaderBackup $DEV --header-backup-file /etc/luks-header.img"
echo "  base64 /etc/luks-header.img"
