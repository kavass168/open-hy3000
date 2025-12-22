#!/usr/bin/env bash
set -e

echo "===== SL3000 全链路一致性检测 ====="

[ -f openwrt/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts ] || {
  echo "❌ DTS 缺失"
  exit 1
}

grep -q "DEVICE_DTS := mediatek/mt7981-sl3000-emmc" \
  openwrt/target/linux/mediatek/image/filogic.mk || {
  echo "❌ filogic.mk 未对齐"
  exit 1
}

grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" openwrt/.config || {
  echo "❌ config 未对齐"
  exit 1
}

echo "===== 检测通过 ====="
