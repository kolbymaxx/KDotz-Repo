# GrokAgent — rootless Theos tweak
# Build:   make package
# Install: make do   (set THEOS_DEVICE_IP first)
#
# For a roothide build, use the roothide Theos fork and:
#   THEOS_PACKAGE_SCHEME=roothide make package

export THEOS_PACKAGE_SCHEME ?= rootless

TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

# Set your device here or export THEOS_DEVICE_IP in your shell
THEOS_DEVICE_IP ?= 192.168.1.231
THEOS_DEVICE_PORT ?= 22

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GrokAgent

GrokAgent_FILES = Tweak.x $(wildcard Sources/*.m)
GrokAgent_CFLAGS = -fobjc-arc -IHeaders -ISources -Wno-deprecated-declarations
GrokAgent_FRAMEWORKS = UIKit Foundation CoreGraphics AVFoundation
GrokAgent_PRIVATE_FRAMEWORKS =
GrokAgent_LIBRARIES =

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
