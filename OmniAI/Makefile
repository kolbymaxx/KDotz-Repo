# OmniAI — system-wide AI for iOS 16–18 (rootless)
# Build:   make package
# Install: make do   (set THEOS_DEVICE_IP first)
#
# For a roothide build, use the roothide Theos fork and:
#   THEOS_PACKAGE_SCHEME=roothide make package

export THEOS_PACKAGE_SCHEME ?= rootless

TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_DEVICE_IP ?= 192.168.1.231
THEOS_DEVICE_PORT ?= 22

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OmniAI

OmniAI_FILES = Tweak.x $(wildcard Sources/*.m)
OmniAI_CFLAGS = -fobjc-arc -IHeaders -ISources -Wno-deprecated-declarations
OmniAI_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore WebKit SafariServices Security
OmniAI_PRIVATE_FRAMEWORKS =
OmniAI_LIBRARIES =

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
