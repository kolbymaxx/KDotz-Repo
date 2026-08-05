TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard
# Default rootless; CI / local builds override with THEOS_PACKAGE_SCHEME=roothide
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Aether

Aether_FILES = Tweak.x \
	Shared/AEPrefs.m \
	Shared/AEClipboardStore.m \
	Shared/AESculptStore.m \
	Shared/AEScreenLens.m \
	Shared/AEGlassPanel.m \
	Shared/AEGestureHost.m

Aether_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -DDISABLE_ROOTLESS_COMPAT_WARNING=1
Aether_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Vision

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	@cp -f layout/Library/PreferenceLoader/Preferences/Aether.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/"
