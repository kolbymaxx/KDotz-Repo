TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CC27Prefs

CC27Prefs_FILES = CC27RootListController.m
CC27Prefs_FRAMEWORKS = UIKit
CC27Prefs_PRIVATE_FRAMEWORKS = Preferences
CC27Prefs_INSTALL_PATH = /Library/PreferenceBundles
CC27Prefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CC27.plist$(ECHO_END)
