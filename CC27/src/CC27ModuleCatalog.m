#import "CC27.h"

@implementation CC27ModuleInfo
@end

@implementation CC27ModuleCatalog {
    NSArray<CC27ModuleInfo *> *_modules;
}

+ (instancetype)shared {
    static CC27ModuleCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        shared = [self new];
    });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self reload];
    }
    return self;
}

- (NSString *)_prettyNameForIdentifier:(NSString *)identifier bundle:(NSBundle *)bundle {
    NSString *display = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (display.length) return display;
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (name.length) return name;

    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"com.apple.control-center.ConnectivityModule": @"Connectivity",
            @"com.apple.control-center.DisplayModule": @"Brightness",
            @"com.apple.control-center.AudioModule": @"Volume",
            @"com.apple.mediaremote.controlcenter.audio": @"Volume",
            @"com.apple.mediaremote.controlcenter.nowplaying": @"Now Playing",
            @"com.apple.control-center.FlashlightModule": @"Flashlight",
            @"com.apple.control-center.CameraModule": @"Camera",
            @"com.apple.control-center.CalculatorModule": @"Calculator",
            @"com.apple.control-center.OrientationLockModule": @"Orientation Lock",
            @"com.apple.control-center.LowPowerModule": @"Low Power Mode",
            @"com.apple.control-center.AppleTVRemoteModule": @"Apple TV Remote",
            @"com.apple.control-center.CarModeModule": @"Do Not Disturb While Driving",
            @"com.apple.donotdisturb.DoNotDisturbModule": @"Do Not Disturb",
            @"com.apple.FocusUIModule": @"Focus",
            @"com.apple.Home.ControlCenter": @"Home",
            @"com.apple.mobiletimer.controlcenter.timer": @"Timer",
            @"com.apple.MobileSMS.SilenceModule": @"Mute",
            @"com.apple.mediaremote.controlcenter.airplaymirroring": @"Screen Mirroring",
            @"com.apple.replaykit.RecentsControlCenterModule": @"Screen Recording",
            @"com.apple.control-center.HearingAidsModule": @"Hearing",
            @"com.apple.control-center.QRCodeModule": @"Scan Code",
            @"com.apple.control-center.MagnifierModule": @"Magnifier",
            @"com.apple.control-center.QuickNoteModule": @"Quick Note",
            @"com.apple.control-center.DarkModeModule": @"Dark Mode",
            @"com.apple.ShazamKit.ShazamModule": @"Recognize Music",
            @"com.kolby.cc27.respring": @"Respring",
            @"com.kolby.cc27.safemode": @"Safe Mode",
            @"com.kolby.cc27.uicache": @"UICache",
            @"com.kolby.cc27.userspace": @"Userspace Reboot",
        };
    });
    NSString *mapped = map[identifier];
    if (mapped) return mapped;

    NSString *last = identifier.pathExtension.length ? identifier.pathExtension : identifier.lastPathComponent;
    if ([last hasSuffix:@"Module"]) last = [last substringToIndex:last.length - 6];
    if (last.length == 0) return identifier;
    return last;
}

- (NSString *)_categoryForIdentifier:(NSString *)identifier isThirdParty:(BOOL)third isCC27:(BOOL)cc27 {
    if (cc27) return @"CC27";
    if (third) return @"Third Party";
    if ([identifier containsString:@"mediaremote"] || [identifier containsString:@"Shazam"] || [identifier containsString:@"nowplaying"] || [identifier containsString:@"Audio"])
        return @"Media";
    if ([identifier containsString:@"Connectivity"] || [identifier containsString:@"airplay"] || [identifier containsString:@"Bluetooth"] || [identifier containsString:@"WiFi"])
        return @"Connectivity";
    if ([identifier containsString:@"Display"] || [identifier containsString:@"Flashlight"] || [identifier containsString:@"DarkMode"] || [identifier containsString:@"LowPower"] || [identifier containsString:@"Orientation"])
        return @"Utilities";
    return @"System";
}

- (UIImage *)_iconForIdentifier:(NSString *)identifier bundle:(NSBundle *)bundle {
    NSArray *names = @[ @"SettingsIcon", @"AppIcon", @"Icon", @"glyph" ];
    for (NSString *name in names) {
        UIImage *img = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
        if (img) return img;
    }
    // SF Symbol fallbacks for stock modules
    NSDictionary *symbols = @{
        @"com.apple.control-center.FlashlightModule": @"flashlight.on.fill",
        @"com.apple.control-center.CameraModule": @"camera.fill",
        @"com.apple.control-center.CalculatorModule": @"plus.forwardslash.minus",
        @"com.apple.control-center.OrientationLockModule": @"lock.rotation",
        @"com.apple.control-center.LowPowerModule": @"battery.25",
        @"com.apple.control-center.DisplayModule": @"sun.max.fill",
        @"com.apple.control-center.AudioModule": @"speaker.wave.2.fill",
        @"com.apple.mediaremote.controlcenter.audio": @"speaker.wave.2.fill",
        @"com.apple.mediaremote.controlcenter.nowplaying": @"music.note",
        @"com.apple.control-center.ConnectivityModule": @"wifi",
        @"com.apple.FocusUIModule": @"moon.fill",
        @"com.apple.Home.ControlCenter": @"homekit",
        @"com.apple.mobiletimer.controlcenter.timer": @"timer",
        @"com.apple.mediaremote.controlcenter.airplaymirroring": @"airplayvideo",
        @"com.apple.control-center.QRCodeModule": @"qrcode.viewfinder",
        @"com.apple.control-center.DarkModeModule": @"circle.lefthalf.filled",
        @"com.apple.ShazamKit.ShazamModule": @"shazam.logo.fill",
        @"com.kolby.cc27.respring": @"arrow.clockwise",
        @"com.kolby.cc27.safemode": @"exclamationmark.shield.fill",
        @"com.kolby.cc27.uicache": @"paintbrush.fill",
        @"com.kolby.cc27.userspace": @"bolt.fill",
    };
    NSString *symbol = symbols[identifier] ?: @"switch.2";
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:symbol];
    }
    return nil;
}

- (void)_addBundleAtURL:(NSURL *)url
               into:(NSMutableDictionary<NSString *, CC27ModuleInfo *> *)map
          thirdParty:(BOOL)thirdParty {
    if (!url) return;
    NSBundle *bundle = [NSBundle bundleWithURL:url];
    NSString *identifier = bundle.bundleIdentifier;
    if (identifier.length == 0) {
        identifier = [[url lastPathComponent] stringByDeletingPathExtension];
    }
    if (identifier.length == 0 || map[identifier]) return;

    CC27ModuleInfo *info = [CC27ModuleInfo new];
    info.identifier = identifier;
    info.displayName = [self _prettyNameForIdentifier:identifier bundle:bundle];
    info.icon = [self _iconForIdentifier:identifier bundle:bundle];
    info.isCC27 = [identifier hasPrefix:@"com.kolby.cc27."];
    info.isThirdParty = thirdParty || info.isCC27;
    info.category = [self _categoryForIdentifier:identifier isThirdParty:thirdParty isCC27:info.isCC27];
    info.subtitle = info.isCC27 ? @"CC27" : (thirdParty ? @"Third-party module" : @"System");
    map[identifier] = info;
}

- (void)reload {
    NSMutableDictionary<NSString *, CC27ModuleInfo *> *map = [NSMutableDictionary dictionary];
    NSFileManager *fm = NSFileManager.defaultManager;

    // Stock + any already-registered modules via repository when available.
    Class repoCls = NSClassFromString(@"CCSModuleRepository");
    Class mgrCls = NSClassFromString(@"CCUIModuleInstanceManager");
    id mgr = [mgrCls respondsToSelector:@selector(sharedInstance)] ? [mgrCls sharedInstance] : nil;
    CCSModuleRepository *repo = nil;
    if (mgr) {
        @try { repo = [mgr valueForKey:@"_repository"]; } @catch (__unused NSException *e) {}
    }

    NSSet *loadable = nil;
    if ([repo respondsToSelector:@selector(loadableModuleIdentifiers)]) {
        loadable = [repo loadableModuleIdentifiers];
    }
    for (NSString *identifier in loadable) {
        CCSModuleMetadata *meta = nil;
        if ([repo respondsToSelector:@selector(moduleMetadataForModuleIdentifier:)]) {
            meta = [repo moduleMetadataForModuleIdentifier:identifier];
        }
        if (meta.moduleBundleURL) {
            BOOL third = ![meta.moduleBundleURL.path containsString:@"/System/Library/"];
            [self _addBundleAtURL:meta.moduleBundleURL into:map thirdParty:third];
        } else {
            CC27ModuleInfo *info = [CC27ModuleInfo new];
            info.identifier = identifier;
            info.displayName = [self _prettyNameForIdentifier:identifier bundle:nil];
            info.icon = [self _iconForIdentifier:identifier bundle:nil];
            info.isCC27 = [identifier hasPrefix:@"com.kolby.cc27."];
            info.isThirdParty = NO;
            info.category = [self _categoryForIdentifier:identifier isThirdParty:NO isCC27:info.isCC27];
            map[identifier] = info;
        }
    }

    // Scan CCSupport module directories (rootless + roothide + rootful).
    NSMutableArray<NSString *> *dirs = [NSMutableArray arrayWithObjects:
                                        @"/Library/ControlCenter/Bundles",
                                        @"/var/jb/Library/ControlCenter/Bundles",
                                        @"/System/Library/ControlCenter/Bundles",
                                        nil];
    const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    if (jbrootFn) {
        const char *p = jbrootFn("/Library/ControlCenter/Bundles");
        if (p && p[0]) [dirs insertObject:[NSString stringWithUTF8String:p] atIndex:0];
    }
    for (NSString *dir in dirs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *item in contents) {
            if (![item.pathExtension isEqualToString:@"bundle"]) continue;
            NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:item]];
            BOOL third = ![dir hasPrefix:@"/System/"];
            [self _addBundleAtURL:url into:map thirdParty:third];
        }
    }

    // Ensure CC27 built-ins exist even before provider load.
    for (NSString *identifier in @[ @"com.kolby.cc27.respring",
                                    @"com.kolby.cc27.safemode",
                                    @"com.kolby.cc27.uicache",
                                    @"com.kolby.cc27.userspace" ]) {
        if (map[identifier]) continue;
        CC27ModuleInfo *info = [CC27ModuleInfo new];
        info.identifier = identifier;
        info.displayName = [self _prettyNameForIdentifier:identifier bundle:nil];
        info.icon = [self _iconForIdentifier:identifier bundle:nil];
        info.isCC27 = YES;
        info.isThirdParty = YES;
        info.category = @"CC27";
        info.subtitle = @"CC27";
        map[identifier] = info;
    }

    NSSet *enabled = [NSSet setWithArray:CC27LayoutStore.shared.enabledIdentifiers];
    for (CC27ModuleInfo *info in map.allValues) {
        info.enabled = [enabled containsObject:info.identifier];
    }

    _modules = [map.allValues sortedArrayUsingComparator:^NSComparisonResult(CC27ModuleInfo *a, CC27ModuleInfo *b) {
        NSComparisonResult cat = [a.category localizedStandardCompare:b.category];
        if (cat != NSOrderedSame) return cat;
        return [a.displayName localizedStandardCompare:b.displayName];
    }];
}

- (NSArray<CC27ModuleInfo *> *)allModules {
    return _modules ?: @[];
}

- (NSArray<CC27ModuleInfo *> *)modulesMatchingSearch:(NSString *)query {
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    if (q.length == 0) return self.allModules;
    NSMutableArray *out = [NSMutableArray array];
    for (CC27ModuleInfo *info in self.allModules) {
        if ([info.displayName.lowercaseString containsString:q] ||
            [info.identifier.lowercaseString containsString:q] ||
            [info.category.lowercaseString containsString:q] ||
            [info.subtitle.lowercaseString containsString:q]) {
            [out addObject:info];
        }
    }
    return out;
}

- (CC27ModuleInfo *)infoForIdentifier:(NSString *)identifier {
    for (CC27ModuleInfo *info in _modules) {
        if ([info.identifier isEqualToString:identifier]) return info;
    }
    return nil;
}

@end
