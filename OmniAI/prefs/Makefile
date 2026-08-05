include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OmniAIPrefs

OmniAIPrefs_FILES = OmniAIRootListController.m OmniAILoginController.m ../Sources/OmniAIKeychain.m
OmniAIPrefs_INSTALL_PATH = /Library/PreferenceBundles
OmniAIPrefs_FRAMEWORKS = UIKit WebKit SafariServices Security
OmniAIPrefs_PRIVATE_FRAMEWORKS = Preferences
OmniAIPrefs_CFLAGS = -fobjc-arc -I../Headers -I../Sources

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/OmniAI.plist$(ECHO_END)
