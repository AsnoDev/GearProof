"""Fabrique le zip a deposer sur CurseForge.

Le zip CurseForge doit contenir UN dossier racine portant le nom de l'addon : le
gestionnaire extrait tel quel dans `Interface\\AddOns`. Un zip a plat installe les
fichiers en vrac et casse toutes les installations qui l'appliquent.

Ce qui n'a rien a faire dedans : l'outillage, le depot Git, les notes de developpement.
La liste des fichiers livres est CELLE DU DEPLOIEMENT — `deploy.shipped_files()`. Deux
listes divergentes finiraient par livrer autre chose que ce qu'on teste, et ce depot a
paye assez cher la duplication.

Comme le deploiement, il REFUSE de produire un zip si la validation echoue.

Usage :
    tools\\package.cmd
"""

from __future__ import annotations

import re
import subprocess
import zipfile
from pathlib import Path

from common import ADDON_ROOT, Report, run
from deploy import shipped_files

ADDON_NAME = "GearProof"
OUTPUT_DIR = ADDON_ROOT.parent / "_dist"

# Fichiers livres au joueur mais PAS au zip public : ils portent des chemins de la
# machine de developpement ou ne servent qu'a moi.
EXCLUDED_FROM_ZIP = {"CLAUDE.md"}


def version() -> str:
    """`## Version` du .toc — la seule source de verite."""
    toc = (ADDON_ROOT / f"{ADDON_NAME}.toc").read_text(encoding="utf-8")
    match = re.search(r"^##\s*Version:\s*(.+)$", toc, re.M)
    if not match:
        raise SystemExit("[FAIL] pas de ## Version dans le .toc")
    return match.group(1).strip()


def website() -> str | None:
    toc = (ADDON_ROOT / f"{ADDON_NAME}.toc").read_text(encoding="utf-8")
    match = re.search(r"^##\s*X-Website:\s*(.+)$", toc, re.M)
    return match.group(1).strip() if match else None


def validate() -> bool:
    script = ADDON_ROOT / "tools" / "check_addon.cmd"
    result = subprocess.run([str(script)], capture_output=True, text=True, shell=True)
    if result.returncode != 0:
        print(result.stdout)
        print("[FAIL] validation en echec — aucun zip produit")
        return False
    return True


def main() -> int:
    if not validate():
        return 1

    report = Report("paquet")

    # Ce qui doit exister AVANT une mise en ligne. Chaque absence est un vrai probleme,
    # pas une preference : une licence manquante interdit juridiquement la
    # redistribution par les gestionnaires d'addons.
    for name, why in [
        ("LICENSE", "sans licence, la redistribution par les gestionnaires est interdite"),
        ("CHANGELOG.md", "CurseForge affiche le changelog a chaque version"),
        ("README.md", "c'est la page de presentation"),
        ("NOTICE.md", "provenance des donnees livrees"),
    ]:
        if not (ADDON_ROOT / name).is_file():
            report.error(name, f"absent — {why}")

    site = website()
    if not site or "REMPLACER" in site:
        report.error("GearProof.toc",
                     "## X-Website n'est pas renseigne — le bouton « Signaler un bug » "
                     "fabrique un rapport sans destination")

    if report.errors:
        report.finish()
        return 2

    files = [f for f in shipped_files() if f.as_posix() not in EXCLUDED_FROM_ZIP]
    # LICENSE et CHANGELOG ne portent pas de suffixe reconnu par `shipped_files`.
    for extra in ("LICENSE", "CHANGELOG.md", "NOTICE.md"):
        path = Path(extra)
        if (ADDON_ROOT / path).is_file() and path not in files:
            files.append(path)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    archive = OUTPUT_DIR / f"{ADDON_NAME}-{version()}.zip"
    if archive.exists():
        archive.unlink()

    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zip_file:
        for relative in sorted(files, key=lambda p: p.as_posix()):
            # Le prefixe est obligatoire : un zip a plat s'extrait en vrac dans AddOns.
            zip_file.write(ADDON_ROOT / relative, f"{ADDON_NAME}/{relative.as_posix()}")

    size = archive.stat().st_size
    print(f"[ok]   {len(files)} fichiers, {size // 1024} Ko")
    print(f"       {archive}")
    print()
    print(f"       Racine du zip : {ADDON_NAME}/  — verifie avant de televerser.")
    return 0


run(main)
