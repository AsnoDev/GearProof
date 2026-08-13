"""Rejoue le demarrage complet de l'addon sous un stub d'API STRICT.

Le test de chargement de `test_lua.py` prouve que les fichiers se compilent et s'executent.
Il ne prouve pas qu'ils appellent des methodes qui EXISTENT : le stub permissif rend une
fonction pour n'importe quelle cle. `tools/wowstrict.lua` connait les methodes de chaque
type de widget et leve sur une methode qui appartient a un autre type.

Trois regles apprises en ecrivant ce fichier, et qui expliquent pourquoi les tests
precedents ne voyaient rien :

  1. Il faut rejouer les EVENEMENTS, pas appeler les vues a la main. `ns.db` n'existe
     qu'apres ADDON_LOADED, et sans lui tout echoue pour la mauvaise raison.
  2. Il faut rafraichir DEUX FOIS. Les vues reconstruisent leur contenu depuis des pools :
     la fonction de remise a neuf d'un widget ne s'execute qu'au RECYCLAGE, donc jamais au
     premier rendu. C'est exactement la ou se cachait le bug qui a casse l'addon —
     `resetIssueCard` touchait `card.body`, un widget supprime trois commits plus tot.
  3. Il faut un equipement qui PORTE des problemes. Un audit sans correctif ne pose aucune
     carte, donc n'en recycle aucune.

Usage :
    tools\\strictload.cmd
"""

from __future__ import annotations

from common import Report, run
from luaenv import ADDON_ROOT, new_runtime

TABS = ["gear", "reco", "raid", "guild", "help"]

# Toutes les commandes du gestionnaire de `Core.lua`. Une commande qui leve est une
# fonctionnalite morte que rien d'autre ne signale.
COMMANDS = ["", "gear", "bags", "reco", "guild", "simc", "simcdiag", "droptimizer",
            "theme", "options", "help", "minimap", "lang", "weights", "alerts", "debug"]


def toc_files() -> list[str]:
    toc = (ADDON_ROOT / "GearProof.toc").read_text(encoding="utf-8")
    return [line.strip().replace("\\", "/") for line in toc.splitlines()
            if line.strip().lower().endswith(".lua")]


def first_line(error: Exception) -> str:
    lines = [line.strip() for line in str(error).splitlines() if line.strip()]
    return lines[0] if lines else str(error)


def main() -> int:
    report = Report("demarrage strict")
    files = toc_files()

    try:
        lua, ns, _ = new_runtime(files, locale=False, strict=True)
    except Exception as error:  # noqa: BLE001
        report.error("chargement", first_line(error))
        return report.finish()

    lua.globals().GEARPROOF_NS = ns

    def step(label: str, code: str) -> bool:
        try:
            lua.execute(code)
            return True
        except Exception as error:  # noqa: BLE001
            report.error(label, first_line(error))
            return False

    # Le vrai demarrage : les evenements du client, dans l'ordre.
    step("ADDON_LOADED", 'GEARPROOF_NS.events:Fire("OnEvent", "ADDON_LOADED", "GearProof")')
    if ns.db is None:
        report.error("ADDON_LOADED", "ns.db non pose — la suite ne prouverait rien")
        return report.finish()
    step("PLAYER_LOGIN", 'GEARPROOF_NS.events:Fire("OnEvent", "PLAYER_LOGIN")')

    # Un equipement qui porte des problemes, sinon aucune carte n'est posee ni recyclee.
    lua.execute("""
        GetInventoryItemLink = function(_, slot)
            if slot == 5 or slot == 1 then
                return "|cffa335ee|Hitem:212014:0:0:0:0:0:0:0:80:577:0:0:2:6652:1524:0|h[Piece]|h|r"
            end
            return nil
        end
        GetInventoryItemTexture = function() return "Interface\\\\Icons\\\\INV_Misc_QuestionMark" end
        GetInventoryItemDurability = function() return 40, 100 end
    """)
    ns.Gear.Invalidate()

    # DEUX passages sur chaque onglet. Le second est le seul qui exerce la remise a neuf
    # des pools — sans lui, ce fichier n'aurait pas trouve le bug qu'il a trouve.
    for pass_number in (1, 2):
        for tab in TABS:
            step(f"passe {pass_number} — onglet {tab}", f"GEARPROOF_NS.UI.Show('{tab}')")

    step("RefreshNow", "GEARPROOF_NS.UI.RefreshNow()")

    for command in COMMANDS:
        label = f"/gp {command}".strip()
        step(label, f'SlashCmdList.GEARPROOF("{command}")')

    # Changement de langue a chaud : il repose tous les libelles enregistres.
    step("/gp lang fr", 'SlashCmdList.GEARPROOF("lang fr")')
    step("/gp lang en", 'SlashCmdList.GEARPROOF("lang en")')

    # Habillages : chacun rejoue le registre de cadres entier.
    for skin in ("minimal", "blizzard", "dark"):
        step(f"habillage {skin}", f'GEARPROOF_NS.Theme.Set("{skin}")')

    unknown = lua.globals().GEARPROOF_STRICT_NOTES
    if unknown is not None:
        seen = set()
        for index in range(1, len(unknown) + 1):
            note = unknown[index]
            if note not in seen:
                seen.add(note)
                report.warn("stub", note)

    print(f"       {len(files)} fichiers, {len(TABS)} onglets x2, {len(COMMANDS)} commandes")
    return report.finish()


run(main)
