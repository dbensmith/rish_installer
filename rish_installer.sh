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
      shift; [ "$#" -gt 0 ] || { echo "missing value for --repo" >&2; exit 1; }
      SHIZUKU_REPOS+=("$1") ;;
    --apk-package)
      shift; [ "$#" -gt 0 ] || { echo "missing value for --apk-package" >&2; exit 1; }
      APK_PACKAGES+=("$1") ;;
    *) ;;
  esac
  shift
done

[ "${#SHIZUKU_REPOS[@]}" -eq 0 ] && SHIZUKU_REPOS=("thedjchi/Shizuku" "RikkaApps/Shizuku")
DEFAULT_PACKAGES=("moe.shizuku.privileged.api")

if [ -t 2 ]; then
  C0='\033[0m' CR='\033[31m' CG='\033[32m' CY='\033[33m' CB='\033[34m' CC='\033[36m'
else
  C0='' CR='' CG='' CY='' CB='' CC=''
fi

msg(){   echo -e "${CB}[i]${C0} $*" >&2; }
ok(){    echo -e "${CG}[+]${C0} $*" >&2; }
warn(){  echo -e "${CY}[!]${C0} $*" >&2; }
err(){   echo -e "${CR}[x]${C0} $*" >&2; exit 1; }
stage(){ echo -e "${CC}[${1}]${C0} ${2}" >&2; }

cleanup(){ rm -rf "${TMP_SUBDIR:-}"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

detect_pkg(){
  local p
  for p in "${PREFIX:-}" "${HOME:-}"; do
    [[ "$p" == /data/data/* ]] && { echo "${p#/data/data/}" | cut -d/ -f1; return; }
    [[ "$p" == /data/user/* ]] && { echo "$p" | cut -d/ -f5; return; }
  done
  echo "unknown"
}

PKG="$(detect_pkg)"
[ "$PKG" = "unknown" ] && err "Failed to detect terminal package name"
[ "$PKG" = "com.termux" ] && IS_TERMUX=true || IS_TERMUX=false

BIN_PATH="$(command -v bash 2>/dev/null)" || err "bash not found"
BIN="$(dirname "$BIN_PATH")"
RISH="$BIN/rish"
DEX="$BIN/rish_shizuku.dex"

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

if [ "$ACTION" = "uninstall" ]; then
  rm -f "$RISH" "$DEX" "$HOME/rish" "$HOME/rish_shizuku.dex"
  find "$HOME" -maxdepth 1 -type l -name 'rish*' -delete 2>/dev/null || true
  ok "rish uninstalled"; exit 0
fi

if [ -f "$RISH" ] && [ "$ACTION" != "reinstall" ]; then
  warn "rish already installed at $RISH — use --reinstall to replace"; exit 0
fi

TMP_SUBDIR="$(mktemp -d "${TMPDIR:-/tmp}/rish.XXXXXX")"
APK_SOURCE=""

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

UNZIP_CMD="" SED_CMD="" GREP_CMD="" INSTALL_CMD=""

use_busybox(){ UNZIP_CMD="$1 unzip"; SED_CMD="$1 sed"; GREP_CMD="$1 grep"; INSTALL_CMD="$1 install"; }
have_tools(){
  local t; for t in unzip sed grep install; do
    command -v "$t" >/dev/null 2>&1 || return 1
  done
}

ensure_tools(){
  stage "tools" "Checking required tools"
  if have_tools; then
    UNZIP_CMD="unzip"; SED_CMD="sed"; GREP_CMD="grep"; INSTALL_CMD="install"
    ok "Native tools available"; return
  fi
  if command -v busybox >/dev/null 2>&1; then
    use_busybox "busybox"; ok "Using installed busybox"; return
  fi
  if [ "$IS_TERMUX" = true ]; then
    stage "tools" "Installing busybox via Termux"
    { command -v pkg >/dev/null 2>&1 && pkg install -y busybox </dev/null >/dev/null 2>&1; } \
      || { command -v apt >/dev/null 2>&1 && apt install -y busybox </dev/null >/dev/null 2>&1; } \
      || true
    if command -v busybox >/dev/null 2>&1; then
      use_busybox "busybox"; ok "busybox installed"; return
    fi
    warn "Termux busybox install failed"
  fi
  err "Required tools missing (unzip sed grep install). On Termux: pkg install busybox"
}

# ---------------------------------------------------------------------------
# ADB
# All adb calls redirect stdin from /dev/null. When this script is saved to
# a file and executed directly (recommended), this is a no-op. When piped
# into bash, adb shell would otherwise consume the remaining script from
# the shared stdin pipe.
# ---------------------------------------------------------------------------

ADB_OK=false
check_adb(){
  command -v adb >/dev/null 2>&1 || return 1
  adb devices -l </dev/null 2>/dev/null \
    | grep -qvE '^(List of devices|[[:space:]]*)$' || return 1
  ADB_OK=true
}

adb_pull_apk(){
  local pkg="$1" path
  path="$(adb shell pm path "$pkg" </dev/null 2>/dev/null \
    | sed 's/^package://' | head -n1 | tr -d '\r[:space:]')"
  [ -n "$path" ] || return 1
  stage "probe" "  ADB: $path"
  adb pull "$path" "$TMP_SUBDIR/app.apk" </dev/null >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Package discovery
# ---------------------------------------------------------------------------

discover_pkgs(){
  {
    [ "${#APK_PACKAGES[@]}" -gt 0 ] && printf '%s\n' "${APK_PACKAGES[@]}"
    printf '%s\n' "${DEFAULT_PACKAGES[@]}"
    cmd package list packages 2>/dev/null | sed 's/^package://' | grep -i shizuku || true
    pm list packages        2>/dev/null | sed 's/^package://' | grep -i shizuku || true
    [ "$ADB_OK" = true ] && \
      adb shell pm list packages </dev/null 2>/dev/null \
        | sed 's/^package://' | grep -i shizuku || true
  } | awk '!seen[$0]++' | grep -v '^$'
}

# ---------------------------------------------------------------------------
# Local APK probe
# ---------------------------------------------------------------------------

# Resolve APK path for $1 via cmd package path then pm path.
resolve_path(){
  local p
  p="$(cmd package path "$1" 2>/dev/null | sed 's/^package://' | head -n1 | tr -d '[:space:]')"
  [ -n "$p" ] || \
    p="$(pm path "$1" 2>/dev/null | sed 's/^package://' | head -n1 | tr -d '[:space:]')"
  printf '%s' "$p"
}

try_copy(){ cp "$1" "$TMP_SUBDIR/app.apk" 2>/dev/null; }

extract_local(){
  local pkg path
  stage "probe" "Searching for installed Shizuku APK"
  while IFS= read -r pkg; do
    stage "probe" "Trying: $pkg"
    path="$(resolve_path "$pkg")"
    if [ -n "$path" ]; then
      stage "probe" "  Path: $path"
      if try_copy "$path"; then
        ok "Local APK from $pkg"; APK_SOURCE="local:$pkg"; return 0
      fi
      warn "  Copy denied — trying ADB"
    fi
    if [ "$ADB_OK" = true ] && adb_pull_apk "$pkg"; then
      ok "APK via ADB from $pkg"; APK_SOURCE="adb:$pkg"; return 0
    fi
    warn "  $pkg: all local methods failed"
  done < <(discover_pkgs)
  return 1
}

# ---------------------------------------------------------------------------
# Online fallback
# ---------------------------------------------------------------------------

find_release_url(){
  local repo url
  for repo in "${SHIZUKU_REPOS[@]}"; do
    stage "fetch" "Checking releases: $repo"
    url="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
      | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.apk"' \
      | head -n1 | grep -oE '"[^"]+\.apk"$' | tr -d '"')"
    [ -n "$url" ] && { printf '%s' "$url"; return 0; }
    warn "  No APK in $repo latest release"
  done
  return 1
}

fetch_apk(){
  [ "$ALLOW_DOWNLOAD" = true ] \
    || err "No local/ADB APK found and --no-download is set"
  stage "fetch" "All local probes failed — downloading from GitHub"
  local url
  url="$(find_release_url)" \
    || err "No Shizuku release found. Install Shizuku first or check network."
  curl -fsSL -o "$TMP_SUBDIR/app.apk" "$url" || err "APK download failed"
  APK_SOURCE="downloaded:$(printf '%s' "$url" \
    | grep -oE 'github\.com/[^/]+/[^/]+' | head -n1 | cut -d/ -f2-3)"
  ok "Downloaded $APK_SOURCE"
}

# ---------------------------------------------------------------------------
# Extract, patch, install, verify
# ---------------------------------------------------------------------------

extract_assets(){
  stage "extract" "Unpacking assets"
  $UNZIP_CMD -qq "$TMP_SUBDIR/app.apk" -d "$TMP_SUBDIR" \
    || err "APK extraction failed — corrupt archive?"
  [ -f "$TMP_SUBDIR/assets/rish" ]             || err "assets/rish not in APK"
  [ -f "$TMP_SUBDIR/assets/rish_shizuku.dex" ] || err "assets/rish_shizuku.dex not in APK"
  ok "Extracted rish + rish_shizuku.dex"
}

patch_rish(){
  stage "extract" "Patching rish for $PKG"
  { printf '#!%s\n' "$(command -v sh)"
    $GREP_CMD -v '^#' "$TMP_SUBDIR/assets/rish"
  } > "$TMP_SUBDIR/rish"
  $SED_CMD -i "s/PKG/$PKG/g" "$TMP_SUBDIR/rish"
  ok "rish patched"
}

do_install(){
  stage "install" "Installing to $BIN"
  if $INSTALL_CMD -m755 "$TMP_SUBDIR/rish" "$RISH" 2>/dev/null && \
     $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$DEX" 2>/dev/null; then
    ln -sf "$RISH" "$HOME/rish" 2>/dev/null || true
    ln -sf "$DEX"  "$HOME/rish_shizuku.dex" 2>/dev/null || true
    ok "Installed to $BIN"
  else
    stage "install" "Cannot write to $BIN — using \$HOME"
    $INSTALL_CMD -m755 "$TMP_SUBDIR/rish" "$HOME/rish" \
      || err "Failed to install rish"
    $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$HOME/rish_shizuku.dex" \
      || err "Failed to install rish_shizuku.dex"
    RISH="$HOME/rish"; DEX="$HOME/rish_shizuku.dex"
    ok "Installed to $HOME"
  fi
}

verify_install(){
  stage "verify" "Verifying"
  [ -f "$RISH" ] || err "rish missing at $RISH"
  [ -x "$RISH" ] || err "rish not executable at $RISH"
  [ -f "$DEX"  ] || err "rish_shizuku.dex missing at $DEX"
  ok "rish:             $RISH"
  ok "rish_shizuku.dex: $DEX"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_adb 2>/dev/null || true
ensure_tools
extract_local || fetch_apk
extract_assets
patch_rish
do_install
verify_install

stage "done" "Completed (source: ${APK_SOURCE})"
msg "Run: rish"
