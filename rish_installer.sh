#!/usr/bin/env bash
set -euo pipefail

ACTION="install"
SHIZUKU_REPOS=()
APK_PACKAGES=("moe.shizuku.privileged.api")

while [ "$#" -gt 0 ]; do
  case "$1" in
    --uninstall) ACTION="uninstall" ;;
    --reinstall) ACTION="reinstall" ;;
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

if [ -t 2 ]; then
  C0='\033[0m'; CR='\033[31m'; CG='\033[32m'; CY='\033[33m'; CB='\033[34m'; CC='\033[36m'
else
  C0=''; CR=''; CG=''; CY=''; CB=''; CC=''
fi
# All logging goes to stderr so none of it can pollute command substitutions.
msg(){ echo -e "${CB}[i]${C0} $1" >&2; }
ok(){  echo -e "${CG}[+]${C0} $1" >&2; }
warn(){ echo -e "${CY}[!]${C0} $1" >&2; }
err(){  echo -e "${CR}[x]${C0} $1" >&2; exit 1; }
step(){ echo -e "${CC}==>${C0} $1" >&2; }

cleanup(){ rm -rf "${TMP_SUBDIR:-}"; }
trap cleanup EXIT

detect_pkg(){
  local p="${PREFIX:-}"
  [ -z "$p" ] && p="$(pwd)"
  if [[ "$p" == /data/data/* ]]; then
    echo "${p#/data/data/}" | cut -d/ -f1
    return
  fi
  if [[ "$p" == /data/user/* ]]; then
    echo "$p" | cut -d/ -f5
    return
  fi
  if [ -n "${HOME:-}" ]; then
    if [[ "$HOME" == /data/data/* ]]; then
      echo "${HOME#/data/data/}" | cut -d/ -f1
      return
    fi
    if [[ "$HOME" == /data/user/* ]]; then
      echo "$HOME" | cut -d/ -f5
      return
    fi
  fi
  echo "unknown"
}

is_termux(){
  case "${PREFIX:-}" in
    */com.termux/*) return 0 ;;
  esac
  case "${HOME:-}" in
    */com.termux/*) return 0 ;;
  esac
  [ "$(detect_pkg 2>/dev/null || true)" = "com.termux" ]
}

PKG="$(detect_pkg)"
[ "$PKG" = "unknown" ] && err "Failed to detect terminal package name"

BIN_PATH="$(command -v bash 2>/dev/null || true)"
[ -z "$BIN_PATH" ] && err "bash not found"
BIN="$(dirname "$BIN_PATH")"
RISH="$BIN/rish"
DEX="$BIN/rish_shizuku.dex"

if [ "$ACTION" = "uninstall" ]; then
  rm -f "$RISH" "$DEX" "$HOME/rish" "$HOME/rish_shizuku.dex"
  find "$HOME" -maxdepth 1 -type l -name 'rish*' -delete 2>/dev/null || true
  ok "rish has been removed"
  exit 0
fi

if [ -f "$RISH" ] && [ "$ACTION" != "reinstall" ]; then
  warn "rish is already installed; use --reinstall to replace it"
  exit 0
fi

BASE_TMPDIR="${TMPDIR:-/tmp}"
TMP_SUBDIR="$(mktemp -d "$BASE_TMPDIR/rish.XXXXXX")"

UNZIP_CMD=""
SED_CMD=""
GREP_CMD=""
INSTALL_CMD=""

use_busybox(){
  local bb="$1"
  UNZIP_CMD="$bb unzip"
  SED_CMD="$bb sed"
  GREP_CMD="$bb grep"
  INSTALL_CMD="$bb install"
}

have_native_tools(){
  local t
  for t in unzip sed grep install; do
    command -v "$t" >/dev/null 2>&1 || return 1
  done
  return 0
}

ensure_tools(){
  if have_native_tools; then
    UNZIP_CMD="unzip"
    SED_CMD="sed"
    GREP_CMD="grep"
    INSTALL_CMD="install"
    ok "native tools available"
    return 0
  fi

  if command -v busybox >/dev/null 2>&1; then
    use_busybox "busybox"
    ok "using installed busybox"
    return 0
  fi

  if is_termux; then
    step "installing busybox via Termux"
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

extract_local(){
  local apk_path pkg_name
  step "offline/local APK probe"
  for pkg_name in "${APK_PACKAGES[@]}"; do
    apk_path="$(cmd package path "$pkg_name" --user 0 2>/dev/null | cut -d: -f2 | head -n1)"
    if [ -n "$apk_path" ]; then
      if cp "$apk_path" "$TMP_SUBDIR/app.apk" 2>/dev/null; then
        ok "using local APK from $pkg_name"
        return 0
      fi
      warn "found $pkg_name but could not read APK"
    fi
  done
  return 1
}

find_release_apk(){
  local repo api url
  for repo in "${SHIZUKU_REPOS[@]}"; do
    step "checking releases: $repo"
    api="https://api.github.com/repos/${repo}/releases/latest"
    # grep -oE extracts only the URL value; no surrounding JSON text leaks out.
    url="$(curl -fsSL "$api" \
      | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.apk"' \
      | head -n1 \
      | grep -oE '"[^"]+\.apk"$' \
      | tr -d '"')"
    if [ -n "$url" ]; then
      printf '%s\n' "$url"
      return 0
    fi
  done
  return 1
}

ensure_tools

if ! extract_local; then
  step "online fallback"
  APK_URL="$(find_release_apk)" || err "failed to locate a Shizuku APK release"
  curl -fsSL -o "$TMP_SUBDIR/app.apk" "$APK_URL" || err "APK download failed"
  ok "downloaded APK from release"
fi

step "extracting assets"
$UNZIP_CMD -qq "$TMP_SUBDIR/app.apk" -d "$TMP_SUBDIR" || err "APK extraction failed"
[ -f "$TMP_SUBDIR/assets/rish" ] || err "assets/rish not found"
[ -f "$TMP_SUBDIR/assets/rish_shizuku.dex" ] || err "assets/rish_shizuku.dex not found"

TMP_RISH="$TMP_SUBDIR/rish"
printf '#!%s\n' "$(command -v sh)" > "$TMP_RISH"
$GREP_CMD -v '^#' "$TMP_SUBDIR/assets/rish" >> "$TMP_RISH"
$SED_CMD -i "s/PKG/$PKG/g" "$TMP_RISH"

step "installing"
if $INSTALL_CMD -m755 "$TMP_RISH" "$RISH" 2>/dev/null && \
   $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$DEX" 2>/dev/null; then
  ln -sf "$RISH" "$HOME/rish" 2>/dev/null || true
  ln -sf "$DEX" "$HOME/rish_shizuku.dex" 2>/dev/null || true
  ok "installed to $BIN"
  msg "run: rish"
else
  warn "cannot write to $BIN; falling back to HOME"
  $INSTALL_CMD -m755 "$TMP_RISH" "$HOME/rish" || err "failed to install rish"
  $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$HOME/rish_shizuku.dex" || err "failed to install dex"
  ok "installed to $HOME"
  msg "run: $HOME/rish"
fi
