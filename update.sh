#!/bin/bash
# Met à jour Kapte depuis GitHub (lancé par l'icône 👁 → Mettre à jour).
# Remplace le code dans ~/.kapte ; config.json, la pause et les logs sont conservés.

# Ce fichier est lui-même remplacé pendant la mise à jour : on s'exécute depuis une copie.
if [ -z "$KAPTE_UPDATE_COPY" ]; then
  COPY="$(mktemp)"
  cp "$0" "$COPY"
  KAPTE_UPDATE_COPY=1 exec /bin/bash "$COPY" "$@"
fi

DEST="$HOME/.kapte"
ZIP_URL="https://github.com/Enzo-MAILLEFER/kapte/archive/refs/heads/main.zip"
UID_NUM="$(id -u)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$0"' EXIT

bubble() {
  osascript -l JavaScript "$DEST/overlay.js" "$1" "${2:-6}" >/dev/null 2>&1 &
}
fail() {
  echo "$(date '+%F %T') échec : $1"
  pkill -f "$DEST/overlay.js Mise à jour" >/dev/null 2>&1
  bubble "Mise à jour de Kapte impossible : $1" 8
  exit 1
}

echo "$(date '+%F %T') mise à jour depuis la v$(cat "$DEST/VERSION" 2>/dev/null)"
curl -fsSL --max-time 60 "$ZIP_URL" -o "$TMP/kapte.zip" || fail "téléchargement échoué"
ditto -x -k "$TMP/kapte.zip" "$TMP" || fail "archive illisible"
NEW="$TMP/kapte-main"

FILES="kapte.py overlay.js menubar.js update.sh VERSION"
for f in $FILES; do
  [ -f "$NEW/$f" ] || fail "fichier $f manquant"
done
/usr/bin/python3 -m py_compile "$NEW/kapte.py" || fail "nouvelle version invalide"

for f in $FILES; do
  cp "$NEW/$f" "$DEST/$f"
done
cp "$NEW/Desinstaller Kapte.command" "$DEST/" 2>/dev/null
chmod +x "$DEST/kapte.py" "$DEST/update.sh" "$DEST/Desinstaller Kapte.command" 2>/dev/null

VERSION="$(cat "$DEST/VERSION")"
echo "$(date '+%F %T') installé : v$VERSION"

launchctl kickstart -k "gui/$UID_NUM/com.kapte"
pkill -f "$DEST/overlay.js Mise à jour" >/dev/null 2>&1
bubble "Kapte est à jour (v$VERSION) ✓" 5
launchctl kickstart -k "gui/$UID_NUM/com.kapte.menubar"
