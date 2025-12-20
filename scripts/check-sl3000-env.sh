#!/bin/bash

echo "=== SL3000 构建环境自检（openwrt/）开始 ==="

ROOT="openwrt"

# 1. 检查 filogic.mk
if [ ! -f "$ROOT/target/linux/mediatek/image/filogic.mk" ]; then
    echo "❌ 缺少 $ROOT/target/linux/mediatek/image/filogic.mk"
    exit 1
else
    echo "✅ filogic.mk 存在"
fi

grep -q "Device/sl3000-emmc" "$ROOT/target/linux/mediatek/image/filogic.mk"
if [ $? -ne 0 ]; then
    echo "❌ filogic.mk 中没有 Device/sl3000-emmc 定义"
    exit 1
else
    echo "✅ filogic.mk 中包含 Device/sl3000-emmc"
fi

# 2. 检查 DTS
if [ ! -f "$ROOT/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts" ]; then
    echo "❌ 缺少 DTS：$ROOT/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts"
    exit 1
else
    echo "✅ DTS 文件存在"
fi

# 3. 检查 .config
if [ ! -f "$ROOT/.config" ]; then
    echo "❌ 缺少 $ROOT/.config（构建无法继续）"
    exit 1
else
    echo "✅ .config 存在"
fi

grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" "$ROOT/.config"
if [ $? -ne 0 ]; then
    echo "❌ .config 未启用 SL3000"
    exit 1
else
    echo "✅ .config 已启用 SL3000"
fi

echo "=== ✅ SL3000 构建环境自检通过（openwrt/）==="
exit 0
