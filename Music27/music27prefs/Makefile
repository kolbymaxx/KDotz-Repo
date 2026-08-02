TARGET := iphone:clang:16.5:15.0
# Must include arm64e — RootHide/jbroot Settings loads PreferenceBundles as arm64e.
# (Hardcoding arm64-only broke Music27Prefs: "have arm64, need arm64e".)
ARCHS = arm64 arm64e

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
