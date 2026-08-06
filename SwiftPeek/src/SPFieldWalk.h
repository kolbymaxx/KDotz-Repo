#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Walk Swift stored fields of a live object using type metadata.
/// Field *names* from FieldDescriptor; *offsets* from the runtime field
/// offset vector (fovo). Fail-closed: returns empty array on anything unexpected.
///
/// Hosting path: only `_UIHostingView` / `UIHostingView` UIViews.
/// Depth forced to 0 (names/offsets/types only — no value previews / nesting).
/// `maxDepth` / `maxNodes` are clamped; callers should pass 0 / 8.
///
/// Each entry is a dictionary with stable keys: name, offset, type.
NSArray<NSDictionary *> *SPWalkFields(id _Nullable object, NSInteger maxDepth, NSInteger maxNodes);

/// Music 16.x has no `_UIHostingView` in the window tree (proven 0.3.4).
/// Allowlisted Music *UIView* classes only — never UIViewControllers.
/// Same depth-0 envelope as SPWalkFields.
NSArray<NSDictionary *> *SPWalkFieldsMusicView(id _Nullable object,
                                               NSInteger maxDepth,
                                               NSInteger maxNodes);

/// True if class name matches the Music UIView meta allowlist.
BOOL SPClassNameIsMusicMetaView(const char * _Nullable name);

NS_ASSUME_NONNULL_END
