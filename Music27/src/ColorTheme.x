#import "Music27.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// Artwork-driven color theming for album / playlist / now-playing screens.
//
// FIXES vs. the black-screen binary:
// 1. Matchers no longer treat "container" alone as an album/playlist screen —
//    that matched Music's root container VC and washed the whole app black.
// 2. The wash is a translucent CAGradientLayer on the view's layer (behind
//    content) instead of an opaque UIView inserted as a subview (which sat
//    on top of SwiftUI hosting layers and covered everything).
// 3. No artwork => no theme (no systemGray fallback that darkened to black).
// 4. Theme is only applied to album/playlist detail + now-playing surfaces.

static const NSInteger kM27WashTag = 0x4D323757; // 'M27W' — used on layer name

static BOOL M27LooksLikeAlbumOrPlaylist(UIViewController *vc) {
    // Require a "detail-ish" token; bare "container"/"product" alone is too
    // broad and matched Music's root container (the black-screen root cause).
    static NSArray<NSString *> *strong;
    static NSArray<NSString *> *weak;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        strong = @[
            @"albumdetail", @"playlistdetail", @"collectiondetail",
            @"librarydetail", @"albumpage", @"playlistpage",
            @"albumvc", @"playlistvc"
        ];
        weak = @[ @"album", @"playlist" ];
    });
    if (M27ClassNameContains(vc, strong)) return YES;
    if (!M27ClassNameContains(vc, weak)) return NO;
    // Weak match must also look like a detail surface (has large artwork).
    UIImage *art = M27LargestImageInView(vc.view);
    return art != nil && art.size.width >= 120;
}

static BOOL M27IsNowPlayingController(UIViewController *vc) {
    static NSArray<NSString *> *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[
            @"nowplaying", @"playerview", @"nowplayingview",
            @"fullscreenplayer", @"mputnowplaying", @"nowplayingcontrols"
        ];
    });
    return M27ClassNameContains(vc, needles);
}

static BOOL M27ShouldThemeController(UIViewController *vc) {
    if (M27IsNowPlayingController(vc)) return YES;
    if (M27LooksLikeAlbumOrPlaylist(vc)) return YES;
    return NO;
}

static CAGradientLayer *M27FindWashLayer(UIView *view) {
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"M27Wash"]) return (CAGradientLayer *)layer;
    }
    return nil;
}

static void M27RemoveWash(UIView *view) {
    CAGradientLayer *wash = M27FindWashLayer(view);
    [wash removeFromSuperlayer];
}

static void M27ApplyWash(UIView *view, M27ColorPalette *palette) {
    if (!view) return;
    if (!palette) {
        M27RemoveWash(view);
        return;
    }

    // FIX: use a translucent gradient layer inserted at the back of the layer
    // hierarchy. An opaque UIView subview (the old approach) ended up covering
    // SwiftUI's hosting layers and produced the black screen.
    CAGradientLayer *wash = M27FindWashLayer(view);
    if (!wash) {
        wash = [CAGradientLayer layer];
        wash.name = @"M27Wash";
        wash.zPosition = -1000;
        [view.layer insertSublayer:wash atIndex:0];
    }
    wash.frame = view.bounds;
    wash.colors = @[
        (id)[palette.background colorWithAlphaComponent:0.55].CGColor,
        (id)[palette.backgroundSecondary colorWithAlphaComponent:0.25].CGColor,
        (id)[UIColor clearColor].CGColor
    ];
    wash.startPoint = CGPointMake(0.5, 0.0);
    wash.endPoint = CGPointMake(0.5, 1.0);
}

static void M27TintControls(UIView *view, M27ColorPalette *palette) {
    if (!view || !palette) return;
    // Light touch: only tint common UIKit controls, never force opaque bg.
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:view];
    NSInteger visited = 0;
    while (stack.count > 0 && visited < 80) {
        UIView *current = stack.lastObject;
        [stack removeLastObject];
        visited++;
        if ([current isKindOfClass:UISlider.class]) {
            UISlider *slider = (UISlider *)current;
            slider.minimumTrackTintColor = palette.tint;
            slider.thumbTintColor = palette.foreground;
        } else if ([current isKindOfClass:UIProgressView.class]) {
            UIProgressView *progress = (UIProgressView *)current;
            progress.progressTintColor = palette.tint;
        }
        if (current.subviews.count && visited < 80) {
            [stack addObjectsFromArray:current.subviews];
        }
    }
}

static UIImage *M27ArtworkFromNowPlayingInfo(void) {
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    id artwork = info[MPMediaItemPropertyArtwork];
    if (![artwork isKindOfClass:MPMediaItemArtwork.class]) return nil;
    return [(MPMediaItemArtwork *)artwork imageWithSize:CGSizeMake(300, 300)];
}

static void M27ThemeController(UIViewController *vc) {
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.colorThemeEnabled)) {
        M27RemoveWash(vc.view);
        return;
    }
    if (!M27ShouldThemeController(vc)) return;

    UIImage *artwork = M27LargestImageInView(vc.view);
    if (!artwork && M27IsNowPlayingController(vc)) {
        artwork = M27ArtworkFromNowPlayingInfo();
    }
    M27ColorPalette *palette = [M27ColorTheme.shared paletteFromImage:artwork];
    if (!palette) {
        // Keep any existing theme; don't invent a black one.
        return;
    }
    [M27ColorTheme.shared applyPalette:palette animated:YES];
    M27ApplyWash(vc.view, palette);
    M27TintControls(vc.view, palette);
}

static void M27ClearThemeOnController(UIViewController *vc) {
    M27RemoveWash(vc.view);
    if (M27IsNowPlayingController(vc) || M27LooksLikeAlbumOrPlaylist(vc)) {
        // Only clear the shared theme when leaving a themed surface.
        UIViewController *top = M27TopViewController();
        if (top != vc) {
            [M27ColorTheme.shared clearThemeAnimated:YES];
        }
    }
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    M27ThemeController(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.colorThemeEnabled)) return;
    if (!M27ShouldThemeController(self)) return;
    // Keep wash sized to bounds; don't re-extract artwork every layout.
    M27ColorPalette *palette = M27ColorTheme.shared.activePalette;
    if (palette) {
        M27ApplyWash(self.view, palette);
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    M27ClearThemeOnController(self);
}

%end

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.colorThemeEnabled)) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIImage *artwork = nil;
        id artObj = info[MPMediaItemPropertyArtwork];
        if ([artObj isKindOfClass:MPMediaItemArtwork.class]) {
            artwork = [(MPMediaItemArtwork *)artObj imageWithSize:CGSizeMake(300, 300)];
        }
        M27ColorPalette *palette = [M27ColorTheme.shared paletteFromImage:artwork];
        if (!palette) return;
        [M27ColorTheme.shared applyPalette:palette animated:YES];

        UIViewController *top = M27TopViewController();
        if (top && M27IsNowPlayingController(top)) {
            M27ApplyWash(top.view, palette);
            M27TintControls(top.view, palette);
        }
    });
}

%end
