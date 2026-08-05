#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Walk Swift stored fields of a live object using type metadata.
/// Field *names* from FieldDescriptor; *offsets* from the runtime field
/// offset vector (fovo). Fail-closed: returns empty array on anything unexpected.
///
/// Each entry is a dictionary with stable keys:
/// name, offset, type, value (optional string/number), children (optional).
NSArray<NSDictionary *> *SPWalkFields(id _Nullable object, NSInteger maxDepth, NSInteger maxNodes);

NS_ASSUME_NONNULL_END
