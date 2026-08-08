"""Socle partage des verificateurs statiques de l'addon.

Aucun interpreteur Lua n'est installe sur la machine : ces scripts sont la seule
validation automatique disponible avant de copier les fichiers dans le dossier de jeu.
Ils remplacent les trois classes de bug qui ont echappe a la relecture humaine :
encodage corrompu, cles de traduction incoherentes, references mortes.
"""

from __future__ import annotations

import sys
from pathlib import Path

# La console Windows est en cp1252 par defaut : les constats parlent de caracteres
# accentues et de mojibake, ils doivent sortir lisibles, pas en points d'interrogation.
for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

ADDON_ROOT = Path(__file__).resolve().parent.parent

# Fichiers generes par l'outil Python : ils ne suivent pas les memes regles que le code
# ecrit a la main (pas de cles de traduction, pas de fonctions).
GENERATED = {"Data/Meta.lua", "Data/Sim.lua"}


def lua_files(include_generated: bool = False):
    """Fichiers Lua de l'addon, chemins relatifs a la racine, ordre stable."""
    for path in sorted(ADDON_ROOT.rglob("*.lua")):
        relative = path.relative_to(ADDON_ROOT).as_posix()
        if not include_generated and relative in GENERATED:
            continue
        yield relative, path


class Report:
    """Collecte les constats et decide du code de sortie.

    Un avertissement n'echoue pas : la detection de code mort a des faux positifs
    connus (les cles construites a l'execution, par exemple), et faire echouer sur
    un faux positif est le plus sur moyen de faire desactiver un verificateur.
    """

    def __init__(self, title: str):
        self.title = title
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")

    def finish(self) -> int:
        for line in self.warnings:
            print(f"  warn  {line}")
        for line in self.errors:
            print(f"  ERROR {line}")

        if self.errors:
            print(f"[FAIL] {self.title} — {len(self.errors)} erreur(s), "
                  f"{len(self.warnings)} avertissement(s)")
            return 1

        suffix = f" ({len(self.warnings)} avertissement(s))" if self.warnings else ""
        print(f"[ok]   {self.title}{suffix}")
        return 0


def run(main) -> None:
    sys.exit(main())
