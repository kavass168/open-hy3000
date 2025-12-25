#!/bin/bash
set -e

log() { echo -e "\033[1;32m[SL3000]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

ROOT="$(pwd)/immortalwrt"
cd "$ROOT"

log "复制三件套"
cp -vf ../configs/sl3000.config "$ROOT/.config"
cp -vf ../dts/mt7981-sl3000-emmc.dts "$ROOT/target/linux/mediatek/dts/"
cp -vf ../image/filogic.mk "$ROOT/target/linux/mediatek/image/"

log "注册 DTS"
DTS_FILE=$(find target/linux/mediatek/dts -maxdepth 1 -name "mt7981*sl3000*.dts" | sort | head -n1)
[ -z "$DTS_FILE" ] && { err "未找到 SL3000 DTS"; exit 1; }
DTS_NAME=$(basename "$DTS_FILE")
MED_MK="target/linux/mediatek/Makefile"
grep -q "$DTS_NAME" "$MED_MK" || echo "dts-\$(CONFIG_TARGET_mediatek_filogic) += $DTS_NAME" >> "$MED_MK"

log "修复 image.mk include"
IMG_MAKE="target/linux/mediatek/image/Makefile"
grep -q "filogic.mk" "$IMG_MAKE" || echo "include ./filogic.mk" >> "$IMG_MAKE"

log "feeds 更新"
./scripts/feeds update -a || true
./scripts/feeds install -a || true

log "补全 TARGET 三件套"
grep -q "CONFIG_TARGET_mediatek=y" .config || echo "CONFIG_TARGET_mediatek=y" >> .config
grep -q "CONFIG_TARGET_mediatek_filogic=y" .config || echo "CONFIG_TARGET_mediatek_filogic=y" >> .config
grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" .config || echo "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" >> .config

make defconfig

log "安装工具链"
make toolchain/install -j1 V=s

log "编译内核"
make target/linux/compile -j1 V=sc || make target/linux/compile -j1 V=sc

log "安装内核/镜像"
make target/linux/install -j1 V=s

log "编译 world"
make -j"$(nproc)" || make -j1 V=s

log "验证固件"
TARGET_DIR=$(find bin/targets -maxdepth 3 -type d | grep -E "mediatek|filogic" | head -n1)
test -f "$TARGET_DIR/profiles.json"
grep -q sl3000 "$TARGET_DIR/profiles.json"
ls "$TARGET_DIR"/*sl3000*.bin
sha256sum "$TARGET_DIR"/*sl3000*.bin > "$TARGET_DIR"/sha256.txt
cat "$TARGET_DIR"/sha256.txt

log "构建完成 ✅"
