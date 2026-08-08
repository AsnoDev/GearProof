"""Validation syntaxique de tous les fichiers Lua, fichiers generes compris.

Aucun interpreteur Lua n'est installe : luaparser, cote Python, est le seul moyen
de savoir qu'un fichier se charge avant de le copier dans le dossier de jeu.
"""

from __future__ import annotations

from luaparser import ast

from common import Report, lua_files, run


def main() -> int:
    report = Report("syntaxe")
    count = 0

    for where, path in lua_files(include_generated=True):
        count += 1
        try:
            ast.parse(path.read_text(encoding="utf-8"))
        except Exception as exc:  # luaparser leve des types varies
            first_line = str(exc).strip().splitlines()[0] if str(exc).strip() else type(exc).__name__
            report.error(where, first_line)

    print(f"       {count} fichiers analyses")
    return report.finish()


run(main)
