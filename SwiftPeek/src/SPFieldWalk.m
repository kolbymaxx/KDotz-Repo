#import "SPFieldWalk.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdint.h>
#import <string.h>

// Swift type-context kinds (flags & 0x1F) — same as tools/swiftmd.c
enum {
    SPKindClass  = 16,
    SPKindStruct = 17,
    SPKindEnum   = 18,
};

// Hard caps for the Music-safe path (0.3.3). Depth 0 = names/offsets/types only.
static const uint32_t kSPMaxFieldsPerObject = 8;
static const NSInteger kSPHardMaxDepth = 0;
static const NSInteger kSPHardMaxNodes = 32;

static const void *SPStripMeta(const void *isa) {
    if (!isa) return NULL;
    return (const void *)((uintptr_t)isa & 0x0000000FFFFFFFFFULL);
}

static int SPReadableCString(const char *p, size_t max) {
    if (!p) return 0;
    size_t n = 0;
    for (; n < max; n++) {
        unsigned char c = (unsigned char)p[n];
        if (c == 0) return n > 0;
        if (c < 0x20 || c > 0x7E) return 0;
    }
    return 0;
}

static uint64_t SPRelDirect(const void *at) {
    if (!at) return 0;
    int32_t v = 0;
    memcpy(&v, at, sizeof(v));
    if (v == 0) return 0;
    return (uint64_t)(uintptr_t)at + (int64_t)v;
}

static const char *SPReadCStringAt(uint64_t addr) {
    if (addr < 0x1000) return NULL;
    const char *p = (const char *)(uintptr_t)addr;
    return SPReadableCString(p, 256) ? p : NULL;
}

static BOOL SPClassNameLooksLikeHostingView(const char *name) {
    if (!name) return NO;
    if (strstr(name, "_UIHostingView") != NULL) return YES;
    if (strstr(name, "UIHostingView") != NULL) return YES;
    if (strstr(name, "HostingView") != NULL && strstr(name, "Controller") == NULL) {
        return YES;
    }
    return NO;
}

static BOOL SPObjectIsHostingView(id object) {
    if (![object isKindOfClass:[UIView class]]) return NO;
    if ([object isKindOfClass:[UIViewController class]]) return NO;
    Class hv = NSClassFromString(@"_UIHostingView");
    if (hv && [object isKindOfClass:hv]) return YES;
    Class hv2 = NSClassFromString(@"UIHostingView");
    if (hv2 && [object isKindOfClass:hv2]) return YES;
    return SPClassNameLooksLikeHostingView(object_getClassName(object));
}

/// Reject types that previously SIGSEGV'd under FOVO walks on Music.
static BOOL SPClassNameIsMetaDenylisted(const char *name) {
    if (!name) return YES;
    if (strstr(name, "ViewController") != NULL) return YES;
    if (strstr(name, "UIHostingController") != NULL) return YES;
    if (strstr(name, "ViewGraph") != NULL) return YES;
    if (strstr(name, "AttributeGraph") != NULL) return YES;
    if (strstr(name, "ScrollView") != NULL) return YES;
    return NO;
}

BOOL SPClassNameIsMusicMetaView(const char *name) {
    if (!name) return NO;
    if (SPClassNameIsMetaDenylisted(name)) return NO;
    // From 0.3.4 view_class_sample on iPhone X / 16.7.14 — UIViews only.
    static const char *const allow[] = {
        "NowPlayingContentView",
        "PaletteContainerView",
        "UberNavigationTitleView",
        "MusicArtworkComponentImageView",
        "NowPlayingTransportControlStackView",
        "NowPlayingVibrancyEffectView",
        NULL,
    };
    for (const char *const *p = allow; *p; p++) {
        if (strstr(name, *p) != NULL) return YES;
    }
    return NO;
}

static const void *SPFindTypeDescriptor(const void *metadata, uint32_t *outKind) {
    if (!metadata) return NULL;
    const void *const *words = (const void *const *)metadata;
    for (int i = 1; i <= 24; i++) {
        const void *cand = words[i];
        if (!cand) continue;
        uintptr_t a = (uintptr_t)cand;
        if (a < 0x100000000ULL || (a & 0x3)) continue;

        uint32_t flags = 0;
        memcpy(&flags, cand, sizeof(flags));
        uint32_t kind = flags & 0x1Fu;
        if (kind != SPKindClass && kind != SPKindStruct && kind != SPKindEnum) continue;

        uint64_t nameAddr = SPRelDirect((const uint8_t *)cand + 8);
        if (!SPReadCStringAt(nameAddr)) continue;

        if (outKind) *outKind = kind;
        return cand;
    }
    return NULL;
}

static const void *SPFieldDescriptor(const void *typeDesc) {
    if (!typeDesc) return NULL;
    uint64_t fd = SPRelDirect((const uint8_t *)typeDesc + 16);
    if (fd < 0x1000) return NULL;
    const void *p = (const void *)(uintptr_t)fd;
    uint16_t recSize = 0;
    uint32_t nfields = 0;
    memcpy(&recSize, (const uint8_t *)p + 10, 2);
    memcpy(&nfields, (const uint8_t *)p + 12, 4);
    if (recSize != 12 || nfields == 0 || nfields > 256) return NULL;
    return p;
}

static uint32_t SPReadFOVO(const void *typeDesc, uint32_t kind) {
    uint32_t maybeFields = 0, maybeFOVO = 0;
    memcpy(&maybeFields, (const uint8_t *)typeDesc + 20, 4);
    memcpy(&maybeFOVO, (const uint8_t *)typeDesc + 24, 4);
    if (maybeFields > 0 && maybeFields <= 256 && maybeFOVO > 0 && maybeFOVO < 128) {
        return maybeFOVO;
    }
    if (kind == SPKindClass) {
        memcpy(&maybeFOVO, (const uint8_t *)typeDesc + 44, 4);
        if (maybeFOVO > 0 && maybeFOVO < 128) return maybeFOVO;
    }
    return 0;
}

static NSString *SPMangledTypePrefix(const char *ftype) {
    if (!ftype) return @"?";
    char buf[96];
    size_t n = 0;
    for (; n < sizeof(buf) - 1 && ftype[n]; n++) {
        unsigned char c = (unsigned char)ftype[n];
        if (c < 0x20) break;
        buf[n] = (char)c;
    }
    buf[n] = 0;
    return n ? @(buf) : @"?";
}

static NSArray *SPWalkFieldsFromMetadata(const void *metadata, const void *valueBase,
                                         BOOL isHeapObject,
                                         NSInteger depth, NSInteger maxDepth,
                                         NSInteger *nodeBudget);

static NSArray *SPWalkFieldsFromMetadata(const void *metadata, const void *valueBase,
                                         BOOL isHeapObject,
                                         NSInteger depth, NSInteger maxDepth,
                                         NSInteger *nodeBudget) {
    if (!metadata || !valueBase || !nodeBudget || *nodeBudget <= 0 || depth > maxDepth) {
        return @[];
    }

    uint32_t kind = 0;
    const void *desc = SPFindTypeDescriptor(metadata, &kind);
    if (!desc) return @[];

    const void *fd = SPFieldDescriptor(desc);
    if (!fd) return @[];

    uint16_t recSize = 0;
    uint32_t nfields = 0;
    memcpy(&recSize, (const uint8_t *)fd + 10, 2);
    memcpy(&nfields, (const uint8_t *)fd + 12, 4);
    if (recSize != 12 || nfields == 0 || nfields > 128) return @[];

    if (kind == SPKindStruct) {
        uint32_t nf = 0;
        memcpy(&nf, (const uint8_t *)desc + 20, 4);
        if (nf > 0 && nf < nfields) nfields = nf;
    }
    if (nfields > kSPMaxFieldsPerObject) nfields = kSPMaxFieldsPerObject;

    uint32_t fovo = SPReadFOVO(desc, kind);
    if (fovo == 0 || fovo > 128) return @[];

    const uint32_t *offsets = (const uint32_t *)((const uint8_t *)metadata +
                                                (size_t)fovo * sizeof(void *));
    for (uint32_t i = 0; i < nfields && i < 4; i++) {
        if (offsets[i] > 0x10000) return @[];
    }

    NSMutableArray *out = [NSMutableArray array];
    for (uint32_t i = 0; i < nfields && *nodeBudget > 0; i++) {
        (*nodeBudget)--;
        const uint8_t *rec = (const uint8_t *)fd + 16 + (size_t)i * recSize;
        uint64_t nameA = SPRelDirect(rec + 8);
        uint64_t typeA = SPRelDirect(rec + 4);
        const char *fname = SPReadCStringAt(nameA);
        const char *ftype = NULL;
        if (typeA >= 0x1000) {
            const char *tp = (const char *)(uintptr_t)typeA;
            if ((unsigned char)tp[0] >= 0x20) ftype = tp;
        }

        uint32_t offset = offsets[i];
        if (isHeapObject && offset < sizeof(void *) && (!fname || !fname[0])) continue;

        NSString *name = fname ? @(fname) : [NSString stringWithFormat:@"$field%u", i];
        // Names / offsets / mangled types only — no heap value previews.
        // Bridging class pointers + String storage crashed Music on 0.3.0.
        NSDictionary *entry = @{
            @"name": name,
            @"offset": @(offset),
            @"type": SPMangledTypePrefix(ftype),
        };
        [out addObject:entry];
    }
    return out;
}

static NSArray<NSDictionary *> *SPWalkFieldsCommon(id object, NSInteger maxDepth,
                                                   NSInteger maxNodes) {
    (void)maxDepth;
    maxDepth = kSPHardMaxDepth;
    if (maxNodes <= 0 || maxNodes > kSPHardMaxNodes) maxNodes = kSPHardMaxNodes;

    Class cls = object_getClass(object);
    if (!cls) return @[];
    const void *metadata = SPStripMeta((__bridge const void *)cls);
    if (!metadata) return @[];
    NSInteger budget = maxNodes;
    return SPWalkFieldsFromMetadata(metadata, (__bridge const void *)object,
                                    YES, 0, maxDepth, &budget) ?: @[];
}

NSArray<NSDictionary *> *SPWalkFields(id object, NSInteger maxDepth, NSInteger maxNodes) {
    if (!object) return @[];

    @try {
        // Hard gates: hosting UIView only. Never walk UIViewControllers.
        if (!SPObjectIsHostingView(object)) return @[];
        const char *cn = object_getClassName(object);
        if (SPClassNameIsMetaDenylisted(cn)) return @[];
        return SPWalkFieldsCommon(object, maxDepth, maxNodes);
    } @catch (__unused id e) {
        return @[];
    }
}

NSArray<NSDictionary *> *SPWalkFieldsMusicView(id object, NSInteger maxDepth,
                                               NSInteger maxNodes) {
    if (!object) return @[];

    @try {
        if (![object isKindOfClass:[UIView class]]) return @[];
        if ([object isKindOfClass:[UIViewController class]]) return @[];
        const char *cn = object_getClassName(object);
        if (!SPClassNameIsMusicMetaView(cn)) return @[];
        return SPWalkFieldsCommon(object, maxDepth, maxNodes);
    } @catch (__unused id e) {
        return @[];
    }
}
