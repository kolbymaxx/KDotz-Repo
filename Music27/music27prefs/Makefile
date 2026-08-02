TARGET := iphone:clang:16.5:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Music27Prefs

Music27Prefs_FILES = Music27RootListController.m
Music27Prefs_FRAMEWORKS = UIKit
Music27Prefs_PRIVATE_FRAMEWORKS = Preferences
Music27Prefs_INSTALL_PATH = /Library/PreferenceBundles
Music27Prefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Music27.plist$(ECHO_END)
