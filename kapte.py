#!/usr/bin/env python3
"""Migration Kapte v1 (Python) -> v2 (app Swift).

Ce fichier ne sert plus qu'à ça : la mise à jour de la v1 le télécharge et le lance
à la place de l'ancien script. Il installe l'app Kapte depuis la dernière release GitHub
(config.json et la pause sont conservés), puis l'ancien service est arrêté.
À supprimer (avec menubar.js, overlay.js et update.sh) quand plus personne n'a la v1.
"""
import subprocess
import time
from pathlib import Path

LOG = Path.home() / ".kapte" / "migration.log"

MIGRATE = r'''
set -u
echo "$(date '+%F %T') migration vers l'app Kapte"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --max-time 120 \
  "https://github.com/Enzo-MAILLEFER/kapte/releases/latest/download/Kapte.zip" -o "$TMP/Kapte.zip" \
  || { echo "téléchargement échoué, nouvel essai dans 5 min"; exit 1; }
ditto -x -k "$TMP/Kapte.zip" "$TMP" || { echo "archive illisible"; exit 1; }
KAPTE_UNATTENDED=1 /bin/bash "$TMP/Kapte/Installer Kapte.command"
'''

# Session séparée : l'installateur arrête ce service, la migration ne doit pas s'arrêter avec lui.
subprocess.Popen(["/bin/bash", "-c", MIGRATE], start_new_session=True,
                 stdout=LOG.open("a"), stderr=subprocess.STDOUT)
# Si la migration échoue (hors ligne…), launchd relance ce fichier après cette pause : nouvel essai.
time.sleep(300)
