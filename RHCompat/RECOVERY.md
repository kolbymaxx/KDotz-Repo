# RHCompat black-screen recovery (1.0.1)

If SpringBoard is stuck on a black screen after installing RHCompat **1.0.1**, remove the dylib over SSH, then respring.

## 1) Get a shell

With the device connected to a Mac/PC (USB):

```bash
# map SSH
iproxy 2222 22
# login (default root password is often alpine — change it)
ssh -p 2222 root@127.0.0.1
```

## 2) Remove RHCompat from jbroot

```bash
JB="$(find /var/containers/Bundle/Application -maxdepth 1 -type d -name '.jbroot-*' 2>/dev/null | head -1)"
echo "jbroot=$JB"

# Substrate / ElleKit locations used by RootHide
rm -f "$JB"/Library/MobileSubstrate/DynamicLibraries/000RHCompat.dylib
rm -f "$JB"/Library/MobileSubstrate/DynamicLibraries/000RHCompat.plist
rm -f "$JB"/usr/lib/TweakInject/000RHCompat.dylib
rm -f "$JB"/usr/lib/TweakInject/000RHCompat.plist

# optional: remove the package metadata so Sileo doesn't think it's installed
dpkg --purge com.kolby.rhcompat 2>/dev/null || true
```

## 3) Respring

```bash
killall -9 SpringBoard
# or: sbreload / ldrestart  (whichever your bootstrap provides)
```

## 4) After you’re back

- Do **not** reinstall 1.0.1.
- Install **RHCompat 1.0.2+** only if you still want prefs bridging (Preferences.app only; no SpringBoard hooks).
- Keep official **rootless-compat** for `/var/jb` binary patching.

## Safe mode (if available)

On some RootHide / Dopamine builds you can enter safe mode / disable tweaks from the jailbreak app after a userspace reboot. Prefer SSH removal if SpringBoard never comes up.
