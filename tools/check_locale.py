"""Coherence entre les cles de traduction et le code qui les consomme.

La cle EST le texte anglais : une cle absente retombe sur l'anglais sans trou
d'affichage. C'est une bonne propriete, mais elle rend les incoherences invisibles
en jeu — une cle mal ecrite affiche simplement la cle. D'ou ce controle.

Trois constats :
  1. cle declaree deux fois dans un meme bloc — en Lua la derniere gagne, en silence.
     `["missing"]` valait "manque" ligne 39 et "absent" ligne 125 : les cartes de
     probleme affichaient "absent" sans que personne ne l'ait demande. ERREUR.
  2. cle referencee dans le code sans entree de traduction. ERREUR : c'est le
     symptome d'une faute de frappe ou d'un encodage casse, pas d'un oubli benin.
  3. cle traduite que plus personne ne reference. AVERTISSEMENT : l'analyse
     statique ne voit pas `L[entry.label]`, d'ou la liste blanche ci-dessous.
"""

from __future__ import annotations

import collections
import re

from common import ADDON_ROOT, Report, lua_files, run

LOCALE_FILE = ADDON_ROOT / "Locale.lua"

# Une cle Lua entre crochets, guillemets doubles, echappements geres.
KEY = r'\["((?:[^"\\]|\\.)*)"\]'

# Langue de reference : celle dont on exige la couverture complete. Les autres blocs
# sont seulement controles en doublons.
REFERENCE = "fr"

# Cles construites a l'execution, invisibles a l'analyse statique.
#   L[entry.label]        -> emplacements d'equipement (Gear.SLOTS)
#   L[definition.label]   -> statistiques secondaires (Gear.STATS)
#   L[definition.hint]    -> nature de l'enchantement attendu
#   L[definition.label]   -> onglets (UI.TABS)
#   L[button.label]       -> sous-vues de l'onglet Guilde
#   L[tile.label or "?"]  -> repli d'infobulle de tuile
DYNAMIC_KEYS = {
    # Gear.SLOTS[].label
    "Head", "Neck", "Shoulders", "Cloak", "Chest", "Wrists", "Hands", "Waist",
    "Legs", "Feet", "Ring 1", "Ring 2", "Trinket 1", "Trinket 2", "Weapon", "Off hand",
    # Gear.STATS[].label
    "Haste", "Crit", "Mastery", "Versatility",
    # Gear.SLOTS[].hint
    "stat enchant", "leg armor", "weapon enchant",
    # UI.TABS[].label
    "Equipment", "Raid", "Guild", "Help",
    # GuildView sous-vues
    "Roster",
    # Options.lua : les libelles et infobulles passent par une variable
    # (`checkbox(parent, anchor, key, text, tip, ...)`), pas par un litteral.
    "Language",
    "Warn me when I enter a dungeon or raid with incomplete gear",
    "Checks enchants, sockets, empty slots and durability a few seconds after the loading screen.",
    "Add measured lines to item tooltips",
    "Simulated gain, item level against what you wear, and the enchant measured for that slot. Nothing estimated.",
    "Show the minimap icon",
    "Share my data with the guild",
    "Answer the roll call with your spec, item level, pending fixes and droptimizer id. Nothing leaves your client while this is off.",
    "Debug messages",
    # Bags.REASON_TEXT[...] : pourquoi une piece des sacs n'est pas chiffree
    "proc — sim required",
    "set piece — sim required",
    "needs a second weapon — sim required",
    "no stat weights — paste a Pawn string to rank bag items",
    # repli
    "?",
}


def blocks(source: str) -> dict[str, str]:
    """Corps de chaque `translations.<code> = { ... }`, par code de langue."""
    found = {}
    for match in re.finditer(r"translations\.(\w+)\s*=\s*\{", source):
        code = match.group(1)
        start = match.end()
        depth = 1
        index = start
        while index < len(source) and depth > 0:
            char = source[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            index += 1
        found[code] = source[start:index - 1]
    return found


def main() -> int:
    report = Report("locale")
    source = LOCALE_FILE.read_text(encoding="utf-8")
    bodies = blocks(source)

    if REFERENCE not in bodies:
        report.error("Locale.lua", f"bloc translations.{REFERENCE} introuvable")
        return report.finish()

    # 1. doublons, dans chaque langue
    for code, body in sorted(bodies.items()):
        keys = re.findall(KEY + r"\s*=", body)
        for key, count in sorted(collections.Counter(keys).items()):
            if count > 1:
                report.error(
                    f"Locale.lua [{code}]",
                    f"cle declaree {count} fois, la derniere gagne en silence : {key!r}",
                )

    reference_keys = set(re.findall(KEY + r"\s*=", bodies[REFERENCE]))

    # 2 et 3. confrontation au code
    # Deux formes de consommation :
    #   L["cle"]                        — lecture directe
    #   ns.Localize(widget, "cle", ...) — libelle pose une fois et retraduit a chaud
    LOCALIZE = r'ns\.Localize\s*\([^,]+,\s*"((?:[^"\\]|\\.)*)"'

    used: dict[str, str] = {}
    for where, path in lua_files():
        if where == "Locale.lua":
            continue
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for pattern in (r"\bL" + KEY, LOCALIZE):
                for key in re.findall(pattern, line):
                    used.setdefault(key, f"{where}:{line_number}")

    for key, origin in sorted(used.items()):
        if key not in reference_keys and key not in DYNAMIC_KEYS:
            report.error(origin, f"cle sans traduction {REFERENCE} : {key!r}")

    orphans = sorted(reference_keys - set(used) - DYNAMIC_KEYS)
    for key in orphans:
        report.warn(f"Locale.lua [{REFERENCE}]", f"cle jamais referencee : {key!r}")

    print(f"       {len(reference_keys)} cles {REFERENCE}, "
          f"{len(used)} referencees dans le code, {len(orphans)} orphelines")

    return report.finish()


run(main)
