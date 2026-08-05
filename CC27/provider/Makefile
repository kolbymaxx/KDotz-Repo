TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CC27Provider

CC27Provider_FILES = CC27Provider.m CC27ActionModule.m
CC27Provider_CFLAGS = -fobjc-arc -I../headers
CC27Provider_FRAMEWORKS = UIKit Foundation CoreGraphics
CC27Provider_INSTALL_PATH = /Library/ControlCenter/CCSupport_Providers
CC27Provider_BUNDLE_EXTENSION = bundle

include $(THEOS_MAKE_PATH)/bundle.mk
