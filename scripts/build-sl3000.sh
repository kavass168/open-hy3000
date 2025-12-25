#!/bin/bash
set -e

log() { echo -e "\033[1;32m[SL3000]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

ROOT="$(pwd)/immortalwrt"
cd "$ROOT"

log "复制三件套"
cp -vf ../configs/sl3000.config "$ROOT/.config"
cp -vf ../dts/mt7981b-sl3000-emmc.dts "$ROOT/target/linux/mediatek/dts/"
cp -vf ../image/filogic.mk "$ROOT/target/linux/mediatek/image/"

log "注册 DTS"
DTS_FILE=$(find target/linux/mediatek/dts -maxdepth 1 -name "mt7981*sl3000*.dts" | sort | head -n1)
[ -z "$DTS_FILE" ] && { err "未找到 SL3000 DTS"; exit 1; }
DTS_NAME=$(basename "$DTS_FILE")
MED_MK="target/linux/mediatek/Makefile"
grep -q "$DTS_NAME" "$MED_MK" || echo "dts-\$(CONFIG_TARGET_mediatek_filogic) += $DTS_NAME" >> "$MED_MK"

log "修复 image.mk include"
IMG_MAKE="target/linux/mediatek/image/Makefile"
grep -q "fil
