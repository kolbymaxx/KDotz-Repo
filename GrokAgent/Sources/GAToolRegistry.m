#import "GAToolRegistry.h"
#import "GAPreferences.h"

static NSDictionary *GATool(NSString *name, NSString *desc, NSDictionary *props, NSArray *required) {
    return @{
        @"type": @"function",
        @"function": @{
            @"name": name,
            @"description": desc,
            @"parameters": @{
                @"type": @"object",
                @"properties": props ?: @{},
                @"required": required ?: @[],
            },
        },
    };
}

static NSDictionary *GAStr(NSString *desc)  { return @{@"type": @"string",  @"description": desc}; }
static NSDictionary *GANum(NSString *desc)  { return @{@"type": @"number",  @"description": desc}; }

@implementation GAToolRegistry

+ (NSArray<NSDictionary *> *)toolSchemas {
    NSMutableArray *tools = [NSMutableArray array];

    // --- Seeing ---
    [tools addObject:GATool(@"describe_screen",
        @"Aggregated snapshot of what is currently on screen: frontmost app, OCR text, and key UI elements. Call this first when you need to know where you are.",
        @{}, nil)];

    [tools addObject:GATool(@"get_ui_elements",
        @"Full accessibility tree of the current screen, with labels and frames. Use when describe_screen is not specific enough.",
        @{@"filter": GAStr(@"Optional substring to match against element labels.")}, nil)];

    [tools addObject:GATool(@"ocr_screen",
        @"Run OCR on the current screen and return recognised text with positions.",
        @{}, nil)];

    // --- Touching ---
    [tools addObject:GATool(@"tap_element",
        @"Tap a UI element by its visible text or accessibility label. Prefer this over tap_screen — it survives layout changes.",
        @{@"text": GAStr(@"Visible text or accessibility label of the element to tap.")}, @[@"text"])];

    [tools addObject:GATool(@"tap_screen",
        @"Tap exact screen coordinates. Only use when no element label is available.",
        @{@"x": GANum(@"X in points."), @"y": GANum(@"Y in points.")}, @[@"x", @"y"])];

    [tools addObject:GATool(@"swipe_screen",
        @"Swipe from one point to another, e.g. to scroll a list.",
        @{@"startX": GANum(@"Start X."), @"startY": GANum(@"Start Y."),
          @"endX": GANum(@"End X."),     @"endY": GANum(@"End Y."),
          @"duration": GANum(@"Seconds, default 0.3.")},
        @[@"startX", @"startY", @"endX", @"endY"])];

    [tools addObject:GATool(@"long_press",
        @"Press and hold at a point.",
        @{@"x": GANum(@"X."), @"y": GANum(@"Y."), @"duration": GANum(@"Seconds, default 1.0.")},
        @[@"x", @"y"])];

    // --- Typing ---
    [tools addObject:GATool(@"input_text",
        @"Type text into the currently focused field. Tap the field first.",
        @{@"text": GAStr(@"Text to type.")}, @[@"text"])];

    [tools addObject:GATool(@"press_key",
        @"Press a special key such as return, delete, tab, or escape.",
        @{@"key": GAStr(@"Key name, e.g. return.")}, @[@"key"])];

    // --- Navigating ---
    [tools addObject:GATool(@"press_home",
        @"Go to the home screen.", @{}, nil)];

    [tools addObject:GATool(@"launch_app",
        @"Launch an app by bundle identifier.",
        @{@"bundleId": GAStr(@"e.g. com.apple.MobileSMS")}, @[@"bundleId"])];

    [tools addObject:GATool(@"list_apps",
        @"List installed apps with their bundle identifiers. Use when unsure of a bundle ID.",
        @{}, nil)];

    [tools addObject:GATool(@"get_frontmost_app",
        @"Which app is in the foreground right now.", @{}, nil)];

    [tools addObject:GATool(@"open_url",
        @"Open a URL or URL scheme.",
        @{@"url": GAStr(@"Full URL or scheme.")}, @[@"url"])];

    // --- Misc ---
    [tools addObject:GATool(@"get_clipboard", @"Read the clipboard.", @{}, nil)];
    [tools addObject:GATool(@"set_clipboard", @"Write the clipboard.",
        @{@"text": GAStr(@"Text to place on the clipboard.")}, @[@"text"])];
    [tools addObject:GATool(@"get_device_info",
        @"Model, iOS version, battery, storage.", @{}, nil)];

    if ([GAPreferences shared].allowShell) {
        [tools addObject:GATool(@"run_command",
            @"Run a shell command on the device. Powerful and dangerous — use only when nothing else will do.",
            @{@"command": GAStr(@"Shell command.")}, @[@"command"])];
    }

    return tools;
}

+ (BOOL)isToolAllowed:(NSString *)name {
    for (NSDictionary *tool in [self toolSchemas]) {
        if ([tool[@"function"][@"name"] isEqualToString:name]) return YES;
    }
    return NO;
}

@end
