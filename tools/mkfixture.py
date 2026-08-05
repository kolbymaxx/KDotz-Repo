import struct
# Synthetic 64-bit Mach-O with real __swift5_types / __swift5_fieldmd layout,
# used to validate the parser end to end.
VM = 0x100000000
hdr_size = 32
nsects = 3
seg_size = 72 + 80*nsects
cmds_size = seg_size
data_off = hdr_size + cmds_size

blob = bytearray()
def put(b):
    off = data_off + len(blob); blob.extend(b); return off
def addr(off): return VM + off

# strings
strs = {}
for s in ["TestKit","MyView","title","tint","Swift.String","SwiftUI.Color"]:
    strs[s] = put(s.encode()+b"\x00")

# field descriptor (built after we know string offsets)
fd_off = data_off + len(blob)
fd = bytearray()
fd += struct.pack("<ii", 0, 0)        # mangledTypeName, superclass
fd += struct.pack("<HHI", 0, 12, 2)   # kind, recordSize, numFields
for fname, ftype in [("title","Swift.String"), ("tint","SwiftUI.Color")]:
    rec_off = fd_off + len(fd)
    typ_rel  = addr(strs[ftype]) - addr(rec_off + 4)
    name_rel = addr(strs[fname]) - addr(rec_off + 8)
    fd += struct.pack("<Iii", 0, typ_rel, name_rel)
put(bytes(fd))

# module descriptor
mod_off = data_off + len(blob)
mod = struct.pack("<Ii", 0, 0) + struct.pack("<i", addr(strs["TestKit"]) - addr(mod_off+8))
put(mod)

# struct type descriptor
td_off = data_off + len(blob)
td  = struct.pack("<I", 17)                                   # flags: struct
td += struct.pack("<i", addr(mod_off) - addr(td_off+4))       # parent
td += struct.pack("<i", addr(strs["MyView"]) - addr(td_off+8))# name
td += struct.pack("<i", 0)                                    # accessFn
td += struct.pack("<i", addr(fd_off) - addr(td_off+16))       # fields
td += struct.pack("<II", 2, 2)                                # numFields, fovo
put(td)

# __swift5_types section: one relative pointer to the type descriptor
types_off = data_off + len(blob)
put(struct.pack("<i", addr(td_off) - addr(types_off)))

total = data_off + len(blob)
def sect(name, a, sz, off):
    return name.encode().ljust(16,b"\x00") + b"__TEXT".ljust(16,b"\x00") + \
           struct.pack("<QQIIIIIIII", a, sz, off, 0,0,0,0,0,0,0)

seg  = struct.pack("<II", 0x19, seg_size) + b"__TEXT".ljust(16,b"\x00")
seg += struct.pack("<QQQQ", VM, total, 0, total)
seg += struct.pack("<IIII", 5, 5, nsects, 0)
seg += sect("__swift5_types",   addr(types_off), 4,        types_off)
seg += sect("__swift5_fieldmd", addr(fd_off),    len(fd),  fd_off)
seg += sect("__cstring",        addr(strs["TestKit"]), 64, strs["TestKit"])

mh = struct.pack("<IIIIIIII", 0xfeedfacf, 0x0100000C, 0, 6, 1, cmds_size, 0, 0)
open("/tmp/fixture.macho","wb").write(mh + seg + bytes(blob))
print("wrote", total, "bytes")
