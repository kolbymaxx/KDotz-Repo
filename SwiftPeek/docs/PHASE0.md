# SwiftPeek Phase 0 — recon report

## Fixture

```
cc -O2 -o tools/swiftmd tools/swiftmd.c
python3 tools/mkfixture.py && ./tools/swiftmd /tmp/fixture.macho
```

Result: `TestKit.MyView` with `title : Swift.String`, `tint : SwiftUI.Color`.

```
verdict: field names ARE recoverable — proceed to the runtime step
```

## iOS 17.3 SwiftUI (iPhone13,1 / 21D50 / arm64e)

Extracted via `ipsw download ipsw --dyld` +
`ipsw dyld extract …/SwiftUI.framework/SwiftUI`.

```
__swift5_types  @0x18d8f37a4  26468 bytes  (6617 descriptors)
__swift5_fieldmd @0x18d857840 287276 bytes

6617 descriptors parsed, 6617 printed, 4893 with field records, 0 unresolved slots
verdict: field names ARE recoverable — proceed to the runtime step
```

`--filter Hosting`: 34 types printed, 20 with field records (includes
`SwiftUI._UIHostingView`, `SwiftUI.UIHostingController`,
`SwiftUI.UIHostingConfiguration`, `SwiftUI.HostingScrollView`,
`SwiftUI.PresentationHostingController`, etc.).

Note: many mangled *type* strings print as `<unresolved>` because relative
pointers in a cache-extracted dylib can land outside the file. Field *names*
still resolve. This matches the tool's documented caveat and is not a gate failure.

## Decision gate

**PASS** — field records are recoverable on every firmware in the sweep.
Proceed to Phase 1.

## Version-drift sweep

Sources: iPhone13,1 arm64e for 17.0–17.3.1; iPhone10,6 arm64 for 16.7.10
(matches the iPhone X control device). Script: [`tools/drift-sweep.sh`](../../tools/drift-sweep.sh).

| Version | Descriptors | With field records | Hosting filter |
|---------|-------------|--------------------|----------------|
| 16.7.10 | 5623 | 4216 | 32 |
| 17.0    | 6540 | 4835 | 33 |
| 17.1    | 6605 | 4888 | 34 |
| 17.2    | 6617 | 4893 | 34 |
| 17.3    | 6617 | 4893 | 34 |
| 17.3.1  | 6617 | 4893 | 34 |

Full type-name set churn (added / removed):

| Transition | + | − |
|------------|---|---|
| 16.7.10 → 17.0 | 1434 | 517 |
| 17.0 → 17.1 | 100 | 35 |
| 17.1 → 17.2 | 13 | 1 |
| 17.2 → 17.3 | 1 | 1 |
| 17.3 → 17.3.1 | 0 | 0 |

### Takeaways

1. **Metadata is present on both device firmwares** (16.7.10 and 17.3). The
   approach is not a 17-only one-off.
2. **Point releases inside 17.2–17.3.1 are effectively frozen** for SwiftUI
   reflection counts; 17.3 ≡ 17.3.1 for type-name sets.
3. **Major churn is 16 → 17**, not point releases. Hosting surface still
   exposes `_UIHostingView` / `UIHostingController` on both sides, so milestone
   1's attach hook is the right shared entry point.
4. Field-offset resilience for milestone 2+ should prefer **runtime field
   offset vectors** over hard-coded layouts — static field *names* are stable
   enough to key on; byte offsets should come from live metadata (`fovo`).
