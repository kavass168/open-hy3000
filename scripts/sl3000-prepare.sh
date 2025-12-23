#!/usr/bin/env bash
set -e

echo "===== SL3000 构建前准备脚本（dry-run + 自动检测 + 自动修复 + DTS 自动重命名 + fail-fast）====="

CONFIG_FILE="openwrt/.config"
MK_FILE="openwrt/target/linux/mediatek/image/filogic.mk"
DTS_DIR_MAIN="openwrt/target/linux/mediatek/dts"

# ================================
# 0. dry-run：检测基础依赖
# ================================
echo "[0] dry-run：检测构建依赖..."

REQUIRED_CMDS=(gcc g++ make python3 rsync flex bison)

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
# 6. dry-run：检测 OpenWrt 构建目录结构
# ================================
echo "[6] dry-run：检测 OpenWrt 构建依赖..."

OPENWRT_REQUIRED_DIRS=(
    "openwrt/dl"
    "openwrt/staging_dir"
    "openwrt/scripts"
)

for dir in "${OPENWRT_REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "⚠️ 缺少目录：$dir"
        echo "⚙️ 自动修复：创建目录 $dir"
        mkdir -p "$dir"
    fi
done

echo "✅ OpenWrt 目录结构完整"

# ================================
# 7. dry-run：检测 feeds 冲突（增强版）
# ================================
echo "[7] dry-run：检测 feeds 冲突..."

CONFLICT_FILES=$(grep -Rl "<<<<<<<" openwrt/package 2>/dev/null || true)

if [ -n "$CONFLICT_FILES" ]; then
    echo "❌ feeds 存在合并冲突"
    echo "⚙️ 自动修复：清理冲突标记"

    for f in $CONFLICT_FILES; do
        echo "  → 修复冲突文件：$f"
        sed -i '/<<<<<<<\|=======\|>>>>>>>/d' "$f"
    done

    echo "✅ 冲突标记已清理"
else
    echo "✅ feeds 无冲突"
fi

# ================================
# 8. 最终一致性检查（按 Device profile 名，而不是 DTS 名）
# ================================
echo "[8] 最终一致性检查..."

DEVICE_PROFILE=$(
  awk -v dts="$DTS_NAME" '
    # 记录当前的 Device profile，行可能有缩进
    /^[[:space:]]*define Device\// {
      if (match($0, /Device\/[A-Za-z0-9_-]+/)) {
        dev = substr($0, RSTART + 7, RLENGTH - 7)
      }
    }
    # 当遇到包含当前 DTS 的 DEVICE_DTS 行时，输出对应的 profile
    /DEVICE_DTS/ && $0 ~ dts {
      if (dev != "") {
        print dev
        exit
      }
    }
  ' "$MK_FILE"
)

if [ -z "$DEVICE_PROFILE" ]; then
    echo "❌ 无法根据 DTS 名称找到对应的 Device profile（检查 filogic.mk）"
    exit 1
fi

echo "✅ 识别 Device profile：$DEVICE_PROFILE"

CFG_SYM="CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_PROFILE}=y"
echo "预期 .config 中应存在：${CFG_SYM}"

if ! grep -q "^${CFG_SYM}" "$CONFIG_FILE"; then
    echo "❌ .config 未启用设备：${DEVICE_PROFILE}"
    echo "   期望存在：${CFG_SYM}"
    exit 1
fi

echo "✅ .config 已启用设备：${DEVICE_PROFILE}"
echo "===== 所有检查通过，SL3000 构建环境已准备完毕 ====="
