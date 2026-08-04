TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Music SpringBoard
# Default rootless; CI / local builds override with THEOS_PACKAGE_SCHEME=roothide
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SwiftPeek

SwiftPeek_FILES = Tweak.x \
	src/SPPrefs.m \
	src/SPSwiftMeta.m \
	src/SPDumpWriter.m

SwiftPeek_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -DDISABLE_ROOTLESS_COMPAT_WARNING=1
SwiftPeek_FRAMEWORKS = UIKit Foundation
SwiftPeek_LIBRARIES =

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	@cp -f layout/Library/PreferenceLoader/Preferences/SwiftPeek.plist \
		"$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/"
