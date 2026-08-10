"""Validation syntaxique de tous les fichiers Lua, fichiers generes compris.

Aucun interpreteur Lua n'est installe : luaparser, cote Python, est le seul moyen de
savoir qu'un fichier se charge avant de le copier dans le dossier de jeu.

Mais luaparser est PLUS PERMISSIF que le vrai Lua, et sur au moins un point la
difference est fatale : il accepte un retour a la ligne litteral au milieu d'une chaine
entre guillemets. Le client, lui, refuse le fichier ENTIER — l'addon perd alors un module
complet, et l'onglet correspondant s'affiche noir sans le moindre message. C'est arrive,
et ce script a dit « ok ». D'ou le controle explicite ci-dessous.
"""

from __future__ import annotations

import re

from luaparser import ast

from common import Report, lua_files, run

# Une chaine longue `[[...]]` a le droit de couvrir plusieurs lignes. Une chaine entre
# guillemets ou apostrophes, non.
LONG_BRACKET = re.compile(r"\[=*\[")


def unterminated_string(line: str) -> bool:
    """La ligne laisse-t-elle une chaine ouverte ?"""
    if LONG_BRACKET.search(line):
        return False

    quote = None
    index = 0
    while index < len(line):
        char = line[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "-" and line.startswith("--", index):
            return False   # le reste est un commentaire
        index += 1
    return quote is not None


def main() -> int:
    report = Report("syntaxe")
    count = 0

    for where, path in lua_files(include_generated=True):
        count += 1
        text = path.read_text(encoding="utf-8")

        for number, line in enumerate(text.splitlines(), start=1):
            if unterminated_string(line):
                report.error(f"{where}:{number}",
                             "chaine non terminee — un retour a la ligne litteral dans "
                             "une chaine fait rejeter le FICHIER ENTIER par le client")

        try:
            ast.parse(text)
        except Exception as exc:  # luaparser leve des types varies
            first_line = str(exc).strip().splitlines()[0] if str(exc).strip() else type(exc).__name__
            report.error(where, first_line)

    print(f"       {count} fichiers analyses")
    return report.finish()


run(main)
