#import "Music27.h"
#import <objc/runtime.h>

// Library Pins — floating "Pinned" row at the top of the Library root, plus
// Pin/Unpin entries in context menus and a pin button on detail nav bars.
// Mirrors the iOS 26/27 Library pin affordance.

static const NSInteger kM27PinnedHeaderTag = 0x4D323750; // 'M27P'
static const NSInteger kM27PinButtonTag = 0x4D323742;    // 'M27B'
static const CGFloat kM27PinnedHeaderHeight = 128.0;

static BOOL M27IsLibraryRoot(UIViewController *vc) {
    if (!vc) return NO;
    // SwiftPeek: MusicApplication.LibraryViewController is the Library root host.
    // Do not attach overlays to LibraryMenu / LibraryRecentlyAdded.
    return M27ClassNameHasSuffix(vc, @"LibraryViewController");
}

static M27PinType M27InferTypeFromClassName(NSString *name) {
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"playlist"]) return M27PinTypePlaylist;
    if ([lower containsString:@"artist"]) return M27PinTypeArtist;
    if ([lower containsString:@"album"]) return M27PinTypeAlbum;
    return M27PinTypeOther;
}

static NSString *M27TypeLabel(M27PinType type) {
    switch (type) {
        case M27PinTypePlaylist: return @"Playlist";
        case M27PinTypeArtist: return @"Artist";
        case M27PinTypeAlbum: return @"Album";
        default: return @"Item";
    }
}

static NSString *M27IdentifierForTitle(NSString *title, NSString *subtitle, M27PinType type) {
    return [NSString stringWithFormat:@"%@|%@|%ld",
            title ?: @"", subtitle ?: @"", (long)type];
}

static M27PinnedItem *M27ItemFromViewController(UIViewController *vc) {
    if (!vc) return nil;
    NSString *title = vc.title ?: vc.navigationItem.title;
    if (title.length == 0) {
        // Fall back to a large label in the view.
        for (UIView *sub in vc.view.subviews) {
            if ([sub isKindOfClass:UILabel.class]) {
                UILabel *label = (UILabel *)sub;
                if (label.font.pointSize >= 20 && label.text.length > 0) {
                    title = label.text;
                    break;
                }
            }
        }
    }
    if (title.length == 0) return nil;

    M27PinType type = M27InferTypeFromClassName(NSStringFromClass(vc.class));
    M27PinnedItem *item = [M27PinnedItem new];
    item.title = title;
    item.subtitle = M27TypeLabel(type);
    item.type = type;
    item.identifier = M27IdentifierForTitle(title, item.subtitle, type);

    UIImage *art = M27LargestImageInView(vc.view);
    if (art) {
        item.artworkJPEG = UIImageJPEGRepresentation(art, 0.7);
    }
    return item;
}

static void M27PresentPinError(UIViewController *host, NSError *error) {
    if (!host || !error) return;
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Music27"
                                            message:error.localizedDescription
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [host presentViewController:alert animated:YES completion:nil];
}

static UIAction *M27PinActionForItem(M27PinnedItem *item, UIViewController *host) {
    BOOL pinned = [M27PinStore.shared isPinned:item.identifier];
    NSString *title = pinned
        ? [NSString stringWithFormat:@"Unpin %@", item.title ?: @""]
        : [NSString stringWithFormat:@"Pin %@", item.title ?: @""];
    UIImage *image = [UIImage systemImageNamed:pinned ? @"pin.slash" : @"pin"];
    return [UIAction actionWithTitle:title image:image identifier:@"com.music27.pin" handler:^(__kindof UIAction *action) {
        if (pinned) {
            [M27PinStore.shared unpinIdentifier:item.identifier];
        } else {
            NSError *error = nil;
            if (![M27PinStore.shared pinItem:item error:&error]) {
                M27PresentPinError(host, error);
            }
        }
    }];
}

static UIMenu *M27MenuByPrependingPin(UIMenu *menu, M27PinnedItem *item, UIViewController *host) {
    if (!item) return menu;
    UIAction *pin = M27PinActionForItem(item, host);
    if (!menu) {
        return [UIMenu menuWithTitle:@"" children:@[ pin ]];
    }
    NSMutableArray *children = [NSMutableArray arrayWithObject:pin];
    [children addObjectsFromArray:menu.children];
    return [UIMenu menuWithTitle:menu.title
                           image:menu.image
                      identifier:menu.identifier
                         options:menu.options
                        children:children];
}

static void M27AttachPinnedHeader(UIViewController *vc) {
    M27Prefs *prefs = M27Prefs.shared;
    UIView *existing = [vc.view viewWithTag:kM27PinnedHeaderTag];

    if (!(prefs.enabled && prefs.libraryPinsEnabled)) {
        [existing removeFromSuperview];
        return;
    }

    UIViewController *target = vc;
    if ([vc isKindOfClass:UINavigationController.class]) {
        target = ((UINavigationController *)vc).visibleViewController ?: vc;
    }
    if (!M27IsLibraryRoot(target)) {
        [existing removeFromSuperview];
        return;
    }

    M27PinnedHeaderView *header = (M27PinnedHeaderView *)existing;
    if (![header isKindOfClass:M27PinnedHeaderView.class]) {
        CGFloat top = target.view.safeAreaInsets.top + 8.0;
        header = [[M27PinnedHeaderView alloc] initWithFrame:CGRectMake(0, top, target.view.bounds.size.width, kM27PinnedHeaderHeight)];
        header.tag = kM27PinnedHeaderTag;
        header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        __weak UIViewController *weakTarget = target;
        header.onSelect = ^(M27PinnedItem *item) {
            UIViewController *host = weakTarget;
            if (!host) return;
            NSString *message = [NSString stringWithFormat:@"Pinned %@ (local to this device).",
                                 M27TypeLabel(item.type)];
            UIAlertController *alert =
                [UIAlertController alertControllerWithTitle:item.title ?: @"Pinned"
                                                    message:message
                                             preferredStyle:UIAlertControllerStyleActionSheet];
            [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Unpin"]
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(__unused UIAlertAction *a) {
                [M27PinStore.shared unpinIdentifier:item.identifier];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            alert.popoverPresentationController.sourceView = host.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(host.view.bounds.size.width / 2.0,
                                                                        host.view.safeAreaInsets.top + 40,
                                                                        1, 1);
            [host presentViewController:alert animated:YES completion:nil];
        };
        [target.view addSubview:header];
    }

    CGFloat top = target.view.safeAreaInsets.top + 8.0;
    header.frame = CGRectMake(0, top, target.view.bounds.size.width, kM27PinnedHeaderHeight);
    // Hide the overlay when there are no pins — never rewrite Music's scroll
    // insets (that can blank SwiftUI Library pages).
    BOOL hasPins = M27PinStore.shared.pins.count > 0;
    header.hidden = !hasPins;
    if (hasPins) {
        [header reload];
        [target.view bringSubviewToFront:header];
    }
}

static BOOL M27LooksLikePinnableDetail(UIViewController *vc) {
    if (!vc || M27IsLibraryRoot(vc) || M27IsProtectedMusicHost(vc)) return NO;
    return M27ClassNameHasSuffix(vc, @"AlbumDetailViewController")
        || M27ClassNameHasSuffix(vc, @"PlaylistDetailViewController")
        || M27ClassNameHasSuffix(vc, @"ArtistViewController");
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.libraryPinsEnabled)) return;
    if (!M27IsLibraryRoot(self)) return;
    M27AttachPinnedHeader(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.libraryPinsEnabled)) return;
    if ([self.view viewWithTag:kM27PinnedHeaderTag] || M27IsLibraryRoot(self)) {
        M27AttachPinnedHeader(self);
    }
}

%end

%hook UINavigationBar

- (void)didMoveToWindow {
    %orig;
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.libraryPinsEnabled)) return;
    if (!self.window) return;

    UIViewController *top = M27TopViewController();
    if (!top || !M27LooksLikePinnableDetail(top)) return;

    // Avoid duplicating the pin button.
    for (UIBarButtonItem *item in top.navigationItem.rightBarButtonItems ?: @[]) {
        if (item.tag == kM27PinButtonTag) return;
    }

    M27PinnedItem *pinnedItem = M27ItemFromViewController(top);
    if (!pinnedItem) return;

    UIAction *action = M27PinActionForItem(pinnedItem, top);
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithPrimaryAction:action];
    button.tag = kM27PinButtonTag;

    NSMutableArray *items = [NSMutableArray arrayWithArray:top.navigationItem.rightBarButtonItems ?: @[]];
    [items insertObject:button atIndex:0];
    top.navigationItem.rightBarButtonItems = items;
}

%end

%hook UIContextMenuConfiguration

+ (instancetype)configurationWithIdentifier:(id<NSCopying>)identifier
                           previewProvider:(UIContextMenuContentPreviewProvider)previewProvider
                            actionProvider:(UIContextMenuActionProvider)actionProvider {
    M27Prefs *prefs = M27Prefs.shared;
    if (!(prefs.enabled && prefs.libraryPinsEnabled) || !actionProvider) {
        return %orig;
    }

    UIContextMenuActionProvider wrapped = ^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIMenu *original = actionProvider(suggested);
        UIViewController *top = M27TopViewController();
        M27PinnedItem *item = M27ItemFromViewController(top);
        // If the top VC isn't pinnable, try to infer from suggested menu titles.
        if (!item) {
            for (UIMenuElement *element in suggested) {
                NSString *t = element.title;
                if (t.length == 0) continue;
                // Heuristic: skip system verbs.
                NSString *lower = t.lowercaseString;
                if ([lower containsString:@"play"] || [lower containsString:@"shuffle"] ||
                    [lower containsString:@"delete"] || [lower containsString:@"share"] ||
                    [lower containsString:@"download"] || [lower containsString:@"add"]) {
                    continue;
                }
                M27PinnedItem *candidate = [M27PinnedItem new];
                candidate.title = t;
                candidate.type = M27PinTypeOther;
                candidate.subtitle = @"Item";
                candidate.identifier = M27IdentifierForTitle(t, candidate.subtitle, candidate.type);
                item = candidate;
                break;
            }
        }
        return M27MenuByPrependingPin(original, item, top);
    };
    return %orig(identifier, previewProvider, wrapped);
}

%end
