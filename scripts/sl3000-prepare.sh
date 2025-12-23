#!/bin/bash
set -e

# ============================
# 基础路径与日志
# ============================
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
# 1. 复制三件套（按你仓库路径）
# ============================
log "复制 SL3000 三件套..."

# 1.1 config
if [ -f "config/sl3000.config" ]; then
    cp -f "config/sl3000.config" "$ROOT/.config"
    log "已复制 config/sl3000.config -> openwrt/.config"
else
    err "缺少 config/sl3000.config"
fi

# 1.2 DTS
if ls dts/*.dts >/dev/null 2>&1; then
    cp -f dts/*.dts "$ROOT/target/linux/mediatek/dts/"
    log "已复制 dts/*.dts -> target/linux/mediatek/dts/"
else
    err "缺少 dts/*.dts"
fi

# 1.3 image.mk
if ls image/*.mk >/dev/null 2>&1; then
    cp -f image/*.mk "$ROOT/target/linux/mediatek/image/"
    log "已复制 image/*.mk -> target/linux/mediatek/image/"
else
    err "缺少 image/*.mk"
fi

# ============================
# 2. DTS 自动修复
# ============================
DTS="$ROOT/target/linux/mediatek/dts/mt7981b-sl3000-emmc.dts"
if [ -f "$DTS" ]; then
    log "检查 DTS: $(basename "$DTS")"
    # 常见 SoC 兼容字段修正
    sed -i 's/mediatek,mt7981/mediatek,mt7981b/g' "$DTS" || true
else
    err "DTS 不存在: $DTS"
fi

# ============================
# 3. image.mk 自动修复/检查
# ============================
MK="$ROOT/target/linux/mediatek/image/filogic.mk"
if [ -f "$MK" ]; then
    log "检查 image.mk: filogic.mk 中的 sl3000 定义"
    if ! grep -q "sl3000" "$MK"; then
        err "image.mk 未包含 sl3000 定义，请检查 filogic.mk 内机型段"
    fi
else
    err "image.mk 不存在: $MK"
fi

# ============================
# 4. kernel include 兼容修复
# ============================
INC="$ROOT/include/kernel-defaults.mk"
if [ -f "$INC" ]; then
    log "检查 kernel-defaults.mk..."
    # 某些版本中 CONFIG_KERNEL_ 前缀变动时的兼容处理
    sed -i 's/CONFIG_KERNEL_/CONFIG_/g' "$INC" || true
fi

# ============================
# 5. feeds & package 依赖修复
# ============================
log "开始 feeds & package 自动修复..."
cd "$ROOT"

# 5.1 feeds update/install 容错
for i in 1 2; do
    log "feeds update -a (第 $i 次尝试)..."
    ./scripts/feeds update -a && break || sleep 5
done || log "feeds update 可能部分失败，继续尝试后续步骤"

for i in 1 2; do
    log "feeds install -a (第 $i 次尝试)..."
    ./scripts/feeds install -a && break || sleep 5
done || log "feeds install 可能部分失败，继续尝试后续步骤"

# 5.2 触发 defconfig，让缺失包尽可能自动对齐
log "执行 make defconfig 进行配置自愈..."
make defconfig || true

# 5.3 常见插件自动安装（如有）
log "尝试自动安装常见插件（如存在于 feeds 中）..."
COMMON_PKGS=(
    "luci"
    "luci-compat"
    "luci-app-passwall2"
    "luci-app-dockerman"
    "docker"
)
for p in "${COMMON_PKGS[@]}"; do
    if ! grep -q "$p" .config 2>/dev/null; then
        continue
    fi
    log "检测到配置中包含 $p，尝试自动安装..."
    ./scripts/feeds install "$p" || log "安装 $p 失败，略过"
done

# ============================
# 6. 常见路径 / 目标自愈
# ============================
log "检查常见路径与目标目录..."
mkdir -p "$ROOT/bin/targets"
mkdir -p "$ROOT/build_dir"
mkdir -p "$ROOT/tmp"

# ============================
# 7. 上游 DTS/image 变更提示（只提示，不乱改）
# ============================
log "检查 DTS/image 是否有上游改动痕迹（提示级）..."

UP_DTS_REF="$ROOT/target/linux/mediatek/dts/mt7981b-rfb.dts"
if [ -f "$UP_DTS_REF" ]; then
    if ! diff -q "$UP_DTS_REF" "$DTS" >/dev/null 2>&1; then
        log "提示：sl3000 DTS 与上游参考 DTS 有差异，建议手动 review 一次。"
    fi
fi

UP_MK_REF="$ROOT/target/linux/mediatek/image/filogic.mk"
if [ -f "$UP_MK_REF" ]; then
    if ! grep -q "sl3000" "$UP_MK_REF"; then
        log "提示：上游 filogic.mk 可能更新，sl3000 段落请保持关注。"
    fi
fi

# ============================
# 8. 最终构建
# ============================
log "开始最终构建固件..."
cd "$ROOT"

# 再跑一次 defconfig，保证前面变更已收敛
make defconfig

# 真正构建
if ! make -j"$(nproc)"; then
    err "构建失败，具体请查看 $LOG 与 build_dir 内日志"
    exit 1
fi

log "构建成功，固件已生成在 openwrt/bin/targets 下"
exit 0
