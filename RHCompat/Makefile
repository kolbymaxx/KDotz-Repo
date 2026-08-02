TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

# RootHide-only package. Do not build with THEOS_PACKAGE_SCHEME=rootless.
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

# Leading 000 so TweakInject/ElleKit loads us before most tweaks (alpha order).
TWEAK_NAME = 000RHCompat

000RHCompat_FILES = \
	src/Tweak.x \
	src/PathShim.m \
	src/PrefsBridge.m

000RHCompat_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -DDISABLE_ROOTLESS_COMPAT_WARNING=1
000RHCompat_FRAMEWORKS = Foundation CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	@cp -f layout/Library/PreferenceLoader/Preferences/RHCompat.plist \
		"$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/"
