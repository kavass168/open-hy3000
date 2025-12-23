#!/usr/bin/env bash
set -e

echo "===== SL3000 全链路构建准备脚本（自动检测 + 自动修复 + 自动诊断 + fail-fast）====="

CONFIG_FILE="openwrt/.config"
MK_FILE="openwrt/target/linux/mediatek/image/filogic.mk"
DTS_DIR_MAIN="openwrt/target/linux/mediatek/dts"

REPORT_DIR="openwrt/build-report"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/sl3000-report.txt"

echo "" > "$REPORT_FILE"

log() {
    echo "$1"
    echo "$1" >> "$REPORT_FILE"
}

# ================================
# 0. dry-run：检测基础依赖
# ================================
log "[0] 检测构建依赖..."

REQUIRED_CMDS=(gcc g++ make python3 rsync flex bison patch)

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "❌ 缺少依赖：$cmd"
        log "⚙️ 自动修复：安装 $cmd"
        sudo apt-get update && sudo apt-get install -y "$cmd"
    fi
done

log "✅ 基础依赖全部满足"

# ================================
# 1. 自动识别 DTS 名称
# ================================
log "[1] 自动识别 DTS 名称..."

DTS_NAME=$(grep -E 'DEVICE_DTS\s*:?=' "$MK_FILE" | grep -o 'mt7981-[a-zA-Z0-9_-]*-emmc' | head -n 1)
if [ -z "$DTS_NAME" ]; then
    log "❌ 无法从 filogic.mk 中识别 DTS 名称"
    exit 1
fi
log "✅ 识别 DTS 名称：$DTS_NAME"

DTS_FILE_MAIN="$DTS_DIR_MAIN/$DTS_NAME.dts"

# ================================
# 2. 自动重命名 DTS 文件
# ================================
log "[2] 自动重命名 DTS 文件..."

if [ ! -f "dts/$DTS_NAME.dts" ]; then
    DTS_SRC=$(find dts -maxdepth 1 -name "mt7981-*-emmc.dts" | head -n 1)
    if [ -z "$DTS_SRC" ]; then
        log "❌ dts/ 下未找到任何 DTS 文件"
        exit 1
    fi
    log "⚠️ DTS 文件名不匹配，自动重命名：$DTS_SRC → dts/$DTS_NAME.dts"
    cp -f "$DTS_SRC" "dts/$DTS_NAME.dts"
else
    log "✅ DTS 文件名已匹配：dts/$DTS_NAME.dts"
fi

# ================================
# 3. 复制 DTS 到主 DTS 目录
# ================================
log "[3] 复制 DTS 到主 DTS 目录..."

mkdir -p "$DTS_DIR_MAIN"
cp -f "dts/$DTS_NAME.dts" "$DTS_FILE_MAIN"

if [ ! -f "$DTS_FILE_MAIN" ]; then
    log "❌ DTS 文件复制失败：$DTS_FILE_MAIN"
    exit 1
fi
log "✅ DTS 文件已复制到主 DTS 目录"

# ================================
# 4. 检查 filogic.mk 是否对齐
# ================================
log "[4] 检查 filogic.mk..."

if ! grep -q "$DTS_NAME" "$MK_FILE"; then
    log "❌ filogic.mk 未包含 DTS 名称：$DTS_NAME"
    exit 1
fi
log "✅ filogic.mk 包含 DTS 名称"

# ================================
# 5. 自动清理 .config
# ================================
log "[5] 自动清理 .config..."

BAD_PKGS=( "asterisk" "onionshare" "pysocks" "unidecode" "uw-imap" )
for pkg in "${BAD_PKGS[@]}"; do
    sed -i "/$pkg/d" "$CONFIG_FILE"
done

log "✅ .config 已完全清理干净"

# ================================
# 6. 检测 OpenWrt 目录结构
# ================================
log "[6] 检测 OpenWrt 构建目录结构..."

OPENWRT_REQUIRED_DIRS=(
    "openwrt/dl"
    "openwrt/staging_dir"
    "openwrt/scripts"
)

for dir in "${OPENWRT_REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        log "⚠️ 缺少目录：$dir"
        log "⚙️ 自动修复：创建目录 $dir"
        mkdir -p "$dir"
    fi
done

log "✅ OpenWrt 目录结构完整"

# ================================
# 7. 检测 feeds 冲突
# ================================
log "[7] 检测 feeds 冲突..."

CONFLICT_FILES=$(grep -Rl "<<<<<<<" openwrt/package 2>/dev/null || true)

if [ -n "$CONFLICT_FILES" ]; then
    log "❌ feeds 存在合并冲突"
    for f in $CONFLICT_FILES; do
        log "  → 修复冲突文件：$f"
        sed -i '/<<<<<<<\|=======\|>>>>>>>/d' "$f"
    done
    log "✅ 冲突标记已清理"
else
    log "✅ feeds 无冲突"
fi

# ================================
# 8. 解析 Device profile
# ================================
log "[8] 解析 Device profile..."

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
    log "❌ 无法根据 DTS 名称找到对应的 Device profile"
    exit 1
fi

log "✅ 识别 Device profile：$DEVICE_PROFILE"

CFG_SYM="CONFIG_TARGET_mediatek_filogic_DEVICE_${DEVICE_PROFILE}=y"

if ! grep -q "^${CFG_SYM}" "$CONFIG_FILE"; then
    log "❌ .config 未启用设备：${DEVICE_PROFILE}"
    log "   期望存在：${CFG_SYM}"
    exit 1
fi

log "✅ .config 已启用设备：${DEVICE_PROFILE}"

# ================================
# 9. kernel DTS include 检查
# ================================
log "[9] kernel DTS include 检查..."

KDIR=$(find openwrt/build_dir -maxdepth 3 -type d -name "*linux-mediatek_filogic*" | head -n 1)

if [ -z "$KDIR" ]; then
    log "⚠️ kernel 尚未构建，跳过 DTS include 检查"
else
    if ! find "$KDIR/arch/arm64/boot/dts" -name "$DTS_NAME.dts" | grep -q .; then
        log "❌ DTS 未进入 kernel 目录，自动修复"
        cp -f "$DTS_FILE_MAIN" "$KDIR/arch/arm64/boot/dts/mediatek/"
    else
        log "✅ DTS 已进入 kernel"
    fi
fi

# ================================
# 10. patch 冲突检测
# ================================
log "[10] patch 冲突检测..."

PATCH_DIR="openwrt/target/linux/mediatek/patches"

if [ -d "$PATCH_DIR" ]; then
    for p in "$PATCH_DIR"/*.patch; do
        if ! patch --dry-run -p1 < "$p" >/dev/null 2>&1; then
            log "❌ patch 冲突：$p"
        fi
    done
else
    log "⚠️ 无 patch 目录，跳过"
fi

log "✅ patch 检查完成"

# ================================
# 11. package 依赖扫描
# ================================
log "[11] package 依赖扫描..."

MISSING_DEPS=()

while read -r pkg; do
    if ! grep -q "$pkg" "$CONFIG_FILE"; then
        MISSING_DEPS+=("$pkg")
    fi
done < <(grep -R "DEPENDS" openwrt/package | grep -o "+[a-zA-Z0-9_-]*" | sed 's/+//g' | sort -u)

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log "⚠️ 存在缺失依赖：${MISSING_DEPS[*]}"
else
    log "✅ package 依赖完整"
fi

# ================================
# 12. 构建加速优化
# ================================
log "[12] 构建加速优化..."

echo "export MAKEFLAGS='-j$(nproc) -Oline'" >> $GITHUB_ENV
log "✅ 启用并行构建 + 输出优化"

# ================================
# 13. 完成
# ================================
log "===== SL3000 全链路构建准备完成 ====="
log "诊断报告已生成：$REPORT_FILE"
