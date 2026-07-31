TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard SiriViewService
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = FloatingSiri

FloatingSiri_FILES = Tweak.x \
	SwiftUIWave/Models/SiriWave.swift \
	SwiftUIWave/Views/SupportLine.swift \
	SwiftUIWave/Views/WaveView.swift \
	SwiftUIWave/Views/SiriWaveView.swift \
	SwiftUIWave/Views/SiriMetalView.swift \
	SwiftUIWave/WaveManager.swift \
	Shared/LGSharedSupport.m \
	Shared/LGHookSupport.m \
	Shared/LGBannerCaptureSupport.m \
	Shared/LGMetalShaderSource.m \
	Shared/LGGlassRenderer.m \
	Shared/LGBackButtonSupport.m \
	Shared/LGRWBSupport.m \
	Runtime/LGLiquidGlassRuntime.m \
	Runtime/LGSnapshotCaptureSupport.m

FloatingSiri_SWIFTFLAGS = -swift-version 5
FloatingSiri_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -DFLOATINGSIRI=1
FloatingSiri_FRAMEWORKS = UIKit Foundation SwiftUI AVFoundation Accelerate AudioToolbox MetalKit CoreMotion

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	@cp -f layout/Library/PreferenceLoader/Preferences/FloatingSiri.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/"
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/Application Support/FloatingSiri.bundle"
	@if command -v xcrun >/dev/null 2>&1; then \
		xcrun -sdk iphoneos metal -c Shared/SiriWave.metal -o "$(THEOS_STAGING_DIR)/Library/Application Support/FloatingSiri.bundle/SiriWave.air" && \
		xcrun -sdk iphoneos metallib "$(THEOS_STAGING_DIR)/Library/Application Support/FloatingSiri.bundle/SiriWave.air" -o "$(THEOS_STAGING_DIR)/Library/Application Support/FloatingSiri.bundle/default.metallib" && \
		rm -f "$(THEOS_STAGING_DIR)/Library/Application Support/FloatingSiri.bundle/SiriWave.air"; \
	fi
