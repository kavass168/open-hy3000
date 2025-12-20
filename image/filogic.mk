define Device/sl3000-emmc
  DEVICE_VENDOR := SiLuo
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := eMMC
  DEVICE_DTS := mt7981-sl3000-emmc
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := \
    kmod-usb3 \
    kmod-usb2 \
    kmod-usb-net \
    kmod-usb-net-asix \
    kmod-usb-net-rtl8152 \
    kmod-mt7981-wmac \
    luci \
    block-mount \
    kmod-fs-ext4
  IMAGE_SIZE := 32m
  SUPPORTED_DEVICES := sl3000-emmc
endef
TARGET_DEVICES += sl3000-emmc
