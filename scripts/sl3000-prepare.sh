#!/bin/bash
set -e

ROOT="$(pwd)/openwrt"
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

log "开始 SL3000 全自动修复 + 构建流程"

# ============================
# 0. 基础目录自愈
# ============================
log "检查基础目录..."
mkdir -p "$ROOT"
mkdir -p "$ROOT/staging_dir"
mkdir -p "$ROOT/toolchain"
mkdir -p "$ROOT/bin"
mkdir -p "$ROOT/target/linux/mediatek/dts"
mkdir -p "$ROOT/target/linux/mediatek/image"

# ============================
# 1. 复制三件套
# ============================
log "复制 SL3000 三件套..."

cp -f config/sl3000.config "$ROOT/.config" || err "缺少 config/sl3000.config"
cp -f dts/*.dts "$ROOT/target/linux/mediatek/dts/" || err "缺少 dts/*.dts"
cp -f image/*.mk "$ROOT/target/linux/mediatek/image/" || err "缺少 image/*.mk"

# ============================
# 2. 自动识别 DTS 文件
# ============================
log "自动识别 DTS 文件..."

DTS_FILE=$(ls "$ROOT/target/linux/mediatek/dts/" | grep -E "sl3000|s13000|7981" | head -n 1)

if [ -z "$DTS_FILE" ]; then
    err "未找到 SL3000 DTS 文件，请检查 dts 目录"
else
    DTS="$ROOT/target/linux/mediatek/dts/$DTS_FILE"
    log "检测到 DTS 文件: $DTS_FILE"
    sed -i 's/mediatek,mt7981/mediatek,mt7981b/g' "$DTS" || true
fi

# ============================
# 3. image.mk 自动修复
# ============================
MK="$ROOT/target/linux/mediatek/image/filogic.mk"
if [ -f "$MK" ]; then
    log "检查 image.mk..."
    grep -q "sl3000" "$MK" || err "image.mk 未包含 sl3000 定义"
else
    err "image.mk 不存在: $MK"
fi

# ============================
# 4. kernel include 修复
# ============================
INC="$ROOT/include/kernel-defaults.mk"
if [ -f "$INC" ]; then
    log "修复 kernel-defaults.mk..."
    sed -i 's/CONFIG_KERNEL_/CONFIG_/g' "$INC" || true
fi

# ============================
# 5. feeds & package 自动修复
# ============================
log "开始 feeds & package 自动修复..."
cd "$ROOT"

# feeds update/install 容错
for i in 1 2; do
    ./scripts/feeds update -a && break || sleep 3
done

for i in 1 2; do
    ./scripts/feeds install -a && break || sleep 3
done

# 自动禁用不存在依赖的包
log "清理不存在依赖的包..."
BAD_PKGS=(
    "uw-imap"
    "python3-pysocks"
    "python3-unidecode"
)
for p in "${BAD_PKGS[@]}"; do
    sed -i "/$p/d" .config || true
done

# 自动禁用循环依赖包 backuppc
sed -i '/CONFIG_PACKAGE_backuppc/d' .config || true

# 触发 defconfig
log "执行 make defconfig..."
make defconfig || true

# ============================
# 6. 常见插件自动安装
# ============================
log "自动安装常见插件..."

COMMON_PKGS=(
    "luci"
    "luci-compat"
    "luci-app-dockerman"
    "docker"
)
for p in "${COMMON_PKGS[@]}"; do
    if grep -q "$p" .config; then
        log "尝试安装 $p..."
        ./scripts/feeds install "$p" || true
    fi
done

# ============================
# 7. 上游变更提示
# ============================
log "检查 DTS/image 上游变更（提示级）..."

UP_DTS_REF="$ROOT/target/linux/mediatek/dts/mt7981b-rfb.dts"
if [ -f "$UP_DTS_REF" ]; then
    if ! diff -q "$UP_DTS_REF" "$DTS" >/dev/null 2>&1; then
        log "提示：上游 DTS 有更新，建议 review"
    fi
fi

# ============================
# 8. 最终构建
# ============================
log "开始最终构建固件..."
cd "$ROOT"

make defconfig
make -j"$(nproc)" || {
    err "构建失败，请查看 $LOG"
    exit 1
}

log "构建成功，固件已生成"
exit 0
