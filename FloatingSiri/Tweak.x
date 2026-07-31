#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <notify.h>
#import "LiquidGlass.h"
#import "Shared/LGBannerCaptureSupport.h"
#import "Runtime/LGSnapshotCaptureSupport.h"
#import "FloatingSiri-Swift.h"

// -----------------------------------------------------------------------------
// FloatingSiri — iOS 27-style liquid glass Siri orb
// Orb geometry / motion ported 1:1 from LiquidSiri (Thijs) — proven look.
// Audio pipeline (mic gain / deadzone / talkingFactor) is the FloatingSiri fix.
// -----------------------------------------------------------------------------

@interface SiriUIBackgroundBlurViewController : UIViewController
@end

@interface SBAssistantRootViewController : UIViewController
@end

@interface SUICOrbView : UIView
@end

@interface SiriSharedUIOrbView : UIView
@end

@interface SUICFlamesView : UIView
@end

@interface SiriUIFlamesView : UIView
@end

@interface SiriWaveformView : UIView
@end

@interface SiriListeningView : UIView
@end

@interface AFUISiriSession : NSObject
@end

@interface VSSpeechSynthesizer : NSObject
@end

static NSInteger globalSiriState = 1;
static NSString * const kFSPrefsDomain = @"com.kolby.floatingsiri";
static const char *kFSDarwinLevel = "com.kolby.floatingsiri/level";

OBJC_EXTERN UIImage *_UICreateScreenUIImage(void);

// -----------------------------------------------------------------------------
// Jailbreak root resolution — supports rootful (""), rootless ("/var/jb") and
// roothide (randomized "/var/containers/Bundle/Application/.jbroot-XXXX").
// Derived from where OUR dylib was injected from, so no scheme guessing.
// -----------------------------------------------------------------------------
static NSString *FSJailbreakRootPrefix(void) {
    static NSString *prefix = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefix = @"";
        // Prefer roothide's own resolver when it's loaded in this process
        const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
        if (jbrootFn) {
            const char *p = jbrootFn("/");
            if (p && strlen(p) > 1) {
                prefix = [[NSString stringWithUTF8String:p] stringByStandardizingPath];
                return;
            }
        }
        // Fall back to parsing this dylib's install path
        Dl_info info = {0};
        if (dladdr((const void *)FSJailbreakRootPrefix, &info) && info.dli_fname) {
            NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
            for (NSString *marker in @[@"/Library/MobileSubstrate/DynamicLibraries/",
                                       @"/usr/lib/TweakInject/"]) {
                NSRange r = [dylibPath rangeOfString:marker];
                if (r.location != NSNotFound && r.location > 0) {
                    prefix = [dylibPath substringToIndex:r.location];
                    return;
                }
            }
        }
    });
    return prefix;
}

// -----------------------------------------------------------------------------
// Prefs
// -----------------------------------------------------------------------------
static NSDictionary *FSPrefs(void) {
    static NSDictionary *cached = nil;
    static CFAbsoluteTime lastLoad = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (cached && (now - lastLoad) < 0.5) return cached;

    NSString *rel = @"/var/mobile/Library/Preferences/com.kolby.floatingsiri.plist";
    NSMutableArray *paths = [NSMutableArray array];
    NSString *jbPrefix = FSJailbreakRootPrefix();
    if (jbPrefix.length) [paths addObject:[jbPrefix stringByAppendingString:rel]];
    [paths addObject:[@"/var/jb" stringByAppendingString:rel]];
    [paths addObject:rel];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) { cached = d; lastLoad = now; return cached; }
    }
    cached = @{};
    lastLoad = now;
    return cached;
}

static BOOL FSPrefBool(NSString *key, BOOL fallback) {
    id v = FSPrefs()[key];
    return v ? [v boolValue] : fallback;
}

static CGFloat FSPrefFloat(NSString *key, CGFloat fallback) {
    id v = FSPrefs()[key];
    return v ? [v doubleValue] : fallback;
}

// -----------------------------------------------------------------------------
// Audio level bridge (working — do not regress)
// -----------------------------------------------------------------------------
static void FSSendLevel(float level) {
    [[WaveManager shared] updateTargetPower:@(level)];

    notify_post(kFSDarwinLevel);
    int token = 0;
    if (notify_register_check(kFSDarwinLevel, &token) == NOTIFY_STATUS_OK) {
        uint64_t packed = 0;
        memcpy(&packed, &level, sizeof(float));
        notify_set_state(token, packed);
        notify_cancel(token);
    }
}

static void FSDarwinLevelCallback(CFNotificationCenterRef center, void *observer,
                                  CFStringRef name, const void *object,
                                  CFDictionaryRef userInfo) {
    int token = 0;
    if (notify_register_check(kFSDarwinLevel, &token) != NOTIFY_STATUS_OK) return;
    uint64_t state = 0;
    notify_get_state(token, &state);
    notify_cancel(token);
    float level = 0;
    memcpy(&level, &state, sizeof(float));
    [[WaveManager shared] updateTargetPower:@(level)];
}

static BOOL FSIsSiriSpeaking(id optionalDelegate) {
    if (globalSiriState == 3) return YES;
    @try {
        id audioSession = [NSClassFromString(@"AVAudioSession") sharedInstance];
        NSString *mode = [audioSession valueForKey:@"mode"];
        if ([mode isEqualToString:@"VoicePrompt"]) return YES;
    } @catch (__unused NSException *e) {}
    @try {
        if (optionalDelegate && [optionalDelegate respondsToSelector:@selector(isSpeaking)]) {
            if ([[optionalDelegate valueForKey:@"isSpeaking"] boolValue]) return YES;
        }
    } @catch (__unused NSException *e) {}
    return NO;
}

static float FSNormalizeAudioLevel(float level) {
    if (!isfinite(level)) return 0;
    if (level < 0) {
        level = powf(10.0f, fmaxf(level, -120.0f) / 20.0f);
    } else if (level > 1.5f) {
        level = level / 100.0f;
    }
    return fminf(1.0f, fmaxf(0.0f, level));
}

static void FSAttachFlamesPoll(UIView *viewSelf, SEL pollSel) {
    if (!viewSelf.window) {
        CADisplayLink *link = objc_getAssociatedObject(viewSelf, pollSel);
        [link invalidate];
        objc_setAssociatedObject(viewSelf, pollSel, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    CADisplayLink *existing = objc_getAssociatedObject(viewSelf, pollSel);
    if (existing) return;
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:viewSelf selector:pollSel];
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(viewSelf, pollSel, link, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void FSPollFlames(id objSelf) {
    id delegate = nil;
    @try {
        if ([objSelf respondsToSelector:@selector(flamesDelegate)]) {
            delegate = [objSelf valueForKey:@"flamesDelegate"];
        } else if ([objSelf respondsToSelector:@selector(delegate)]) {
            delegate = [objSelf valueForKey:@"delegate"];
        }
    } @catch (__unused NSException *e) {}

    float level = 0;
    BOOL got = NO;
    if (delegate && [delegate respondsToSelector:@selector(audioLevelForFlamesView:)]) {
        level = ((float (*)(id, SEL, id))objc_msgSend)(delegate, @selector(audioLevelForFlamesView:), objSelf);
        got = YES;
    } else if ([objSelf respondsToSelector:@selector(audioLevel)]) {
        @try { level = [[objSelf valueForKey:@"audioLevel"] floatValue]; got = YES; } @catch (__unused NSException *e) {}
    }
    if (!got) return;

    level = FSNormalizeAudioLevel(level);
    if (FSIsSiriSpeaking(delegate)) level = 0;
    FSSendLevel(level);
}

// -----------------------------------------------------------------------------
// Backdrop capture (wallpaper preferred; normalized to physical portrait pixels)
// In-process screen captures return BLACK frames inside SiriViewService on many
// jailbreaks, so SpringBoard captures and shares via a cache file, and every
// candidate is luminance-checked before it can reach the glass shader.
// -----------------------------------------------------------------------------
static NSString *FSBackdropDirectory(void) {
    NSMutableArray *roots = [NSMutableArray array];
    NSString *jbPrefix = FSJailbreakRootPrefix();
    if (jbPrefix.length) [roots addObject:[jbPrefix stringByAppendingString:@"/var/mobile/Library/Caches"]];
    [roots addObject:@"/var/jb/var/mobile/Library/Caches"];
    [roots addObject:@"/var/mobile/Library/Caches"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in roots) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:root isDirectory:&isDir] && isDir) {
            NSString *dir = [root stringByAppendingPathComponent:@"com.kolby.floatingsiri"];
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
            return dir;
        }
    }
    return nil;
}

static NSString *FSBackdropFilePath(void) {
    NSString *dir = FSBackdropDirectory();
    return dir ? [dir stringByAppendingPathComponent:@"backdrop.jpg"] : nil;
}

// Downscale and average luminance — reject effectively-black frames.
static BOOL FSImageLooksBlack(UIImage *image) {
    if (!image || !image.CGImage) return YES;
    const size_t sample = 16;
    uint8_t pixels[sample * sample * 4];
    memset(pixels, 0, sizeof(pixels));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, sample, sample, 8, sample * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return YES;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, sample, sample), image.CGImage);
    CGContextRelease(ctx);

    double total = 0;
    for (size_t i = 0; i < sample * sample; i++) {
        double r = pixels[i*4 + 0] / 255.0;
        double g = pixels[i*4 + 1] / 255.0;
        double b = pixels[i*4 + 2] / 255.0;
        total += 0.299*r + 0.587*g + 0.114*b;
    }
    double mean = total / (double)(sample * sample);
    return mean < 0.04;
}

// Soft dark-blue gradient so the orb reads as tinted glass, never a solid pill.
static UIImage *FSFallbackGradientImage(void) {
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGSize px = CGSizeMake(screen.width * scale, screen.height * scale);
    UIGraphicsBeginImageContextWithOptions(px, YES, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[] = {
        0.16, 0.20, 0.32, 1.0,
        0.10, 0.11, 0.20, 1.0,
        0.05, 0.05, 0.10, 1.0
    };
    CGFloat locs[] = { 0.0, 0.55, 1.0 };
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, locs, 3);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(px.width * 0.3, 0), CGPointMake(px.width * 0.7, px.height), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static UIImage *FSNormalizeToScreen(UIImage *raw) {
    if (!raw) return nil;
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGSize expected = CGSizeMake(screen.width * scale, screen.height * scale);
    CGImageRef cg = raw.CGImage;
    if (!cg) return raw;
    size_t cgW = CGImageGetWidth(cg);
    size_t cgH = CGImageGetHeight(cg);
    BOOL needsRotation = (cgW > cgH) && (expected.height > expected.width);
    BOOL needsScaling = (cgW != (size_t)expected.width) || (cgH != (size_t)expected.height);
    if (!needsRotation && !needsScaling) {
        return [UIImage imageWithCGImage:cg scale:1.0 orientation:UIImageOrientationUp];
    }

    UIGraphicsBeginImageContextWithOptions(expected, NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (needsRotation) {
        CGContextTranslateCTM(ctx, expected.width/2.0, expected.height/2.0);
        CGContextRotateCTM(ctx, M_PI_2);
        CGContextDrawImage(ctx, CGRectMake(-expected.height/2.0, -expected.width/2.0, expected.height, expected.width), cg);
    } else {
        CGContextDrawImage(ctx, CGRectMake(0, 0, expected.width, expected.height), cg);
    }
    UIImage *tmp = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    UIGraphicsBeginImageContextWithOptions(expected, NO, 1.0);
    ctx = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(ctx, 0, expected.height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
    [tmp drawInRect:CGRectMake(0, 0, expected.width, expected.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

static UIImage *FSWallpaperControllerImage(void) {
    @try {
        Class cls = NSClassFromString(@"SBWallpaperController");
        id ctrl = [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
        if (!ctrl) return nil;
        NSArray *sels = @[ @"wallpaperImageForVariant:", @"homescreenWallpaperImage", @"legacyWallpaperImage" ];
        for (NSString *selName in sels) {
            SEL sel = NSSelectorFromString(selName);
            if (![ctrl respondsToSelector:sel]) continue;
            UIImage *img = nil;
            if ([selName hasSuffix:@":"]) {
                img = ((UIImage *(*)(id, SEL, long long))objc_msgSend)(ctrl, sel, 1);
            } else {
                img = ((UIImage *(*)(id, SEL))objc_msgSend)(ctrl, sel);
            }
            if ([img isKindOfClass:[UIImage class]] && img.size.width > 2) {
                return FSNormalizeToScreen(img);
            }
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

static UIImage *FSScreenCaptureImage(void) {
    UIImage *raw = nil;
    @try { raw = _UICreateScreenUIImage(); } @catch (__unused NSException *e) {}
    return FSNormalizeToScreen(raw);
}

// SpringBoard writes its (working) capture here so SiriViewService can use it.
static void FSWriteSharedBackdrop(UIImage *image) {
    if (!image || FSImageLooksBlack(image)) return;
    NSString *path = FSBackdropFilePath();
    if (!path) return;
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.85);
    if (jpeg.length > 0) {
        [jpeg writeToFile:path atomically:YES];
    }
}

static UIImage *FSReadSharedBackdrop(BOOL requireFresh) {
    NSString *path = FSBackdropFilePath();
    if (!path) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return nil;
    if (requireFresh) {
        NSDate *mtime = [[fm attributesOfItemAtPath:path error:NULL] fileModificationDate];
        if (!mtime || [[NSDate date] timeIntervalSinceDate:mtime] > 10.0) return nil;
    }
    UIImage *img = [UIImage imageWithContentsOfFile:path];
    if (!img || FSImageLooksBlack(img)) return nil;
    return img;
}

// Returns a usable (non-black) backdrop or nil. Caller decides on fallback.
static UIImage *FSCaptureBackdropImage(void) {
    UIImage *img = FSWallpaperControllerImage();
    if (img && !FSImageLooksBlack(img)) return img;

    img = FSReadSharedBackdrop(YES);
    if (img) return img;

    img = FSScreenCaptureImage();
    if (img && !FSImageLooksBlack(img)) return img;

    // Stale shared backdrop still beats a black frame
    return FSReadSharedBackdrop(NO);
}

// -----------------------------------------------------------------------------
// Orb host state — attached per host VC (LiquidSiri geometry, verbatim)
// -----------------------------------------------------------------------------
static const void *kFSOrbBackdropViewKey = &kFSOrbBackdropViewKey;

@interface FSOrbState : NSObject
@property (nonatomic, strong) LiquidGlassView *glassOrbView;
@property (nonatomic, strong) UIView *glowLineView;
@property (nonatomic, strong) UIView *externalWhiteGlowView;
@property (nonatomic, strong) UIImage *capturedWallpaper;
@property (nonatomic, assign) BOOL hasCapturedBackdrop;
// Live glass (real see-through refraction, liquidass banner technique)
@property (nonatomic, strong) CADisplayLink *liveLink;
@property (nonatomic, assign) CFTimeInterval lastLiveCapture;
@property (nonatomic, assign) NSInteger liveFailCount;
@property (nonatomic, assign) NSInteger liveProbeCount;
@property (nonatomic, assign) NSInteger liveBlackProbes;
@property (nonatomic, assign) NSInteger liveIdleTicks;
@property (nonatomic, assign) BOOL liveConfirmed;
- (void)fsLiveTick:(CADisplayLink *)link;
- (void)fsStopLiveCapture;
- (void)fsFallBackToSnapshot;
@end

// Probe the backdrop view's actual content — if it renders black, live capture
// doesn't work in this process and we must fall back to snapshots.
static BOOL FSBackdropViewLooksBlack(UIView *backdropView) {
    if (!backdropView) return YES;
    const size_t sample = 16;
    uint8_t pixels[sample * sample * 4];
    memset(pixels, 0, sizeof(pixels));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, sample, sample, 8, sample * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return YES;
    CGRect bounds = backdropView.bounds;
    if (bounds.size.width < 1 || bounds.size.height < 1) { CGContextRelease(ctx); return YES; }
    CGContextTranslateCTM(ctx, 0, sample);
    CGContextScaleCTM(ctx, sample / bounds.size.width, -(CGFloat)sample / bounds.size.height);
    UIGraphicsPushContext(ctx);
    LGDrawViewHierarchyIntoCurrentContext(backdropView, bounds, NO);
    UIGraphicsPopContext();
    CGContextRelease(ctx);

    double total = 0;
    for (size_t i = 0; i < sample * sample; i++) {
        double r = pixels[i*4 + 0] / 255.0;
        double g = pixels[i*4 + 1] / 255.0;
        double b = pixels[i*4 + 2] / 255.0;
        total += 0.299*r + 0.587*g + 0.114*b;
    }
    return (total / (double)(sample * sample)) < 0.03;
}

@implementation FSOrbState

- (void)fsLiveTick:(CADisplayLink *)link {
    LiquidGlassView *glass = self.glassOrbView;
    if (!glass || !glass.window || glass.hidden) {
        // Safety: never let the link spin forever on a dead host (~20s at 60Hz)
        if (++self.liveIdleTicks > 1200) [self fsStopLiveCapture];
        return;
    }
    self.liveIdleTicks = 0;

    CGFloat fps = MAX(8.0, MIN(60.0, FSPrefFloat(@"liveGlassFPS", 24.0)));
    CFTimeInterval now = CACurrentMediaTime();
    if (self.lastLiveCapture > 0 && (now - self.lastLiveCapture) < (1.0 / fps)) return;
    self.lastLiveCapture = now;

    CGPoint origin = CGPointZero;
    CGSize sampling = CGSizeZero;
    BOOL ok = LGCaptureLiveBackdropTextureForHost(glass, glass, kFSOrbBackdropViewKey, &origin, &sampling);

    // Keep the feed view BELOW the white bottom-glow so the glow's blur is never
    // part of the captured backdrop (it was washing out the glass and rainbow).
    UIView *backdropView = objc_getAssociatedObject(glass, kFSOrbBackdropViewKey);
    UIView *glow = self.externalWhiteGlowView;
    if (backdropView && glow && backdropView.superview && backdropView.superview == glow.superview) {
        NSArray *siblings = backdropView.superview.subviews;
        NSInteger bIdx = [siblings indexOfObjectIdenticalTo:backdropView];
        NSInteger gIdx = [siblings indexOfObjectIdenticalTo:glow];
        if (bIdx != NSNotFound && gIdx != NSNotFound && bIdx > gIdx) {
            [backdropView.superview insertSubview:backdropView belowSubview:glow];
        }
    }

    if (ok) {
        glass.wallpaperOrigin = origin;
        glass.wallpaperSamplingResolution = sampling;
        [glass updateOrigin];
        [glass scheduleDraw];
        self.liveFailCount = 0;

        // Confirm the backdrop actually contains pixels (not a black plate)
        if (!self.liveConfirmed && self.liveProbeCount < 12) {
            self.liveProbeCount++;
            UIView *backdropView = objc_getAssociatedObject(glass, kFSOrbBackdropViewKey);
            if (FSBackdropViewLooksBlack(backdropView)) {
                self.liveBlackProbes++;
            } else {
                self.liveConfirmed = YES;
            }
            if (self.liveProbeCount >= 12 && !self.liveConfirmed) {
                [self fsFallBackToSnapshot];
            }
        }
    } else {
        self.liveFailCount++;
        if (self.liveFailCount > 45) {
            [self fsFallBackToSnapshot];
        }
    }
}

- (void)fsStopLiveCapture {
    [self.liveLink invalidate];
    self.liveLink = nil;
    if (self.glassOrbView) {
        LGRemoveLiveBackdropCaptureView(self.glassOrbView, kFSOrbBackdropViewKey);
    }
}

- (void)fsFallBackToSnapshot {
    [self fsStopLiveCapture];
    LiquidGlassView *glass = self.glassOrbView;
    if (!glass) return;
    glass.wallpaperSamplingResolution = CGSizeZero;
    UIImage *img = self.capturedWallpaper ?: FSCaptureBackdropImage();
    if (img) {
        self.capturedWallpaper = img;
        self.hasCapturedBackdrop = YES;
        glass.wallpaperImage = img;
    } else {
        glass.wallpaperImage = FSFallbackGradientImage();
    }
    glass.wallpaperOrigin = CGPointZero;
    [glass updateOrigin];
    [glass scheduleDraw];
}

@end

static const void *kFSOrbStateKey = &kFSOrbStateKey;

static FSOrbState *FSOrbStateFor(UIViewController *vc) {
    FSOrbState *state = objc_getAssociatedObject(vc, kFSOrbStateKey);
    if (!state) {
        state = [FSOrbState new];
        objc_setAssociatedObject(vc, kFSOrbStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void FSOrbViewDidLoad(UIViewController *vc) {
    FSOrbState *st = FSOrbStateFor(vc);
    if (st.glassOrbView) return;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat width = 154.0;
    CGFloat height = 105.0;
    CGRect orbFrame = CGRectMake((screenBounds.size.width - width)/2.0, 35, width, height);

    UIGraphicsBeginImageContextWithOptions(screenBounds.size, NO, 0.0);
    UIImage *tempBg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    st.glassOrbView = [[LiquidGlassView alloc] initWithFrame:orbFrame wallpaper:tempBg wallpaperOrigin:CGPointZero];
    st.glassOrbView.updateGroup = 255; // Unregistered group so liquidass prefs can't overwrite

    st.glassOrbView.refractionScale = 1.4;
    st.glassOrbView.refractiveIndex = 1.15;
    st.glassOrbView.specularOpacity = 1.0;
    st.glassOrbView.blur = 0.0;
    st.glassOrbView.bezelWidth = 24.0;
    st.glassOrbView.glassThickness = 120.0;

    st.glassOrbView.layer.shadowColor = [UIColor blackColor].CGColor;
    st.glassOrbView.layer.shadowOffset = CGSizeMake(0, 6);
    st.glassOrbView.layer.shadowOpacity = 0.4;
    st.glassOrbView.layer.shadowRadius = 12;
    [vc.view addSubview:st.glassOrbView];

    st.externalWhiteGlowView = [[UIView alloc] initWithFrame:CGRectMake(orbFrame.origin.x + width * 0.15, orbFrame.origin.y + height - 35.0, width * 0.7, 30.0)];
    st.externalWhiteGlowView.backgroundColor = [UIColor clearColor];
    UIBezierPath *shadowPath = [UIBezierPath bezierPathWithOvalInRect:st.externalWhiteGlowView.bounds];
    st.externalWhiteGlowView.layer.shadowPath = shadowPath.CGPath;
    st.externalWhiteGlowView.layer.shadowColor = [UIColor whiteColor].CGColor;
    st.externalWhiteGlowView.layer.shadowOffset = CGSizeZero;
    st.externalWhiteGlowView.layer.shadowOpacity = 0.65;
    st.externalWhiteGlowView.layer.shadowRadius = 12.0;
    st.externalWhiteGlowView.alpha = 0.0;
    [vc.view insertSubview:st.externalWhiteGlowView belowSubview:st.glassOrbView];

    st.glowLineView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    st.glowLineView.backgroundColor = [UIColor clearColor];
    st.glowLineView.clipsToBounds = NO;
    [st.glassOrbView addSubview:st.glowLineView];

    st.glassOrbView.alpha = 0.0;
}

static void FSOrbViewWillAppear(UIViewController *vc) {
    FSOrbState *st = FSOrbStateFor(vc);
    // Hide default Siri blur effects so they don't darken the screen behind the orb
    vc.view.backgroundColor = [UIColor clearColor];
    for (UIView *sub in vc.view.subviews) {
        if (sub == st.glassOrbView || sub == st.glowLineView || sub == st.externalWhiteGlowView) continue;
        // Never dim the live-capture backdrop feed
        if ([NSStringFromClass(sub.class) containsString:@"LGLiveBackdropCaptureView"]) continue;
        sub.alpha = 0.01; // DO NOT USE hidden=YES! iOS stops sending audio levels if hidden.
    }
}

static void FSOrbViewDidAppear(UIViewController *vc) {
    FSOrbState *st = FSOrbStateFor(vc);
    if (!st.glassOrbView) FSOrbViewDidLoad(vc);

    [[WaveManager shared] startRecording];
    [[WaveManager shared] reloadPrefs];

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat safeTop = vc.view.safeAreaInsets.top;
    if (safeTop == 0 && vc.view.window) { safeTop = vc.view.window.safeAreaInsets.top; }

    CGFloat width = 130.0;
    CGFloat height = 105.0;
    CGFloat physicalY = 31.0;

    if (safeTop >= 59.0) {
        // Dynamic Island devices — wraps the black dome around the island
        width = 180.0;
        height = 148.0;
        physicalY = 9.0;
    } else if (safeTop > 44.0) {
        // iPhone 12 / 13 (incl. mini)
        width = 144.0;
        height = 116.0;
        physicalY = 36.0;
    }

    CGFloat customYOffset = FSPrefFloat(@"yOffset", FSPrefFloat(@"topOffset", 0.0));
    CGFloat customScale = FSPrefFloat(@"orbScale", 1.0);
    CGFloat customWidth = FSPrefFloat(@"customWidth", 1.0);
    CGFloat customHeight = FSPrefFloat(@"customHeight", 1.0);
    CGFloat customCorner = FSPrefFloat(@"customCorner", 1.0);
    CGFloat customRefraction = FSPrefFloat(@"refractionScale", FSPrefFloat(@"customRefraction", 1.4));

    width *= customScale * customWidth;
    height *= customScale * customHeight;
    physicalY += customYOffset;

    CGFloat physicalX = (screenSize.width - width)/2.0;
    CGRect absoluteScreenFrame = CGRectMake(physicalX, physicalY, width, height);
    CGRect orbFrame = [vc.view convertRect:absoluteScreenFrame fromCoordinateSpace:[UIScreen mainScreen].coordinateSpace];

    st.glassOrbView.frame = orbFrame;
    CGFloat rawCorner = (height / 2.0) * customCorner;
    CGFloat maxCorner = MIN(width, height) / 2.0;
    st.glassOrbView.cornerRadius = MIN(rawCorner, maxCorner);
    st.glassOrbView.refractionScale = customRefraction;

    st.externalWhiteGlowView.frame = CGRectMake(orbFrame.origin.x + width * 0.15, orbFrame.origin.y + height - (35.0 * customScale), width * 0.7, 30.0 * customScale);
    UIBezierPath *newShadowPath = [UIBezierPath bezierPathWithOvalInRect:st.externalWhiteGlowView.bounds];
    st.externalWhiteGlowView.layer.shadowPath = newShadowPath.CGPath;
    st.externalWhiteGlowView.layer.shadowOpacity = FSPrefBool(@"glowEnabled", YES) ? FSPrefFloat(@"glowIntensity", 0.65) : 0.0;

    // Flawless coordinate math: wallpaperOrigin (0,0) gives a 1:1 physical screen match.
    st.glassOrbView.wallpaperOrigin = CGPointMake(0, 0);
    [st.glassOrbView updateOrigin];

    // Clean up to strictly prevent any double layers
    for (CALayer *sub in [st.glassOrbView.layer.sublayers copy]) {
        if ([sub isKindOfClass:[CAGradientLayer class]] || [sub.name isEqualToString:@"fs.blackDome"]) {
            [sub removeFromSuperlayer];
        }
    }

    // Solid black curved dome overlay — verbatim LiquidSiri geometry
    CGFloat domeOpacity = FSPrefFloat(@"domeOpacity", 0.95);
    CAShapeLayer *blackDomeLayer = [CAShapeLayer layer];
    blackDomeLayer.name = @"fs.blackDome";
    blackDomeLayer.frame = CGRectMake(0, 0, width, height);
    blackDomeLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:domeOpacity].CGColor;

    UIBezierPath *domePath = [UIBezierPath bezierPath];
    [domePath moveToPoint:CGPointMake(0, 0)];
    [domePath addLineToPoint:CGPointMake(width, 0)];
    [domePath addLineToPoint:CGPointMake(width, height * 0.55)];
    [domePath addQuadCurveToPoint:CGPointMake(0, height * 0.55) controlPoint:CGPointMake(width / 2.0, height * 0.52)];
    [domePath closePath];
    blackDomeLayer.path = domePath.CGPath;

    blackDomeLayer.shadowColor = [UIColor blackColor].CGColor;
    blackDomeLayer.shadowOffset = CGSizeZero;
    blackDomeLayer.shadowRadius = 10.0;
    blackDomeLayer.shadowOpacity = 1.0;

    CAGradientLayer *fadeMask = [CAGradientLayer layer];
    fadeMask.frame = blackDomeLayer.bounds;
    fadeMask.type = kCAGradientLayerRadial;
    fadeMask.colors = @[(id)[UIColor blackColor].CGColor,
                        (id)[UIColor blackColor].CGColor,
                        (id)[UIColor clearColor].CGColor];
    fadeMask.locations = @[@0.0, @0.65, @1.0];
    fadeMask.startPoint = CGPointMake(0.5, 0.0);
    fadeMask.endPoint = CGPointMake(1.24, 0.55);
    blackDomeLayer.mask = fadeMask;

    [st.glassOrbView.layer insertSublayer:blackDomeLayer below:st.glowLineView.layer];

    // Start hidden and tucked up inside the notch
    st.glassOrbView.hidden = YES;
    st.glassOrbView.alpha = 0.0;

    CGFloat orbOpacity = FSPrefFloat(@"orbOpacity", 1.0);

    void (^popIn)(void) = ^{
        st.glassOrbView.hidden = NO;
        [UIView animateWithDuration:0.6 delay:0.0 usingSpringWithDamping:0.7 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
            st.glassOrbView.transform = CGAffineTransformIdentity;
            st.glassOrbView.alpha = orbOpacity;
            st.externalWhiteGlowView.alpha = 1.0;
        } completion:^(BOOL finished) {
            // Gentle infinite breathing so the liquid feels alive
            CABasicAnimation *breatheAnim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            breatheAnim.fromValue = @(1.0);
            breatheAnim.toValue = @(1.03);
            breatheAnim.duration = 1.2;
            breatheAnim.autoreverses = YES;
            breatheAnim.repeatCount = HUGE_VALF;
            breatheAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [st.glassOrbView.layer addAnimation:breatheAnim forKey:@"orbBreathing"];
        }];
    };

    BOOL liveGlass = FSPrefBool(@"liveGlass", YES);
    if (liveGlass) {
        // TRUE liquid glass: a CABackdropLayer feed under the orb, redrawn into
        // the Metal texture every frame (liquidass banner technique). You see
        // what's actually behind the orb, live, with real refraction.
        st.liveProbeCount = 0;
        st.liveBlackProbes = 0;
        st.liveFailCount = 0;
        st.liveIdleTicks = 0;
        st.lastLiveCapture = 0;
        // Model geometry keeps the capture rect (and Metal texture size) stable
        // while the orb runs its pop-in / breathing transform animations.
        LGSetLiveBackdropCaptureUsesModelGeometry(st.glassOrbView, YES);
        if (!st.liveLink) {
            st.liveLink = [CADisplayLink displayLinkWithTarget:st selector:@selector(fsLiveTick:)];
            [st.liveLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        }
        // Seed a couple of captures, then pop in — no screenshot delay needed
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            popIn();
        });
    } else if (!st.hasCapturedBackdrop) {
        // 0.45s delay so iOS finishes the transition and resolves the full-res buffer
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIImage *img = FSCaptureBackdropImage();
            if (img) {
                // Good (non-black) capture — safe to cache for future invocations
                st.capturedWallpaper = img;
                st.glassOrbView.wallpaperImage = img;
                st.hasCapturedBackdrop = YES;
            } else {
                // Never let a black frame reach the glass; use tinted-glass gradient
                // and DON'T mark as captured so the next invocation retries.
                st.glassOrbView.wallpaperImage = FSFallbackGradientImage();
            }
            popIn();
        });
    } else {
        if (st.capturedWallpaper) st.glassOrbView.wallpaperImage = st.capturedWallpaper;
        popIn();
    }

    // Reposition wave line with vertical breathing room
    st.glowLineView.frame = CGRectMake(0, 0, width, height);

    // Remove old wave views to prevent stacking / off-center bugs
    for (UIView *subview in st.glowLineView.subviews) {
        [subview removeFromSuperview];
    }

    UIView *swiftWave = [[WaveManager shared] createWaveViewWithFrame:st.glowLineView.bounds];
    swiftWave.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [st.glowLineView addSubview:swiftWave];
}

static void FSOrbViewWillDisappear(UIViewController *vc) {
    FSOrbState *st = FSOrbStateFor(vc);
    [st fsStopLiveCapture];
    [UIView animateWithDuration:0.35 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        st.glassOrbView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, -50), CGAffineTransformMakeScale(0.6, 0.6));
        st.glassOrbView.alpha = 0.0;
        st.externalWhiteGlowView.alpha = 0.0;
    } completion:nil];
}

void LG_registerGlassView(UIView *view, LGUpdateGroup group) {}
void LG_unregisterGlassView(UIView *view, LGUpdateGroup group) {}
void LG_updateRegisteredGlassViews(LGUpdateGroup group) {}
void LG_redrawRegisteredGlassViews(LGUpdateGroup group) {}

// -----------------------------------------------------------------------------
// Stock orb — hide visually, steal power levels
// -----------------------------------------------------------------------------
%group FSSUICOrb
%hook SUICOrbView

- (id)initWithFrame:(CGRect)arg1 {
    id view = %orig(arg1);
    if ([view isKindOfClass:[UIView class]]) {
        [(UIView *)view setAlpha:0.0];
    }
    return view;
}

- (void)setMode:(NSInteger)mode {
    %orig;
    globalSiriState = mode;
}

- (void)setPowerLevel:(float)arg1 {
    %orig;
    float level = FSNormalizeAudioLevel(arg1);
    if (FSIsSiriSpeaking(nil)) level = 0;
    FSSendLevel(level);
}

%end
%end

%group FSSiriSharedOrb
%hook SiriSharedUIOrbView
- (id)initWithFrame:(CGRect)arg1 {
    id view = %orig(arg1);
    if ([view isKindOfClass:[UIView class]]) [(UIView *)view setAlpha:0.0];
    return view;
}
- (void)setPowerLevel:(float)arg1 {
    %orig;
    float level = FSNormalizeAudioLevel(arg1);
    if (!FSIsSiriSpeaking(nil)) FSSendLevel(level);
}
%end
%end

// -----------------------------------------------------------------------------
// Primary Siri UI host (iOS 14–16, usually present on 17 too)
// -----------------------------------------------------------------------------
%group FSSiriUIHost
%hook SiriUIBackgroundBlurViewController

- (void)viewDidLoad {
    %orig;
    FSOrbViewDidLoad(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    FSOrbViewWillAppear(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    FSOrbViewDidAppear(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    FSOrbViewWillDisappear(self);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[WaveManager shared] stopRecording];
    FSSendLevel(0);
}

%end
%end

// -----------------------------------------------------------------------------
// SpringBoard backdrop provider — always active in SpringBoard. Fires right as
// Siri is invoked, BEFORE the screen dims, and shares a known-good capture with
// the SiriViewService orb via the cache file. Hosts nothing itself.
// -----------------------------------------------------------------------------
%group FSBackdropProvider
%hook SBAssistantRootViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImage *img = FSWallpaperControllerImage();
        if (!img || FSImageLooksBlack(img)) {
            img = FSScreenCaptureImage();
        }
        FSWriteSharedBackdrop(img);
    });
}

%end
%end

// -----------------------------------------------------------------------------
// Fallback host for iOS 17+ ONLY when SiriUIBackgroundBlurViewController is gone.
// Never active together with FSSiriUIHost (prevents double orbs).
// -----------------------------------------------------------------------------
%group FSAssistantRootFallback
%hook SBAssistantRootViewController

- (void)viewDidLoad {
    %orig;
    FSOrbViewDidLoad(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    FSOrbViewWillAppear(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    FSOrbViewDidAppear(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    FSOrbViewWillDisappear(self);
}

%end
%end

%group FSAFUISession
%hook AFUISiriSession
- (void)setState:(long long)state {
    %orig;
    if (state == 3) globalSiriState = 3;
    else if (state == 1 || state == 2) globalSiriState = (NSInteger)state;
}
%end
%end

%group FSVSSpeech
%hook VSSpeechSynthesizer
- (id)startSpeakingRequest:(id)arg1 {
    globalSiriState = 3;
    return %orig;
}
- (id)stopSpeakingRequest:(id)arg1 {
    globalSiriState = 1;
    return %orig;
}
- (id)stopSpeakingAtNextBoundary:(long long)arg1 {
    globalSiriState = 1;
    return %orig;
}
%end
%end

%group FSSUICFlames
%hook SUICFlamesView
- (void)setState:(NSInteger)state {
    %orig;
    globalSiriState = state;
}
- (void)transitionToState:(NSInteger)state animated:(BOOL)animated {
    %orig;
    globalSiriState = state;
}
- (void)didMoveToWindow {
    %orig;
    FSAttachFlamesPoll((UIView *)self, @selector(fsPollAudio:));
}
%new
- (void)fsPollAudio:(CADisplayLink *)link {
    FSPollFlames(self);
}
%end
%end

%group FSSiriUIFlames
%hook SiriUIFlamesView
- (void)setState:(NSInteger)state {
    %orig;
    globalSiriState = state;
}
- (void)didMoveToWindow {
    %orig;
    FSAttachFlamesPoll((UIView *)self, @selector(fsPollAudio:));
}
%new
- (void)fsPollAudio:(CADisplayLink *)link {
    FSPollFlames(self);
}
%end
%end

static void FSPrefsChangedCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    [[WaveManager shared] reloadPrefs];
}

%ctor {
    BOOL enabled = FSPrefBool(@"enabled", YES);
    if (!enabled) return;

    if (NSClassFromString(@"SUICOrbView")) %init(FSSUICOrb);
    if (NSClassFromString(@"SiriSharedUIOrbView")) %init(FSSiriSharedOrb);
    if (NSClassFromString(@"AFUISiriSession")) %init(FSAFUISession);
    if (NSClassFromString(@"SUICFlamesView")) %init(FSSUICFlames);
    if (NSClassFromString(@"SiriUIFlamesView")) %init(FSSiriUIFlames);
    if (NSClassFromString(@"VSSpeechSynthesizer")) %init(FSVSSpeech);

    // SpringBoard always shares a good backdrop capture for the Siri process
    if (NSClassFromString(@"SBAssistantRootViewController")) {
        %init(FSBackdropProvider);
    }

    // Exactly ONE orb host per process
    if (NSClassFromString(@"SiriUIBackgroundBlurViewController")) {
        %init(FSSiriUIHost);
    } else if (NSClassFromString(@"SBAssistantRootViewController")) {
        %init(FSAssistantRootFallback);
    }

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    FSDarwinLevelCallback,
                                    CFSTR("com.kolby.floatingsiri/level"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    FSPrefsChangedCallback,
                                    CFSTR("com.kolby.floatingsiri/prefschanged"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
