#import "OmniAIToolRegistry.h"
#import "OmniAIPreferences.h"

static NSDictionary *OATool(NSString *name, NSString *desc, NSDictionary *props, NSArray *required) {
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

static NSDictionary *OAStr(NSString *desc) { return @{ @"type": @"string", @"description": desc }; }
static NSDictionary *OANum(NSString *desc) { return @{ @"type": @"number", @"description": desc }; }

@implementation OmniAIToolRegistry

+ (NSArray<NSDictionary *> *)toolSchemas {
    NSMutableArray *tools = [NSMutableArray array];

    [tools addObject:OATool(@"describe_screen",
        @"Aggregated snapshot of what is currently on screen: frontmost app, OCR text, and key UI elements. Call this first when you need to know where you are.",
        @{}, nil)];

    [tools addObject:OATool(@"get_ui_elements",
        @"Full accessibility tree of the current screen, with labels and frames.",
        @{ @"filter": OAStr(@"Optional substring to match against element labels.") }, nil)];

    [tools addObject:OATool(@"ocr_screen",
        @"Run OCR on the current screen and return recognised text with positions.",
        @{}, nil)];

    [tools addObject:OATool(@"tap_element",
        @"Tap a UI element by its visible text or accessibility label. Prefer this over tap_screen.",
        @{ @"text": OAStr(@"Visible text or accessibility label of the element to tap.") }, @[ @"text" ])];

    [tools addObject:OATool(@"tap_screen",
        @"Tap exact screen coordinates. Only use when no element label is available.",
        @{ @"x": OANum(@"X in points."), @"y": OANum(@"Y in points.") }, @[ @"x", @"y" ])];

    [tools addObject:OATool(@"swipe_screen",
        @"Swipe from one point to another, e.g. to scroll a list.",
        @{ @"startX": OANum(@"Start X."), @"startY": OANum(@"Start Y."),
           @"endX": OANum(@"End X."), @"endY": OANum(@"End Y."),
           @"duration": OANum(@"Seconds, default 0.3.") },
        @[ @"startX", @"startY", @"endX", @"endY" ])];

    [tools addObject:OATool(@"long_press",
        @"Press and hold at a point.",
        @{ @"x": OANum(@"X."), @"y": OANum(@"Y."), @"duration": OANum(@"Seconds, default 1.0.") },
        @[ @"x", @"y" ])];

    [tools addObject:OATool(@"input_text",
        @"Type text into the currently focused field. Tap the field first.",
        @{ @"text": OAStr(@"Text to type.") }, @[ @"text" ])];

    [tools addObject:OATool(@"press_key",
        @"Press a special key such as return, delete, tab, or escape.",
        @{ @"key": OAStr(@"Key name, e.g. return.") }, @[ @"key" ])];

    [tools addObject:OATool(@"press_home", @"Go to the home screen.", @{}, nil)];

    [tools addObject:OATool(@"launch_app",
        @"Launch an app by bundle identifier.",
        @{ @"bundleId": OAStr(@"e.g. com.apple.MobileSMS") }, @[ @"bundleId" ])];

    [tools addObject:OATool(@"list_apps",
        @"List installed apps with their bundle identifiers.",
        @{}, nil)];

    [tools addObject:OATool(@"get_frontmost_app",
        @"Which app is in the foreground right now.", @{}, nil)];

    [tools addObject:OATool(@"open_url",
        @"Open a URL or URL scheme.",
        @{ @"url": OAStr(@"Full URL or scheme.") }, @[ @"url" ])];

    [tools addObject:OATool(@"get_clipboard", @"Read the clipboard.", @{}, nil)];
    [tools addObject:OATool(@"set_clipboard", @"Write the clipboard.",
        @{ @"text": OAStr(@"Text to place on the clipboard.") }, @[ @"text" ])];
    [tools addObject:OATool(@"get_device_info",
        @"Model, iOS version, battery, storage.", @{}, nil)];

    if ([OmniAIPreferences shared].allowShell) {
        [tools addObject:OATool(@"run_command",
            @"Run a shell command on the device. Powerful and dangerous — use only when nothing else will do.",
            @{ @"command": OAStr(@"Shell command.") }, @[ @"command" ])];
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
