BIN="$(dirname "$(command -v bash)")"
RISH="$BIN/rish"
DEX="$BIN/rish_shizuku.dex"

ACTION="install"
for a in "$@"; do
case "$a" in
--uninstall) ACTION="uninstall" ;;
--reinstall) ACTION="reinstall" ;;
esac
done
if [ "$ACTION" = "uninstall" ]; then
rm -f "$RISH" "$DEX" "$HOME/rish" "$HOME/rish_shizuku.dex"
find "$HOME" -maxdepth 1 -type l -name "rish*" -delete 2>/dev/null || true
echo "[+] rish has been removed."
exit 0
fi

if [ -t 1 ]; then
C0='\033[0m'; CR='\033[31m'; CG='\033[32m'; CY='\033[33m'; CB='\033[34m'; CC='\033[36m'
else
C0=''; CR=''; CG=''; CY=''; CB=''; CC=''
fi
msg(){ echo -e "${CB}[i]${C0} $1"; }
ok(){ echo -e "${CG}[+]${C0} $1"; }
warn(){ echo -e "${CY}[!]${C0} $1"; }
err(){ echo -e "${CR}[x]${C0} $1"; exit 1; }
step(){ echo -e "${CC}==>${C0} $1"; }

cleanup(){ rm -rf "${TMP_SUBDIR:-}"; }
trap cleanup EXIT

detect_pkg(){
p="${PREFIX:-}"
[ -z "$p" ] && p="$(pwd)"
if [[ "$p" == /data/data/* ]]; then
echo "${p#/data/data/}" | cut -d/ -f1
return
fi
if [[ "$p" == /data/user/* ]]; then
echo "$p" | cut -d/ -f5
return
fi
if [ -n "$HOME" ]; then
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

PKG="$(detect_pkg)"
[ "$PKG" = "unknown" ] && err "pkg detect failed"

BASE_TMPDIR="${TMPDIR:-/tmp}"
TMP_SUBDIR="$(mktemp -d "$BASE_TMPDIR/rish.XXXX")"

PLAN_A=1
for t in unzip sed grep install; do
command -v "$t" >/dev/null || PLAN_A=0
done

if [ "$PLAN_A" -eq 1 ]; then
UNZIP=unzip; SED=sed; GREP=grep; INSTALL=install
else
warn "using busybox"
ARCH="$(uname -m)"
case "$ARCH" in
aarch64*) ARCH=arm64;;
arm*) ARCH=arm;;
x86_64*) ARCH=x86_64;;
*) err "arch";;
esac
URL="https://raw.githubusercontent.com/merbah3266/rish_installer/main/busybox/$ARCH/busybox"
BB="$TMP_SUBDIR/busybox"
curl -fsSL "$URL" -o "$BB" || err "bb download"
chmod +x "$BB"
UNZIP="$BB unzip"
SED="$BB sed"
GREP="$BB grep"
INSTALL="$BB install"
ok "busybox ready"
fi

extract_local(){
step "offline attempt"
APK_PATH="$(cmd package path moe.shizuku.privileged.api --user 0 2>/dev/null | cut -d: -f2)"
[ -z "$APK_PATH" ] && return 1
if cp "$APK_PATH" "$TMP_SUBDIR/app.apk" 2>/dev/null; then
ok "local apk used"
return 0
fi
warn "permission denied"
return 1
}

APK_OK=0
if extract_local; then
APK_OK=1
fi

if [ "$APK_OK" -eq 0 ]; then
step "online fallback"
URL="$(curl -fsSL https://api.github.com/repos/RikkaApps/Shizuku/releases/latest \
| sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\.apk\)".*/\1/p' | head -n1)"
[ -z "$URL" ] && err "no url"
curl -fsSL -o "$TMP_SUBDIR/app.apk" "$URL" || err "download"
fi

step "extracting"
$UNZIP -qq "$TMP_SUBDIR/app.apk" -d "$TMP_SUBDIR" || err "unzip"
[ ! -f "$TMP_SUBDIR/assets/rish" ] && err "no rish"
[ ! -f "$TMP_SUBDIR/assets/rish_shizuku.dex" ] && err "no dex"

TMP_RISH="$TMP_SUBDIR/rish"
echo "#!$(command -v sh)" > "$TMP_RISH"
$GREP -v '^#' "$TMP_SUBDIR/assets/rish" >> "$TMP_RISH"
$SED -i "s/PKG/$PKG/g" "$TMP_RISH"

step "installing"
if $INSTALL -m755 "$TMP_RISH" "$RISH" 2>/dev/null && \
   $INSTALL -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$DEX" 2>/dev/null; then
ok "installed in bin"
ln -sf "$RISH" "$HOME/rish" 2>/dev/null
ln -sf "$DEX" "$HOME/rish_shizuku.dex" 2>/dev/null
msg "symlinks created in home"
else
warn "fallback home"
$INSTALL -m755 "$TMP_RISH" "$HOME/rish" || err "fail"
$INSTALL -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$HOME/rish_shizuku.dex"
msg "installed directly in home"
fi
ok "done, run: rish"    return
  fi
  echo "unknown"
}
PKG="$(detect_pkg)"
[ "$PKG" = "unknown" ] && err "Failed to detect package name"
BIN_PATH="$(command -v bash)"
BIN="$(dirname "$BIN_PATH")"
RISH="$BIN/rish"
DEX="$BIN/rish_shizuku.dex"
ACTION="install"
for a in "$@"; do
  case "$a" in
    --uninstall) ACTION="uninstall" ;;
    --reinstall) ACTION="reinstall" ;;
  esac
done
if [ "$ACTION" = "uninstall" ]; then
  rm -f "$RISH" "$DEX" "$HOME/rish" "$HOME/rish_shizuku.dex"
  find "$HOME" -maxdepth 1 -type l -name "rish*" -delete 2>/dev/null || true
  ok "rish has been removed."
  exit 0
fi
if [ -f "$RISH" ] && [ "$ACTION" != "reinstall" ]; then
  [ -t 1 ] && tput cnorm 2>/dev/null || true
  echo -ne "${Y}  [?]${X} rish is already installed. Reinstall? [y/N]: "
  read -r c < /dev/tty
  [ -t 1 ] && tput civis 2>/dev/null || true
  case "$c" in
    y|Y) ACTION="reinstall" ;;
    *) msg "Cancelled."; exit 0 ;;
  esac
fi
BASE_TMPDIR="${TMPDIR:-/tmp}"
TMP_SUBDIR="$(mktemp -d "$BASE_TMPDIR/rish.XXXXXX")"
PLAN_A_OK=1
MISSING_TOOLS=""
for t in unzip sed grep install; do
  if ! command -v "$t" >/dev/null 2>&1; then
    PLAN_A_OK=0
    MISSING_TOOLS="$MISSING_TOOLS $t"
  fi
done
if [ "$PLAN_A_OK" -eq 1 ]; then
  msg "All the required tools are available."
  UNZIP_CMD="unzip"; SED_CMD="sed"; GREP_CMD="grep"; INSTALL_CMD="install"
else
  warn "Missing tools:${MISSING_TOOLS}"
  msg "Using BusyBox..."
  detect_arch() {
    ARCH="$(uname -m)"
    case "$ARCH" in
      aarch64|arm64|armv8*) echo "arm64" ;;
      armv*|armhf|arm) echo "arm" ;;
      x86_64|amd64) echo "x86_64" ;;
      i386|i486|i586|i686|x86) echo "x86" ;;
      *) echo "unknown" ;;
    esac
  }
  ARCH_DIR="$(detect_arch)"
  [ "$ARCH_DIR" = "unknown" ] && err "Unsupported arch"
  BB_BASE="https://raw.githubusercontent.com/merbah3266/rish_installer/main/busybox"
  BB_URL="$BB_BASE/$ARCH_DIR/busybox"
  BUSYBOX="$TMP_SUBDIR/busybox"
  step "Downloading BusyBox ($ARCH_DIR)..."
  curl -fsSL "$BB_URL" -o "$BUSYBOX" || err "BusyBox download failed"
  chmod +x "$BUSYBOX"
  $BUSYBOX --help >/dev/null 2>&1 || err "Invalid busybox"
  BB="$BUSYBOX"
  UNZIP_CMD="$BB unzip"; SED_CMD="$BB sed"; GREP_CMD="$BB grep"; INSTALL_CMD="$BB install"
  ok "BusyBox ready."
fi
step "Fetching latest Shizuku APK..."
APK_URL="$(curl -fsSL https://api.github.com/repos/RikkaApps/Shizuku/releases/latest \
 | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\.apk\)".*/\1/p' | head -n1)"
[ -z "$APK_URL" ] && err "Failed to fetch APK URL"
step "Downloading APK..."
curl -fsSL -o "$TMP_SUBDIR/app.apk" "$APK_URL" || err "Download failed"
step "Extracting files..."
 $UNZIP_CMD -qq "$TMP_SUBDIR/app.apk" -d "$TMP_SUBDIR" || err "Extraction failed"

[ ! -f "$TMP_SUBDIR/assets/rish" ] && err "rish not found in APK"
[ ! -f "$TMP_SUBDIR/assets/rish_shizuku.dex" ] && err "dex not found in APK"
SH_PATH="$(command -v sh)"
[ -z "$SH_PATH" ] && err "sh not found"
TMP_RISH="$(mktemp "$TMP_SUBDIR/rish.XXXXXX")"
echo "#!$SH_PATH" > "$TMP_RISH"
 $GREP_CMD -v '^#' "$TMP_SUBDIR/assets/rish" >> "$TMP_RISH"
 $SED_CMD -i "s/PKG/$PKG/g" "$TMP_RISH"
step "Installing rish..." 
INSTALL_SUCCESS=0
if $INSTALL_CMD -m755 "$TMP_RISH" "$RISH" 2>/dev/null && \
   $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$DEX" 2>/dev/null; then
    ok "Installed to bin directory ($BIN)"
    ln -sf "$RISH" "$HOME/rish" 2>/dev/null
    ln -sf "$DEX" "$HOME/rish_shizuku.dex" 2>/dev/null
    msg "Symlinks created."
    INSTALL_SUCCESS=1
else
    warn "Cannot write to bin directory. Trying Home directory..."
    if $INSTALL_CMD -m755 "$TMP_RISH" "$HOME/rish" && \
       $INSTALL_CMD -m400 "$TMP_SUBDIR/assets/rish_shizuku.dex" "$HOME/rish_shizuku.dex"; then
        ok "Installed to Home."
        msg "Run: $HOME/rish"
    else
        err "Installation failed."
    fi
fi
if [ "$INSTALL_SUCCESS" -eq 1 ]; then
    ok "Setup complete. Run 'rish' directly."
else
    ok "Setup complete, Run '~/rish' or 'rish'."
fi
