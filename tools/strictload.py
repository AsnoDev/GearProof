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
        # `roster` est un local de portee fichier : on l'expose pour pouvoir peupler la
        # guilde. Sans membres, l'onglet Guilde ne rend QUE son etat vide — donc aucune
        # ligne, aucune section, aucune carte de boss, et le test ne prouve rien.
        lua, ns, locals_ = new_runtime(files, locale=False, strict=True,
                                       expose={"Guild.lua": ["roster"],
                                               "GuildView.lua": ["sectionOnClick"]})
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

    # DEUX etats d'equipement, et c'est indispensable.
    #
    # Un equipement AVEC problemes pose des cartes de correctif ; un equipement SANS
    # probleme emprunte une branche entierement differente — la carte « Rien a corriger ».
    # Cette branche-la posait `card.body` sur une carte qui n'en a plus, et n'etait
    # atteinte par aucun test tant que le personnage simule avait le moindre defaut.
    # Un onglet ne se teste pas sur un seul jeu de donnees.
    STATES = {
        "equipement incomplet": """
            GetInventoryItemLink = function(_, slot)
                if slot == 5 or slot == 1 then
                    return "|cffa335ee|Hitem:212014:0:0:0:0:0:0:0:80:577:0:0:2:6652:1524:0|h[P]|h|r"
                end
                return nil
            end
            GetInventoryItemDurability = function() return 40, 100 end
        """,
        "equipement complet": """
            GetInventoryItemLink = function()
                return "|cffa335ee|Hitem:212014:7350:0:0:0:0:0:0:80:577:0:0:2:6652:1524:0|h[P]|h|r"
            end
            GetInventoryItemDurability = function() return 100, 100 end
        """,
        "aucun equipement": """
            GetInventoryItemLink = function() return nil end
            GetInventoryItemDurability = function() return nil end
        """,
    }

    lua.execute("""
        GetInventoryItemTexture = function() return "Interface\\\\Icons\\\\INV_Misc_QuestionMark" end
        -- Des CHASSES sur les pieces : sans elles, le bloc gemmes de l'onglet
        -- Equipement sort en amont et n'est jamais rendu.
        C_Item.GetItemStats = function() return { EMPTY_SOCKET_PRISMATIC = 2 } end
    """)

    # DEUX passages par etat. Le second est le seul qui exerce la remise a neuf des pools :
    # une fonction de reset ne tourne jamais au premier rendu.
    for state, setup in STATES.items():
        lua.execute(setup)
        ns.Gear.Invalidate()
        if ns.Bags and ns.Bags.Invalidate:
            ns.Bags.Invalidate()
        for pass_number in (1, 2):
            for tab in TABS:
                step(f"{state}, passe {pass_number} — onglet {tab}",
                     f"GEARPROOF_NS.UI.Show('{tab}')")

    step("RefreshNow", "GEARPROOF_NS.UI.RefreshNow()")

    # L'onglet Guilde a DEUX ecrans et une section repliable, tous derriere des boutons.
    # `UI.Show('guild')` n'en montre qu'un : le defaut. La derniere panne en date venait
    # exactement de la : une branche jamais atteinte parce que le test ne changeait pas
    # d'etat. On pilote donc les boutons, comme le ferait un joueur.
    # Une guilde qui couvre les QUATRE rangs du tri : correctifs, aucun droptimizer,
    # droptimizer perime, rien a signaler. Sans ca, la section « rien a signaler » et son
    # repli ne sont jamais atteints.
    lua.globals().GEARPROOF_ROSTER = locals_["roster"]
    lua.execute("""
        local gains = {
            [2607] = { instance = 1273, difficulty = 15, items = {
                [212014] = { percent = 4.25, ilvl = 639 },
                [212020] = { percent = 1.10, ilvl = 626 },
            } },
            [2611] = { instance = 1273, difficulty = 15, items = {
                [212099] = { percent = 2.75, ilvl = 639 },
            } },
        }
        local people = {
            { name = "Ashaya",  spec = "Devastation", ilvl = 662, fixes = 3, sim = "abc", simAge = 2 },
            { name = "Morwen",  spec = "Fureur",      ilvl = 638, fixes = 2, sim = "",    simAge = -1 },
            { name = "Doumbra", spec = "Ombre",       ilvl = 671, fixes = 0, sim = "",    simAge = -1 },
            { name = "Ysmir",   spec = "Givre",       ilvl = 644, fixes = 0, sim = "def", simAge = 14 },
            { name = "Cora",    spec = "Restau",      ilvl = 664, fixes = 0, sim = "ghi", simAge = 1 },
            { name = "Brann",   spec = "Protection",  ilvl = 658, fixes = 0, sim = "jkl", simAge = 3 },
        }
        for _, card in ipairs(people) do
            card.encounters = { 2607, 2611 }
            card.gains = gains
            GEARPROOF_ROSTER[card.name] = card
        end
    """)

    # La fenetre Droptimizer est derriere un bouton, donc invisible d'un simple Show().
    # Ses DEUX etats — attente du lien, puis attente du fichier de donnees — sont deux
    # branches distinctes : la seconde pose une boite que la premiere cache.
    step("droptimizer, ouverture", "GEARPROOF_NS.Droptimizer.Open()")
    step("droptimizer, collage d'un lien",
         'GEARPROOF_DROP = GEARPROOF_NS.Droptimizer')
    lua.execute("""
        GEARPROOF_NS.db.droptimizer = { id = "7HV5eabh1G1pAQ8n9RS3Pc", stamp = 1 }
    """)
    step("droptimizer, etape du fichier", "GEARPROOF_NS.Droptimizer.Refresh()")
    step("droptimizer, reouverture", "GEARPROOF_NS.Droptimizer.Open()")

    lua.execute("GEARPROOF_GUILD = GEARPROOF_NS.GuildView.Create(nil)")
    for label, code in [
        ("guilde, ecran Butin", 'GEARPROOF_GUILD.modes[2]:Fire("OnClick")'),
        ("guilde, retour Roster", 'GEARPROOF_GUILD.modes[1]:Fire("OnClick")'),
        ("guilde, case de partage", 'GEARPROOF_GUILD.share:Fire("OnClick")'),
        ("guilde, infobulle de partage", 'GEARPROOF_GUILD.share:Fire("OnEnter")'),
        ("guilde, appel de guilde", 'GEARPROOF_GUILD.request:Fire("OnClick")'),
        ("guilde, export Discord", 'GEARPROOF_GUILD.export:Fire("OnClick")'),
    ]:
        step(label, code)

    # Deux passes de plus sur les deux ecrans : le recyclage des pools de CE tab.
    for pass_number in (1, 2):
        step(f"guilde, Butin passe {pass_number}", 'GEARPROOF_GUILD.modes[2]:Fire("OnClick")')
        step(f"guilde, Roster passe {pass_number}", 'GEARPROOF_GUILD.modes[1]:Fire("OnClick")')

    # Le repli de « rien a signaler » est une branche a part entiere. On appelle son
    # gestionnaire directement : les pools ne sont pas exposables (ils valent nil au
    # chargement, et `expose` capture une VALEUR, pas une reference).
    lua.globals().GEARPROOF_FOLD = locals_["sectionOnClick"]
    for label in ("deplier", "replier"):
        step(f"guilde, {label} la section", "GEARPROOF_FOLD()")

    # Un [ok] sur un ecran VIDE ne prouverait rien. On verifie la donnee que l'ecran rend,
    # et l'invariant qui fonde toute la mise en page : chaque partition somme au total.
    state = ns.Guild.RosterState()
    if state.total != 6:
        report.error("guilde, roster", f"{state.total} membre(s), attendu 6")
    gear = state.gear.withFixes + state.gear.clean
    sim = state.sim.missing + state.sim.stale + state.sim.fresh
    if gear != state.total:
        report.error("guilde, partition equipement", f"{gear} != {state.total}")
    if sim != state.total:
        report.error("guilde, partition droptimizer", f"{sim} != {state.total}")

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
