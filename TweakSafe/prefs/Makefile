TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = TweakSafePrefs

TweakSafePrefs_FILES = TweakSafeRootListController.m
TweakSafePrefs_FRAMEWORKS = UIKit Foundation
TweakSafePrefs_PRIVATE_FRAMEWORKS = Preferences
TweakSafePrefs_INSTALL_PATH = /Library/PreferenceBundles
TweakSafePrefs_CFLAGS = -fobjc-arc -DDISABLE_ROOTLESS_COMPAT_WARNING=1

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/TweakSafe.plist$(ECHO_END)
