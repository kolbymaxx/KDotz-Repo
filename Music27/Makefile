TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Music Preferences

# Default rootless; CI / local builds override with THEOS_PACKAGE_SCHEME=roothide
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Music27

Music27_FILES = \
	src/Tweak.x \
	src/GlassTabBar.x \
	src/AlbumControls.x \
	src/ColorTheme.x \
	src/LibraryPins.x \
	src/Helpers.m \
	src/M27GlassChrome.m \
	src/M27FloatingDock.m \
	src/M27Prefs.m \
	src/M27ColorTheme.m \
	src/M27PinStore.m \
	src/M27PinnedHeaderView.m

Music27_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
Music27_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore MediaPlayer CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += music27prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
