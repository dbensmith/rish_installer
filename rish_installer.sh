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
  R='\033[1;31m'; G='\033[1;32m'; B='\033[1;34m'; Y='\033[1;33m'; X='\033[0m'
else
  R=''; G=''; B=''; Y=''; X=''
fi

msg(){ echo -e "${B}[*]${X} $1"; }
ok(){ echo -e "${G}[+]${X} $1"; }
warn(){ echo -e "${Y}[-]${X} $1"; }
err(){ echo -e "${R}[!]${X} $1"; }

hide_cursor(){
  command -v tput >/dev/null 2>&1 && tput civis 2>/dev/null || echo -ne '\e[?25l'
}
show_cursor(){
  command -v tput >/dev/null 2>&1 && tput cnorm 2>/dev/null || echo -ne '\e[?25h'
}

cleanup(){
  show_cursor
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}
trap cleanup EXIT INT TERM HUP

BIN_PATH="$(command -v bash)"
BIN="$(dirname "$BIN_PATH")"
RISH="$BIN/rish"
DEX="$BIN/rish_shizuku.dex"

if [ "$ACTION" = "uninstall" ]; then
  if [ ! -f "$RISH" ]; then
    warn "rish is not installed"
    exit 0
  fi
  echo -ne "${Y}[?]${X} rish is installed. Uninstall? [y/N]: "
  read -r c
  case "$c" in
    y|Y)
      hide_cursor
      rm -f "$RISH" "$DEX" "$HOME/rish" "$HOME/rish_shizuku.dex"
      ok "rish uninstalled"
      ;;
    *)
      msg "Canceled"
      ;;
  esac
  exit 0
fi

for tool in curl unzip sed install; do
  command -v "$tool" >/dev/null 2>&1 || { err "Missing tool: $tool"; exit 1; }
done

if [ -f "$RISH" ] && [ "$ACTION" != "reinstall" ]; then
  echo -ne "${Y}[?]${X} rish already installed. Reinstall? [y/N]: "
  read -r c
  case "$c" in
    y|Y) ACTION="reinstall" ;;
    *) msg "Canceled"; exit 0 ;;
  esac
fi

hide_cursor
TMPBASE="${TMPDIR:-$PREFIX/tmp}"
[ -d "$TMPBASE" ] || mkdir -p "$TMPBASE"
TMPDIR="$(mktemp -d "$TMPBASE/rish.XXXXXX")"

U="$(curl -sL https://api.github.com/repos/RikkaApps/Shizuku/releases/latest \
  | grep '"browser_download_url"' \
  | grep '\.apk"' \
  | head -n1 \
  | sed -E 's/.*"(https.*\.apk)".*/\1/')"

[ -z "$U" ] && err "Failed to fetch APK URL" && exit 1

msg "Downloading Shizuku APK"
curl -sS -L -o "$TMPDIR/S.apk" "$U" || { err "Download failed"; exit 1; }

msg "Extracting rish"
unzip -q "$TMPDIR/S.apk" -d "$TMPDIR"

[ ! -f "$TMPDIR/assets/rish" ] && err "rish not found" && exit 1
[ ! -f "$TMPDIR/assets/rish_shizuku.dex" ] && err "dex not found" && exit 1

install -m755 "$TMPDIR/assets/rish" "$BIN/"
install -m644 "$TMPDIR/assets/rish_shizuku.dex" "$BIN/"

sed -i'' '/^#/d;s/PKG/com.termux/g' "$RISH" || true

ln -sf "$RISH" "$HOME/rish"
ln -sf "$DEX" "$HOME/rish_shizuku.dex"

ok "rish ready"

if ! "$RISH" -c 'id' >/dev/null 2>&1; then
  warn "Shizuku is not running"
fi

exit 0
