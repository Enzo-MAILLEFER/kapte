#!/bin/bash
# Désinstalle Kapte : double-clic sur ce fichier.

DEST="$HOME/.kapte"
LA="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

clear
echo "=============================================="
echo "       Désinstallation de Kapte"
echo "=============================================="
echo
echo "Ça va arrêter Kapte et supprimer ses fichiers (dont ta clé Gemini)."
echo "Tes captures dans le dossier « Screenshots » ne sont pas touchées."
echo
read -r -p "Continuer ? (o/n) " ANSWER
if [ "$ANSWER" != "o" ] && [ "$ANSWER" != "O" ]; then
  echo "Annulé, rien n'a été modifié."
  read -r -n 1 -p "Appuie sur une touche pour fermer…"
  exit 0
fi

for L in com.kapte com.kapte.menubar; do
  launchctl bootout "gui/$UID_NUM/$L" >/dev/null 2>&1
  rm -f "$LA/$L.plist"
done
pkill -f "$DEST/menubar.js" >/dev/null 2>&1
rm -rf "$DEST"
defaults delete com.apple.screencapture location >/dev/null 2>&1

echo
echo "✅ Kapte est désinstallé."
echo
echo "Pour que tes captures retournent sur le Bureau :"
echo "Cmd + Shift + 5 → Options → « Enregistrer dans » → Bureau."
echo
read -r -n 1 -p "Appuie sur une touche pour fermer…"
echo
