# Shizuku Rish Installer for Termux
[![Stars](https://img.shields.io/github/stars/merbah3266/rish_installer?style=flat-square&color=black&labelColor=white)](https://github.com/merbah3266/rish_installer/stargazers)

## Overview
This script automates the installation of `rish` in Termux.  
Instead of manually extracting files from the Shizuku APP and placing them in the correct directory, this installer does it for you in one step.

It downloads the latest Shizuku APK, extracts `rish` and its companion file `rish_shizuku.dex`, and installs them into Termux with proper permissions.

## Why
Installing `rish` manually requires multiple steps:
- Downloading the Shizuku APP.
- Extracting `rish` and `rish_shizuku.dex` from the APK.
- Placing them in the Termux home directory to run with `~/rish`.

This script simplifies the process.  
The main benefit is that after installation you can run `rish` directly instead of using `~/rish`, saving time and avoiding manual errors.

## Installation
Run the following inside Termux to install/reinstall:
```bash
bash <(curl -fsSL tinyurl.com/rish3266)
```
If you want to uninstall, run this:
```bash
bash -s -- --uninstall < <(curl -fsSL tinyurl.com/rish3266)
```

**Requirements:**
- Termux environment
- Internet connection

**The script will handle:**
1. Fetching the latest Shizuku APK from GitHub.
2. Extracting `rish` and `rish_shizuku.dex`.
3. Installing them in the correct Termux directory with proper permissions.

## How to Run rish
After installation, simply execute:
```bash
rish
```
**Note:**  
rish works through Shizuku, which provides ADB-like permissions. Make sure Shizuku is running and authorized.

## Benefits
- Saves time by automating the manual installation process.
- Lets you run `rish` directly in Termux instead of `~/rish`.
- Reduces mistakes from manual extraction and setup.

## Important Notes
- This script is designed specifically for Termux.
- You must authorize Shizuku before using `rish`.
