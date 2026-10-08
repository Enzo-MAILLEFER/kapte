# Kapte

Fais une capture d'écran sur ton Mac : une petite bulle en bas à gauche de l'écran te donne la réponse (question de quiz, traduction, explication…), dans la langue de la question.

Gratuit : l'analyse est faite par Gemini (Google) avec ta propre clé gratuite.

## Installer (5 minutes)

Nécessite un Mac (macOS 13 ou plus récent). Rien d'autre à installer.

1. **[Télécharge Kapte](https://github.com/Enzo-MAILLEFER/kapte/releases/latest/download/Kapte.zip)** puis ouvre le fichier zip téléchargé (il se dézippe tout seul dans Téléchargements).
2. Double-clique sur **`Installer Kapte.command`** et suis les étapes de la fenêtre :
   - créer ta clé Gemini (la page s'ouvre toute seule, il faut un compte Google) ;
   - choisir le dossier « Screenshots » pour les captures ;
   - faire une capture pour tester.

Kapte s'installe dans le dossier `Applications` de ton dossier perso et démarre tout seul à chaque ouverture de session.

### Si macOS bloque le fichier

« Impossible d'ouvrir… développeur non identifié » :

- Va dans **Réglages Système → Confidentialité et sécurité**, descends tout en bas et clique sur **« Ouvrir quand même »** à côté de Kapte.
- Ou ouvre l'app **Terminal**, tape `bash ` (avec un espace), glisse le fichier `Installer Kapte.command` dans la fenêtre, puis appuie sur Entrée.

## Utiliser

- **Capture** : Cmd + Shift + 4 (zone) ou Cmd + Shift + 3 (écran entier). Trois petits points apparaissent en bas à gauche pendant l'analyse, puis la réponse.
- **La réponse est copiée** dans le presse-papiers : Cmd + V pour la coller.
- **Cacher la bulle** : appuie sur **Échap** (la touche n'est prise par Kapte que pendant que la bulle est affichée).
- **Activer / mettre en pause** : clique sur l'icône 👁 en haut de l'écran (barre des menus). En pause, l'œil est barré et tes captures ne sont ni envoyées ni supprimées.
- **Garder une capture** : Kapte supprime chaque capture après l'avoir analysée. Pour en garder une, mets-le en pause, ou copie la capture dans le presse-papiers avec Cmd + Ctrl + Shift + 4.

## Mettre à jour

Rien à faire : Kapte vérifie au démarrage puis toutes les 6 h s'il existe une nouvelle version, l'installe tout seul (jamais pendant une analyse) et te le dit avec une petite bulle. Ta clé et tes réglages sont conservés. Pour vérifier tout de suite : icône 👁 → **Rechercher les mises à jour**.

## Désinstaller

Double-clique sur **`Desinstaller Kapte.command`** (une copie est aussi dans le dossier caché `~/.kapte`).

## Réglages (facultatif)

Dans `~/.kapte/config.json` (dans le Finder : Cmd + Shift + G, puis colle `~/.kapte`) :

| Réglage | Rôle |
|---|---|
| `display_seconds` | Durée d'affichage de la bulle, en secondes (15 par défaut) |
| `max_words` | Longueur max de la réponse |
| `extra_instructions` | Contexte en plus, ex. « Je révise l'anglais, explique-moi brièvement le mot. » |
| `copy_answer` | `false` pour ne plus copier la réponse dans le presse-papiers |
| `gemini_model` / `gemini_fallback_model` | Modèle principal, et modèle de secours essayé en parallèle si le premier met plus de 5 s à répondre |

Les changements sont pris en compte dès la capture suivante.

## Confidentialité

Chaque capture est envoyée à Google pour analyse. Avec la clé gratuite, Google peut utiliser ces données pour améliorer ses produits. Mets Kapte en pause avant de capturer quelque chose de privé (mots de passe, banque, messages perso).

## Ça ne marche pas ?

- **Rien ne s'affiche après une capture** : vérifie que tes captures arrivent bien dans le dossier `Screenshots` et pas sur le Bureau (Cmd + Shift + 5 → Options → Autre emplacement… → Screenshots).
- **L'icône 👁 a disparu** : tu as cliqué sur « Quitter ». Rouvre **Kapte** (dossier Applications de ton dossier perso), ou redémarre le Mac.
- **Bulle « Erreur : … »** : Gemini est surchargé ou la clé ne marche plus. Réessaie plus tard, ou supprime `~/.kapte/config.json` et relance l'installation pour remettre une clé.
- Le détail (captures, réponses, erreurs) est dans `~/.kapte/kapte.log`.

## Pour les développeurs

L'app est en Swift (AppKit, sans dépendance), dans `App/`.

- **Compiler** : `./build.sh` → `build/Kapte.app` et `build/Kapte.zip` (Xcode requis).
- **Tester sans toucher à l'installation** : `KAPTE_DEV=1 build/Kapte.app/Contents/MacOS/Kapte` (arrête d'abord le service : `launchctl bootout gui/$(id -u)/com.kapte`).
- **Publier une version** : change le numéro dans `VERSION`, commit, puis `git tag vX.Y.Z && git push --tags`. GitHub compile l'app et crée la release ; les Kapte installés se mettent à jour tout seuls.

`kapte.py`, `overlay.js`, `menubar.js` et `update.sh` sont les restes de la v1 (Python) : ils ne servent qu'à faire migrer automatiquement les anciennes installations vers l'app.
