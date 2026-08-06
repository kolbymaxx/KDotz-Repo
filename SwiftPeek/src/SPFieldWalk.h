#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Walk Swift stored fields of a live object using type metadata.
/// Field *names* from FieldDescriptor; *offsets* from the runtime field
/// offset vector (fovo). Fail-closed: returns empty array on anything unexpected.
///
/// Hardened (0.3.3): only `_UIHostingView` / `UIHostingView` UIViews;
/// rejects UIViewControllers and MusicApplication types; depth forced to 0
/// (names/offsets/types only — no value previews or nested walks).
/// `maxDepth` / `maxNodes` are clamped; callers should pass 0 / 8.
///
/// Each entry is a dictionary with stable keys: name, offset, type.
NSArray<NSDictionary *> *SPWalkFields(id _Nullable object, NSInteger maxDepth, NSInteger maxNodes);

NS_ASSUME_NONNULL_END
