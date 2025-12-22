define Device/sl3000-emmc
  DEVICE_TITLE := SL3000 (EMMC)
  DEVICE_DTS := mediatek/mt7981-sl3000-emmc
  DEVICE_PACKAGES := \
        kmod-mt7981-firmware \
        kmod-mt76-connac-lib \
        kmod-mt7915e \
        kmod-usb3 \
        kmod-usb2 \
        kmod-usb-ledtrig-usbport \
        kmod-leds-gpio \
        kmod-gpio-button-hotplug
endef
TARGET_DEVICES += sl3000-emmc
