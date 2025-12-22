#!/usr/bin/env bash

set -e

echo "===== SL3000 全链路一致性检测 ====="

# 1. 仓库名称检查
echo "[1] 仓库名称检查"
if [ "${GITHUB_REPOSITORY}" != "ykm0595/sl3000" ]; then
  echo "❌ 仓库名称不一致，应为 ykm0595/sl3000"
  exit 1
fi
echo "✅ 仓库名称正确"

# 2. 构建路径检查
echo "[2] 构建路径检查"
case "$(pwd)" in
  *"/sl3000") echo "✅ 构建路径正确" ;;
  *)
    echo "❌ 构建路径不包含 /sl3000"
    exit 1
    ;;
esac

# 3. DTS 文件检查
echo "[3] DTS 文件检查"
if [ ! -f openwrt/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts ]; then
  echo "❌ DTS 文件不存在：mt7981-sl3000-emmc.dts"
  exit 1
fi
echo "✅ DTS 文件存在"

# 4. filogic.mk DEVICE_DTS 检查
echo "[4] filogic.mk DEVICE_DTS 检查"
DTS_LINE=$(grep -E "DEVICE_DTS *:= *mediatek/mt7981-sl3000-emmc" \
  openwrt/target/linux/mediatek/image/filogic.mk || true)
if [ -z "$DTS_LINE" ]; then
  echo "❌ filogic.mk 中 DEVICE_DTS 未对齐为 mediatek/mt7981-sl3000-emmc"
  exit 1
fi
echo "✅ filogic.mk DEVICE_DTS 对齐"

# 5. DTS Makefile 注册检查
echo "[5] DTS Makefile 注册检查"
if ! grep -q "mt7981-sl3000-emmc.dts" openwrt/target/linux/mediatek/dts/Makefile; then
  echo "❌ DTS 未注册到 Makefile"
  exit 1
fi
echo "✅ DTS 已注册"

# 6. config DEVICE 检查
echo "[6] config DEVICE 检查"
if ! grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" openwrt/.config; then
  echo "❌ config 中 DEVICE 未对齐为 sl3000-emmc"
  exit 1
fi
echo "✅ config DEVICE 对齐"

# 7. 检查是否存在旧的 s13000 残留
echo "[7] 检查 s13000 残留"
BAD=$(grep -R "s13000" -n openwrt/target/linux/mediatek || true)
if [ ! -z "$BAD" ]; then
  echo "❌ 检测到 s13000 残留："
  echo "$BAD"
  exit 1
fi
echo "✅ 没有
