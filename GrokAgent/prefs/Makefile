include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GrokAgentPrefs

GrokAgentPrefs_FILES = GAPrefsRootListController.m
GrokAgentPrefs_INSTALL_PATH = /Library/PreferenceBundles
GrokAgentPrefs_FRAMEWORKS = UIKit
GrokAgentPrefs_PRIVATE_FRAMEWORKS = Preferences
GrokAgentPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/GrokAgent.plist$(ECHO_END)
