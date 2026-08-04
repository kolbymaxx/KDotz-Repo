# SwiftPeek Phase 0 — recon report

## Fixture

```
cc -O2 -o tools/swiftmd tools/swiftmd.c
python3 tools/mkfixture.py && ./tools/swiftmd /tmp/fixture.macho
```

Result: `TestKit.MyView` with `title : Swift.String`, `tint : SwiftUI.Color`.
`verdict: field names ARE recoverable — proceed to the runtime step`

## iOS 17.3 SwiftUI (iPhone13,1 / 21D50 / arm64e)

Extracted via `ipsw download ipsw --dyld` + `ipsw dyld extract …/SwiftUI.framework/SwiftUI`.

```
__swift5_types  @0x18d8f37a4  26468 bytes  (6617 descriptors)
__swift5_fieldmd @0x18d857840 287276 bytes

6617 descriptors parsed, 6617 printed, 4893 with field records, 0 unresolved slots
verdict: field names ARE recoverable — proceed to the runtime step
```

`--filter Hosting`: 34 types printed, 20 with field records (includes
`SwiftUI.UIHostingConfiguration`, `SwiftUI.HostingScrollView`,
`SwiftUI.PresentationHostingController`, etc.).

Note: many mangled *type* strings print as `<unresolved>` because relative
pointers in a cache-extracted dylib can land outside the file. Field *names*
still resolve. This matches the tool's documented caveat and is not a gate failure.

## Decision gate

**PASS** — field records are recoverable. Proceed to Phase 1.

## Version-drift sweep

See `tools/drift-sweep.sh`. Summaries collected under the sweep output dir
and copied into CI artifacts when available. Compare `__swift5_types` size,
descriptor counts, and Hosting-filter type lists across 17.0–17.3.1 + 16.7.10.
