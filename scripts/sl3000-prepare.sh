#!/bin/bash
set -e

ROOT=$(pwd)/openwrt
REPORT_DIR="$ROOT/build-report"
LOG="$REPORT_DIR/error.log"

mkdir -p "$REPORT_DIR"
rm -f "$LOG"

log() {
    echo -e "[SL3000] $1"
}

err() {
    echo -e "[ERROR] $1" | tee -a "$LOG"
}

trap 'err "构建失败，已记录错误日志"; exit 1' ERR

log "开始 SL3000 自动修复流程"

# -----------------------------
# 1. 自动修复 DTS
# -----------------------------
DTS="$ROOT/target/linux/mediatek/dts/mt7981b-sl3000-emmc.dts"
if [ -f "$DTS" ]; then
    log "检查 DTS..."
    sed -i 's/mediatek,mt7981/mediatek,mt7981b/g' "$DTS"
else
    err "DTS 不存在: $DTS"
fi

# -----------------------------
# 2. 自动修复 image.mk
# -----------------------------
MK="$ROOT/target/linux/mediatek/image/filogic.mk"
if [ -f "$MK" ]; then
    log "检查 image.mk..."
    grep -q "sl3000" "$MK" || err "image.mk 未包含 SL3000 定义"
else
    err "image.mk 不存在: $MK"
fi

# -----------------------------
# 3. 自动修复 kernel include
# -----------------------------
INC="$ROOT/include/kernel-defaults.mk"
if [ -f "$INC" ]; then
    log "检查 kernel include..."
    sed -i 's/CONFIG_KERNEL_/CONFIG_/g' "$INC"
fi

# -----------------------------
# 4. 自动修复 package 依赖
# -----------------------------
log "检查 package 依赖..."
$ROOT/scripts/feeds install -a || true

# -----------------------------
# 5. 自动修复路径
# -----------------------------
log "检查路径完整性..."
[ -d "$ROOT/staging_dir" ] || mkdir -p "$ROOT/staging_dir"
[ -d "$ROOT/toolchain" ] || mkdir -p "$ROOT/toolchain"

# -----------------------------
# 6. 自动构建
# -----------------------------
log "开始构建固件..."
cd "$ROOT"
make defconfig
make -j$(nproc) || {
    err "构建失败"
    exit 1
}

log "构建成功"
exit 0
