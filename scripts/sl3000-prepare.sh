#!/bin/bash
set -e

log() { echo -e "\033[1;32m[SL3000]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1" | tee -a "$LOG"; }

# ============================
# 0. 自动定位 openwrt 源码目录
# ============================
if [ -d "openwrt" ]; then
    ROOT="$(pwd)/openwrt"
elif [ -d "../openwrt" ]; then
    ROOT="$(pwd)/../openwrt"
elif [ -n "$GITHUB_REPOSITORY" ] && [ -d "/home/runner/work/${GITHUB_REPOSITORY#*/}/${GITHUB_REPOSITORY#*/}/openwrt" ]; then
    ROOT="/home/runner/work/${GITHUB_REPOSITORY#*/}/${GITHUB_REPOSITORY#*/}/openwrt"
else
    err "未找到 openwrt 源码目录，请检查工作流 clone 目录"
    exit 1
fi

cd "$ROOT"

REPORT_DIR="$ROOT/build-report"
LOG="$REPORT_DIR/error.log"
mkdir -p "$REPORT_DIR"
rm -f "$LOG"

trap 'err "构建失败，已记录错误日志"; exit 1' ERR

log "开始 SL3000 全自动修复 + 构建流程"

# ============================
# 1. 复制三件套
# ============================
cp -vf ../config/sl3000.config "$ROOT/.config" || err "缺少 config/sl3000.config"
cp -vf ../dts/*.dts "$ROOT/target/linux/mediatek/dts/" || err "缺少 dts/*.dts"
cp -vf ../image/*.mk "$ROOT/target/linux/mediatek/image/" || err "缺少 image/*.mk"

# ============================
# 2. 注册 DTS 到 Makefile
# ============================
DTS_NAME=$(basename $(ls target/linux/mediatek/dts/mt7981*-sl3000*.dts 2>/dev/null | head -n1))
[ -z "$DTS_NAME" ] && err "未找到 SL3000 DTS 文件"

MAKEFILE="target/linux/mediatek/Makefile"
grep -q "$DTS_NAME" "$MAKEFILE" || {
    echo "dts-\$(CONFIG_TARGET_mediatek_filogic) += $DTS_NAME" >> "$MAKEFILE"
    log "已自动注册 DTS 到 mediatek/Makefile: $DTS_NAME"
}

# ============================
# 3. 校验 image.mk 定义
# ============================
MK="target/linux/mediatek/image/filogic.mk"
grep -q "Device/sl3000" "$MK" || err "filogic.mk 未包含 Device/sl3000 定义"
grep -q "TARGET_DEVICES += sl3000" "$MK" || err "filogic.mk 未添加 sl3000 到 TARGET_DEVICES"

# ============================
# 4. feeds 修复 + 冲突包清理
# ============================
./scripts/feeds update -a || true
./scripts/feeds install -a || true

for p in uw-imap python3-pysocks python3-unidecode; do
    sed -i "/$p/d" .config || true
done
sed -i '/CONFIG_PACKAGE_backuppc/d' .config || true

make defconfig || true

# ============================
# 5. gpio-button-hotplug 补丁（兼容性检测）
# ============================
PATCH_SRC="../patches/gpio-button-hotplug"
PATCH_FILE="$PATCH_SRC/001-fix-broadcast_uevent.patch"
PKG_DIR="package/kernel/gpio-button-hotplug"
PATCH_DST="$PKG_DIR/patches"

if [ -d "$PKG_DIR" ] && [ -f "$PATCH_FILE" ]; then
    log "检测 gpio-button-hotplug 补丁兼容性..."
    make package/kernel/gpio-button-hotplug/{clean,prepare} V=s || true
    SRC_DIR=$(find build_dir/target-*/linux-*/gpio-button-hotplug -maxdepth 0 2>/dev/null | head -n1)

    if [ -d "$SRC_DIR" ]; then
        if patch --dry-run -p1 -d "$SRC_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
            log "补丁匹配成功，已启用"
            mkdir -p "$PATCH_DST"
            cp "$PATCH_FILE" "$PATCH_DST/"
        else
            log "补丁不兼容，已跳过"
        fi
    else
        log "未找到 gpio-button-hotplug 源码目录，跳过补丁"
    fi
else
    log "未找到 gpio-button-hotplug 补丁或包，跳过"
fi

# ============================
# 6. 科学上网支持（Passwall2）
# ============================
log "检查科学上网支持..."
grep -q "CONFIG_PACKAGE_luci-app-passwall2=y" .config || {
    cat >> .config <<EOF

# === Passwall2 ===
CONFIG_PACKAGE_luci-app-passwall2=y
CONFIG_PACKAGE_passwall2=y
CONFIG_PACKAGE_passwall2-proxy=y
CONFIG_PACKAGE_passwall2-core=y
CONFIG_PACKAGE_xray-core=y
CONFIG_PACKAGE_v2ray-core=y
CONFIG_PACKAGE_sing-box=y
CONFIG_PACKAGE_trojan=y
CONFIG_PACKAGE_trojan-plus=y
CONFIG_PACKAGE_trojan-go=y
CONFIG_PACKAGE_chinadns-ng=y
CONFIG_PACKAGE_dns2socks=y
CONFIG_PACKAGE_dns2tcp=y
CONFIG_PACKAGE_pdnsd-alt=y
CONFIG_PACKAGE_ipt2socks=y
CONFIG_PACKAGE_libopenssl=y
CONFIG_PACKAGE_libustream-openssl=y
EOF
    log "已注入 Passwall2 配置"
}

# ============================
# 7. 构建固件
# ============================
log "开始构建固件..."
make defconfig
if ! make -j"$(nproc)"; then
    log "并行构建失败，尝试单线程详细模式..."
    make -j1 V=s 2>&1 | tee -a "$LOG" || { err "构建失败，请查看 $LOG"; exit 1; }
fi

log "构建成功 ✅"
find bin/targets/ -type f -name "*.bin" -exec echo "生成固件: {}" \;
exit 0
