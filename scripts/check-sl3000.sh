#!/usr/bin/env bash
set -e

echo "===== SL3000 全链路一致性检测 ====="

echo "[1] 仓库名称检查"
if [ "${GITHUB_REPOSITORY}" != "ykm0595/sl3000" ]; then
  echo "❌ 仓库名称不一致，应为 ykm0595/sl3000"
  exit 1
fi
echo "✅ 仓库名称正确"

echo "[2] 构建路径检查"
case "$(pwd)" in
  *"/sl3000") echo "✅ 构建路径正确" ;;
  *)
    echo "❌ 构建路径不包含 /sl3000"
    exit 1
    ;;
esac

echo "[3] DTS 文件检查"
if [ ! -f openwrt/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts ]; then
  echo "❌ DTS 文件不存在"
  exit 1
fi
echo "✅ DTS 文件存在"

echo "[4] filogic.mk DEVICE_DTS 检查"
grep -q "DEVICE_DTS := mediatek/mt7981-sl3000-emmc" \
  openwrt/target/linux/mediatek/image/filogic.mk || {
  echo "❌ DEVICE_DTS 未对齐"
  exit 1
}
echo "✅ DEVICE_DTS 对齐"

echo "[5] DTS Makefile 注册检查"
grep -q "mt7981-sl3000-emmc.dts" openwrt/target/linux/mediatek/dts/Makefile || {
  echo "❌ DTS 未注册"
  exit 1
}
echo "✅ DTS 已注册"

echo "[6] config DEVICE 检查"
grep -q "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" openwrt/.config || {
  echo "❌ config DEVICE 未对齐"
  exit 1
}
echo "✅ config DEVICE 对齐"

echo "[7] 检查 s13000 残留"
if grep -R "s13000" -n openwrt/target/linux/mediatek; then
  echo "❌ 存在 s13000 残留"
  exit 1
fi
echo "✅ 无 s13000 残留"

echo "===== SL3000 全链路一致性检测通过 ====="
