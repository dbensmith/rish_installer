# Shizuku Rish Installer for Termux

This fork automates installation of `rish` for Termux and similar Android shells.

## What changed in this fork

- Prefer native tools first.
- If native tools are missing, prefer an installed `busybox`.
- On Termux, try `pkg install busybox` or `apt install busybox` before downloading a BusyBox fallback.
- For local APK extraction, probe `moe.shizuku.privileged.api` (compatible with official Shizuku and forks that keep the same package name, including thedjchi/Shizuku).
- For online fallback, check `thedjchi/Shizuku` releases first, then `RikkaApps/Shizuku`.
- All installer and BusyBox fallback URLs now point to `dbensmith/rish_installer`.

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

## Notes

- If you publish a short URL, ensure it redirects to this fork's raw script URL, not the upstream repository.
- The BusyBox fallback downloads from this fork's `busybox/` directory, so keep it in sync with the upstream.
- Based on [merbah3266/rish_installer](https://github.com/merbah3266/rish_installer).
