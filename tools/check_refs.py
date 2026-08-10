"""References croisees entre modules, et fuites de globales.

L'addon n'a pas d'interpreteur pour lui dire qu'il appelle `ns.Meta.Truc` alors que
personne ne la definit : l'erreur ne sort qu'en jeu, au moment ou le joueur clique.
Ce script fait ce travail a froid.

Trois constats :
  1. `ns.X.Y` reference sans definition nulle part. ERREUR.
  2. affectation a une globale hors liste blanche. ERREUR : une globale accidentelle
     est un conflit d'addon en puissance.
  3. fonction exposee que personne n'appelle, ni depuis un autre module ni depuis son
     propre fichier. AVERTISSEMENT : code mort, ou reste d'une fonctionnalite retiree
     sans avoir ete demontee.

Analyse lexicale, pas syntaxique : l'AST de luaparser ne porte pas de numeros de
ligne exploitables, et la grammaire n'apporte rien de plus ici. En contrepartie il
faut suivre a la main deux choses que la grammaire donnerait gratuitement — les noms
declares `local`, et la profondeur d'accolades qui distingue une affectation de
variable d'un champ de table.
"""

from __future__ import annotations

import re

from common import Report, lua_files, run

# Globales que l'addon a le droit de poser : ses SavedVariables, les tables de donnees
# generees, et les points d'entree que le client exige a portee globale.
ALLOWED_GLOBALS = {
    "GearProofDB",
    "GearProofMeta",
    "GearProofSim",
    "SLASH_GEARPROOF1",
    "SLASH_GEARPROOF2",
    "SLASH_GEARPROOF3",
}

EXPORT = re.compile(r"^\s*ns\.(\w+)\s*=\s*(\w+)\s*$", re.M)
DEFINE_ON_TABLE = re.compile(r"^\s*function\s+(\w+)[.:](\w+)\s*\(", re.M)
DEFINE_ON_NS = re.compile(r"^\s*function\s+ns\.(\w+)\s*\(", re.M)
ASSIGN_ON_TABLE = re.compile(r"^\s*(\w+)\.(\w+)\s*=\s*(?:function\b|\w)", re.M)

USE_VIA_NS = re.compile(r"\bns\.(\w+)\.(\w+)")

LOCAL_DECL = re.compile(r"^\s*local\s+(?!function\b)([\w\s,]+?)\s*(?:=|$)", re.M)
LOCAL_FUNC = re.compile(r"^\s*local\s+function\s+(\w+)", re.M)
FUNC_PARAMS = re.compile(r"function\s*[\w.:]*\s*\(([^)]*)\)")
FOR_NUM = re.compile(r"\bfor\s+(\w+)\s*=")
FOR_IN = re.compile(r"\bfor\s+([\w\s,]+?)\s+in\b")

ASSIGN = re.compile(r"^\s*([A-Za-z_]\w*)\s*=[^=]")


def strip_noise(line: str) -> str:
    """Retire commentaires et litteraux de chaine : leurs accolades ne comptent pas."""
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)
    return line.split("--", 1)[0]


def file_scope_locals(text: str) -> dict[str, int]:
    """Ligne de declaration des `local` de PORTEE FICHIER, colonne 0 uniquement.

    Sert a detecter l'usage AVANT declaration. En Lua, un `local` ne couvre que ce qui le
    suit : du code ecrit plus haut qui porte le meme nom touche une GLOBALE, presque
    toujours nil. Le piege a mordu trois fois dans ce depot — `toggleSpecMenu` appelant
    `refresh`, `GuildView.Refresh` appelant `layoutRosterRow`, et un selecteur de
    difficulte ecrivant son propre index depuis une closure ecrite plus haut.

    La colonne 0 n'est pas un detail : un `local` INDENTE vit dans une fonction ou un
    bloc, ou l'ordre lexical est celui de l'execution. Prendre aussi ces declarations
    produisait vingt faux positifs — des parametres et des variables de boucle
    parfaitement legitimes, portant un nom reutilise ailleurs dans le fichier.
    """
    lines: dict[str, int] = {}

    def note(name: str, number: int) -> None:
        name = name.strip()
        if name and name not in lines:
            lines[name] = number

    for number, line in enumerate(text.splitlines(), start=1):
        match = re.match(r"^local\s+function\s+(\w+)", line)
        if match:
            note(match.group(1), number)
            continue
        match = re.match(r"^local\s+(?!function\b)([\w\s,]+?)\s*(?:=|$)", line)
        if match:
            for part in match.group(1).split(","):
                note(part, number)
    return lines


def declared_locals(text: str) -> set[str]:
    """Tous les noms lies localement dans le fichier.

    Approximation assumee : on ignore la portee. Un nom declare `local` quelque part
    dans le fichier n'est jamais signale comme globale, meme s'il est reaffecte dans
    un autre bloc. Le faux negatif est acceptable ; le faux positif ne l'est pas — un
    verificateur bruyant est un verificateur desactive.
    """
    names: set[str] = set()

    for group in LOCAL_DECL.findall(text):
        names.update(part.strip() for part in group.split(",") if part.strip())
    names.update(LOCAL_FUNC.findall(text))
    for params in FUNC_PARAMS.findall(text):
        names.update(part.strip() for part in params.split(",") if part.strip())
    names.update(FOR_NUM.findall(text))
    for group in FOR_IN.findall(text):
        names.update(part.strip() for part in group.split(",") if part.strip())

    names.discard("")
    names.discard("...")
    return names


def main() -> int:
    report = Report("references")

    sources: dict[str, str] = {}
    exported: dict[str, tuple[str, str]] = {}   # module -> (fichier, table locale)

    for where, path in lua_files():
        text = path.read_text(encoding="utf-8")
        sources[where] = text
        for module, local_table in EXPORT.findall(text):
            exported[module] = (where, local_table)

    local_to_module = {table: module for module, (_, table) in exported.items()}

    defined: set[str] = set()
    used: dict[str, str] = {}

    for where, text in sources.items():
        for local_table, member in DEFINE_ON_TABLE.findall(text):
            module = local_to_module.get(local_table)
            if module:
                defined.add(f"{module}.{member}")
        for local_table, member in ASSIGN_ON_TABLE.findall(text):
            module = local_to_module.get(local_table)
            if module:
                defined.add(f"{module}.{member}")

        locals_here = declared_locals(text)
        declared_at = file_scope_locals(text)
        # Table locale de CE fichier : `Gear.Scan()` a l'interieur de Gear.lua est un
        # appel legitime, invisible au motif `ns.X.Y`.
        own_tables = {table for table, module in local_to_module.items()
                      if exported[module][0] == where}

        depth = 0
        for line_number, raw_line in enumerate(text.splitlines(), start=1):
            line = strip_noise(raw_line)
            opened_at_depth = depth

            for module, member in USE_VIA_NS.findall(line):
                used.setdefault(f"{module}.{member}", f"{where}:{line_number}")

            for table in own_tables:
                # La ligne de DEFINITION n'est pas un usage : sans cette exclusion,
                # `function Gear.Scan(` se comptait lui-meme et plus rien n'etait
                # jamais mort. Un APPEL `Gear.Scan()` en debut de ligne, lui, compte —
                # d'ou la distinction sur le mot-cle `function` et sur le `=`.
                if re.match(rf"^\s*function\s+{table}[.:]\w+", line):
                    continue
                if re.match(rf"^\s*{table}\.\w+\s*=", line):
                    continue
                for member in re.findall(rf"\b{table}\.(\w+)", line):
                    used.setdefault(f"{local_to_module[table]}.{member}",
                                    f"{where}:{line_number}")

            depth += line.count("{") - line.count("}")

            # Une affectation a l'interieur d'un constructeur de table est un champ,
            # pas une variable. C'est ce qui faisait passer `bgFile = ...` pour une
            # globale accidentelle.
            if opened_at_depth > 0:
                continue
            match = ASSIGN.match(line)
            if not match:
                continue
            name = match.group(1)
            if name in ALLOWED_GLOBALS:
                continue
            if name not in locals_here:
                report.error(f"{where}:{line_number}", f"globale accidentelle : {name}")
                continue
            declared = declared_at.get(name)
            if declared is not None and declared > line_number:
                report.error(
                    f"{where}:{line_number}",
                    f"{name} est ecrit ici mais declare `local` ligne {declared} — "
                    "cette affectation touche une GLOBALE",
                )

    # Champs de donnees et helpers poses directement sur `ns`, sans table de module.
    NS_DIRECT = {"db", "L", "version", "events", "handlers", "translations",
                 "LANGUAGES", "On", "Print", "Debug", "ApplyLanguage",
                 "CurrentLanguage", "Localize"}

    for reference, origin in sorted(used.items()):
        module, member = reference.split(".", 1)
        if module in NS_DIRECT:
            continue
        if module not in exported:
            report.error(origin, f"module inconnu : ns.{module}")
            continue
        if reference in defined:
            continue
        # Champ de donnees declare dans la table litterale du module
        # (`Gear.SLOTS`, `Weights.STAT_KEYS`, `Armory.WIDTH`...).
        body = sources[exported[module][0]]
        if re.search(rf"^\s*{member}\s*=", body, re.M):
            continue
        if re.search(rf"\b{exported[module][1]}\.{member}\s*=", body):
            continue
        report.error(origin, f"ns.{reference} reference mais jamais defini")

    dead = sorted(reference for reference in defined if reference not in used)
    for reference in dead:
        module = reference.split(".", 1)[0]
        report.warn(exported.get(module, ("?", ""))[0],
                    f"expose mais jamais appele : ns.{reference}")

    print(f"       {len(exported)} modules, {len(defined)} fonctions exposees, "
          f"{len(used)} references, {len(dead)} mortes")

    return report.finish()


run(main)
