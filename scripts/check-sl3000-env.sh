- name: Apply SL3000 device files (force overwrite)
        run: |
          cp -f image/filogic.mk openwrt/target/linux/mediatek/image/filogic.mk
          cp -f dts/mt7981-sl3000-emmc.dts openwrt/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts
          cp -f config/sl3000.config openwrt/.config

      - name: Verify SL3000 configuration alignment
        run: |
          echo "===== 仓库名称检查 ====="
          echo "当前仓库: ${GITHUB_REPOSITORY}"
          if [ "${GITHUB_REPOSITORY}" != "ykm0595/sl3000" ]; then
            echo "❌ 仓库名称不一致，应为 ykm0595/sl3000"
            exit 1
          fi
          echo "✅ 仓库名称正确"

          echo "===== 构建路径检查 ====="
          pwd
          if [[ "$(pwd)" != *"/sl3000" ]]; then
            echo "❌ 构建路径不正确，应包含 sl3000"
            exit 1
          fi
          echo "✅ 构建路径正确"

          echo "===== DTS 文件检查 ====="
          if [ ! -f openwrt/target/linux/mediatek/dts/mt7981-sl3000-emmc.dts ]; then
            echo "❌ DTS 文件不存在：mt7981-sl3000-emmc.dts"
            exit 1
          fi
          echo "✅ DTS 文件存在"

          echo "===== filogic.mk DEVICE_DTS 检查 ====="
          DTS_LINE=$(grep -E "DEVICE_DTS *:= *mt7981-sl3000-emmc" openwrt/target/linux/mediatek/image/filogic.mk || true)
          if [ -z "$DTS_LINE" ]; then
            echo "❌ filogic.mk 中 DEVICE_DTS 未对齐为 mt7981-sl3000-emmc"
            exit 1
          fi
          echo "✅ filogic.mk DEVICE_DTS 对齐"

          echo "===== config DEVICE 检查 ====="
          CFG_LINE=$(grep "CONFIG_TARGET_mediatek_filogic_DEVICE_sl3000-emmc=y" openwrt/.config || true)
          if [ -z "$CFG_LINE" ]; then
            echo "❌ config 中 DEVICE 未对齐为 sl3000-emmc"
            exit 1
          fi
          echo "✅ config DEVICE 对齐"

          echo "===== DTS Makefile 注册检查 ====="
          REG_LINE=$(grep "mt7981-sl3000-emmc.dts" openwrt/target/linux/mediatek/dts/Makefile || true)
          if [ -z "$REG_LINE" ]; then
            echo "❌ DTS 未注册到 Makefile"
            exit 1
          fi
          echo "✅ DTS 注册正确"

          echo "===== 检查是否存在旧的 s13000 残留 ====="
          BAD=$(grep -R "s13000" -n openwrt/target/linux/mediatek || true)
          if [ ! -z "$BAD" ]; then
            echo "❌ 检测到 s13000 残留："
            echo "$BAD"
            exit 1
          fi
          echo "✅ 没有 s13000 残留"

          echo "===== 全部检查通过，开始构建 ====="
