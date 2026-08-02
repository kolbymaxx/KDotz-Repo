TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

# RootHide-only
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
