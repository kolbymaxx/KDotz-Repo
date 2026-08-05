TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

# Default rootless; CI / local builds override with THEOS_PACKAGE_SCHEME=roothide
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CC27

CC27_FILES = \
	src/Tweak.x \
	src/CC27Prefs.m \
	src/CC27Glass.m \
	src/CC27LayoutStore.m \
	src/CC27ModuleCatalog.m \
	src/CC27EditSession.m \
	src/CC27GalleryController.m

CC27_CFLAGS = -fobjc-arc -Iheaders -Isrc -Wno-unused-variable -Wno-deprecated-declarations
CC27_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreFoundation
# Private CC frameworks are resolved at runtime via NSClassFromString / Logos %hook.

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs provider
include $(THEOS_MAKE_PATH)/aggregate.mk
