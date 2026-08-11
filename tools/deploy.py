"""Copie l'addon dans le dossier AddOns du jeu.

C'est l'etape qui manquait. Le depot de developpement et le dossier de jeu sont deux
endroits differents, et rien ne les reliait : on pouvait valider, committer et croire
avoir livre, alors que le client chargeait toujours une version d'il y a trois jours.

Le deploiement REFUSE de copier si la validation echoue. Copier un fichier dont on sait
qu'il ne se charge pas remplacerait un addon qui marche par un addon casse.

Usage :
    tools\\deploy.cmd              -- detecte l'installation
    tools\\deploy.cmd D:\\WoW\\...  -- chemin AddOns explicite

Variable d'environnement reconnue : GEARPROOF_ADDON_DIR (le dossier de destination,
AddOns\\GearProof compris).
"""

from __future__ import annotations

import os
import shutil
import string
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from common import ADDON_ROOT

ADDON_NAME = "GearProof"

# Ce qui part dans le jeu. Le reste — outillage, depot Git, notes de developpement —
# n'a rien a y faire : le client lit le dossier entier a chaque demarrage.
SHIPPED_SUFFIXES = {".lua", ".toc"}
SHIPPED_EXTRA = {"README.md"}
EXCLUDED_DIRS = {".git", "tools", "__pycache__"}

# Fichiers que le JOUEUR possede, ecrits hors du depot. Le depot n'en a qu'une amorce
# vide ; un deploiement ne doit jamais l'ecraser par-dessus des donnees reelles.
USER_DATA = ["Data/Sim.lua"]

_COMMON_ROOTS = [
    "World of Warcraft",
    "Program Files (x86)/World of Warcraft",
    "Program Files/World of Warcraft",
    "Games/World of Warcraft",
    "Battle.net/World of Warcraft",
]


def find_addons_dir() -> Path | None:
    """Dossier AddOns du client Retail, ou None."""
    override = os.getenv("GEARPROOF_ADDON_DIR")
    if override:
        return Path(override).parent

    for letter in string.ascii_uppercase:
        root = Path(f"{letter}:/")
        if not root.exists():
            continue
        for suffix in _COMMON_ROOTS:
            candidate = root / suffix / "_retail_" / "Interface" / "AddOns"
            if candidate.is_dir():
                return candidate
    return None


def shipped_files() -> list[Path]:
    """Fichiers a copier, chemins relatifs a la racine du depot."""
    found = []
    for path in sorted(ADDON_ROOT.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(ADDON_ROOT)
        if any(part in EXCLUDED_DIRS for part in relative.parts):
            continue
        if path.suffix in SHIPPED_SUFFIXES or relative.as_posix() in SHIPPED_EXTRA:
            found.append(relative)
    return found


def validate() -> bool:
    """Lance la suite de verification. Un echec interdit la copie."""
    script = ADDON_ROOT / "tools" / "check_addon.cmd"
    if not script.exists():
        print("[FAIL] tools/check_addon.cmd introuvable")
        return False
    result = subprocess.run([str(script)], capture_output=True, text=True, shell=True)
    if result.returncode != 0:
        print(result.stdout)
        print("[FAIL] validation en echec — rien n'est copie")
        return False
    return True


def main() -> int:
    if not validate():
        return 1

    if len(sys.argv) > 1:
        addons = Path(sys.argv[1])
    else:
        addons = find_addons_dir()

    if not addons or not addons.is_dir():
        print("[FAIL] dossier AddOns introuvable.")
        print("       Passe-le en argument, ou definis GEARPROOF_ADDON_DIR.")
        return 2

    target = addons / ADDON_NAME
    files = shipped_files()

    # Data/Sim.lua appartient au JOUEUR : c'est son droptimizer importe, ecrit par
    # `specanalyser raidbots --to-addon`. Le depot n'en contient qu'une amorce vide, et
    # la copier par-dessus detruirait des donnees que l'addon ne sait pas reconstruire.
    # On la met de cote avant le nettoyage, et on la rend apres.
    preserved = {}
    for relative in USER_DATA:
        existing = target / relative
        if existing.is_file() and existing.stat().st_size > (ADDON_ROOT / relative).stat().st_size:
            preserved[relative] = existing.read_bytes()

    # On repart d'un dossier propre : un fichier .lua supprime du depot mais laisse dans
    # le jeu continuerait d'etre charge par le .toc... ou pire, resterait la sans etre
    # charge, a semer le doute pendant le prochain diagnostic.
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True)

    for relative in files:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ADDON_ROOT / relative, destination)

    for relative, payload in preserved.items():
        (target / relative).write_bytes(payload)
        print(f"       {relative} conserve ({len(payload)} octets, donnees du joueur)")

    # Tampon de build, ecrit APRES la copie : l'entete de la fenetre l'affiche, et
    # « je n'ai aucun changement en jeu » devient une question a laquelle le joueur
    # repond seul, en lisant. Sans lui il a fallu comparer a la main des horodatages de
    # fichiers et de SavedVariables pour decouvrir qu'un /reload avait simplement precede
    # le deploiement de quelques secondes.
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    (target / "Data" / "Build.lua").write_text(
        "-- Genere par tools\\deploy.cmd — ne pas editer.\n"
        f'GearProofBuild = "{stamp}"\n',
        encoding="utf-8", newline="\n")
    print(f"       build {stamp}")

    print(f"[ok]   {len(files)} fichiers copies")
    print(f"       vers {target}")

    legacy = addons / "SpecAnalyser"
    if legacy.is_dir():
        print()
        print("       ATTENTION : l'ancien dossier SpecAnalyser est toujours installe.")
        print("       Les deux addons se chargeront en meme temps — deux icones de")
        print("       minicarte, deux fenetres. Voir README, section Installation.")

    print()
    print("       REDEMARRE COMPLETEMENT LE CLIENT : WoW ne detecte un nouveau dossier")
    print("       d'addon qu'au demarrage, jamais sur /reload.")
    return 0


# Garde d'import : `package.py` a besoin de `shipped_files()` et rien d'autre. Sans elle,
# l'importer declencherait un deploiement complet vers le dossier de jeu.
if __name__ == "__main__":
    sys.exit(main())
