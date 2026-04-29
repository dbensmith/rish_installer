# Shizuku Rish Installer for Termux

This fork automates installation of `rish` for Termux and similar Android shells.

## What changed in this fork

- Prefer native tools first.
- If native tools are missing, use an already-installed `busybox`.
- On Termux, automatically run `pkg install busybox` or `apt install busybox` if needed.
- If no tools are available and Termux package install fails, the script exits with a clear error rather than downloading a binary.
- For local APK extraction, probe `moe.shizuku.privileged.api` (compatible with official Shizuku and forks that keep the same package name, including thedjchi/Shizuku).
- For online fallback, check `thedjchi/Shizuku` releases first, then `RikkaApps/Shizuku`.
- No bundled BusyBox binaries in this repo.

## Requirements

- Termux (recommended) or any Android shell with `bash` and `curl`
- Shizuku or a compatible fork (e.g. [thedjchi/Shizuku](https://github.com/thedjchi/Shizuku)) installed and running

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/dbensmith/rish_installer/main/rish_installer.sh | bash
```

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/dbensmith/rish_installer/main/rish_installer.sh | bash -s -- --uninstall
```

## Reinstall

```sh
curl -fsSL https://raw.githubusercontent.com/dbensmith/rish_installer/main/rish_installer.sh | bash -s -- --reinstall
```

## Optional overrides

Specify a different Shizuku fork repo (checked in order):

```sh
bash rish_installer.sh --repo thedjchi/Shizuku --repo RikkaApps/Shizuku
```

Specify an additional APK package name to probe locally:

```sh
bash rish_installer.sh --apk-package moe.shizuku.privileged.api
```

## Missing tools

If the script exits with `Required tools missing`, install BusyBox manually:

```sh
pkg install busybox
```

Then re-run the installer.

## Credits

Based on [merbah3266/rish_installer](https://github.com/merbah3266/rish_installer).
