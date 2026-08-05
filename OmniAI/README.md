# OmniAI

System-wide AI for jailbroken iOS 16–18 (rootless + roothide). Select text → **OmniAI**, or summon a floating overlay to ask Grok, Claude, or Gemini about what is on screen.

Replaces **GrokAgent** (`com.kolby.grokagent`).

## Features

- **Text selection hook** — injects an OmniAI action into the iOS 16+ edit menu (`UITextView` / `UITextField` / `UIEditMenuInteraction`)
- **On-screen awareness** — captures a compressed JPEG of the frontmost window; optionally enriches with iOS MCP `describe_screen`
- **Web login** — Settings pane signs into Grok (xAI), Claude, and Google/Gemini via `WKWebView`; sessions land in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`)
- **Device Agent** — optional tool loop over [witchan's iOS MCP](https://github.com/witchan) (tap, OCR, launch apps, type, …)
- **Floating overlay** — provider picker, screen-context toggle, Device Agent toggle, prompt / reply, Replace / Copy

## Requirements

- iOS 16–18, rootless or roothide
- Substrate / ElleKit + PreferenceLoader
- Optional: **iOS MCP** (`com.witchan.ios-mcp`) on `127.0.0.1:8090` for Device Agent and richer screen context

## Build

```bash
export THEOS=~/theos
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
# or
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

## Activation

| Method | How |
|--------|-----|
| Edit menu | Select text → **OmniAI** |
| Status bar | Tap status bar (default) |
| Volume ×2 | Double-press volume up |
| Darwin | `notifyutil -p com.kolby.omniai/activate` |

## Package

| Field | Value |
|-------|--------|
| ID | `com.kolby.omniai` |
| Prefs | `com.kolby.omniaiprefs` |
| Injects | `com.apple.UIKit`, `com.apple.springboard` |
