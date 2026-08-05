// swiftmd.c — dump Swift reflection metadata from a 64-bit Mach-O.
//
// Answers the question everything else depends on:
//   "Does SwiftUI on this device still ship __swift5_* metadata, and can I
//    recover type names + field names from it?"
//
// Self-contained: no <mach-o/*.h>, so it builds on macOS, iOS, or Linux.
//
//   cc -O2 -o swiftmd swiftmd.c
//   ./swiftmd /path/to/SwiftUI --filter Hosting
//
// Input must be a single-arch, already-extracted Mach-O. For a system
// framework, pull it out of the dyld shared cache first:
//   ipsw dyld extract dyld_shared_cache_arm64e /System/Library/Frameworks/SwiftUI.framework/SwiftUI
//
// Caveat that matters: relative pointers inside a cache-extracted dylib can
// point outside the file. Those resolve to 0 here and print as <unresolved>.
// A high unresolved rate means the extraction was lossy, not that metadata
// is missing.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

#define MH_MAGIC_64   0xfeedfacfu
#define MH_CIGAM_64   0xcffaedfeu
#define FAT_MAGIC     0xcafebabeu
#define FAT_CIGAM     0xbebafecau
#define LC_SEGMENT_64 0x19u

// ---- minimal Mach-O structs -------------------------------------------------

struct mh64 {
    uint32_t magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved;
};
struct lc {
    uint32_t cmd, cmdsize;
};
struct seg64 {
    uint32_t cmd, cmdsize;
    char     segname[16];
    uint64_t vmaddr, vmsize, fileoff, filesize;
    uint32_t maxprot, initprot, nsects, flags;
};
struct sect64 {
    char     sectname[16], segname[16];
    uint64_t addr, size;
    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};

// ---- vmaddr -> file pointer -------------------------------------------------

typedef struct { uint64_t vmaddr, vmsize, fileoff, filesize; } seg_t;

static const uint8_t *g_base;
static size_t         g_size;
static seg_t          g_segs[64];
static int            g_nsegs;

static const void *vm2p(uint64_t addr) {
    if (!addr) return NULL;
    for (int i = 0; i < g_nsegs; i++) {
        seg_t *s = &g_segs[i];
        if (addr >= s->vmaddr && addr < s->vmaddr + s->filesize) {
            uint64_t off = s->fileoff + (addr - s->vmaddr);
            if (off < g_size) return g_base + off;
        }
    }
    return NULL;
}

static int read_i32(uint64_t addr, int32_t *out) {
    const void *p = vm2p(addr);
    if (!p) return 0;
    memcpy(out, p, 4);
    return 1;
}
static int read_u32(uint64_t addr, uint32_t *out) {
    const void *p = vm2p(addr);
    if (!p) return 0;
    memcpy(out, p, 4);
    return 1;
}
static int read_u16(uint64_t addr, uint16_t *out) {
    const void *p = vm2p(addr);
    if (!p) return 0;
    memcpy(out, p, 2);
    return 1;
}

// Swift relative pointer: int32 stored at `at`, target = at + value.
//
// Two flavours, and conflating them is the classic way to get silent garbage:
//
//   RelativeDirectPointer      — names, field descriptors, field records.
//                                The full int32 is the offset. Odd values are
//                                legal, so DO NOT mask the low bit.
//   RelativeIndirectablePointer — parent/context references. Low bit set means
//                                the target is a pointer to the real thing.
//
// Masking bit 0 on a direct pointer shifts every odd offset by one byte, which
// resolves to an empty or garbage string rather than a hard failure — so it
// looks like "metadata was stripped" when it wasn't.
static uint64_t rel_direct(uint64_t at) {
    int32_t v;
    if (!read_i32(at, &v) || v == 0) return 0;
    return at + (int64_t)v;
}

// Returns 0 and sets *indirect if the target needs a pointer deref, which in a
// static file is usually an unbound fixup we can't follow.
static uint64_t rel_indirectable(uint64_t at, int *indirect) {
    int32_t v;
    if (indirect) *indirect = 0;
    if (!read_i32(at, &v) || v == 0) return 0;
    if (v & 1) {
        if (indirect) *indirect = 1;
        return 0;
    }
    return at + (int64_t)v;
}

// ---- strings ----------------------------------------------------------------

// Mangled names can embed symbolic references (control bytes < 0x20 followed
// by a relative pointer). We print the readable prefix and mark the rest.
static void print_mangled(uint64_t addr) {
    const uint8_t *p = vm2p(addr);
    if (!p) { printf("<unresolved>"); return; }
    size_t max = g_size - (size_t)(p - g_base);
    if (max > 512) max = 512;
    int printed = 0;
    for (size_t i = 0; i < max; i++) {
        uint8_t c = p[i];
        if (c == 0) break;
        if (c < 0x20) { printf("%s<symbolic>", printed ? " " : ""); return; }
        putchar(c);
        printed = 1;
    }
    if (!printed) printf("<empty>");
}

static void print_cstr(uint64_t addr) {
    const uint8_t *p = vm2p(addr);
    if (!p) { printf("<unresolved>"); return; }
    size_t max = g_size - (size_t)(p - g_base);
    if (max > 512) max = 512;
    for (size_t i = 0; i < max && p[i]; i++) putchar(p[i]);
}

static int cstr_contains(uint64_t addr, const char *needle) {
    const char *p = vm2p(addr);
    if (!p) return 0;
    size_t max = g_size - (size_t)((const uint8_t *)p - g_base);
    char buf[256];
    size_t n = 0;
    for (; n < sizeof(buf) - 1 && n < max && p[n]; n++) buf[n] = p[n];
    buf[n] = 0;
    return strstr(buf, needle) != NULL;
}

// ---- context descriptors ----------------------------------------------------
//
// ContextDescriptor:   +0 u32 flags | +4 i32 parent
// TypeContextDesc:     +8 i32 name  | +12 i32 accessFn | +16 i32 fields
// StructDescriptor:   +20 u32 numFields | +24 u32 fieldOffsetVectorOffset
//
// kind = flags & 0x1F:  0 module, 1 extension, 2 anonymous, 3 protocol,
//                      16 class, 17 struct, 18 enum

#define KIND(f) ((f) & 0x1Fu)

static const char *kind_name(uint32_t k) {
    switch (k) {
        case 0:  return "module";
        case 1:  return "extension";
        case 2:  return "anonymous";
        case 3:  return "protocol";
        case 16: return "class";
        case 17: return "struct";
        case 18: return "enum";
        default: return "?";
    }
}

// Walk parent chain and print Module.Outer.Inner.
static void print_qualified(uint64_t desc, int depth) {
    if (!desc || depth > 8) return;
    uint32_t flags;
    if (!read_u32(desc, &flags)) return;
    uint32_t k = KIND(flags);
    if (k == 1 || k == 2) return;              // extensions/anonymous have no name
    uint64_t parent = rel_indirectable(desc + 4, NULL);
    if (parent) { print_qualified(parent, depth + 1); }
    uint64_t name = rel_direct(desc + 8);
    if (name) {
        if (parent) putchar('.');
        print_cstr(name);
    }
}

// FieldDescriptor: +0 i32 mangledTypeName | +4 i32 superclass | +8 u16 kind
//                  +10 u16 recordSize | +12 u32 numFields | +16 records[]
// FieldRecord:     +0 u32 flags | +4 i32 mangledTypeName | +8 i32 fieldName
static int dump_fields(uint64_t fd) {
    uint16_t recsize;
    uint32_t nfields;
    if (!read_u16(fd + 10, &recsize) || !read_u32(fd + 12, &nfields)) return 0;
    if (recsize != 12 || nfields > 4096) return 0;   // sanity

    for (uint32_t i = 0; i < nfields; i++) {
        uint64_t rec = fd + 16 + (uint64_t)i * recsize;
        uint64_t fname = rel_direct(rec + 8);
        uint64_t ftype = rel_direct(rec + 4);
        printf("    [%2u] ", i);
        if (fname) print_cstr(fname); else printf("<unnamed>");
        printf(" : ");
        if (ftype) print_mangled(ftype); else printf("<none>");
        putchar('\n');
    }
    return (int)nfields;
}

// ---- main -------------------------------------------------------------------

int main(int argc, char **argv) {
    const char *path = NULL, *filter = NULL;
    int verbose = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--filter") && i + 1 < argc) filter = argv[++i];
        else if (!strcmp(argv[i], "-v")) verbose = 1;
        else path = argv[i];
    }
    if (!path) {
        fprintf(stderr, "usage: %s <mach-o> [--filter Substring] [-v]\n", argv[0]);
        return 2;
    }

    int fd = open(path, O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }
    struct stat st;
    if (fstat(fd, &st) || st.st_size < (off_t)sizeof(struct mh64)) {
        fprintf(stderr, "bad file\n"); return 1;
    }
    g_size = (size_t)st.st_size;
    g_base = mmap(NULL, g_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (g_base == MAP_FAILED) { perror("mmap"); return 1; }

    uint32_t magic;
    memcpy(&magic, g_base, 4);
    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        fprintf(stderr, "fat binary — thin it first: lipo -thin arm64e %s -output %s.arm64e\n",
                path, path);
        return 1;
    }
    if (magic != MH_MAGIC_64) {
        fprintf(stderr, "not a 64-bit little-endian Mach-O (magic %08x)\n", magic);
        return 1;
    }

    const struct mh64 *mh = (const struct mh64 *)g_base;
    const uint8_t *cmd = g_base + sizeof(struct mh64);

    uint64_t types_addr = 0, types_size = 0;
    uint64_t fieldmd_addr = 0, fieldmd_size = 0;

    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct lc *l = (const struct lc *)cmd;
        if (l->cmdsize == 0 || (size_t)(cmd - g_base) + l->cmdsize > g_size) break;
        if (l->cmd == LC_SEGMENT_64) {
            const struct seg64 *s = (const struct seg64 *)cmd;
            if (g_nsegs < 64) {
                g_segs[g_nsegs++] = (seg_t){ s->vmaddr, s->vmsize, s->fileoff, s->filesize };
            }
            const struct sect64 *sec = (const struct sect64 *)(cmd + sizeof(struct seg64));
            for (uint32_t j = 0; j < s->nsects; j++, sec++) {
                char nm[17] = {0};
                memcpy(nm, sec->sectname, 16);
                if (!strcmp(nm, "__swift5_types"))   { types_addr = sec->addr;   types_size = sec->size; }
                if (!strcmp(nm, "__swift5_fieldmd")) { fieldmd_addr = sec->addr; fieldmd_size = sec->size; }
                if (verbose && !strncmp(nm, "__swift5", 8))
                    fprintf(stderr, "section %-20s addr=0x%llx size=%llu\n",
                            nm, (unsigned long long)sec->addr, (unsigned long long)sec->size);
            }
        }
        cmd += l->cmdsize;
    }

    if (!types_addr) {
        fprintf(stderr,
                "no __swift5_types section.\n"
                "  -> reflection metadata was stripped, or this isn't a Swift binary.\n"
                "  -> if __swift5_fieldmd exists (%s), field names survived even though\n"
                "     the type list didn't — dump that section directly.\n",
                fieldmd_addr ? "it does" : "it doesn't");
        return 3;
    }

    fprintf(stderr, "__swift5_types  @0x%llx  %llu bytes  (%llu descriptors)\n",
            (unsigned long long)types_addr, (unsigned long long)types_size,
            (unsigned long long)(types_size / 4));
    fprintf(stderr, "__swift5_fieldmd @0x%llx %llu bytes\n\n",
            (unsigned long long)fieldmd_addr, (unsigned long long)fieldmd_size);

    uint64_t total = 0, shown = 0, with_fields = 0, unresolved = 0;

    for (uint64_t off = 0; off + 4 <= types_size; off += 4) {
        uint64_t slot = types_addr + off;
        uint64_t desc = rel_direct(slot);
        if (!desc) { unresolved++; continue; }
        total++;

        uint32_t flags;
        if (!read_u32(desc, &flags)) { unresolved++; continue; }
        uint32_t k = KIND(flags);
        if (k != 16 && k != 17 && k != 18) continue;   // class/struct/enum only

        uint64_t name = rel_direct(desc + 8);
        if (filter && (!name || !cstr_contains(name, filter))) continue;
        shown++;

        printf("%-8s ", kind_name(k));
        print_qualified(desc, 0);
        printf("  [desc 0x%llx]", (unsigned long long)desc);

        if (k == 17) {   // struct: field offset vector offset lives here
            uint32_t fovo;
            if (read_u32(desc + 24, &fovo)) printf("  fovo=%u", fovo);
        }
        putchar('\n');

        uint64_t fdsc = rel_direct(desc + 16);
        if (fdsc && dump_fields(fdsc) > 0) with_fields++;
    }

    fprintf(stderr,
            "\n%llu descriptors parsed, %llu printed, %llu with field records, "
            "%llu unresolved slots\n",
            (unsigned long long)total, (unsigned long long)shown,
            (unsigned long long)with_fields, (unsigned long long)unresolved);
    fprintf(stderr,
            "verdict: %s\n",
            with_fields ? "field names ARE recoverable — proceed to the runtime step"
                        : "no field records recovered — check extraction, then re-run");
    return 0;
}
