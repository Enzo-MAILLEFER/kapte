# Kapte

Fais une capture d'écran sur ton Mac : une petite bulle en bas à gauche de l'écran te donne la réponse (question de quiz, traduction, explication…), dans la langue de la question.

Gratuit : l'analyse est faite par Gemini (Google) avec ta propre clé gratuite.

## Installer (5 minutes)

Nécessite un Mac (macOS 13 ou plus récent).

1. **[Télécharge Kapte](https://github.com/Enzo-MAILLEFER/kapte/archive/refs/heads/main.zip)** puis ouvre le fichier zip téléchargé (il se dézippe tout seul dans Téléchargements).
2. Double-clique sur **`Installer Kapte.command`** et suis les étapes de la fenêtre :
   - créer ta clé Gemini (la page s'ouvre toute seule, il faut un compte Google) ;
   - choisir le dossier « Screenshots » pour les captures ;
   - faire une capture pour tester.

### Si macOS bloque le fichier

« Impossible d'ouvrir… développeur non identifié » :

- Va dans **Réglages Système → Confidentialité et sécurité**, descends tout en bas et clique sur **« Ouvrir quand même »** à côté de Kapte.
- Ou ouvre l'app **Terminal**, tape `bash ` (avec un espace), glisse le fichier `Installer Kapte.command` dans la fenêtre, puis appuie sur Entrée.

Si une fenêtre demande d'installer les « outils de développement », accepte, attends la fin, puis relance l'installation.

## Utiliser

- **Capture** : Cmd + Shift + 4 (zone) ou Cmd + Shift + 3 (écran entier). Trois petits points apparaissent en bas à gauche pendant l'analyse, puis la réponse.
- **Activer / mettre en pause** : clique sur l'icône 👁 en haut de l'écran (barre des menus). En pause, l'œil est barré et tes captures ne sont ni envoyées ni supprimées.
- **Garder une capture** : Kapte supprime chaque capture après l'avoir analysée. Pour en garder une, mets-le en pause, ou copie la capture dans le presse-papiers avec Cmd + Ctrl + Shift + 4.

## Désinstaller

Double-clique sur **`Desinstaller Kapte.command`** (une copie est aussi dans le dossier caché `~/.kapte`).

## Réglages (facultatif)

Dans `~/.kapte/config.json` (dans le Finder : Cmd + Shift + G, puis colle `~/.kapte`) :

| Réglage | Rôle |
|---|---|
| `display_seconds` | Durée d'affichage de la bulle, en secondes (15 par défaut) |
| `max_words` | Longueur max de la réponse |
| `extra_instructions` | Contexte en plus, ex. « Je révise l'anglais, explique-moi brièvement le mot. » |

Les changements sont pris en compte dès la capture suivante.

## Confidentialité

Chaque capture est envoyée à Google pour analyse. Avec la clé gratuite, Google peut utiliser ces données pour améliorer ses produits. Mets Kapte en pause avant de capturer quelque chose de privé (mots de passe, banque, messages perso).

## Ça ne marche pas ?

- **Rien ne s'affiche après une capture** : vérifie que tes captures arrivent bien dans le dossier `Screenshots` et pas sur le Bureau (Cmd + Shift + 5 → Options → Autre emplacement… → Screenshots).
- **L'icône 👁 a disparu** : tu as cliqué sur « Quitter ». Elle revient au prochain redémarrage, ou relance l'installation.
- **Bulle « Erreur : … »** : Gemini est surchargé ou la clé ne marche plus. Réessaie plus tard, ou supprime `~/.kapte/config.json` et relance l'installation pour remettre une clé.
- Le détail des erreurs est dans `~/.kapte/error.log`.
