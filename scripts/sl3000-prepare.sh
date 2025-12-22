#!/usr/bin/env bash
set -e

echo "===== SL3000 构建前准备脚本（自动清理 + 自动检测 + fail-fast）====="

CONFIG_FILE="openwrt/.config"
DTS_FILE="openwrt/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts"
MK_FILE="openwrt/target/linux/mediatek/image/filogic.mk"
DTS_MAKEFILE="openwrt/target/linux/mediatek/dts/Makefile"

echo "[1] 检查 DTS 文件..."
if [ ! -f "$DTS_FILE" ]; then
    echo "❌ DTS 缺失：$DTS_FILE"
    exit 1
fi
echo "✅ DTS 存在"

echo "[2] 检查 filogic.mk..."
if ! grep -q "DEVICE_DTS := mediatek/mt7981-sl3000-emmc" "$MK_FILE"; then
    echo "❌ filogic.mk 未对齐 DEVICE_DTS"
    exit 1
fi
echo "✅ filogic.mk 对齐正确"

echo "[3] 检查 DTS Makefile 注册..."
if ! grep -q "mt7981-sl3000-emmc.dts" "$DTS_MAKEFILE"; then
    echo "⚠️ 未注册 DTS，正在自动注册..."
    echo 'DTS_MT7981 += mt7981-sl3000-emmc.dts' >> "$DTS_MAKEFILE"
    echo "✅ 已自动注册 DTS"
else
    echo "✅ DTS 已注册"
fi

echo "[4] 自动清理 .config..."
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未找到 .config：$CONFIG_FILE"
    exit 1
fi

BAD_PKGS=(
  "asterisk"
  "onionshare"
  "pysocks"
  "unidecode"
  "uw-imap"
)

echo "清理以下不存在的包："
printf '%s\n' "${BAD_PKGS[@]}"

for pkg in "${BAD_PKGS[@]}"; do
    sed -i "/$pkg/d" "$CONFIG_FILE"
done

echo "验证清理结果..."
for pkg in "${BAD_PKGS[@]}"; do
    if grep -q "$pkg" "$CONFIG_FILE"; then
        echo "❌ 清理失败：仍然存在 $pkg"
        exit 1
    fi
done
echo "✅ .config 已完全清理干净"

echo "[5] 最终一致性检查..."
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" "$CONFIG_FILE"; then
    echo "❌ .config 未启用 SL3000 设备"
    exit 1
fi

echo "===== 所有检查通过，SL3000 构建环境已准备完毕 ====="
