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
# 2. 注册 DTS 到 Makefile（增强版）
# ============================
DTS_FILE=$(find target/linux/mediatek/dts -maxdepth 1 -name "mt7981*-sl3000*.dts" | sort | head -n1)
[ -z "$DTS_FILE" ] && err "未找到 SL3000 DTS 文件"

DTS_NAME=$(basename "$DTS_FILE")
MAKEFILE="target/linux/mediatek/Makefile"

grep -q "$DTS_NAME" "$MAKEFILE" || {
    echo "dts-\$(CONFIG_TARGET_mediatek_filogic) += $DTS_NAME" >> "$MAKEFILE"
    log "已自动注册 DTS: $DTS_NAME"
}

# ============================
# 3. 校验 image.mk 定义 + include 修复
# ============================
MK="target/linux/mediatek/image/filogic.mk"
grep -q "Device/sl3000" "$MK" || err "filogic.mk 未包含 Device/sl3000 定义"
grep -q "TARGET_DEVICES += sl3000" "$MK" || err "filogic.mk 未添加 sl3000 到 TARGET_DEVICES"

IMG_MAKE="target/linux/mediatek/image/Makefile"
grep -q "filogic.mk" "$IMG_MAKE" || echo "include ./filogic.mk" >> "$IMG_MAKE"

# ============================
# 4. feeds 修复 + 冲突包清理（增强版）
# ============================
./scripts/feeds update -a || err "feeds update 失败"
./scripts/feeds install -a || err "feeds install 失败"

for p in uw-imap python3-pysocks python3-unidecode python3-charset-normalizer python3-certifi python3-idna; do
    sed -i "/$p/d" .config || true
done

sed -i '/CONFIG_PACKAGE_backuppc/d' .config || true

# ============================
# 5. TARGET 三件套补全（必须修复）
# ============================
grep -q "CONFIG_TARGET_mediatek=y" .config || echo "CONFIG_TARGET_mediatek=y" >> .config
grep -q "CONFIG_TARGET_mediatek_filogic=y" .config || echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" .config || echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" >> .config

make defconfig

# ============================
# 6. gpio-button-hotplug 补丁（增强版）
# ============================
PATCH_SRC="../patches/gpio-button-hotplug"
PATCH_FILE="$PATCH_SRC/001-fix-broadcast_uevent.patch"
PKG_DIR="package/kernel/gpio-button-hotplug"
PATCH_DST="$PKG_DIR/patches"

if [ -d "$PKG_DIR" ] && [ -f "$PATCH_FILE" ]; then
    log "检测 gpio-button-hotplug 补丁兼容性..."
    make package/kernel/gpio-button-hotplug/{clean,prepare} V=s || true

    SRC_DIR=$(find build_dir -type d -path "*gpio-button-hotplug*" | head -n1)

    if [ -d "$SRC_DIR" ]; then
        if patch --dry-run -p1 -d "$SRC_DIR" < "$PATCH_FILE" >/dev/null 2>&1; then
            mkdir -p "$PATCH_DST"
            cp "$PATCH_FILE" "$PATCH_DST/"
            log "补丁已启用"
        else
            log "补丁不兼容，跳过"
        fi
    else
        log "未找到 gpio-button-hotplug 源码目录，跳过补丁"
    fi
else
    log "未找到补丁，跳过"
fi

# ============================
# 7. 移除科学上网（彻底）
# ============================
log "移除科学上网相关配置"
sed -i '/passwall2/d;/xray-core/d;/v2ray-core/d;/sing-box/d;/trojan/d;/chinadns-ng/d;/dns2socks/d;/dns2tcp/d;/pdnsd-alt/d;/ipt2socks/d' .config || true

make defconfig

# ============================
# 8. 构建固件（增强版）
# ============================
log "开始构建固件..."

log "先构建内核（syncconfig 错误可见）"
make target/linux/compile -j1 V=sc || {
    log "内核阶段失败，重试一次"
    make target/linux/compile -j1 V=sc
}

log "构建 world..."
if ! make -j"$(nproc)"; then
    log "并行构建失败，尝试单线程详细模式..."
    make -j1 V=s 2>&1 | tee -a "$LOG" || { err "构建失败，请查看 $LOG"; exit 1; }
fi

log "构建成功 ✅"
find bin/targets/ -type f -name "*.bin" -exec echo "生成固件: {}" \;

exit 0
