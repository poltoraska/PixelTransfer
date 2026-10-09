#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mtp_prefix=$(brew --prefix libmtp)
usb_prefix=$(brew --prefix libusb)
mkdir -p MyApp/Libraries.bundle MyApp/Native
cp "$mtp_prefix/include/libmtp.h" MyApp/Native/libmtp.h
cp "$mtp_prefix/lib/libmtp.9.dylib" MyApp/Libraries.bundle/
cp "$usb_prefix/lib/libusb-1.0.0.dylib" MyApp/Libraries.bundle/
install_name_tool -id '@loader_path/libmtp.9.dylib' \
  -change "$usb_prefix/lib/libusb-1.0.0.dylib" '@loader_path/libusb-1.0.0.dylib' \
  MyApp/Libraries.bundle/libmtp.9.dylib
install_name_tool -id '@loader_path/libusb-1.0.0.dylib' MyApp/Libraries.bundle/libusb-1.0.0.dylib
codesign --force --sign - MyApp/Libraries.bundle/libusb-1.0.0.dylib
codesign --force --sign - MyApp/Libraries.bundle/libmtp.9.dylib
