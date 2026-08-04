#import "SPSwiftMeta.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// Swift runtime helpers — resolved at runtime, never linked hard.
typedef const char *(*SPSwiftGetTypeNameFn)(const void *type, _Bool qualified);
typedef char *(*SPSwiftDemangleFn)(const char *mangledName,
                                   size_t mangledNameLength,
                                   char *outputBuffer,
                                   size_t *outputBufferSize,
                                   uint32_t flags);

static SPSwiftGetTypeNameFn SPResolveGetTypeName(void) {
    static SPSwiftGetTypeNameFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (SPSwiftGetTypeNameFn)dlsym(RTLD_DEFAULT, "swift_getTypeName");
    });
    return fn;
}

static SPSwiftDemangleFn SPResolveDemangle(void) {
    static SPSwiftDemangleFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (SPSwiftDemangleFn)dlsym(RTLD_DEFAULT, "swift_demangle");
        if (!fn) fn = (SPSwiftDemangleFn)dlsym(RTLD_DEFAULT, "swift_stdlib_demangleImpl");
    });
    return fn;
}

static const void *SPStripISA(const void *isa) {
    if (!isa) return NULL;
    // Strip PAC / non-pointer ISA bits. Masking is enough for read-only name
    // lookup and stays portable across arm64 / arm64e without <ptrauth.h>.
    return (const void *)((uintptr_t)isa & 0x0000000FFFFFFFFFULL);
}

NSString *SPSwiftDemangle(NSString *mangled) {
    if (mangled.length == 0) return nil;
    SPSwiftDemangleFn demangle = SPResolveDemangle();
    if (!demangle) return nil;
    const char *in = mangled.UTF8String;
    if (!in) return nil;
    char *out = demangle(in, strlen(in), NULL, NULL, 0);
    if (!out) return nil;
    NSString *result = [NSString stringWithUTF8String:out];
    free(out);
    return result.length ? result : nil;
}

NSString *SPSwiftTypeNameFromMetadata(const void *metadata) {
    if (!metadata) return nil;
    uintptr_t p = (uintptr_t)metadata;
    if (p < 0x1000) return nil;

    SPSwiftGetTypeNameFn getName = SPResolveGetTypeName();
    if (!getName) return nil;

    const char *name = NULL;
    @try {
        name = getName(metadata, true);
    } @catch (__unused id e) {
        return nil;
    }
    if (!name || name[0] == '\0') return nil;
    if ((unsigned char)name[0] < 0x20) return nil;
    return [NSString stringWithUTF8String:name];
}

NSString *SPSwiftTypeNameFromObject(id object) {
    if (!object) return nil;

    Class cls = object_getClass(object);
    if (cls) {
        const void *meta = SPStripISA((__bridge const void *)cls);
        NSString *swiftName = SPSwiftTypeNameFromMetadata(meta);
        // Prefer names that look like Module.Type over empty/UIKit fallbacks.
        if (swiftName.length && ![swiftName isEqualToString:@"UIView"] &&
            ![swiftName isEqualToString:@"UIViewController"]) {
            return swiftName;
        }
    }

    const char *cname = object_getClassName(object);
    if (!cname) return nil;
    NSString *raw = [NSString stringWithUTF8String:cname];
    // Demangle any Swift mangled ObjC name (_Tt… / $s…).
    if ([raw hasPrefix:@"_Tt"] || [raw hasPrefix:@"$s"] || [raw hasPrefix:@"_T"]) {
        NSString *demangled = SPSwiftDemangle(raw);
        if (demangled.length) return demangled;
    }
    return raw;
}
