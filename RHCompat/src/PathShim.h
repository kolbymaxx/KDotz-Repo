#import <Foundation/Foundation.h>
#import <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// True when RootHide jbroot is live and the user has not disabled the shim.
bool RHCompatEnabled(void);

/// Resolve the current jbroot prefix (no trailing slash), or nil if unavailable.
NSString *RHCompatJBRootPrefix(void);

/**
 Rewrite a narrow set of legacy rootless / classic paths into the live jbroot.

 Returns NULL when no rewrite is needed (caller must use the original path).
 Returned pointer is valid until the next rewrite on the same thread.
 */
const char *RHCompatRewritePath(const char *path);

/// NSString convenience wrapper; returns nil when no rewrite is needed.
NSString *RHCompatRewritePathNS(NSString *path);

/// Recursion guard — call around original file APIs invoked from our hooks.
void RHCompatEnterBypass(void);
void RHCompatLeaveBypass(void);
bool RHCompatInBypass(void);

#ifdef __cplusplus
}
#endif
