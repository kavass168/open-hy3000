define Device/sl3000-emmc
  DEVICE_VENDOR := SL
  DEVICE_MODEL := SL3000 (EMMC)
  DEVICE_DTS := mt7981-sl3000-emmc
  DEVICE_PACKAGES := \
	kmod-mt7981-firmware \
	kmod-mt76-connac-lib \
	kmod-mt7915e \
	kmod-leds-gpio \
	kmod-gpio-button-hotplug
endef
TARGET_DEVICES += sl3000-emmc
