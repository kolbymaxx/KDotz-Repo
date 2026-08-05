# What GrokAgent takes from Siri27 / Music27 / RHCompat

Read once, then delete. This records *why* several things in GrokAgent look the
way they do, so nobody "simplifies" them back into bugs later.

## 1. Prefs must resolve jbroot (fixed in 0.1.1)

`GAPreferences` used `NSUserDefaults initWithSuiteName:`. On RootHide that reads
the rootfs plist while PreferenceLoader writes under the randomized jbroot —
every toggle reads as its default, permanently, while looking correct in
Settings. Music27 shipped 1.1.6 *and* 1.1.7 chasing this.

Now ported from `M27Prefs.m` / `Siri27/Tweak.x`:

- `dlsym(RTLD_DEFAULT, "jbroot")` when roothide's resolver is in-process
- else derive the root from `dladdr` on our own function, splitting the dylib
  path at `/Library/MobileSubstrate/DynamicLibraries/` or `/usr/lib/TweakInject/`
- candidate order: jbroot → `/var/jb` → rootfs
- `CFPreferencesCopyAppValue` as a last-resort fallback

Deriving the root from where our own dylib was loaded is the good idea here —
no scheme guessing, and it is correct on all three layouts by construction.

`GAPreferences.resolvedPrefsPath` is logged at boot for exactly this reason.

## 2. Overlay failsafe (added in 0.1.1)

Music27's changelog is a list of black and white screens: 1.0.0 black, 1.1.1
blank launch, 1.1.3 blank Library, 1.1.5 "dock starts OFF once". GrokAgent puts
a `UIWindow` at `UIWindowLevelAlert + 100` inside SpringBoard, which is the same
class of risk.

`GAOverlayController` now writes a breadcrumb before creating the window and
clears it once presented. `%ctor` checks for a stale breadcrumb and logs.
`GAOverlaySafeMode` suppresses the overlay entirely — recoverable from Settings
without SSH.

Music27 1.1.5's harder lesson is also worth remembering: its first attempt at a
recovery mode *wrote* the disable flag, to the wrong plist, and then fought
Settings. Read-only failsafes are safer than self-writing ones.

## 3. Do not hook POSIX open/stat in SpringBoard

RHCompat 1.0.1 injected into SpringBoard and hooked `open`/`stat` process-wide;
it could black-screen after respring. 1.0.2 dropped both and narrowed the filter
to `com.apple.Preferences` only.

GrokAgent's filter stays SpringBoard-only and touches no POSIX layer. If prefs
paths ever need shimming, that belongs in a separate Preferences-only tweak,
which is what RHCompat already is.

## 4. Guarded %group init is the right pattern

Siri27's `%ctor` gates every group on `NSClassFromString`, picks exactly one orb
host per process, and logs a WARNING when no host class is found. GrokAgent's
`GAClassHasSelector` guards are the same idea at selector granularity. Keep the
warning branch — a silent no-hook is much worse to debug than a loud one.

## 5. STT: what Siri27 actually proves, and what it does not

`WaveManager.startRecording()` is empty. Siri27 never touches the microphone.
It gets audio levels by hooking `-[SUICOrbView setPowerLevel:]` and polling
`SUICFlamesView`, then broadcasting a float cross-process over the Darwin
notification `com.kolby.siri27/level`.

- **Proves:** you can ride Siri's audio pipeline from a tweak with no mic
  entitlement and no usage-description strings, and move data between
  SpringBoard and the Siri process over Darwin notifications.
- **Does not prove:** that a *transcript* is reachable the same way. Levels are
  a float; text is not.

The promising lead is `AFUISiriSession`, which Siri27 already hooks
(`-setState:`) and which lives in the Siri process — Siri27 builds with
`INSTALL_TARGET_PROCESSES = SpringBoard SiriViewService Siri` and a filter to
match. If a recognized-utterance string is reachable off that session object,
that is GrokAgent's STT, and it costs no entitlement.

Next step: class-dump `AFUISiriSession` and `SiriCore`/`AssistantServices` on
17.3 and look for a result or transcription property. If it is there, GrokAgent
grows a Siri-process component that forwards the transcript to SpringBoard the
same way Siri27 forwards levels.

## 6. Packaging

Siri27's Makefile is the template for the roothide variant:

    TARGET := iphone:clang:latest:14.0
    ARCHS = arm64 arm64e
    THEOS_PACKAGE_SCHEME ?= rootless      # CI overrides with roothide

Note `?=`, not `=` — that is what lets one project build both. Siri27 also does
its PreferenceLoader plist copy in `after-stage::` rather than `internal-stage::`.
Worth matching, since that ordering is the one you have actually shipped.
