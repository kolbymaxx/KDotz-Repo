#import "CC27ActionModule.h"
#import <dlfcn.h>
#import <spawn.h>

extern char **environ;

@implementation CC27ActionContentViewController {
    UIButton *_button;
    UIImageView *_icon;
    UILabel *_label;
}

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.view.backgroundColor = UIColor.clearColor;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _button = [UIButton buttonWithType:UIButtonTypeCustom];
    _button.translatesAutoresizingMaskIntoConstraints = NO;
    [_button addTarget:self action:@selector(_tapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_button];

    _icon = [[UIImageView alloc] initWithFrame:CGRectZero];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.tintColor = UIColor.whiteColor;
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    [_button addSubview:_icon];

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.numberOfLines = 2;
    [_button addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_button.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_button.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_button.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_button.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_icon.centerXAnchor constraintEqualToAnchor:_button.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_button.centerYAnchor],
        [_icon.widthAnchor constraintEqualToConstant:26],
        [_icon.heightAnchor constraintEqualToConstant:26],
        [_label.leadingAnchor constraintEqualToAnchor:_button.leadingAnchor constant:4],
        [_label.trailingAnchor constraintEqualToAnchor:_button.trailingAnchor constant:-4],
        [_label.bottomAnchor constraintEqualToAnchor:_button.bottomAnchor constant:-6],
    ]];

    _label.hidden = YES; // 1x1 glass circles clip the subtitle; icon-only is readable.
    [self _refreshChrome];
}

- (void)_refreshChrome {
    if (@available(iOS 13.0, *)) {
        _icon.image = [[UIImage systemImageNamed:self.symbolName ?: @"sparkles"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    _label.text = self.titleText;
}

- (void)setSymbolName:(NSString *)symbolName {
    _symbolName = [symbolName copy];
    [self _refreshChrome];
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    [self _refreshChrome];
}

- (void)_tapped {
    if (self.action) self.action();
}

- (CGFloat)preferredExpandedContentHeight { return 0; }
- (BOOL)providesOwnPlatter { return NO; }
- (BOOL)_canShowWhileLocked { return YES; }

@end

@implementation CC27ActionModule

- (instancetype)initWithIdentifier:(NSString *)identifier
                        symbolName:(NSString *)symbolName
                             title:(NSString *)title
                            action:(void (^)(void))action {
    if ((self = [super init])) {
        _moduleIdentifier = [identifier copy];
        _contentViewController = [CC27ActionContentViewController new];
        _contentViewController.symbolName = symbolName;
        _contentViewController.titleText = title;
        _contentViewController.action = action;
    }
    return self;
}

- (UIViewController *)backgroundViewController { return nil; }

- (CCUILayoutSize)moduleSizeForOrientation:(int)orientation {
    (void)orientation;
    return (CCUILayoutSize){1, 1};
}

@end

void CC27Spawn(NSArray<NSString *> *args) {
    if (args.count == 0) return;
    NSString *leaf = args.firstObject.lastPathComponent;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    const char *(*jbrootFn)(const char *) = (const char *(*)(const char *))dlsym(RTLD_DEFAULT, "jbroot");
    if (jbrootFn) {
        for (NSString *prefix in @[ @"/usr/bin/", @"/bin/" ]) {
            const char *p = jbrootFn([[prefix stringByAppendingString:leaf] UTF8String]);
            if (p && p[0]) [candidates addObject:[NSString stringWithUTF8String:p]];
        }
    }
    [candidates addObject:args.firstObject];
    [candidates addObject:[@"/var/jb/usr/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/usr/bin/" stringByAppendingString:leaf]];
    [candidates addObject:[@"/bin/" stringByAppendingString:leaf]];

    NSString *binary = nil;
    for (NSString *c in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:c]) { binary = c; break; }
    }
    if (!binary) binary = args.firstObject;

    NSUInteger argc = args.count;
    char **argv = calloc(argc + 1, sizeof(char *));
    argv[0] = strdup(binary.fileSystemRepresentation);
    for (NSUInteger i = 1; i < argc; i++) argv[i] = strdup(args[i].fileSystemRepresentation);
    pid_t pid = 0;
    posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    for (NSUInteger i = 0; i < argc; i++) free(argv[i]);
    free(argv);
}
