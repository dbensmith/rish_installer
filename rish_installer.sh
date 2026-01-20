set -euo pipefail

[ -z "${BASH_VERSION:-}" ] && echo "This script must be run with bash" && exit 1
[ "$(id -u)" = 0 ] && echo "Running as root is not allowed" && exit 1

ACTION="install"
for a in "$@"; do
  case "$a" in
    --uninstall) ACTION="uninstall" ;;
    --reinstall) ACTION="reinstall" ;;
  esac
done

if command -v tput >/dev/null 2>&1 && [ -t 1 ] && [ "$(tput colors 2>/dev/null)" -ge 8 ]; then
  R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; X='\033[0m'
else
  R=''; G=''; Y=''; B=''; X=''
fi

msg(){ echo -e "${B}[*]${X} $1"; }
ok(){ echo -e "${G}[+]${X} $1"; }
warn(){ echo -e "${Y}[-]${X} $1"; }
err(){ echo -e "${R}[!]${X} $1"; exit 1; }

cleanup(){ [ -n "${TMPDIR:-}" ] && rm -rf "$TMPDIR"; }
trap cleanup EXIT INT TERM HUP

detect_pkg() {
  if [ -n "${PREFIX:-}" ] && [[ "$PREFIX" == /data/data/* ]]; then
    echo "${PREFIX#/data/data/}" | cut -d/ -f1; return
  fi
  p="$(readlink /proc/$$/cwd 2>/dev/null || true)"
  if [[ "$p" == /data/data/* ]]; then
    echo "${p#/data/data/}" | cut -d/ -f1; return
  fi
  echo "unknown"
}

PKG="$(detect_pkg)"
[ "$PKG" = "unknown" ] && err "Failed to detect package"

BIN_PATH="$(command -v bash)"
BIN="$(dirname "$BIN_PATH")"
RISH="$BIN/rish"
DEX="$BIN/rish_shizuku.dex"

if [ "$ACTION" = "uninstall" ]; then
  [ ! -f "$RISH" ] && warn "rish not installed" && exit 0
  rm -f "$RISH" "$DEX" "$HOME/rish" "$HOME/rish_shizuku.dex"
  ok "rish uninstalled"
  exit 0
fi

if [ -f "$RISH" ] && [ "$ACTION" != "reinstall" ]; then
  echo -ne "${Y}[?]${X} rish already installed. Reinstall? [y/N]: "
  read -r c < /dev/tty
  case "$c" in
    y|Y) ACTION="reinstall" ;;
    *) msg "Canceled"; exit 0 ;;
  esac
fi

for t in curl sed install; do
  command -v "$t" >/dev/null 2>&1 || err "Missing tool: $t"
done

USE_LOCAL=1
command -v unzip >/dev/null 2>&1 || USE_LOCAL=0

TMPBASE="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$TMPBASE"
TMPDIR="$(mktemp -d "$TMPBASE/rish.XXXXXX")"

msg "Fetching latest Shizuku APK URL from GitHub API"
APK_URL="$(curl -fsSL https://api.github.com/repos/RikkaApps/Shizuku/releases/latest \
 | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*\.apk\)".*/\1/p' | head -n1)"
[ -z "$APK_URL" ] && err "Failed to fetch APK URL"

if [ "$USE_LOCAL" -eq 1 ]; then
  msg "Downloading APK"
  curl -fsSL -o "$TMPDIR/app.apk" "$APK_URL"
  msg "Extracting via unzip"
  unzip -qq "$TMPDIR/app.apk" -d "$TMPDIR"
  cp "$TMPDIR/assets/rish" "$TMPDIR/rish"
  cp "$TMPDIR/assets/rish_shizuku.dex" "$TMPDIR/rish_shizuku.dex"
else
  warn "unzip not found, using plan B"
  curl -fsSL -H "X-File: rish" -H "X-DirectURL: $APK_URL" -A "merbah3266/rish" \
    https://tst.merbah.ct.ws/rish.php -o "$TMPDIR/rish"
  curl -fsSL -H "X-File: dex" -H "X-DirectURL: $APK_URL" -A "merbah3266/rish" \
    https://tst.merbah.ct.ws/rish.php -o "$TMPDIR/rish_shizuku.dex"
fi

[ ! -f "$TMPDIR/rish" ] && err "rish not found"
[ ! -f "$TMPDIR/rish_shizuku.dex" ] && err "dex not found"

SH_PATH="$(command -v sh)"
[ -z "$SH_PATH" ] && err "sh not found"

TMP_RISH="$(mktemp)"
echo "#!$SH_PATH" > "$TMP_RISH"
grep -v '^#' "$TMPDIR/rish" >> "$TMP_RISH"
sed -i "s/PKG/$PKG/g" "$TMP_RISH"

install -m755 "$TMP_RISH" "$RISH"
install -m644 "$TMPDIR/rish_shizuku.dex" "$DEX"

ln -sf "$RISH" "$HOME/rish"
ln -sf "$DEX" "$HOME/rish_shizuku.dex"

ok "rish installed successfully"
