#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <notify.h>
#import "LiquidGlass.h"
#import "FloatingSiri-Swift.h"

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


// -----------------------------------------------------------------------------
// FloatingSiri — iOS 27-style liquid glass Siri orb
// Glass runtime adapted from LiquidSiri (Thijs) / Liquid (Gl)ass (liquidass)
// Fixes vs 1.22: half-dark glass (not solid black), voice-reactive wave,
// SpringBoard + SiriViewService injection, SBAssistant hosting for iOS 17.
// -----------------------------------------------------------------------------

static NSInteger globalSiriState = 1;
static NSString * const kFSPrefsDomain = @"com.kolby.floatingsiri";
static NSString * const kFSPrefsChanged = @"com.kolby.floatingsiri/prefschanged";
static const char *kFSDarwinLevel = "com.kolby.floatingsiri/level";

OBJC_EXTERN UIImage *_UICreateScreenUIImage(void);

static NSDictionary *FSPrefs(void) {
    static NSDictionary *cached = nil;
    static CFAbsoluteTime lastLoad = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (cached && (now - lastLoad) < 0.5) return cached;

    NSArray *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.kolby.floatingsiri.plist",
        @"/var/mobile/Library/Preferences/com.kolby.floatingsiri.plist"
    ];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) { cached = d; lastLoad = now; return cached; }
    }
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kFSPrefsDomain];
    cached = ud.dictionaryRepresentation ?: @{};
    lastLoad = now;
    return cached;
}

static id FSPref(NSString *key, id fallback) {
    id v = FSPrefs()[key];
    return v ?: fallback;
}

static BOOL FSPrefBool(NSString *key, BOOL fallback) {
    id v = FSPrefs()[key];
    return v ? [v boolValue] : fallback;
}

static CGFloat FSPrefFloat(NSString *key, CGFloat fallback) {
    id v = FSPrefs()[key];
    return v ? [v doubleValue] : fallback;
}

static void FSSendLevel(float level) {
    // Same-process Swift wave
    [[WaveManager shared] updateTargetPower:@(level)];

    // Cross-process (SpringBoard ↔ SiriViewService)
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
    // Some builds report 0...1, others roughly -160...0 dB, others 0...100
    if (level < 0) {
        level = powf(10.0f, fmaxf(level, -120.0f) / 20.0f);
    } else if (level > 1.5f) {
        level = level / 100.0f;
    }
    return fminf(1.0f, fmaxf(0.0f, level));
}

// Prefer SpringBoard wallpaper so the glass isn't sampling a black Siri blur plate.
static UIImage *FSCaptureBackdropImage(void) {
    // 1) SBWallpaperController (best for liquid glass)
    @try {
        Class cls = NSClassFromString(@"SBWallpaperController");
        id ctrl = [cls respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(cls, @selector(sharedInstance)) : nil;
        if (ctrl) {
            // try common selectors across iOS 14–17
            NSArray *sels = @[ @"wallpaperImageForVariant:", @"homescreenWallpaperImage", @"legacyWallpaperImage" ];
            for (NSString *selName in sels) {
                SEL sel = NSSelectorFromString(selName);
                if (![ctrl respondsToSelector:sel]) continue;
                UIImage *img = nil;
                if ([selName hasSuffix:@":"]) {
                    img = ((UIImage *(*)(id, SEL, long long))objc_msgSend)(ctrl, sel, 1); // homescreen variant
                } else {
                    img = ((UIImage *(*)(id, SEL))objc_msgSend)(ctrl, sel);
                }
                if ([img isKindOfClass:[UIImage class]] && img.size.width > 2) {
                    return img;
                }
            }
        }
    } @catch (__unused NSException *e) {}

    // 2) Full-screen snapshot
    UIImage *raw = nil;
    @try { raw = _UICreateScreenUIImage(); } @catch (__unused NSException *e) {}
    if (!raw) return nil;

    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGSize expected = CGSizeMake(screen.width * scale, screen.height * scale);
    CGImageRef cg = raw.CGImage;
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

static void FSAddBlackDome(UIView *glassOrb, CGFloat width, CGFloat height, UIView *aboveSibling) {
    // Remove old dome layers tagged by name
    for (CALayer *sub in [glassOrb.layer.sublayers copy]) {
        if ([sub.name isEqualToString:@"fs.blackDome"] || [sub isKindOfClass:[CAGradientLayer class]]) {
            [sub removeFromSuperlayer];
        }
    }

    CGFloat domeOpacity = FSPrefFloat(@"domeOpacity", 0.92);
    CGFloat domeHeight = FSPrefFloat(@"domeHeight", 0.55); // fraction of orb height

    CAShapeLayer *blackDomeLayer = [CAShapeLayer layer];
    blackDomeLayer.name = @"fs.blackDome";
    blackDomeLayer.frame = CGRectMake(0, 0, width, height);
    // Slightly translucent so glass still reads as glass under the dome
    blackDomeLayer.fillColor = [UIColor colorWithWhite:0.0 alpha:domeOpacity].CGColor;

    UIBezierPath *domePath = [UIBezierPath bezierPath];
    [domePath moveToPoint:CGPointMake(0, 0)];
    [domePath addLineToPoint:CGPointMake(width, 0)];
    [domePath addLineToPoint:CGPointMake(width, height * domeHeight)];
    [domePath addQuadCurveToPoint:CGPointMake(0, height * domeHeight)
                     controlPoint:CGPointMake(width / 2.0, height * (domeHeight - 0.03))];
    [domePath closePath];
    blackDomeLayer.path = domePath.CGPath;
    blackDomeLayer.shadowColor = [UIColor blackColor].CGColor;
    blackDomeLayer.shadowOffset = CGSizeZero;
    blackDomeLayer.shadowRadius = 10.0;
    blackDomeLayer.shadowOpacity = 0.85;

    CAGradientLayer *fadeMask = [CAGradientLayer layer];
    fadeMask.frame = blackDomeLayer.bounds;
    fadeMask.type = kCAGradientLayerRadial;
    fadeMask.colors = @[
        (id)[UIColor blackColor].CGColor,
        (id)[UIColor blackColor].CGColor,
        (id)[UIColor clearColor].CGColor
    ];
    fadeMask.locations = @[@0.0, @0.62, @1.0];
    fadeMask.startPoint = CGPointMake(0.5, 0.0);
    fadeMask.endPoint = CGPointMake(1.22, domeHeight);
    blackDomeLayer.mask = fadeMask;

    if (aboveSibling && aboveSibling.layer.superlayer == glassOrb.layer) {
        [glassOrb.layer insertSublayer:blackDomeLayer below:aboveSibling.layer];
    } else {
        [glassOrb.layer addSublayer:blackDomeLayer];
    }
}

static void FSDimStockSiriChrome(UIView *root) {
    if (!FSPrefBool(@"hideOldUI", YES) || !root) return;
    // Dim, don't hide — keeping hierarchy alive preserves flame audio delegates.
    for (UIView *v in root.subviews) {
        NSString *cls = NSStringFromClass(v.class);
        if ([cls containsString:@"Orb"] || [cls containsString:@"Flame"] ||
            [cls containsString:@"Waveform"] || [cls containsString:@"Listening"] ||
            [cls containsString:@"BackgroundBlur"] || [cls containsString:@"Material"]) {
            if (v.alpha > 0.02) v.alpha = 0.01;
        }
    }
}

@interface FSOrbHost : NSObject
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, strong) LiquidGlassView *glassOrbView;
@property (nonatomic, strong) UIView *glowLineView;
@property (nonatomic, strong) UIView *externalWhiteGlowView;
@property (nonatomic, strong) UIImage *capturedWallpaper;
@property (nonatomic, assign) BOOL hasCapturedBackdrop;
@property (nonatomic, assign) BOOL installed;
- (void)installOn:(UIView *)host;
- (void)appear;
- (void)disappear;
- (void)layoutOrb;
@end

@implementation FSOrbHost

+ (instancetype)shared {
    static FSOrbHost *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [FSOrbHost new]; });
    return s;
}

- (void)installOn:(UIView *)host {
    if (!host) return;
    self.hostView = host;
    if (self.glassOrbView) {
        if (self.glassOrbView.superview != host) {
            [host addSubview:self.glassOrbView];
            if (self.externalWhiteGlowView) {
                [host insertSubview:self.externalWhiteGlowView belowSubview:self.glassOrbView];
            }
        }
        return;
    }

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat width = FSPrefFloat(@"orbWidth", 192);
    CGFloat height = FSPrefFloat(@"orbHeight", 188);
    CGFloat top = FSPrefFloat(@"topOffset", 0);
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = host.safeAreaInsets.top;
        if (safeTop <= 0) safeTop = [UIApplication sharedApplication].windows.firstObject.safeAreaInsets.top;
    }
    // Notch / Dynamic Island defaults if prefs still at "legacy square" sizes
    if (safeTop >= 59 && width < 170) { width = 180; height = 148; }
    else if (safeTop > 44 && width < 150) { width = 160; height = 130; }

    CGRect orbFrame = CGRectMake((screenBounds.size.width - width)/2.0, MAX(8.0, safeTop - 12.0) + top, width, height);

    UIGraphicsBeginImageContextWithOptions(screenBounds.size, NO, 0);
    UIImage *tempBg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    self.glassOrbView = [[LiquidGlassView alloc] initWithFrame:orbFrame wallpaper:tempBg wallpaperOrigin:CGPointZero];
    self.glassOrbView.updateGroup = 255;
    self.glassOrbView.refractionScale = FSPrefFloat(@"refractionScale", 1.4);
    self.glassOrbView.refractiveIndex = 1.15;
    self.glassOrbView.specularOpacity = 1.0;
    self.glassOrbView.blur = 0.0;
    self.glassOrbView.bezelWidth = 24.0;
    self.glassOrbView.glassThickness = 120.0;
    self.glassOrbView.cornerRadius = MIN(width, height) / 2.0;
    self.glassOrbView.alpha = FSPrefFloat(@"orbOpacity", 1.0) * 0.0; // fade in later
    self.glassOrbView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.glassOrbView.layer.shadowOffset = CGSizeMake(0, 6);
    self.glassOrbView.layer.shadowOpacity = 0.35;
    self.glassOrbView.layer.shadowRadius = 12;
    // Critical: keep MTKView clear so failed samples don't paint a solid black pill
    self.glassOrbView.backgroundColor = [UIColor clearColor];
    self.glassOrbView.opaque = NO;

    self.externalWhiteGlowView = [[UIView alloc] initWithFrame:CGRectMake(orbFrame.origin.x + width * 0.15, orbFrame.origin.y + height - 35.0, width * 0.7, 30.0)];
    self.externalWhiteGlowView.backgroundColor = [UIColor clearColor];
    UIBezierPath *shadowPath = [UIBezierPath bezierPathWithOvalInRect:self.externalWhiteGlowView.bounds];
    self.externalWhiteGlowView.layer.shadowPath = shadowPath.CGPath;
    self.externalWhiteGlowView.layer.shadowColor = [UIColor whiteColor].CGColor;
    self.externalWhiteGlowView.layer.shadowOffset = CGSizeZero;
    self.externalWhiteGlowView.layer.shadowOpacity = FSPrefBool(@"glowEnabled", YES) ? FSPrefFloat(@"glowIntensity", 0.7) : 0.0;
    self.externalWhiteGlowView.layer.shadowRadius = 12.0;
    self.externalWhiteGlowView.alpha = 0.0;

    [host addSubview:self.externalWhiteGlowView];
    [host addSubview:self.glassOrbView];

    self.glowLineView = [[UIView alloc] initWithFrame:self.glassOrbView.bounds];
    self.glowLineView.backgroundColor = [UIColor clearColor];
    self.glowLineView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.glowLineView.clipsToBounds = NO;
    [self.glassOrbView addSubview:self.glowLineView];

    UIView *swiftWave = [[WaveManager shared] createWaveViewWithFrame:self.glowLineView.bounds];
    swiftWave.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.glowLineView addSubview:swiftWave];

    FSAddBlackDome(self.glassOrbView, width, height, self.glowLineView);
    self.installed = YES;
}

- (void)layoutOrb {
    UIView *host = self.hostView;
    if (!host || !self.glassOrbView) return;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat width = FSPrefFloat(@"orbWidth", 192);
    CGFloat height = FSPrefFloat(@"orbHeight", 188);
    CGFloat top = FSPrefFloat(@"topOffset", 0);
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = host.safeAreaInsets.top;
    }
    CGFloat physicalY = MAX(8.0, safeTop - 12.0) + top;
    CGFloat physicalX = (screenBounds.size.width - width) / 2.0;
    CGRect absolute = CGRectMake(physicalX, physicalY, width, height);
    CGRect orbFrame = [host convertRect:absolute fromCoordinateSpace:UIScreen.mainScreen.coordinateSpace];

    self.glassOrbView.frame = orbFrame;
    self.glassOrbView.cornerRadius = MIN(width, height) / 2.0;
    self.glassOrbView.refractionScale = FSPrefFloat(@"refractionScale", 1.4);
    self.glassOrbView.wallpaperOrigin = CGPointZero;
    [self.glassOrbView updateOrigin];

    self.externalWhiteGlowView.frame = CGRectMake(orbFrame.origin.x + width * 0.15, orbFrame.origin.y + height - 35.0, width * 0.7, 30.0);
    self.externalWhiteGlowView.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:self.externalWhiteGlowView.bounds].CGPath;
    self.externalWhiteGlowView.layer.shadowOpacity = FSPrefBool(@"glowEnabled", YES) ? FSPrefFloat(@"glowIntensity", 0.7) : 0.0;

    self.glowLineView.frame = self.glassOrbView.bounds;
    FSAddBlackDome(self.glassOrbView, width, height, self.glowLineView);
}

- (void)appear {
    [self layoutOrb];
    [[WaveManager shared] reloadPrefs];

    void (^animateIn)(void) = ^{
        self.glassOrbView.hidden = NO;
        CGFloat targetAlpha = FSPrefFloat(@"orbOpacity", 1.0);
        [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.55 options:0 animations:^{
            self.glassOrbView.transform = CGAffineTransformIdentity;
            self.glassOrbView.alpha = targetAlpha;
            self.externalWhiteGlowView.alpha = 1.0;
        } completion:^(__unused BOOL finished) {
            CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            breathe.fromValue = @1.0;
            breathe.toValue = @1.03;
            breathe.duration = MAX(0.6, FSPrefFloat(@"pulseSpeed", 2.4));
            breathe.autoreverses = YES;
            breathe.repeatCount = HUGE_VALF;
            breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self.glassOrbView.layer addAnimation:breathe forKey:@"orbBreathing"];
        }];
    };

    if (!self.hasCapturedBackdrop) {
        // Capture ASAP (wallpaper preferred) so bottom glass isn't black.
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *img = FSCaptureBackdropImage();
            if (img) {
                self.capturedWallpaper = img;
                self.glassOrbView.wallpaperImage = img;
            }
            self.hasCapturedBackdrop = YES;
            // Second pass after Siri settles — only keep if brighter/non-black
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIImage *again = FSCaptureBackdropImage();
                if (again) {
                    self.capturedWallpaper = again;
                    self.glassOrbView.wallpaperImage = again;
                }
                animateIn();
            });
        });
    } else {
        if (self.capturedWallpaper) self.glassOrbView.wallpaperImage = self.capturedWallpaper;
        animateIn();
    }
}

- (void)disappear {
    [self.glassOrbView.layer removeAnimationForKey:@"orbBreathing"];
    [UIView animateWithDuration:0.3 animations:^{
        self.glassOrbView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, -40), CGAffineTransformMakeScale(0.7, 0.7));
        self.glassOrbView.alpha = 0.0;
        self.externalWhiteGlowView.alpha = 0.0;
    }];
    [[WaveManager shared] stopRecording];
    FSSendLevel(0);
}

@end

void LG_registerGlassView(UIView *view, LGUpdateGroup group) {}
void LG_unregisterGlassView(UIView *view, LGUpdateGroup group) {}
void LG_updateRegisteredGlassViews(LGUpdateGroup group) {}
void LG_redrawRegisteredGlassViews(LGUpdateGroup group) {}

// -----------------------------------------------------------------------------
// Stock orb — hide visually, steal power levels
// -----------------------------------------------------------------------------

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

// Some iOS 17 builds expose similarly named helpers
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
// Primary Siri UI host (iOS 14–16, often still present on 17)
// -----------------------------------------------------------------------------
%group FSSiriUIHost
%hook SiriUIBackgroundBlurViewController

- (void)viewDidLoad {
    %orig;
    [[FSOrbHost shared] installOn:self.view];
    FSDimStockSiriChrome(self.view);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [[FSOrbHost shared] installOn:self.view];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    FSDimStockSiriChrome(self.view);
    [[FSOrbHost shared] appear];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [[FSOrbHost shared] disappear];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[WaveManager shared] stopRecording];
    FSSendLevel(0);
}

%end
%end

// -----------------------------------------------------------------------------
// SpringBoard assistant root — critical for iPhone X / 12 mini paths & iOS 17
// -----------------------------------------------------------------------------
%group FSAssistantRoot
%hook SBAssistantRootViewController

- (void)viewDidLoad {
    %orig;
    [[FSOrbHost shared] installOn:self.view];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [[FSOrbHost shared] installOn:self.view];
    // Pre-capture wallpaper before Siri darkens the plate
    if (![FSOrbHost shared].hasCapturedBackdrop) {
        UIImage *img = FSCaptureBackdropImage();
        if (img) {
            [FSOrbHost shared].capturedWallpaper = img;
            [FSOrbHost shared].glassOrbView.wallpaperImage = img;
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    FSDimStockSiriChrome(self.view);
    [[FSOrbHost shared] appear];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [[FSOrbHost shared] disappear];
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

%group FSWaveformChrome
%hook SiriWaveformView
- (void)didMoveToWindow {
    %orig;
    if (self.window) self.alpha = 0.01;
}
- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    self.alpha = 0.01;
}
%end

%hook SiriListeningView
- (void)didMoveToWindow {
    %orig;
    if (self.window) self.alpha = 0.01;
}
- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    self.alpha = 0.01;
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

    // No bare %init — every hook group is class-gated for iOS 17 soft-fail.
    if (NSClassFromString(@"SUICOrbView")) %init(FSSUICOrb);
    if (NSClassFromString(@"SiriUIBackgroundBlurViewController")) %init(FSSiriUIHost);
    if (NSClassFromString(@"SBAssistantRootViewController")) %init(FSAssistantRoot);
    if (NSClassFromString(@"AFUISiriSession")) %init(FSAFUISession);
    if (NSClassFromString(@"SUICFlamesView")) %init(FSSUICFlames);
    if (NSClassFromString(@"SiriSharedUIOrbView")) %init(FSSiriSharedOrb);
    if (NSClassFromString(@"SiriUIFlamesView")) %init(FSSiriUIFlames);
    if (NSClassFromString(@"SiriWaveformView") && NSClassFromString(@"SiriListeningView")) %init(FSWaveformChrome);
    if (NSClassFromString(@"VSSpeechSynthesizer")) %init(FSVSSpeech);

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
