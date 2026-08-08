"""Refuse tout fichier dont les octets ne sont pas ceux qu'on croit.

Deux chaines de GuildView.lua ont ete livrees avec un em-dash double-encode :
la cle de traduction ne matchait plus, et le fallback affichait `â€"` en jeu. Une
relecture humaine ne voit pas ca — l'editeur rend le texte correctement.

Trois controles :
  1. le fichier se decode en UTF-8 strict ;
  2. aucune sequence de double encodage (UTF-8 relu comme du Latin-1) ;
  3. aucun BOM — WoW lit l'UTF-8 sans marqueur, et un BOM en tete d'un .lua se
     retrouve dans la premiere chaine du fichier.
"""

from __future__ import annotations

import re

from common import ADDON_ROOT, Report, run

# Signature d'un double encodage : les octets UTF-8 d'un caractere non-ASCII relus
# comme du Latin-1 produisent toujours un prefixe C3 / C2 / E2-80 suivi de dechets.
# On cible les formes reellement rencontrees plutot qu'une heuristique large, pour
# ne pas rejeter un texte francais legitime.
MOJIBAKE = [
    ("â€", "em-dash / apostrophe / guillemet double-encode"),
    ("Ã©", "e-acute double-encode"),
    ("Ã¨", "e-grave double-encode"),
    ("Ã ", "a-grave double-encode"),
    ("Ãª", "e-circonflexe double-encode"),
    ("Ã§", "c-cedille double-encode"),
    ("Ã´", "o-circonflexe double-encode"),
    ("Â ", "espace insecable double-encode"),
    ("ï»¿", "BOM double-encode"),
]

TEXT_SUFFIXES = {".lua", ".toc", ".md", ".xml"}


def main() -> int:
    report = Report("encodage")

    for path in sorted(ADDON_ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
            continue
        if ".git" in path.parts:
            continue

        where = path.relative_to(ADDON_ROOT).as_posix()
        raw = path.read_bytes()

        if raw.startswith(b"\xef\xbb\xbf"):
            report.error(where, "BOM UTF-8 en tete — a retirer")

        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            report.error(where, f"non decodable en UTF-8 ({exc.reason} a l'octet {exc.start})")
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            for needle, label in MOJIBAKE:
                if needle in line:
                    column = line.index(needle) + 1
                    report.error(f"{where}:{line_number}:{column}", f"{label} : {needle!r}")

        if re.search(r"[ \t]+$", text, re.M):
            report.warn(where, "espaces en fin de ligne")

    return report.finish()


run(main)
