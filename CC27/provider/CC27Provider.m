#import "CC27ActionModule.h"

@protocol CCSModuleProvider <NSObject>
- (NSUInteger)numberOfProvidedModules;
- (NSString *)identifierForModuleAtIndex:(NSUInteger)index;
- (id)moduleInstanceForModuleIdentifier:(NSString *)identifier;
@optional
- (NSString *)displayNameForModuleIdentifier:(NSString *)identifier;
- (UIImage *)settingsIconForModuleIdentifier:(NSString *)identifier;
- (NSSet *)supportedDeviceFamiliesForModuleWithIdentifier:(NSString *)identifier;
- (NSSet *)requiredDeviceCapabilitiesForModuleWithIdentifier:(NSString *)identifier;
@end

@interface CC27Provider : NSObject <CCSModuleProvider>
@end

@implementation CC27Provider {
    NSArray<NSString *> *_identifiers;
    NSMutableDictionary<NSString *, CC27ActionModule *> *_modules;
}

- (instancetype)init {
    if ((self = [super init])) {
        _identifiers = @[
            @"com.kolby.cc27.respring",
            @"com.kolby.cc27.safemode",
            @"com.kolby.cc27.uicache",
            @"com.kolby.cc27.userspace",
        ];
        _modules = [NSMutableDictionary new];
    }
    return self;
}

- (NSUInteger)numberOfProvidedModules {
    return _identifiers.count;
}

- (NSString *)identifierForModuleAtIndex:(NSUInteger)index {
    return index < _identifiers.count ? _identifiers[index] : nil;
}

- (NSString *)displayNameForModuleIdentifier:(NSString *)identifier {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"com.kolby.cc27.respring": @"Respring",
            @"com.kolby.cc27.safemode": @"Safe Mode",
            @"com.kolby.cc27.uicache": @"UICache",
            @"com.kolby.cc27.userspace": @"Userspace Reboot",
        };
    });
    return names[identifier] ?: identifier;
}

- (UIImage *)settingsIconForModuleIdentifier:(NSString *)identifier {
    NSDictionary *symbols = @{
        @"com.kolby.cc27.respring": @"arrow.clockwise",
        @"com.kolby.cc27.safemode": @"exclamationmark.shield.fill",
        @"com.kolby.cc27.uicache": @"paintbrush.fill",
        @"com.kolby.cc27.userspace": @"bolt.fill",
    };
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:symbols[identifier] ?: @"switch.2"];
    }
    return nil;
}

- (id)moduleInstanceForModuleIdentifier:(NSString *)identifier {
    CC27ActionModule *existing = _modules[identifier];
    if (existing) return existing;

    NSString *title = [self displayNameForModuleIdentifier:identifier];
    NSString *symbol = @"sparkles";
    void (^action)(void) = nil;

    if ([identifier isEqualToString:@"com.kolby.cc27.respring"]) {
        symbol = @"arrow.clockwise";
        action = ^{ CC27Spawn(@[ @"/usr/bin/sbreload" ]); };
    } else if ([identifier isEqualToString:@"com.kolby.cc27.safemode"]) {
        symbol = @"exclamationmark.shield.fill";
        action = ^{
            // Kick SpringBoard into safe mode via common jailbreak helpers.
            CC27Spawn(@[ @"/usr/bin/killall", @"-SEGV", @"SpringBoard" ]);
        };
    } else if ([identifier isEqualToString:@"com.kolby.cc27.uicache"]) {
        symbol = @"paintbrush.fill";
        action = ^{ CC27Spawn(@[ @"/usr/bin/uicache", @"-a" ]); };
    } else if ([identifier isEqualToString:@"com.kolby.cc27.userspace"]) {
        symbol = @"bolt.fill";
        action = ^{ CC27Spawn(@[ @"/bin/launchctl", @"reboot", @"userspace" ]); };
    } else {
        return nil;
    }

    CC27ActionModule *module = [[CC27ActionModule alloc] initWithIdentifier:identifier
                                                                 symbolName:symbol
                                                                      title:title
                                                                     action:action];
    _modules[identifier] = module;
    return module;
}

- (NSSet *)supportedDeviceFamiliesForModuleWithIdentifier:(NSString *)identifier {
    (void)identifier;
    return [NSSet setWithObjects:@1, @2, nil];
}

- (NSSet *)requiredDeviceCapabilitiesForModuleWithIdentifier:(NSString *)identifier {
    (void)identifier;
    return [NSSet setWithObject:@"arm64"];
}

@end
