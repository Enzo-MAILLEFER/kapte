#!/bin/bash
# Installe Kapte : double-clic sur ce fichier (ou : bash "Installer Kapte.command").
# Peut être relancé sans risque pour mettre à jour (la clé Gemini est conservée).

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.kapte"
LA="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

pause_exit() {
  echo
  read -r -n 1 -p "Appuie sur une touche pour fermer cette fenêtre…"
  echo
  exit "${1:-0}"
}

clear
echo "=============================================="
echo "        Installation de Kapte"
echo "=============================================="
echo

# 1. Python (fourni par les outils de développement d'Apple)
if ! xcode-select -p >/dev/null 2>&1; then
  echo "⚠️  Il manque les outils de développement d'Apple (ils contiennent Python)."
  echo "   Une fenêtre va s'ouvrir : clique sur « Installer » et attends la fin"
  echo "   (quelques minutes), puis relance ce fichier."
  xcode-select --install >/dev/null 2>&1
  pause_exit 1
fi
echo "✅ Python est disponible."

# 2. Copie des fichiers
mkdir -p "$DEST"
for f in kapte.py overlay.js menubar.js update.sh VERSION; do
  if [ ! -f "$SRC/$f" ]; then
    echo "❌ Fichier manquant : $f. Dézippe bien tout le dossier avant de lancer l'installation."
    pause_exit 1
  fi
  cp "$SRC/$f" "$DEST/"
done
cp "$SRC/Desinstaller Kapte.command" "$DEST/" 2>/dev/null
xattr -cr "$DEST" 2>/dev/null
chmod +x "$DEST/kapte.py" "$DEST/update.sh" "$DEST/Desinstaller Kapte.command" 2>/dev/null
echo "✅ Fichiers copiés dans $DEST"

# Ancienne version (« Screen Coach ») : on reprend la config puis on la retire
OLD="$HOME/.screen-coach"
if [ -d "$OLD" ]; then
  [ -f "$DEST/config.json" ] || cp "$OLD/config.json" "$DEST/config.json" 2>/dev/null
  for L in com.screencoach com.screencoach.menubar; do
    launchctl bootout "gui/$UID_NUM/$L" >/dev/null 2>&1
    rm -f "$LA/$L.plist"
  done
  pkill -f "$OLD/menubar.js" >/dev/null 2>&1
  rm -rf "$OLD"
  echo "✅ Ancienne version (Screen Coach) remplacée, réglages conservés."
fi

# 3. Clé Gemini (gardée si déjà configurée)
HAS_KEY="$(/usr/bin/python3 -c '
import json, sys
try:
    print("1" if json.load(open(sys.argv[1])).get("gemini_api_key") else "")
except Exception:
    print("")
' "$DEST/config.json")"

if [ -n "$HAS_KEY" ]; then
  echo "✅ Clé Gemini déjà configurée, je la garde."
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
    KEY="$(echo "$KEY" | tr -d '[:space:]')"
    [ -z "$KEY" ] && continue
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "x-goog-api-key: $KEY" \
      "https://generativelanguage.googleapis.com/v1beta/models")"
    if [ "$CODE" = "200" ]; then
      echo "✅ Clé valide."
      break
    fi
    echo "❌ Cette clé ne marche pas (code $CODE). Vérifie que tu l'as copiée en entier."
  done
  GEMINI_KEY="$KEY" /usr/bin/python3 - "$DEST/config.json" <<'EOF'
import json, os, sys
path = sys.argv[1]
try:
    cfg = json.load(open(path))
except Exception:
    cfg = {}
cfg.update({"provider": "gemini", "gemini_api_key": os.environ["GEMINI_KEY"]})
for k, v in {"gemini_model": "gemini-3.5-flash-lite", "display_seconds": 15,
             "max_words": 45, "watch_dir": "", "extra_instructions": ""}.items():
    cfg.setdefault(k, v)
json.dump(cfg, open(path, "w"), indent=2, ensure_ascii=False)
EOF
  chmod 600 "$DEST/config.json"
fi

# 4. Services : le surveillant + l'icône de la barre des menus
mkdir -p "$LA"
cat > "$LA/com.kapte.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kapte</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>$DEST/kapte.py</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$DEST/error.log</string>
  <key>StandardOutPath</key><string>$DEST/out.log</string>
</dict>
</plist>
EOF
cat > "$LA/com.kapte.menubar.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kapte.menubar</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/osascript</string>
    <string>-l</string>
    <string>JavaScript</string>
    <string>$DEST/menubar.js</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>StandardErrorPath</key><string>$DEST/menubar.log</string>
</dict>
</plist>
EOF
for L in com.kapte com.kapte.menubar; do
  launchctl bootout "gui/$UID_NUM/$L" >/dev/null 2>&1
done
sleep 1
for L in com.kapte com.kapte.menubar; do
  launchctl bootstrap "gui/$UID_NUM" "$LA/$L.plist" 2>/dev/null \
    || { sleep 2; launchctl bootstrap "gui/$UID_NUM" "$LA/$L.plist"; }
done
echo "✅ Kapte est lancé (icône 👁 en haut de l'écran, dans la barre des menus)."

# 5. Dossier des captures (hors Bureau : macOS interdit au service de lire le Bureau)
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
rm -f "$DEST/paused"
BEFORE="$(grep -c 'Nouvelle capture' "$DEST/out.log" 2>/dev/null)"
MARK="$(mktemp)"
OK=""
for _ in $(seq 1 60); do
  sleep 1
  NOW="$(grep -c 'Nouvelle capture' "$DEST/out.log" 2>/dev/null)"
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
    echo "   si rien ne s'affiche, regarde le fichier $DEST/error.log."
  fi
fi
rm -f "$MARK"
echo
echo "----------------------------------------------"
echo " Utilisation :"
echo "  • Fais une capture → la réponse s'affiche en bas à gauche."
echo "  • Icône 👁 en haut de l'écran → « Mettre en pause » / « Activer »."
echo "  • Mises à jour : Kapte te prévient tout seul, puis icône 👁 → « Mettre à jour »."
echo "  • Désinstaller : double-clic sur « Desinstaller Kapte.command »"
echo "    (une copie est aussi dans $DEST)."
echo "----------------------------------------------"
pause_exit 0
