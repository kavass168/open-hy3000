#!/bin/bash
set -e

log() { echo -e "\033[1;32m[SL3000]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

# ============================
# 0. 自动定位源码目录（优先 immortalwrt）
# ============================
if [ -d "immortalwrt" ]; then
  ROOT="$(pwd)/immortalwrt"
elif [ -d "../immortalwrt" ]; then
  ROOT="$(pwd)/../immortalwrt"
else
  err "未找到源码目录 immortalwrt"
  exit 1
fi

cd "$ROOT"

REPORT_DIR="$ROOT/build-report"
LOG="$REPORT_DIR/error.log"
mkdir -p "$REPORT_DIR"
rm -f "$LOG"

trap 'echo -e "\033[1;31m[ERROR]\033[0m 构建失败，错误日志: $LOG"; exit 1' ERR

log "开始 SL3000 自动修复 + 构建流程（ImmortalWrt master 25.12-SNAPSHOT）"

# ============================
# 1. 复制三件套
# ============================
cp -vf ../configs/s13000.config "$ROOT/.config" || { err "缺少 configs/s13000.config"; exit 1; }
cp -vf ../target/linux/mediatek/dts/mt7981b-sl3000-emmc.dts "$ROOT/target/linux/mediatek/dts/" || { err "缺少 mt7981b-sl3000-emmc.dts"; exit 1; }
cp -vf ../target/linux/mediatek/image/filogic.mk "$ROOT/target/linux/mediatek/image/" || { err "缺少 filogic.mk"; exit 1; }

# ============================
# 2. 注册 DTS + 修复 include + 校验 Device
# ============================
DTS_FILE=$(find target/linux/mediatek/dts -maxdepth 1 -name "mt7981*sl3000*.dts" | sort | head -n1)
[ -z "$DTS_FILE" ] && { err "未找到 SL3000 DTS"; exit 1; }
DTS_NAME=$(basename "$DTS_FILE")

MED_MK="target/linux/mediatek/Makefile"
grep -q "$DTS_NAME" "$MED_MK" || echo "dts-\$(CONFIG_TARGET_mediatek_filogic) += $DTS_NAME" >> "$MED_MK"

IMG_MAKE="target/linux/mediatek/image/Makefile"
grep -q "filogic.mk" "$IMG_MAKE" || echo "include ./filogic.mk" >> "$IMG_MAKE"

MK="target/linux/mediatek/image/filogic.mk"
grep -q "Device/sl3000" "$MK" || { err "filogic.mk 未包含 Device/sl3000"; exit 1; }
grep -q "TARGET_DEVICES += sl3000" "$MK" || { err "filogic.mk 未添加 TARGET_DEVICES += sl3000"; exit 1; }

# ============================
# 3. feeds + 冲突清理 + TARGET 三件套 + defconfig
# ============================
./scripts/feeds update -a || true
./scripts/feeds install -a || true

sed -i '/uw-imap/d;/python3-pysocks/d;/python3-unidecode/d;/python3-charset-normalizer/d;/python3-certifi/d;/python3-idna/d' .config || true

grep -q "CONFIG_TARGET_mediatek=y" .config || echo "CONFIG_TARGET_mediatek=y" >> .config
grep -q "CONFIG_TARGET_mediatek_filogic=y" .config || echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" .config || echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" >> .config

# 移除科学上网
sed -i '/passwall2/d;/xray-core/d;/v2ray-core/d;/sing-box/d;/trojan/d;/chinadns-ng/d;/dns2socks/d;/dns2tcp/d;/pdnsd-alt/d;/ipt2socks/d' .config || true

make defconfig

# ============================
# 4. 工具链与内核分段构建
# ============================
log "安装工具链"
make toolchain/install -j1 V=s

log "编译内核（syncconfig 可见）"
make target/linux/compile -j1 V=sc || {
  log "内核阶段失败，重试一次"
  make target/linux/compile -j1 V=sc
}

log "安装内核/镜像（明确可见）"
make target/linux/install -j1 V=s

log "编译 world"
if ! make -j"$(nproc)"; then
  log "并行失败，单线程重试"
  make -j1 V=s 2>&1 | tee -a "$LOG"
fi

# ============================
# 5. 自动验证与摘要
# ============================
TARGET_DIR=$(find bin/targets -maxdepth 3 -type d | grep -E "mediatek|filogic" | head -n1)
[ -z "$TARGET_DIR" ] && { err "未找到 targets 输出目录"; exit 1; }

log "验证 DTB"
find build_dir -name "*sl3000*.dtb" | grep sl3000 >/dev/null || { err "未生成 sl3000 dtb"; exit 1; }

log "验证 profiles.json"
test -f "$TARGET_DIR/profiles.json" || { err "缺少 profiles.json"; exit 1; }
grep -q sl3000 "$TARGET_DIR/profiles.json" || { err "profiles.json 未包含 sl3000"; exit 1; }

log "验证固件与大小"
FW=$(ls "$TARGET_DIR"/*sl3000*.bin | head -n1) || { err "未生成 sl3000 固件"; exit 1; }
SIZE=$(stat -c%s "$FW")
[ "$SIZE" -lt 4000000 ] && { err "固件大小异常（<4MB）"; exit 1; }

log "生成 SHA256"
sha256sum "$TARGET_DIR"/*sl3000*.bin > "$TARGET_DIR"/sha256.txt
cat "$TARGET_DIR"/sha256.txt

log "构建成功 ✅"
echo "固件目录: $TARGET_DIR"
ls -lh "$TARGET_DIR"/*sl3000*.bin
