# Drivere bygget med kjernen.
{
  xone,
  xpadneo,
  msi-ec,
}:
''
  cp -r ${xone}/{auth,bus,driver,transport} drivers/input/joystick/xone/
  sed 's/^obj-m :=/obj-$(CONFIG_JOYSTICK_XONE) +=/' ${xone}/Kbuild > drivers/input/joystick/xone/Makefile

  cp -r ${xpadneo}/hid-xpadneo/src/xpadneo drivers/hid/xpadneo/
  sed -e 's/^obj-m +=/obj-$(CONFIG_HID_XPADNEO) +=/' \
      -e "s/-DVERSION=\$(VERSION)/-DVERSION=$(< ${xpadneo}/VERSION)/" \
      ${xpadneo}/hid-xpadneo/src/Makefile > drivers/hid/xpadneo/Makefile

  rm drivers/platform/x86/msi-ec.h
  cp ${msi-ec}/msi-ec.c ${msi-ec}/ec_memory_configuration.h drivers/platform/x86/
  chmod -R u+w drivers/input/joystick/xone drivers/hid/xpadneo drivers/platform/x86
  patch -p1 < ${./patches/msi-ec.patch}
''
