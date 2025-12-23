#!/bin/bash
set -e

ROOT="$(pwd)/openwrt"
REPORT_DIR="$ROOT/build-report"
LOG="$REPORT_DIR/error.log"

mkdir -p "$REPORT_DIR"
rm -f "$LOG"

log() { echo -e "[SL3000] $1"; }
err() { echo -e "[ERROR] $1" | tee -a "$LOG"; }
trap 'err "构建失败，已记录错误日志"; exit 1' ERR

log "开始 SL3000 全自动修复 + 构建流程"

# ============================
# 0. 基础目录自愈
# ============================
mkdir -p "$ROOT" "$ROOT/staging_dir" "$ROOT/toolchain" "$ROOT/bin"
mkdir -p "$ROOT/target/linux/mediatek/dts" "$ROOT/target/linux/mediatek/image"

# ============================
# 1. 复制三件套
# ============================
cp -f config/sl3000.config "$ROOT/.config" || err "缺少 config/sl3000.config"
cp -f dts/*.dts "$ROOT/target/linux/mediatek/dts/" || err "缺少 dts/*.dts"
cp -f image/*.mk "$ROOT/target/linux/mediatek/image/" || err "缺少 image/*.mk"

# ============================
# 2. 自动识别 DTS
# ============================
DTS_FILE=$(ls "$ROOT/target/linux/mediatek/dts/" | grep -E "sl3000|s13000|7981" | head -n 1)
if [ -z "$DTS_FILE" ]; then
    err "未找到 SL3000 DTS 文件"
else
    DTS="$ROOT/target/linux/mediatek/dts/$DTS_FILE"
    log "检测到 DTS 文件: $DTS_FILE"
    sed -i 's/mediatek,mt7981/mediatek,mt7981b/g' "$DTS" || true
fi

# ============================
# 3. image.mk 修复
# ============================
MK="$ROOT/target/linux/mediatek/image/filogic.mk"
[ -f "$MK" ] && grep -q "sl3000" "$MK" || err "image.mk 未包含 sl3000 定义"

# ============================
# 4. kernel include 修复
# ============================
INC="$ROOT/include/kernel-defaults.mk"
[ -f "$INC" ] && sed -i 's/CONFIG_KERNEL_/CONFIG_/g' "$INC" || true

# ============================
# 5. feeds & package 修复
# ============================
cd "$ROOT"
./scripts/feeds update -a || true
./scripts/feeds install -a || true

# 清理坏包依赖
for p in uw-imap python3-pysocks python3-unidecode; do
    sed -i "/$p/d" .config || true
done

# 循环依赖 backuppc
sed -i '/CONFIG_PACKAGE_backuppc/d' .config || true

make defconfig || true

# ============================
# 6. gpio-button-hotplug 修复
# ============================
GPIO_PKG="$ROOT/package/kernel/gpio-button-hotplug"
if [ -d "$GPIO_PKG" ]; then
    log "检查 gpio-button-hotplug..."
    sed -i '/EXTRA_DEPENDS/d' "$GPIO_PKG/Makefile" || true
    sed -i '/PKG_SOURCE_VERSION/d' "$GPIO_PKG/Makefile" || true
else
    log "gpio-button-hotplug 不存在，跳过"
fi

# ============================
# 7. 科学上网支持（Passwall2）
# ============================
log "检查科学上网支持..."
grep -q "CONFIG_PACKAGE_luci-app-passwall2=y" .config || {
    cat >> .config <<EOF
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
    log "已自动加入科学上网配置"
}

# ============================
# 8. 常见插件安装
# ============================
for p in luci luci-compat luci-app-dockerman docker; do
    grep -q "$p" .config && ./scripts/feeds install "$p" || true
done

# ============================
# 9. 上游变更提示
# ============================
UP_DTS_REF="$ROOT/target/linux/mediatek/dts/mt7981b-rfb.dts"
[ -f "$UP_DTS_REF" ] && ! diff -q "$UP_DTS_REF" "$DTS" >/dev/null 2>&1 && \
    log "提示：上游 DTS 有更新，建议 review"

# ============================
# 10. 构建
# ============================
log "开始最终构建固件..."
make defconfig
if ! make -j"$(nproc)"; then
    log "并行构建失败，尝试单线程详细模式..."
    make -j1 V=s || { err "构建失败，请查看 $LOG"; exit 1; }
fi

log "构建成功，固件已生成"
exit 0
