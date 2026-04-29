#!/usr/bin/env bash
set -euo pipefail

ACTION="install"
SHIZUKU_REPOS=()
APK_PACKAGES=()
ALLOW_DOWNLOAD=true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --uninstall)     ACTION="uninstall" ;;
    --reinstall)     ACTION="reinstall" ;;
    --no-download)   ALLOW_DOWNLOAD=false ;;
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

# Seed well-known package names; discover_shizuku_pkgs() appends any others
# found installed on the device.
DEFAULT_PACKAGES=("moe.shizuku.privileged.api")

if [ -t 2 ]; then
  C0='\033[0m'; CR='\033[31m'; CG='\033[32m'; CY='\033[33m'; CB='\033[34m'; CC='\033[36m'
else
  C0=''; CR=''; CG=''; CY=''; CB=''; CC=''
fi

# All output goes to stderr so nothing pollutes command substitutions.
msg(){  echo -e "${CB}[i]${C0} $*" >&2; }
ok(){   echo -e "${CG}[+]${C0} $*" >&2; }
warn(){ echo -e "${CY}[!]${C0} $*" >&2; }
err(){  echo -e "${CR}[x]${C0} $*" >&2; exit 1; }
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
# APK discovery: user-supplied names + well-known defaults + device scan
# ---------------------------------------------------------------------------

discover_shizuku_pkgs(){
  # Emit candidate package names, deduped, one per line.
  {
    printf '%s\n' "${APK_PACKAGES[@]+${APK_PACKAGES[@]}}"
    printf '%s\n' "${DEFAULT_PACKAGES[@]}"
    # Search all installed packages for anything containing 'shizuku'.
    cmd package list packages 2>/dev/null | sed 's/^package://' | grep -i shizuku || true
    pm list packages 2>/dev/null | sed 's/^package://' | grep -i shizuku || true
  } | awk '!seen[$0]++' | grep -v '^$'
}

extract_local(){
  local pkg_name apk_path
  stage "probe" "Searching for installed Shizuku APK"
  while IFS= read -r pkg_name; do
    stage "probe" "Trying package: $pkg_name"
    apk_path="$(cmd package path "$pkg_name" 2>/dev/null | sed 's/^package://' | head -n1 | tr -d '[:space:]')"
    if [ -z "$apk_path" ]; then
      warn "  $pkg_name: not found on device"
      continue
    fi
    stage "probe" "  Found APK path: $apk_path"
    if cp "$apk_path" "$TMP_SUBDIR/app.apk" 2>/dev/null; then
      ok "Obtained local APK from $pkg_name"
      APK_SOURCE="local:${pkg_name}"
      return 0
    else
      warn "  $pkg_name: APK not readable (permission denied)"
    fi
  done < <(discover_shizuku_pkgs)
  return 1
}

# ---------------------------------------------------------------------------
# Online fallback
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
    err "No local Shizuku APK found and --no-download is set"
  fi
  stage "fetch" "No local APK found — falling back to GitHub release"
  local url
  url="$(find_release_apk)" || err "Could not locate a Shizuku APK release (check network or install Shizuku first)"
  stage "fetch" "Downloading APK"
  curl -fsSL -o "$TMP_SUBDIR/app.apk" "$url" || err "APK download failed"
  # Extract repo name from the URL for the source tag.
  APK_SOURCE="downloaded:$(printf '%s' "$url" | grep -oE 'github\.com/[^/]+/[^/]+' | head -n1 | cut -d/ -f2-3)"
  ok "APK downloaded (source: $APK_SOURCE)"
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------

ensure_tools

if ! extract_local; then
  fetch_apk
fi

# Extract assets
stage "extract" "Unpacking rish assets from APK"
$UNZIP_CMD -qq "$TMP_SUBDIR/app.apk" -d "$TMP_SUBDIR" \
  || err "APK extraction failed — archive may be corrupt"
[ -f "$TMP_SUBDIR/assets/rish" ] \
  || err "assets/rish not found in APK — this may not be a Shizuku APK"
[ -f "$TMP_SUBDIR/assets/rish_shizuku.dex" ] \
  || err "assets/rish_shizuku.dex not found in APK"
ok "Assets extracted"

# Patch shebang and substitute package name
TMP_RISH="$TMP_SUBDIR/rish"
printf '#!%s\n' "$(command -v sh)" > "$TMP_RISH"
$GREP_CMD -v '^#' "$TMP_SUBDIR/assets/rish" >> "$TMP_RISH"
$SED_CMD -i "s/PKG/$PKG/g" "$TMP_RISH"

# Install
stage "install" "Installing rish to $BIN"
if $INSTALL_CMD -m755 "$TMP_RISH" "$RISH" 2>/dev/null && \
   $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$DEX" 2>/dev/null; then
  ln -sf "$RISH" "$HOME/rish" 2>/dev/null || true
  ln -sf "$DEX"  "$HOME/rish_shizuku.dex" 2>/dev/null || true
  ok "Installed to $BIN"
else
  stage "install" "Cannot write to $BIN — falling back to HOME"
  $INSTALL_CMD -m755 "$TMP_RISH" "$HOME/rish" \
    || err "Failed to install rish to $HOME"
  $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$HOME/rish_shizuku.dex" \
    || err "Failed to install rish_shizuku.dex to $HOME"
  RISH="$HOME/rish"
  ok "Installed to $HOME"
fi

# Verify
stage "verify" "Verifying installation"
[ -f "$RISH" ]               || err "rish not found at $RISH after install"
[ -x "$RISH" ]               || err "rish at $RISH is not executable"
[ -f "$DEX" ] || [ -f "$HOME/rish_shizuku.dex" ] \
                             || err "rish_shizuku.dex not found after install"
ok "Verification passed"

stage "done" "Completed successfully (source: ${APK_SOURCE})"
msg "Run: rish"
