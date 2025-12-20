
define Device/sl3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := SL3000
  DEVICE_VARIANT := EMMC
  DEVICE_DTS := mt7981-sl3000-emmc
  DEVICE_PACKAGES := kmod-mt7531 kmod-dsa kmod-dsa-mt7530 kmod-usb3 kmod-usb2 kmod-leds-gpio
  SUPPORTED_DEVICES := sl3000
endef
TARGET_DEVICES += sl3000-emmc
