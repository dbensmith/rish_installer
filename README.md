# Shizuku Rish Installer for Termux

Automatically extracts `rish` and `rish_shizuku.dex` from an installed Shizuku APK
and installs them into Termux so you can run `rish` directly from the shell.

## Requirements

- [Termux](https://github.com/termux/termux-app) (or any Android shell with `bash` and `curl`)
- [Shizuku](https://github.com/RikkaApps/Shizuku) or a compatible fork
  (e.g. [thedjchi/Shizuku](https://github.com/thedjchi/Shizuku)) installed and running on the device
- Optional: [ADB wireless debugging](https://developer.android.com/tools/adb#wireless-android11-command-line)
  already enabled and authorized (used as a fallback APK probe method)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/dbensmith/rish_installer/main/rish_installer.sh -o rish_installer.sh \
  && chmod +x rish_installer.sh \
  && bash rish_installer.sh \
  && rm rish_installer.sh
```

> **Note:** Piping directly into `bash` (`curl ... | bash`) works when ADB is not
> involved, but if ADB is present and connected, `adb shell` will consume the
> remaining script from stdin. The one-liner above avoids this entirely.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/dbensmith/rish_installer/main/rish_installer.sh -o rish_installer.sh \
  && bash rish_installer.sh --uninstall \
  && rm rish_installer.sh
```

## Reinstall

```sh
curl -fsSL https://raw.githubusercontent.com/dbensmith/rish_installer/main/rish_installer.sh -o rish_installer.sh \
  && bash rish_installer.sh --reinstall \
  && rm rish_installer.sh
```

## How it works

The script extracts `rish` and `rish_shizuku.dex` from the Shizuku APK already
installed on your device, patches the Termux package ID into the `rish` script,
and installs both files into Termux's bin directory (or `$HOME` as fallback).

### APK probe order

For each discovered Shizuku package the script tries these methods in order,
moving to the next only on failure:

| # | Method | Notes |
|---|--------|-------|
| 1 | `cmd package path` + `cp` | Fastest; works when Termux can read `/data/app` |
| 2 | `pm path` + `cp` | Alternate PM command; same copy permission requirement |
| 3 | `adb shell pm path` + `adb pull` | Only if `adb` is present and already connected |
| 4 | GitHub release download | Last resort — `thedjchi/Shizuku` then `RikkaApps/Shizuku` |

Package candidates are discovered automatically by scanning all installed packages
for names containing `shizuku`, so any installed fork is found without configuration.

### Progress stages

```
[tools]   — check/acquire unzip, sed, grep, install
[probe]   — scan installed packages; try each APK method
[fetch]   — online download (last resort only)
[extract] — unpack assets/rish and assets/rish_shizuku.dex; patch PKG
[install] — write files to bin or $HOME
[verify]  — confirm both files exist and rish is executable
[done]    — printed only after verification passes
```

## Options

| Flag | Description |
|------|-------------|
| `--reinstall` | Replace an existing installation |
| `--uninstall` | Remove rish and rish_shizuku.dex |
| `--no-download` | Fail if no local/ADB APK is found instead of downloading |
| `--repo <owner/repo>` | Add a GitHub repo to check for releases (repeatable) |
| `--apk-package <name>` | Add a package name to probe locally (repeatable) |

Example — explicit repo order and package override:

```sh
bash rish_installer.sh \
  --repo thedjchi/Shizuku \
  --repo RikkaApps/Shizuku \
  --apk-package moe.shizuku.privileged.api
```

## Troubleshooting

**Script stops after ADB pull with no further output**

You ran it via `curl ... | bash`. Use the one-liner install command above instead,
which saves the script to a file before executing it.

**`Required tools missing`**

Install BusyBox manually then re-run:

```sh
pkg install busybox
bash rish_installer.sh
```

**`No local/ADB Shizuku APK found`**

Shizuku (or a compatible fork) must be installed on the device before running this
script. Install it from [GitHub](https://github.com/RikkaApps/Shizuku/releases) or
[F-Droid](https://f-droid.org/en/packages/moe.shizuku.privileged.api/) first.

## What changed from upstream

- Auto-discover any installed Shizuku fork by scanning all installed packages
- Three local probe methods per package before falling back to network
- ADB-assisted APK pull when local copy is permission-denied
- `--no-download` flag to block network fallback
- All `adb` calls redirect stdin from `/dev/null` to prevent pipe consumption
- Online fallback checks `thedjchi/Shizuku` before `RikkaApps/Shizuku`
- Strict pipeline: `[extract] → [install] → [verify] → [done]`
- No bundled BusyBox binaries in this repo

## Credits

Based on [merbah3266/rish_installer](https://github.com/merbah3266/rish_installer).
