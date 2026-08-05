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

- (UIImage *)_systemImageNamed:(NSString *)name fallbacks:(NSArray<NSString *> *)fallbacks {
    if (@available(iOS 13.0, *)) {
        UIImage *img = [UIImage systemImageNamed:name];
        if (img) return img;
        for (NSString *fb in fallbacks) {
            img = [UIImage systemImageNamed:fb];
            if (img) return img;
        }
    }
    return nil;
}

- (NSString *)_symbolNameForIdentifier:(NSString *)identifier displayName:(NSString *)displayName {
    static NSDictionary *exact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exact = @{
            // Connectivity / radios
            @"com.apple.control-center.ConnectivityModule": @"wifi",
            @"com.apple.control-center.AirplaneModeModule": @"airplane",
            @"com.apple.control-center.CellularDataModule": @"antenna.radiowaves.left.and.right",
            @"com.apple.control-center.WifiModule": @"wifi",
            @"com.apple.control-center.BluetoothModule": @"bolt.horizontal.fill",
            @"com.apple.mediaremote.controlcenter.airplaymirroring": @"airplayvideo",
            // Display / audio
            @"com.apple.control-center.DisplayModule": @"sun.max.fill",
            @"com.apple.control-center.AudioModule": @"speaker.wave.3.fill",
            @"com.apple.mediaremote.controlcenter.audio": @"speaker.wave.3.fill",
            @"com.apple.mediaremote.controlcenter.nowplaying": @"music.note.list",
            // Common toggles
            @"com.apple.control-center.FlashlightModule": @"flashlight.on.fill",
            @"com.apple.control-center.CameraModule": @"camera.fill",
            @"com.apple.control-center.CalculatorModule": @"plus.forwardslash.minus",
            @"com.apple.control-center.OrientationLockModule": @"lock.rotation",
            @"com.apple.control-center.LowPowerModule": @"battery.25",
            @"com.apple.control-center.DarkModeModule": @"circle.lefthalf.filled",
            @"com.apple.control-center.AppearanceModule": @"circle.lefthalf.filled",
            @"com.apple.control-center.QRCodeModule": @"qrcode.viewfinder",
            @"com.apple.control-center.MagnifierModule": @"plus.magnifyingglass",
            @"com.apple.control-center.QuickNoteModule": @"note.text",
            @"com.apple.control-center.HearingAidsModule": @"ear",
            @"com.apple.control-center.HearingModule": @"ear",
            @"com.apple.control-center.AppleTVRemoteModule": @"appletvremote.gen4.fill",
            @"com.apple.control-center.CarModeModule": @"car.fill",
            @"com.apple.control-center.AlarmModule": @"alarm.fill",
            @"com.apple.control-center.StopwatchModule": @"stopwatch.fill",
            @"com.apple.control-center.TimerModule": @"timer",
            @"com.apple.mobiletimer.controlcenter.timer": @"timer",
            @"com.apple.mobiletimer.controlcenter.alarm": @"alarm.fill",
            @"com.apple.mobiletimer.controlcenter.stopwatch": @"stopwatch.fill",
            @"com.apple.donotdisturb.DoNotDisturbModule": @"moon.fill",
            @"com.apple.FocusUIModule": @"moon.fill",
            @"com.apple.Home.ControlCenter": @"house.fill",
            @"com.apple.Home.HomeControlCenterModule": @"house.fill",
            @"com.apple.MobileSMS.SilenceModule": @"bell.slash.fill",
            @"com.apple.replaykit.RecentsControlCenterModule": @"record.circle",
            @"com.apple.replaykit.ScreenRecordingControlCenterModule": @"record.circle",
            @"com.apple.ShazamKit.ShazamModule": @"waveform",
            @"com.apple.control-center.VoiceMemosModule": @"waveform.circle.fill",
            @"com.apple.VoiceMemos.ControlCenterModule": @"waveform.circle.fill",
            @"com.apple.AccessibilityUIServer.AccessibilityShortcutsModule": @"figure.stand",
            @"com.apple.accessibility.controlcenter.AccessibilityShortcuts": @"figure.stand",
            @"com.apple.control-center.AccessibilityModule": @"figure.stand",
            @"com.apple.control-center.TextSizeModule": @"textformat.size",
            @"com.apple.control-center.GuidedAccessModule": @"lock.rectangle",
            @"com.apple.Feedback.FeedbackControlCenterModule": @"exclamationmark.bubble.fill",
            @"com.apple.Translate.TranslateControlCenterModule": @"character.bubble.fill",
            @"com.apple.control-center.WalletModule": @"wallet.pass.fill",
            @"com.apple.PassbookUIService.PassbookControlCenterModule": @"wallet.pass.fill",
            @"com.apple.control-center.NFCModule": @"wave.3.right",
            @"com.apple.BarcodeSupport.BarcodeScannerControlCenterModule": @"barcode.viewfinder",
            // CC27
            @"com.kolby.cc27.respring": @"arrow.clockwise.circle.fill",
            @"com.kolby.cc27.safemode": @"exclamationmark.shield.fill",
            @"com.kolby.cc27.uicache": @"paintbrush.fill",
            @"com.kolby.cc27.userspace": @"bolt.circle.fill",
        };
    });

    NSString *exactHit = exact[identifier];
    if (exactHit) return exactHit;

    NSString *hay = [[NSString stringWithFormat:@"%@ %@", identifier ?: @"", displayName ?: @""] lowercaseString];
    struct { NSString *needle; NSString *symbol; } rules[] = {
        { @"flashlight", @"flashlight.on.fill" },
        { @"camera", @"camera.fill" },
        { @"calculator", @"plus.forwardslash.minus" },
        { @"orientation", @"lock.rotation" },
        { @"rotation", @"lock.rotation" },
        { @"lowpower", @"battery.25" },
        { @"low power", @"battery.25" },
        { @"battery", @"battery.100" },
        { @"brightness", @"sun.max.fill" },
        { @"display", @"sun.max.fill" },
        { @"volume", @"speaker.wave.3.fill" },
        { @"audio", @"speaker.wave.3.fill" },
        { @"nowplaying", @"music.note.list" },
        { @"now playing", @"music.note.list" },
        { @"music", @"music.note" },
        { @"shazam", @"waveform" },
        { @"recognize", @"waveform" },
        { @"airplay", @"airplayvideo" },
        { @"mirroring", @"airplayvideo" },
        { @"wifi", @"wifi" },
        { @"bluetooth", @"bolt.horizontal.fill" },
        { @"cellular", @"antenna.radiowaves.left.and.right" },
        { @"airplane", @"airplane" },
        { @"hotspot", @"personalhotspot" },
        { @"airdrop", @"airpod.right" },
        { @"connectivity", @"wifi" },
        { @"focus", @"moon.fill" },
        { @"donotdisturb", @"moon.fill" },
        { @"do not disturb", @"moon.fill" },
        { @"dark", @"circle.lefthalf.filled" },
        { @"appearance", @"circle.lefthalf.filled" },
        { @"home", @"house.fill" },
        { @"timer", @"timer" },
        { @"alarm", @"alarm.fill" },
        { @"stopwatch", @"stopwatch.fill" },
        { @"clock", @"clock.fill" },
        { @"record", @"record.circle" },
        { @"screen recording", @"record.circle" },
        { @"qr", @"qrcode.viewfinder" },
        { @"scan", @"qrcode.viewfinder" },
        { @"barcode", @"barcode.viewfinder" },
        { @"magnifier", @"plus.magnifyingglass" },
        { @"note", @"note.text" },
        { @"hearing", @"ear" },
        { @"accessibility", @"figure.stand" },
        { @"text size", @"textformat.size" },
        { @"font", @"textformat.size" },
        { @"guided", @"lock.rectangle" },
        { @"wallet", @"wallet.pass.fill" },
        { @"passbook", @"wallet.pass.fill" },
        { @"translate", @"character.bubble.fill" },
        { @"feedback", @"exclamationmark.bubble.fill" },
        { @"voice memo", @"waveform.circle.fill" },
        { @"voicememo", @"waveform.circle.fill" },
        { @"appletv", @"appletv.fill" },
        { @"apple tv", @"appletv.fill" },
        { @"remote", @"appletvremote.gen4.fill" },
        { @"car", @"car.fill" },
        { @"mute", @"bell.slash.fill" },
        { @"silence", @"bell.slash.fill" },
        { @"nfc", @"wave.3.right" },
        { @"respring", @"arrow.clockwise.circle.fill" },
        { @"safemode", @"exclamationmark.shield.fill" },
        { @"safe mode", @"exclamationmark.shield.fill" },
        { @"uicache", @"paintbrush.fill" },
        { @"userspace", @"bolt.circle.fill" },
        { @"reboot", @"arrow.triangle.2.circlepath" },
        { @"power", @"power" },
        { @"lock", @"lock.fill" },
        { @"flashlight", @"flashlight.on.fill" },
    };
    for (size_t i = 0; i < sizeof(rules) / sizeof(rules[0]); i++) {
        if ([hay containsString:rules[i].needle]) return rules[i].symbol;
    }

    // Stable unique-ish fallback from identifier hash so items don't all look identical.
    NSArray *palette = @[
        @"square.grid.2x2.fill", @"slider.horizontal.3", @"switch.2",
        @"dial.max.fill", @"circle.grid.cross.fill", @"button.programmable",
        @"rectangle.3.group.fill", @"puzzlepiece.extension.fill", @"sparkles"
    ];
    NSUInteger hash = identifier.hash;
    return palette[hash % palette.count];
}

- (UIImage *)_iconForIdentifier:(NSString *)identifier bundle:(NSBundle *)bundle {
    NSString *display = [self _prettyNameForIdentifier:identifier bundle:bundle];
    NSString *symbol = [self _symbolNameForIdentifier:identifier displayName:display];

    // Prefer SF Symbols first — many CC bundles ship blank/white SettingsIcon placeholders.
    UIImage *sf = [self _systemImageNamed:symbol fallbacks:@[
        @"square.grid.2x2.fill", @"switch.2", @"circle.fill"
    ]];
    if (sf) return sf;

    // Fall back to a real (non-empty) bundle icon when SF Symbols unavailable.
    for (NSString *name in @[ @"SettingsIcon", @"AppIcon", @"Icon", @"glyph", @"ModuleIcon" ]) {
        UIImage *img = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
        if (!img) continue;
        // Skip tiny/empty placeholders that render as white squares.
        if (img.size.width < 4.0 || img.size.height < 4.0) continue;
        return img;
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
    NSSet *fixed = [NSSet setWithArray:CC27LayoutStore.shared.fixedIdentifiers];
    for (CC27ModuleInfo *info in map.allValues) {
        info.fixed = [fixed containsObject:info.identifier];
        // Fixed modules are always in CC even though they're not user-enabled.
        info.enabled = info.fixed || [enabled containsObject:info.identifier];
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
