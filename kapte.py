#!/usr/bin/env python3
"""Kapte : surveille tes captures d'écran sur Mac, les envoie à une IA
(Gemini par défaut) et affiche la réponse dans une petite bulle en bas à gauche.

Aucune dépendance : Python 3 (fourni avec macOS / Xcode CLT) uniquement.
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path

APP_DIR = Path.home() / ".kapte"
CONFIG_PATH = APP_DIR / "config.json"
PAUSE_FLAG = APP_DIR / "paused"    # créé/supprimé par l'icône de la barre des menus
OVERLAY_JS = Path(__file__).resolve().parent / "overlay.js"

DEFAULTS = {
    "provider": "gemini",          # "claude" (payant), "gemini" (gratuit, en ligne) ou "ollama" (gratuit, local)
    "api_key": "",                 # ou variable d'env ANTHROPIC_API_KEY (provider claude)
    "model": "claude-sonnet-5-5",
    "gemini_api_key": "",          # ou variable d'env GEMINI_API_KEY (provider gemini)
    "gemini_model": "gemini-3.5-flash-lite",
    "ollama_model": "qwen2.5vl:7b",  # plus léger : "gemma3:4b"
    "ollama_url": "http://localhost:11434",
    "display_seconds": 15,         # durée d'affichage de la bulle
    "max_words": 45,               # longueur max de la réponse
    "watch_dir": "",               # vide = dossier de captures de macOS
    "extra_instructions": "",      # ex : "Je suis développeur, parle-moi de code."
}

PROMPT = """Voici une capture d'écran de l'utilisateur.
Donne uniquement l'information utile, en tutoyant, {max_words} mots maximum,
sans markdown :
- si l'écran pose une question (quiz, exercice, formulaire…) : donne seulement la réponse ;
- sinon : seulement l'explication ou l'action utile, en une phrase.
Langue : réponds dans la langue de la question affichée, avec l'orthographe usuelle
de cette langue pour les noms propres (ex. en français : Kiev, Pékin, Londres ;
en anglais : Kyiv, Beijing, London), comme l'attendrait un quiz dans cette langue.
Pour une traduction, réponds dans la langue cible demandée (« traduis en anglais »
→ réponse en anglais). S'il n'y a pas de question, réponds en français.
Rien d'autre : pas d'introduction, pas de commentaire, pas d'encouragement,
pas de description de l'écran, pas de phrase de conclusion.
Exemples : « Framboise » · « Il manque un point-virgule ligne 12. »
{extra}"""


def load_config():
    cfg = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        try:
            cfg.update(json.loads(CONFIG_PATH.read_text()))
        except Exception as e:  # noqa: BLE001
            print(f"Config illisible ({e}), valeurs par défaut utilisées.", file=sys.stderr)
    cfg["api_key"] = cfg["api_key"] or os.environ.get("ANTHROPIC_API_KEY", "")
    cfg["gemini_api_key"] = cfg["gemini_api_key"] or os.environ.get("GEMINI_API_KEY", "")
    return cfg


def screenshot_dir(cfg):
    if cfg["watch_dir"]:
        return Path(cfg["watch_dir"]).expanduser()
    try:
        out = subprocess.run(
            ["defaults", "read", "com.apple.screencapture", "location"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        if out:
            return Path(out).expanduser()
    except Exception:  # noqa: BLE001
        pass
    return Path.home() / "Desktop"


def is_screenshot(path: Path):
    name = unicodedata.normalize("NFC", path.name).lower()
    if name.startswith("."):
        return False
    if path.suffix.lower() not in (".png", ".jpg", ".jpeg"):
        return False
    return name.startswith(("screenshot", "capture d", "captura de pantalla", "bildschirmfoto"))


def wait_until_stable(path: Path, tries=20):
    last = -1
    for _ in range(tries):
        try:
            size = path.stat().st_size
        except FileNotFoundError:
            return False
        if size > 0 and size == last:
            return True
        last = size
        time.sleep(0.3)
    return False


def show(text, seconds, blocking=True):
    """Affiche la bulle en bas à gauche (overlay.js), sinon notification macOS."""
    cmd = ["osascript", "-l", "JavaScript", str(OVERLAY_JS), text, str(seconds)]
    try:
        if blocking:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=seconds + 10)
            if r.returncode == 0:
                return None
            raise RuntimeError(r.stderr)
        return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:  # noqa: BLE001
        print(f"Overlay indisponible ({e}), notification à la place.", file=sys.stderr, flush=True)
        safe = text.replace("\\", "\\\\").replace('"', '\\"')
        subprocess.run(
            ["osascript", "-e", f'display notification "{safe}" with title "Kapte"']
        )
        return None


def prepare_image(path: Path):
    """Réduit l'image (les captures Retina sont énormes) et convertit en JPEG."""
    tmp = Path(tempfile.gettempdir()) / f"kapte_{os.getpid()}.jpg"
    subprocess.run(
        ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "80",
         "-Z", "1568", str(path), "--out", str(tmp)],
        capture_output=True, check=True,
    )
    data = base64.b64encode(tmp.read_bytes()).decode()
    tmp.unlink(missing_ok=True)
    return data


def analyze_ollama(cfg, path: Path):
    body = {
        "model": cfg["ollama_model"],
        "stream": False,
        "messages": [{
            "role": "user",
            "content": PROMPT.format(max_words=cfg["max_words"], extra=cfg["extra_instructions"]),
            "images": [prepare_image(path)],
        }],
    }
    req = urllib.request.Request(
        cfg["ollama_url"].rstrip("/") + "/api/chat",
        data=json.dumps(body).encode(),
        headers={"content-type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.load(resp)
    except urllib.error.URLError as e:
        raise RuntimeError(
            "Ollama injoignable. Lance l'app Ollama et vérifie que le modèle est installé "
            f"(ollama pull {cfg['ollama_model']})."
        ) from e
    return data["message"]["content"].strip()


def analyze_gemini(cfg, path: Path):
    body = {"contents": [{"parts": [
        {"inline_data": {"mime_type": "image/jpeg", "data": prepare_image(path)}},
        {"text": PROMPT.format(max_words=cfg["max_words"], extra=cfg["extra_instructions"])},
    ]}]}
    req = urllib.request.Request(
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{cfg['gemini_model']}:generateContent",
        data=json.dumps(body).encode(),
        headers={"content-type": "application/json", "x-goog-api-key": cfg["gemini_api_key"]},
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.load(resp)
            break
        except urllib.error.HTTPError as e:
            # 503 (surcharge) / 429 (quota minute) : temporaire, on réessaie
            if e.code in (429, 500, 503) and attempt < 3:
                time.sleep(2 * 2 ** attempt)
                continue
            raise RuntimeError(f"Gemini {e.code} : {e.read().decode()[:200]}") from e
        except (urllib.error.URLError, OSError) as e:
            # délai dépassé / réseau : on réessaie aussi
            if attempt < 3:
                time.sleep(2 * 2 ** attempt)
                continue
            raise RuntimeError(f"Gemini injoignable : {e}") from e
    parts = data["candidates"][0]["content"]["parts"]
    return "".join(p.get("text", "") for p in parts).strip()


def analyze(cfg, path: Path):
    if cfg["provider"] == "gemini":
        return analyze_gemini(cfg, path)
    if cfg["provider"] == "ollama":
        return analyze_ollama(cfg, path)
    body = {
        "model": cfg["model"],
        "max_tokens": 400,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image", "source": {
                    "type": "base64", "media_type": "image/jpeg", "data": prepare_image(path)}},
                {"type": "text", "text": PROMPT.format(
                    max_words=cfg["max_words"], extra=cfg["extra_instructions"])},
            ],
        }],
    }
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(body).encode(),
        headers={
            "content-type": "application/json",
            "x-api-key": cfg["api_key"],
            "anthropic-version": "2023-06-01",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"API {e.code} : {e.read().decode()[:200]}") from e
    return "".join(b.get("text", "") for b in data["content"] if b["type"] == "text").strip()


def main():
    cfg = load_config()
    if cfg["provider"] == "gemini" and not cfg["gemini_api_key"]:
        sys.exit("Clé Gemini manquante : mets-la dans ~/.kapte/config.json "
                 "(gemini_api_key) ou la variable GEMINI_API_KEY.")
    if cfg["provider"] == "claude" and not cfg["api_key"]:
        sys.exit("Clé API manquante : mets-la dans ~/.kapte/config.json "
                 "ou la variable ANTHROPIC_API_KEY.")
    folder = screenshot_dir(cfg)
    if not folder.is_dir():
        sys.exit(f"Dossier introuvable : {folder}")
    print(f"Kapte surveille : {folder}", flush=True)

    try:
        seen = {p for p in folder.iterdir() if is_screenshot(p)}
    except PermissionError:
        # launchd + TCC : ~/Desktop, ~/Documents, ~/Downloads sont refusés.
        # On attend au lieu de planter en boucle (KeepAlive).
        print(f"Accès refusé à {folder} (TCC). Utilise un dossier hors Desktop/Documents/"
              "Downloads, ex. ~/Screenshots, ou donne l'accès complet au disque à python3.",
              file=sys.stderr, flush=True)
        time.sleep(300)
        sys.exit(1)
    while True:
        try:
            for p in sorted(folder.iterdir(), key=lambda x: x.stat().st_mtime):
                if p in seen or not is_screenshot(p):
                    continue
                seen.add(p)
                if PAUSE_FLAG.exists():
                    continue  # en pause : ni analysée ni supprimée
                if not wait_until_stable(p):
                    continue
                print(f"Nouvelle capture : {p.name}", flush=True)
                cfg = load_config()  # relue à chaque capture : réglages pris en compte sans redémarrer
                waiting = show("--loading", 60, blocking=False)
                try:
                    text = analyze(cfg, p)
                    # Analyse réussie : la capture ne sert plus, on la supprime
                    # (en cas d'erreur on la garde pour pouvoir réessayer)
                    p.unlink(missing_ok=True)
                    seen.discard(p)
                except Exception as e:  # noqa: BLE001
                    text = f"Erreur : {e}"
                    print(text, file=sys.stderr, flush=True)
                if waiting:
                    waiting.terminate()
                show(text, cfg["display_seconds"])
        except FileNotFoundError:
            pass
        time.sleep(0.7)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
