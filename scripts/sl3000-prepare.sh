#!/usr/bin/env bash
set -e

echo "===== SL3000 构建前准备脚本（自动清理 + 自动检测 + fail-fast）====="

CONFIG_FILE="openwrt/.config"
MK_FILE="openwrt/target/linux/mediatek/image/filogic.mk"
DTS_DIR_MAIN="openwrt/target/linux/mediatek/dts"

# ================================
# 1. 自动识别 DTS 名称（从 image.mk 中提取）
# ================================
echo "[1] 自动识别 DTS 名称..."

DTS_NAME=$(grep -E 'DEVICE_DTS\s*:?=' "$MK_FILE" | grep -o 'mt7981-[a-zA-Z0-9_-]*-emmc' | head -n 1)
if [ -z "$DTS_NAME" ]; then
    echo "❌ 无法从 filogic.mk 中识别 DTS 名称"
    exit 1
fi
echo "✅ 识别 DTS 名称：$DTS_NAME"

DTS_FILE_MAIN="$DTS_DIR_MAIN/$DTS_NAME.dts"

# ================================
# 2. 自动重命名 DTS 文件（如果名称不一致）
# ================================
echo "[2] 自动重命名 DTS 文件..."

if [ ! -f "dts/$DTS_NAME.dts" ]; then
    # 查找 dts 目录下的 mt7981-*-emmc.dts 文件
    DTS_SRC=$(find dts -maxdepth 1 -name "mt7981-*-emmc.dts" | head -n 1)
    if [ -z "$DTS_SRC" ]; then
        echo "❌ dts/ 下未找到任何 DTS 文件"
        exit 1
    fi
    echo "⚠️ DTS 文件名不匹配，自动重命名：$DTS_SRC → dts/$DTS_NAME.dts"
    cp -f "$DTS_SRC" "dts/$DTS_NAME.dts"
else
    echo "✅ DTS 文件名已匹配：dts/$DTS_NAME.dts"
fi

# ================================
# 3. 复制 DTS 到主 DTS 目录
# ================================
echo "[3] 复制 DTS 到主 DTS 目录..."

mkdir -p "$DTS_DIR_MAIN"
cp -f "dts/$DTS_NAME.dts" "$DTS_FILE_MAIN"

if [ ! -f "$DTS_FILE_MAIN" ]; then
    echo "❌ DTS 文件复制失败：$DTS_FILE_MAIN"
    exit 1
fi
echo "✅ DTS 文件已复制到主 DTS 目录"

# ================================
# 4. 检查 filogic.mk 是否对齐
# ================================
echo "[4] 检查 filogic.mk..."

if ! grep -q "$DTS_NAME" "$MK_FILE"; then
    echo "❌ filogic.mk 未包含 DTS 名称：$DTS_NAME"
    exit 1
fi
echo "✅ filogic.mk 包含 DTS 名称"

# ================================
# 5. 自动清理 .config
# ================================
echo "[5] 自动清理 .config..."

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未找到 .config：$CONFIG_FILE"
    exit 1
fi

BAD_PKGS=( "asterisk" "onionshare" "pysocks" "unidecode" "uw-imap" )
for pkg in "${BAD_PKGS[@]}"; do
    sed -i "/$pkg/d" "$CONFIG_FILE"
done

for pkg in "${BAD_PKGS[@]}"; do
    if grep -q "$pkg" "$CONFIG_FILE"; then
        echo "❌ 清理失败：仍然存在 $pkg"
        exit 1
    fi
done
echo "✅ .config 已完全清理干净"

# ================================
# 6. 最终一致性检查
# ================================
echo "[6] 最终一致性检查..."

if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_${DTS_NAME}=y" "$CONFIG_FILE"; then
    echo "❌ .config 未启用设备：${DTS_NAME}"
    exit 1
fi

echo "===== 所有检查通过，SL3000 构建环境已准备完毕 ====="
