# GrokAgent

An on-device AI agent for jailbroken iOS. Natural language in, real device
control out — a replacement for Siri that can actually operate the phone.

Package: `com.kolby.grokagent` · rootless · targets SpringBoard

## Status — v0.1.1

| Layer | State |
|---|---|
| Activation | Darwin notification (working), volume double-press + Siri intercept (hooks written, selectors need on-device verification) |
| Voice | TTS working. STT blocked on an entitlement question — see `GAVoiceManager.h` |
| Agent loop | Working: multi-step tool calling with a step budget |
| LLM client | Working: xAI chat/completions with tool calling |
| Device control | MCP client over `localhost:8090`, backed by iOS MCP |
| Preferences | PreferenceLoader bundle with a connection tester |

## Build

```sh
export THEOS_DEVICE_IP=192.168.1.231
make package install
```

For a roothide build, use the roothide Theos fork and
`THEOS_PACKAGE_SCHEME=roothide make package`.

## Dependencies

GrokAgent does not implement device control itself yet. It drives
[iOS MCP](https://github.com/witchan/ios-mcp) (`com.witchan.ios-mcp`, MIT),
which runs an MCP server inside SpringBoard exposing ~46 tools. Install it,
start its service in Settings, then confirm:

```sh
curl http://127.0.0.1:8090/health
```

## First run

1. Install iOS MCP and start it.
2. Install GrokAgent, respring.
3. Settings → GrokAgent → paste your xAI API key, tap **Test Connection**.
4. Trigger the agent over SSH:

   ```sh
   notifyutil -p com.kolby.grokagent/activate
   ```

5. Watch it work:

   ```sh
   ssh root@192.168.1.231 'oslog | grep GrokAgent'   # or your log tool of choice
   ```

## Architecture

```
Tweak.x                 SpringBoard hooks, runtime selector probing, bootstrap
Sources/
  GAPreferences         cached NSUserDefaults suite + Darwin reload
  GAActivationManager   triggers → activate
  GAOverlayController   HUD + temporary text input
  GAVoiceManager        TTS now, STT pending a design decision
  GAAgentOrchestrator   the loop: reason → act → observe → repeat
  GAGrokClient          xAI (OpenAI-compatible) chat completions with tools
  GAToolRegistry        curated tool schemas + allowlist
  GADeviceControl       MCP JSON-RPC transport
prefs/                  PreferenceLoader bundle
```

The only class that knows how device control is implemented is
`GADeviceControl`. Swapping the HTTP transport for in-process managers
extracted from iOS MCP is a change to one file.

## Open questions

- **Selector names on 17.3.** The volume and Siri hooks are guarded and will
  simply not install if the selectors moved. Debug logging dumps candidate
  selectors at boot — check the log and fix the two `GAClassHasSelector` calls.
- **STT.** See the note in `GAVoiceManager.h`. This decision shapes the whole
  voice pipeline.
- **API key storage.** Currently a preferences plist. Should move to the
  keychain.
- **Screenshots.** `flattenToolResult:` deliberately does not inline base64
  images. Feeding real screenshots to a vision model needs a separate path that
  attaches them as image content blocks rather than tool text.

## Credit

Device control is provided by [iOS MCP](https://github.com/witchan/ios-mcp) by
witchan, MIT licensed. If manager classes are later extracted into this project,
the MIT copyright notice must travel with them.
