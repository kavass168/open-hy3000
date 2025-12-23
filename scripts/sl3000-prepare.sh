#!/usr/bin/env bash
set -e

echo "===== SL3000 全链路构建准备脚本（全自动修复 + 全链路诊断 + 无人值守）====="

CONFIG_FILE="openwrt/.config"
MK_FILE="openwrt/target/linux/mediatek/image/filogic.mk"
DTS_DIR_MAIN="openwrt/target/linux/mediatek/dts"

REPORT_DIR="openwrt/build-report"
mkdir -p "$REPORT_DIR"
ERROR_LOG="$REPORT_DIR/error.log"
BUILD_LOG="$REPORT_DIR/build.log"

# ================================
# [fix] 修复官方 image.mk 中的错误 DTS 名称
# ================================
echo "[fix] 修复官方 image.mk 中的错误 DTS 名称..."

IMAGE_MK="openwrt/target/linux/mediatek/image/filogic.mk"

sed -i 's/image-mt7981-s13000-emmc.dts/image-mt7981-sl3000-emmc.dts/g' "$IMAGE_MK"
sed -i 's/s13000-emmc/sl3000-emmc/g' "$IMAGE_MK"

echo "[fix] image.mk DTS 名称修复完成"

# ================================
# 0. dry-run：检测构建依赖
# ================================
echo "[0] dry-run：检测构建依赖..."

REQUIRED_CMDS=(gcc g++ make python3 rsync flex bison patch)

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ 缺少依赖：$cmd"
        echo "⚙️ 自动修复：安装 $cmd"
        sudo apt-get update && sudo apt-get install -y "$cmd"
    fi
done

echo "✅ 基础依赖全部满足"

# ================================
# 1. 自动识别 DTS 名称
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
# 2. 自动重命名 DTS 文件
# ================================
echo "[2] 自动重命名 DTS 文件..."

if [ ! -f "dts/$DTS_NAME.dts" ]; then
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

BAD_PKGS=( "asterisk" "onionshare" "pysocks" "unidecode" "uw-imap" )
for pkg in "${BAD_PKGS[@]}"; do
    sed -i "/$pkg/d" "$CONFIG_FILE"
done

echo "✅ .config 已完全清理干净"

# ================================
# 6. 自动修复目录结构
# ================================
echo "[6] 自动修复目录结构..."

OPENWRT_REQUIRED_DIRS=(
    "openwrt/dl"
    "openwrt/staging_dir"
    "openwrt/scripts"
)

for dir in "${OPENWRT_REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "⚙️ 自动创建目录：$dir"
        mkdir -p "$dir"
    fi
done

echo "✅ 目录结构完整"

# ================================
# 7. 自动修复 feeds 冲突
# ================================
echo "[7] 自动修复 feeds 冲突..."

CONFLICT_FILES=$(grep -Rl "<<<<<<<" openwrt/package 2>/dev/null || true)

if [ -n "$CONFLICT_FILES" ]; then
    echo "⚠️ 检测到 feeds 冲突，自动修复..."

    for f in $CONFLICT_FILES; do
        sed -i '/<<<<<<<\|=======\|>>>>>>>/d' "$f"
    done

    echo "✅ feeds 冲突已修复"
else
    echo "✅ feeds 无冲突"
fi

# ================================
# 8. 解析 Device profile
# ================================
echo "[8] 解析 Device profile..."

DEVICE_PROFILE=$(
  awk -v dts="$DTS_NAME" '
    /^[[:space:]]*define Device\// {
      if (match($0, /Device\/[A-Za-z0-9_-]+/)) {
        dev = substr($0, RSTART + 7, RLENGTH - 7)
      }
    }
    /DEVICE_DTS/ && $0 ~ dts {
      if (dev != "") {
        print dev
        exit
      }
    }
  ' "$MK_FILE"
)

if [ -z "$DEVICE_PROFILE" ]; then
    echo "❌ 无法根据 DTS 名称找到对应的 Device profile"
    exit 1
fi

echo "✅ 识别 Device profile：$DEVICE_PROFILE"

CFG_SYM="CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_PROFILE}=y"

if ! grep -q "^${CFG_SYM}" "$CONFIG_FILE"; then
    echo "❌ .config 未启用设备：${DEVICE_PROFILE}"
    exit 1
fi

echo "✅ .config 已启用设备：${DEVICE_PROFILE}"

# ================================
# 9. 自动修复 kernel include
# ================================
echo "[9] 自动修复 kernel include..."

KDIR=$(find openwrt/build_dir -maxdepth 3 -type d -name "*linux-mediatek_filogic*" | head -n 1)

if [ -n "$KDIR" ]; then
    DTS_KERNEL_PATH="$KDIR/arch/arm64/boot/dts/mediatek/$DTS_NAME.dts"

    if [ ! -f "$DTS_KERNEL_PATH" ]; then
        echo "⚠️ DTS 未进入 kernel，自动修复"
        cp -f "$DTS_FILE_MAIN" "$DTS_KERNEL_PATH"
    fi

    IMAGE_DTS="$KDIR/image-$DTS_NAME.dts"
    if [ ! -f "$IMAGE_DTS" ]; then
        echo "⚠️ image DTS 缺失，自动生成"
        cp -f "$DTS_FILE_MAIN" "$IMAGE_DTS"
    fi
else
    echo "⚠️ kernel 尚未构建，跳过 include 修复"
fi

echo "✅ kernel include 修复完成"

# ================================
# 10. 自动修复 package 依赖
# ================================
echo "[10] 自动修复 package 依赖..."

MISSING_DEPS=()

while read -r dep; do
    if ! grep -q "$dep" "$CONFIG_FILE"; then
        MISSING_DEPS+=("$dep")
    fi
done < <(grep -R "DEPENDS" openwrt/package | grep -o "+[a-zA-Z0-9_-]*" | sed 's/+//g' | sort -u)

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "⚠️ 检测到缺失依赖：${MISSING_DEPS[*]}"
    echo "⚙️ 自动写入 .config"

    for dep in "${MISSING_DEPS[@]}"; do
        echo "CONFIG_PACKAGE_$dep=y" >> "$CONFIG_FILE"
    done

    echo "⚙️ 自动执行 feeds install"
    (cd openwrt && ./scripts/feeds install -a)
else
    echo "✅ package 依赖完整"
fi

# ================================
# 11. 构建并捕获错误
# ================================
echo "[11] 开始构建（自动捕获错误）..."

(
  cd openwrt
  make -j$(nproc)
) 2>&1 | tee "$BUILD_LOG"

if [ "${PIPESTATUS[0]}" != "0" ]; then
    echo "❌ 构建失败，正在生成错误报告..."

    grep -iE "error|failed|fatal" "$BUILD_LOG" > "$ERROR_LOG" || true

    echo "===== 构建失败，错误报告已生成 ====="
    echo "错误日志路径：$ERROR_LOG"
    exit 1
fi

echo "===== 构建成功 ====="
