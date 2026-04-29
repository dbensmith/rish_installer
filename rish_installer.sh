#!/usr/bin/env bash
set -euo pipefail

ACTION="install"
SHIZUKU_REPOS=()
APK_PACKAGES=()
ALLOW_DOWNLOAD=true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --uninstall)   ACTION="uninstall" ;;
    --reinstall)   ACTION="reinstall" ;;
    --no-download) ALLOW_DOWNLOAD=false ;;
    --repo)
      shift
      [ "$#" -gt 0 ] || { echo "missing value for --repo" >&2; exit 1; }
      SHIZUKU_REPOS+=("$1")
      ;;
    --apk-package)
      shift
      [ "$#" -gt 0 ] || { echo "missing value for --apk-package" >&2; exit 1; }
      APK_PACKAGES+=("$1")
      ;;
    *) ;;
  esac
  shift
done

if [ "${#SHIZUKU_REPOS[@]}" -eq 0 ]; then
  SHIZUKU_REPOS=("thedjchi/Shizuku" "RikkaApps/Shizuku")
fi

# Well-known Shizuku package names; discover_shizuku_pkgs() adds any others
# found installed on the device.
DEFAULT_PACKAGES=("moe.shizuku.privileged.api")

if [ -t 2 ]; then
  C0='\033[0m'; CR='\033[31m'; CG='\033[32m'; CY='\033[33m'
  CB='\033[34m'; CC='\033[36m'
else
  C0=''; CR=''; CG=''; CY=''; CB=''; CC=''
fi

# All output goes to stderr — nothing can pollute command substitutions.
msg(){   echo -e "${CB}[i]${C0} $*" >&2; }
ok(){    echo -e "${CG}[+]${C0} $*" >&2; }
warn(){  echo -e "${CY}[!]${C0} $*" >&2; }
err(){   echo -e "${CR}[x]${C0} $*" >&2; exit 1; }
stage(){ echo -e "${CC}[${1}]${C0} ${2}" >&2; }

cleanup(){ rm -rf "${TMP_SUBDIR:-}"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------

detect_pkg(){
  local p="${PREFIX:-}"
  [ -z "$p" ] && p="$(pwd)"
  if [[ "$p" == /data/data/* ]]; then
    echo "${p#/data/data/}" | cut -d/ -f1; return
  fi
  if [[ "$p" == /data/user/* ]]; then
    echo "$p" | cut -d/ -f5; return
  fi
  if [ -n "${HOME:-}" ]; then
    if [[ "$HOME" == /data/data/* ]]; then
      echo "${HOME#/data/data/}" | cut -d/ -f1; return
    fi
    if [[ "$HOME" == /data/user/* ]]; then
      echo "$HOME" | cut -d/ -f5; return
    fi
  fi
  echo "unknown"
}

is_termux(){
  case "${PREFIX:-}" in */com.termux/*) return 0 ;; esac
  case "${HOME:-}"   in */com.termux/*) return 0 ;; esac
  [ "$(detect_pkg 2>/dev/null || true)" = "com.termux" ]
}

PKG="$(detect_pkg)"
[ "$PKG" = "unknown" ] && err "Failed to detect terminal package name"

BIN_PATH="$(command -v bash 2>/dev/null || true)"
[ -z "$BIN_PATH" ] && err "bash not found"
BIN="$(dirname "$BIN_PATH")"
RISH="$BIN/rish"
DEX="$BIN/rish_shizuku.dex"

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

if [ "$ACTION" = "uninstall" ]; then
  rm -f "$RISH" "$DEX" "$HOME/rish" "$HOME/rish_shizuku.dex"
  find "$HOME" -maxdepth 1 -type l -name 'rish*' -delete 2>/dev/null || true
  ok "rish uninstalled"
  exit 0
fi

if [ -f "$RISH" ] && [ "$ACTION" != "reinstall" ]; then
  warn "rish is already installed at $RISH — use --reinstall to replace"
  exit 0
fi

BASE_TMPDIR="${TMPDIR:-/tmp}"
TMP_SUBDIR="$(mktemp -d "$BASE_TMPDIR/rish.XXXXXX")"
APK_SOURCE=""

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------

UNZIP_CMD="" SED_CMD="" GREP_CMD="" INSTALL_CMD=""

use_busybox(){
  UNZIP_CMD="$1 unzip"; SED_CMD="$1 sed"
  GREP_CMD="$1 grep";   INSTALL_CMD="$1 install"
}

have_native_tools(){
  local t
  for t in unzip sed grep install; do
    command -v "$t" >/dev/null 2>&1 || return 1
  done
}

ensure_tools(){
  stage "tools" "Checking required tools"
  if have_native_tools; then
    UNZIP_CMD="unzip"; SED_CMD="sed"; GREP_CMD="grep"; INSTALL_CMD="install"
    ok "Native tools available"
    return 0
  fi
  if command -v busybox >/dev/null 2>&1; then
    use_busybox "busybox"
    ok "Using installed busybox"
    return 0
  fi
  if is_termux; then
    stage "tools" "Installing busybox via Termux package manager"
    if command -v pkg >/dev/null 2>&1; then
      pkg install -y busybox >/dev/null 2>&1 || true
    elif command -v apt >/dev/null 2>&1; then
      apt install -y busybox >/dev/null 2>&1 || true
    fi
    if command -v busybox >/dev/null 2>&1; then
      use_busybox "busybox"
      ok "busybox installed from Termux package"
      return 0
    fi
    warn "Termux busybox package install failed"
  fi
  err "Required tools missing (unzip sed grep install). On Termux run: pkg install busybox"
}

# ---------------------------------------------------------------------------
# ADB helpers
# ---------------------------------------------------------------------------

# Returns 0 only if adb is present AND a device is already connected/authorized.
# Uses a short timeout so we never stall if ADB is absent or the daemon is cold.
adb_connected(){
  command -v adb >/dev/null 2>&1 || return 1
  local devices
  devices="$(adb devices -l 2>/dev/null)" || return 1
  # "adb devices" always prints the header line; a connected device adds >=1 more.
  echo "$devices" | grep -qvE '(^List of devices|^$|^\s*$)' || return 1
}

# Resolve an APK path for $1 via ADB shell, then pull it into $TMP_SUBDIR/app.apk.
# Returns 0 on success.
adb_pull_apk(){
  local pkg_name="$1" apk_path
  apk_path="$(adb shell pm path "$pkg_name" 2>/dev/null \
    | sed 's/^package://' | head -n1 | tr -d '\r[:space:]')"
  [ -n "$apk_path" ] || return 1
  stage "probe" "  ADB path: $apk_path — pulling"
  adb pull "$apk_path" "$TMP_SUBDIR/app.apk" >/dev/null 2>&1 || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Package discovery
# ---------------------------------------------------------------------------

discover_shizuku_pkgs(){
  {
    # 1. Caller-supplied overrides
    printf '%s\n' "${APK_PACKAGES[@]+${APK_PACKAGES[@]}}"
    # 2. Well-known defaults
    printf '%s\n' "${DEFAULT_PACKAGES[@]}"
    # 3. Scan all installed packages locally
    cmd package list packages 2>/dev/null | sed 's/^package://' \
      | grep -i shizuku || true
    pm list packages 2>/dev/null | sed 's/^package://' \
      | grep -i shizuku || true
    # 4. Scan via ADB if connected (catches forks not visible to pm in Termux)
    if adb_connected 2>/dev/null; then
      adb shell pm list packages 2>/dev/null | sed 's/^package://' \
        | grep -i shizuku || true
    fi
  } | awk '!seen[$0]++' | grep -v '^$'
}

# ---------------------------------------------------------------------------
# Local APK probe (direct cp, then ADB pull as fallback per package)
# ---------------------------------------------------------------------------

extract_local(){
  local pkg_name apk_path
  local adb_ok=false
  adb_connected 2>/dev/null && adb_ok=true

  stage "probe" "Searching for installed Shizuku APK on device"
  while IFS= read -r pkg_name; do
    stage "probe" "Trying package: $pkg_name"

    # Method 1: cmd package path + direct cp
    apk_path="$(cmd package path "$pkg_name" 2>/dev/null \
      | sed 's/^package://' | head -n1 | tr -d '[:space:]')"
    if [ -n "$apk_path" ]; then
      stage "probe" "  Found via cmd: $apk_path"
      if cp "$apk_path" "$TMP_SUBDIR/app.apk" 2>/dev/null; then
        ok "Obtained local APK from $pkg_name (cmd package path)"
        APK_SOURCE="local:${pkg_name}"
        return 0
      fi
      warn "  Direct copy failed (permission denied) — trying pm path"
    fi

    # Method 2: pm path + direct cp
    apk_path="$(pm path "$pkg_name" 2>/dev/null \
      | sed 's/^package://' | head -n1 | tr -d '[:space:]')"
    if [ -n "$apk_path" ]; then
      stage "probe" "  Found via pm: $apk_path"
      if cp "$apk_path" "$TMP_SUBDIR/app.apk" 2>/dev/null; then
        ok "Obtained local APK from $pkg_name (pm path)"
        APK_SOURCE="local:${pkg_name}"
        return 0
      fi
      warn "  Direct copy failed (permission denied) — trying ADB pull"
    fi

    # Method 3: ADB pull (only when a device is already connected)
    if [ "$adb_ok" = true ]; then
      stage "probe" "  Attempting ADB pull for $pkg_name"
      if adb_pull_apk "$pkg_name"; then
        ok "Obtained APK via ADB from $pkg_name"
        APK_SOURCE="adb:${pkg_name}"
        return 0
      fi
      warn "  ADB pull failed for $pkg_name"
    fi

    warn "  $pkg_name: all local methods failed"
  done < <(discover_shizuku_pkgs)
  return 1
}

# ---------------------------------------------------------------------------
# Online fallback (last resort)
# ---------------------------------------------------------------------------

find_release_apk(){
  local repo api url
  for repo in "${SHIZUKU_REPOS[@]}"; do
    stage "fetch" "Checking GitHub releases: $repo"
    api="https://api.github.com/repos/${repo}/releases/latest"
    url="$(curl -fsSL "$api" \
      | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.apk"' \
      | head -n1 \
      | grep -oE '"[^"]+\.apk"$' \
      | tr -d '"')"
    if [ -n "$url" ]; then
      printf '%s\n' "$url"
      return 0
    fi
    warn "  No APK asset found in $repo latest release"
  done
  return 1
}

fetch_apk(){
  if [ "$ALLOW_DOWNLOAD" = false ]; then
    err "No local/ADB Shizuku APK found and --no-download is set"
  fi
  stage "fetch" "All local probes failed — last resort: GitHub release download"
  local url
  url="$(find_release_apk)" \
    || err "Could not locate a Shizuku APK release. Install Shizuku first, or check network."
  stage "fetch" "Downloading APK"
  curl -fsSL -o "$TMP_SUBDIR/app.apk" "$url" \
    || err "APK download failed"
  APK_SOURCE="downloaded:$(printf '%s' "$url" \
    | grep -oE 'github\.com/[^/]+/[^/]+' | head -n1 | cut -d/ -f2-3)"
  ok "APK downloaded (source: $APK_SOURCE)"
}

# ---------------------------------------------------------------------------
# Asset extraction and patching
# ---------------------------------------------------------------------------

extract_assets(){
  stage "extract" "Unpacking rish assets from APK"
  $UNZIP_CMD -qq "$TMP_SUBDIR/app.apk" -d "$TMP_SUBDIR" \
    || err "APK extraction failed — archive may be corrupt"
  [ -f "$TMP_SUBDIR/assets/rish" ] \
    || err "assets/rish not found in APK — is this a Shizuku APK?"
  [ -f "$TMP_SUBDIR/assets/rish_shizuku.dex" ] \
    || err "assets/rish_shizuku.dex not found in APK"
  ok "Assets extracted (rish + rish_shizuku.dex)"
}

patch_rish(){
  stage "extract" "Patching rish shebang and package name"
  local tmp="$TMP_SUBDIR/rish"
  printf '#!%s\n' "$(command -v sh)" > "$tmp"
  $GREP_CMD -v '^#' "$TMP_SUBDIR/assets/rish" >> "$tmp"
  $SED_CMD -i "s/PKG/$PKG/g" "$tmp"
  ok "rish patched for package: $PKG"
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

do_install(){
  stage "install" "Installing rish to $BIN"
  if $INSTALL_CMD -m755 "$TMP_SUBDIR/rish" "$RISH" 2>/dev/null && \
     $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$DEX" 2>/dev/null; then
    ln -sf "$RISH" "$HOME/rish" 2>/dev/null || true
    ln -sf "$DEX"  "$HOME/rish_shizuku.dex" 2>/dev/null || true
    ok "Installed to $BIN"
  else
    stage "install" "Cannot write to $BIN — falling back to \$HOME"
    $INSTALL_CMD -m755 "$TMP_SUBDIR/rish" "$HOME/rish" \
      || err "Failed to install rish to $HOME"
    $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$HOME/rish_shizuku.dex" \
      || err "Failed to install rish_shizuku.dex to $HOME"
    # Update paths so verify_install checks the correct locations.
    RISH="$HOME/rish"
    DEX="$HOME/rish_shizuku.dex"
    ok "Installed to $HOME"
  fi
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

verify_install(){
  stage "verify" "Verifying installation"
  [ -f "$RISH" ] || err "rish not found at $RISH after install"
  [ -x "$RISH" ] || err "rish at $RISH is not executable"
  [ -f "$DEX"  ] || err "rish_shizuku.dex not found at $DEX after install"
  ok "rish installed and executable: $RISH"
  ok "rish_shizuku.dex present:      $DEX"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ensure_tools

if ! extract_local; then
  fetch_apk
fi

extract_assets
patch_rish
do_install
verify_install

stage "done" "Completed successfully (source: ${APK_SOURCE})"
msg "Run: rish"
