"""Compare deux relevés et dit si quelque chose a bougé POUR UN JOUEUR.

La question qui a produit ce fichier : « dois-je publier une version par semaine pour que
les joueurs aient des données fiables ? »

Publier au calendrier est une mauvaise règle. Le relevé bouge beaucoup à l'ouverture d'une
saison et lors des équilibrages de classe, et presque plus au milieu d'un palier : la méta
converge, les taux d'adoption se figent. Une version hebdomadaire ferait alors télécharger
338 Ko à tout le monde pour un enchantement passé de 45 % à 47 % — un chiffre que personne
ne lit et qui ne change aucune décision.

Ce script remplace la règle par une mesure. Il ne compare PAS les fichiers octet par
octet : deux relevés diffèrent toujours, ne serait-ce que par leur date. Il compare ce
qu'un joueur VOIT et sur quoi il AGIT :

  - l'enchantement recommandé d'un emplacement (le premier par adoption) ;
  - la gemme recommandée ;
  - l'ORDRE de priorité des statistiques ;
  - la paire d'enchantements d'armes recommandée ;
  - le build le plus joué ;
  - la couverture : une spé qui apparaît ou disparaît ;
  - la rencontre d'origine, qui change au changement de raid.

Une part qui glisse de deux points n'est pas un changement. Un premier de liste qui change
en est un.

Usage :
    tools\\meta_diff.cmd <ancien.lua> <nouveau.lua>
    tools\\meta_diff.cmd --against-git HEAD~1        (contre la version livrée)
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from common import ADDON_ROOT, Report, run
from luaenv import new_runtime

REFERENCE = ADDON_ROOT / "Data" / "Meta.lua"


def load_reference(source: str) -> dict:
    """Exécute un relevé dans un Lua 5.1 neuf et rend son contenu en Python.

    On l'EXÉCUTE plutôt que de l'analyser au motif : c'est du Lua, le client le lit ainsi,
    et un parseur d'expressions régulières se tromperait sur la première table imbriquée.
    """
    lua, _, _ = new_runtime([], locale=False)
    lua.execute(source)
    table = lua.globals().GearProofMeta
    if table is None:
        raise RuntimeError("aucun GearProofMeta dans ce fichier")

    specs: dict[str, dict] = {}
    for key in table:
        if str(key).startswith("_"):
            continue
        block = table[key]
        specs[str(key)] = {
            "source": block["source"] if block["source"] is not None else "",
            "sample": block["sample"] or 0,
            "enchants": _top_by_slot(block["enchants"]),
            "gem": _first_id(block["gems"]),
            "weapons": _first_ids(block["weapons"]),
            "priority": _priority(block["stats"]),
            "build": _first_ids(block["builds"], field="differs"),
            # Deux sections de plus sur lesquelles un joueur AGIT : la recette qu'il fait
            # faire, et le bijou qu'il porte. Sans elles, ce script pouvait conclure « rien
            # n'a bouge » alors que la recette a commander avait change — exactement le
            # genre de decision qu'il est cense proteger.
            "craft": _first_id(block["crafts"]),
            "trinket": _first_id(block["trinkets"]),
            # Le build de DONJON separement : c'est une decision distincte de celle du
            # raid, et un joueur qui fait des cles la prend chaque semaine.
            "buildMythic": _first_ids(block["buildsMythic"], field="differs"),
        }
    return specs


def _top_by_slot(table) -> dict[str, int]:
    """Premier enchantement de chaque emplacement, par adoption."""
    out: dict[str, int] = {}
    if table is None:
        return out
    for slot in table:
        entries = table[slot]
        if entries is not None and len(entries) > 0:
            out[str(slot)] = int(entries[1]["id"] or 0)
    return out


def _first_id(table) -> int | None:
    if table is None or len(table) == 0:
        return None
    return int(table[1]["id"] or 0)


def _first_ids(table, field: str = "ids") -> tuple:
    if table is None or len(table) == 0:
        return ()
    entry = table[1][field]
    if entry is None:
        return ()
    return tuple(int(entry[i] or 0) for i in range(1, len(entry) + 1))


def _priority(table) -> tuple:
    """Ordre décroissant des statistiques. L'ORDRE, pas les valeurs."""
    if table is None:
        return ()
    rows = []
    for key in table:
        share = table[key]["share"]
        if share is not None:
            rows.append((str(key), float(share)))
    rows.sort(key=lambda row: -row[1])
    return tuple(name for name, _ in rows)


# Ce qui vaut la peine d'être annoncé à un joueur, et le libellé qui le dit.
FIELDS = [
    ("source", "rencontre d'origine"),
    ("enchants", "enchantement recommande"),
    ("gem", "gemme recommandee"),
    ("weapons", "paire d'armes"),
    ("priority", "ordre de priorite des stats"),
    ("build", "build le plus joue"),
    ("craft", "recette recommandee"),
    ("trinket", "bijou le plus porte"),
    ("buildMythic", "build de donjon le plus joue"),
]


def _absent_everywhere(specs: dict, field: str) -> bool:
    """Le champ est-il vide sur TOUTES les spécialisations ?"""
    return all(not block.get(field) for block in specs.values())


def compare(old: dict, new: dict) -> tuple[list[str], dict[str, list[str]], list[str]]:
    """@return (spécialisations touchées, changements par spé, champs nouveaux)

    Un champ ABSENT de tout l'ancien relevé et présent dans le nouveau est un changement
    de SCHÉMA, pas de données : `builds` a été ajouté au générateur, il apparaît donc sur
    les quarante spés d'un coup. L'annoncer comme « le build le plus joué a changé » sur
    chaque ligne serait faux — rien n'a bougé, on mesure quelque chose de neuf. Il est
    signalé une fois, à part, et exclu de la comparaison par spé.
    """
    changes: dict[str, list[str]] = {}

    added = [field for field, _ in FIELDS
             if _absent_everywhere(old, field) and not _absent_everywhere(new, field)]

    for spec in sorted(set(old) | set(new)):
        if spec not in old:
            changes[spec] = ["nouvelle specialisation"]
            continue
        if spec not in new:
            changes[spec] = ["specialisation disparue"]
            continue

        moved = []
        for field, label in FIELDS:
            if field in added:
                continue
            before, after = old[spec][field], new[spec][field]
            if field == "enchants":
                slots = sorted(set(before) | set(after))
                differing = [s for s in slots if before.get(s) != after.get(s)]
                if differing:
                    moved.append(f"{label} ({', '.join(differing)})")
            elif before != after:
                moved.append(label)
        if moved:
            changes[spec] = moved

    return sorted(changes), changes, added


def main() -> int:
    report = Report("diff du releve")
    args = sys.argv[1:]

    if not args:
        print("       usage : meta_diff.cmd <ancien.lua> <nouveau.lua>")
        print("               meta_diff.cmd --against-git <ref>")
        return 2

    if args[0] == "--against-git":
        ref = args[1] if len(args) > 1 else "HEAD"
        result = subprocess.run(
            ["git", "show", f"{ref}:Data/Meta.lua"],
            cwd=ADDON_ROOT, capture_output=True, text=True, encoding="utf-8",
        )
        if result.returncode != 0:
            report.error("git", f"impossible de lire {ref}:Data/Meta.lua")
            return report.finish()
        old_source = result.stdout
        new_source = REFERENCE.read_text(encoding="utf-8")
        left, right = f"git {ref}", "Data/Meta.lua"
    else:
        old_source = Path(args[0]).read_text(encoding="utf-8")
        new_source = Path(args[1]).read_text(encoding="utf-8")
        left, right = args[0], args[1]

    old, new = load_reference(old_source), load_reference(new_source)
    touched, changes, added = compare(old, new)

    print(f"       {left}  ->  {right}")
    print(f"       {len(old)} specialisations avant, {len(new)} apres")

    if added:
        print(f"       champ(s) NOUVEAU(X) dans le releve : {', '.join(added)}")
        print("       (changement de schema, pas de donnees — exclu de la comparaison)")

    if not touched:
        # Le cas qui justifie ce script : rien a annoncer, donc rien a publier.
        print("       AUCUN changement visible par un joueur — publication inutile")
        return report.finish()

    print(f"       {len(touched)} specialisation(s) touchee(s) sur {len(new)}")
    for spec in touched:
        print(f"         {spec:28} {', '.join(changes[spec])}")

    return report.finish()


run(main)
