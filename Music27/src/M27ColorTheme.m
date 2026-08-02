#import "Music27.h"

@implementation M27ColorPalette
@end

static CGFloat M27Luminance(CGFloat r, CGFloat g, CGFloat b) {
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

@implementation M27ColorTheme

+ (instancetype)shared {
    static M27ColorTheme *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [self new];
    });
    return shared;
}

- (UIColor *)_averageColorFromImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return nil;

    // Draw into a 1x1 bitmap; the single resulting pixel is the average.
    uint8_t pixel[4] = {0, 0, 0, 0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), cgImage);
    CGContextRelease(ctx);

    if (pixel[3] == 0) return nil;
    return [UIColor colorWithRed:pixel[0] / 255.0
                           green:pixel[1] / 255.0
                            blue:pixel[2] / 255.0
                           alpha:1.0];
}

- (UIColor *)_darken:(UIColor *)color amount:(CGFloat)amount {
    CGFloat r = 0, g = 0, b = 0, a = 1, w = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [UIColor colorWithRed:r * (1 - amount) green:g * (1 - amount) blue:b * (1 - amount) alpha:1];
    }
    if ([color getWhite:&w alpha:&a]) {
        return [UIColor colorWithWhite:w * (1 - amount) alpha:1];
    }
    return color;
}

- (M27ColorPalette *)paletteFromImage:(UIImage *)image {
    // FIX: the original fell back to systemGrayColor when there was no
    // artwork, which — after darkening — produced a near-black opaque theme
    // for every screen. No artwork now means no theme at all.
    if (!image) return nil;
    UIColor *average = [self _averageColorFromImage:image];
    if (!average) return nil;

    CGFloat r = 0, g = 0, b = 0, a = 1;
    [average getRed:&r green:&g blue:&b alpha:&a];

    M27ColorPalette *palette = [M27ColorPalette new];
    palette.background = [self _darken:average amount:0.55];
    palette.backgroundSecondary = [self _darken:average amount:0.75];
    palette.tint = average;
    palette.glassTint = [average colorWithAlphaComponent:0.35];
    palette.prefersLightContent = M27Luminance(r, g, b) < 0.6;
    palette.foreground = palette.prefersLightContent ? UIColor.whiteColor : UIColor.blackColor;
    return palette;
}

- (void)applyPalette:(M27ColorPalette *)palette animated:(BOOL)animated {
    if (self.activePalette == palette) return;
    self.activePalette = palette;
    void (^notify)(void) = ^{
        NSDictionary *info = palette ? @{ @"palette": palette } : @{};
        [NSNotificationCenter.defaultCenter postNotificationName:M27ThemeDidChangeNotification
                                                          object:nil
                                                        userInfo:info];
    };
    if (animated) {
        [UIView animateWithDuration:0.35 animations:notify completion:nil];
    } else {
        notify();
    }
}

- (void)clearThemeAnimated:(BOOL)animated {
    [self applyPalette:nil animated:animated];
}

@end
