#!/bin/bash
# Installe Kapte : double-clic sur ce fichier (ou : bash "Installer Kapte.command").
# Peut être relancé sans risque (la clé Gemini et les réglages sont conservés).
# KAPTE_UNATTENDED=1 : installation sans question.

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.kapte"
APPS="$HOME/Applications"
LA="$HOME/Library/LaunchAgents"
PLIST="$LA/com.kapte.plist"
UID_NUM="$(id -u)"
UNATTENDED="${KAPTE_UNATTENDED:-}"
RELEASE_ZIP="https://github.com/Enzo-MAILLEFER/kapte/releases/latest/download/Kapte.zip"

pause_exit() {
  if [ -z "$UNATTENDED" ]; then
    echo
    read -r -n 1 -p "Appuie sur une touche pour fermer cette fenêtre…"
    echo
  fi
  exit "${1:-0}"
}

[ -z "$UNATTENDED" ] && clear
echo "=============================================="
echo "        Installation de Kapte"
echo "=============================================="
echo

# 1. L'app : à côté de ce fichier (zip de la release), sinon on la télécharge
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
APP_SRC="$SRC/Kapte.app"
if [ ! -d "$APP_SRC" ]; then
  echo "⬇️  Téléchargement de Kapte…"
  if ! curl -fsSL --max-time 120 "$RELEASE_ZIP" -o "$TMP/Kapte.zip" \
     || ! ditto -x -k "$TMP/Kapte.zip" "$TMP"; then
    echo "❌ Téléchargement impossible. Vérifie ta connexion et relance l'installation."
    pause_exit 1
  fi
  APP_SRC="$TMP/Kapte/Kapte.app"
fi

# 2. On arrête la version en cours avant de la remplacer
mkdir -p "$DEST" "$APPS" "$LA"
launchctl bootout "gui/$UID_NUM/com.kapte" >/dev/null 2>&1

rm -rf "$APPS/Kapte.app"
ditto "$APP_SRC" "$APPS/Kapte.app"
xattr -cr "$APPS/Kapte.app" 2>/dev/null
cp "$SRC/Desinstaller Kapte.command" "$DEST/" 2>/dev/null
chmod +x "$DEST/Desinstaller Kapte.command" 2>/dev/null
VERSION="$(defaults read "$APPS/Kapte.app/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
echo "✅ Kapte v$VERSION installé dans $APPS"

# 3. Clé Gemini (gardée si déjà configurée)
if grep -Eq '"gemini_api_key"[[:space:]]*:[[:space:]]*"[^"]+"' "$DEST/config.json" 2>/dev/null; then
  echo "✅ Clé Gemini déjà configurée, je la garde."
elif [ -n "$UNATTENDED" ]; then
  echo "⚠️  Pas de clé Gemini : relance l'installateur pour en ajouter une."
else
  echo
  echo "🔑 Il te faut une clé Gemini (gratuite, compte Google) :"
  echo "   1. La page va s'ouvrir dans ton navigateur."
  echo "   2. Clique sur « Create API key », puis copie la clé."
  echo "   3. Reviens ici et colle-la (Cmd + V), puis Entrée."
  sleep 2
  open "https://aistudio.google.com/apikey"
  while true; do
    echo
    read -r -p "Colle ta clé Gemini : " KEY
    KEY="$(printf '%s' "$KEY" | tr -cd 'A-Za-z0-9_-')"
    [ -z "$KEY" ] && continue
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "x-goog-api-key: $KEY" \
      "https://generativelanguage.googleapis.com/v1beta/models")"
    if [ "$CODE" = "200" ]; then
      echo "✅ Clé valide."
      break
    fi
    echo "❌ Cette clé ne marche pas (code $CODE). Vérifie que tu l'as copiée en entier."
  done
  cat > "$DEST/config.json" <<EOF
{
  "gemini_api_key": "$KEY",
  "gemini_model": "gemini-3.5-flash-lite",
  "display_seconds": 15,
  "max_words": 45,
  "watch_dir": "",
  "extra_instructions": ""
}
EOF
  chmod 600 "$DEST/config.json"
fi

# 4. Démarrage automatique (et relance si l'app plante)
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kapte</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APPS/Kapte.app/Contents/MacOS/Kapte</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$DEST/kapte.log</string>
  <key>StandardErrorPath</key><string>$DEST/kapte.log</string>
</dict>
</plist>
EOF
[ -n "$UNATTENDED" ] && [ -n "$VERSION" ] && printf '%s' "$VERSION" > "$DEST/just_updated"
[ -z "$UNATTENDED" ] && rm -f "$DEST/paused"
sleep 1
launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null \
  || { sleep 2; launchctl bootstrap "gui/$UID_NUM" "$PLIST"; }
echo "✅ Kapte est lancé (icône 👁 en haut de l'écran, dans la barre des menus)."

[ -n "$UNATTENDED" ] && exit 0

# 5. Dossier des captures (hors Bureau : macOS interdit à Kapte de lire le Bureau)
mkdir -p "$HOME/Screenshots"
defaults write com.apple.screencapture location "$HOME/Screenshots"
echo
echo "=============================================="
echo " Dernière étape (à faire une seule fois) :"
echo "=============================================="
echo " La barre d'outils de capture va s'ouvrir."
echo "   1. Clique sur « Options »"
echo "   2. Dans « Enregistrer dans », choisis « Autre emplacement… »"
echo "   3. Sélectionne le dossier « Screenshots » (dans ton dossier perso)"
echo "   4. Appuie sur Échap"
echo
read -r -p "Appuie sur Entrée pour ouvrir la barre d'outils… "
open -a Screenshot 2>/dev/null || echo "   (Fais Cmd + Shift + 5 toi-même.)"
echo
read -r -p "Quand c'est fait, appuie sur Entrée… "

# 6. Test : on attend une vraie capture
echo
echo "📸 Fais une capture maintenant (Cmd + Shift + 4, puis sélectionne une zone)."
echo "   J'attends 60 secondes…"
BEFORE="$(grep -c 'Nouvelle capture' "$DEST/kapte.log" 2>/dev/null)"
MARK="$TMP/mark"
touch "$MARK"
OK=""
for _ in $(seq 1 60); do
  sleep 1
  NOW="$(grep -c 'Nouvelle capture' "$DEST/kapte.log" 2>/dev/null)"
  if [ "${NOW:-0}" -gt "${BEFORE:-0}" ]; then OK=1; break; fi
done
echo
if [ -n "$OK" ]; then
  echo "🎉 Ça marche ! La réponse va s'afficher en bas à gauche de l'écran."
else
  NEW_ON_DESKTOP="$(find "$HOME/Desktop" -maxdepth 1 \( -name 'Screenshot*' -o -name 'Capture*' \) \
    -newer "$MARK" 2>/dev/null | head -1)"
  if [ -n "$NEW_ON_DESKTOP" ]; then
    echo "⚠️  Ta capture est allée sur le Bureau : le dossier de captures n'est pas réglé."
    echo "   Refais Cmd + Shift + 5 → Options → Autre emplacement… → Screenshots."
  else
    echo "⚠️  Je n'ai pas vu de capture. Refais un essai avec Cmd + Shift + 4 :"
    echo "   si rien ne s'affiche, regarde le fichier $DEST/kapte.log."
  fi
fi
echo
echo "----------------------------------------------"
echo " Utilisation :"
echo "  • Fais une capture → la réponse s'affiche en bas à gauche."
echo "  • Icône 👁 en haut de l'écran → « Mettre en pause » / « Activer »."
echo "  • Mises à jour : automatiques, rien à faire."
echo "  • Désinstaller : double-clic sur « Desinstaller Kapte.command »"
echo "    (une copie est aussi dans $DEST)."
echo "----------------------------------------------"
pause_exit 0
