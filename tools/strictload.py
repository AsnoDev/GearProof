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

# Un droptimizer minimal au format reel : la ligne sans separateur est le personnage nu,
# les suivantes sont des profilesets zone/rencontre/difficulte/objet/ilvl/enchant/emplacement.
CSV_FIXTURE = "\n".join([
    "name,dps_mean,dps_min,dps_max,dps_std_dev,dps_mean_std_dev",
    "Testeur,100000.00,0,0,0,0",
    "1273/2607/raid-heroic/212014/639/0/finger1///,104250.00,0,0,0,0",
    "1273/2607/raid-heroic/212020/626/0/finger2///,101100.00,0,0,0,0",
])


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

    # UNE SPECIALISATION REELLE, ET C'EST INDISPENSABLE.
    #
    # Sans elle, `Spec.Selected()` rend nil, donc `Meta.Available()` rend faux, donc
    # l'onglet Recommandations rendait UNIQUEMENT son etat vide — « pas de releve pour
    # cette specialisation ». Toutes ses sections — builds, statistiques, enchantements,
    # gemmes — n'avaient donc jamais tourne sous test, et l'onglet signalait [ok] a chaque
    # passe. Un onglet qui affiche son message d'absence ne prouve rien du code qui affiche
    # ses donnees.
    #
    # Chasseur de demons Havoc : `UnitClass` du stub rend deja la classe 12, et cette spe
    # figure dans le releve livre.
    lua.execute("""
        UnitClass = function() return "Demon Hunter", "DEMONHUNTER", 12 end
        GetNumSpecializationsForClassID = function() return 3 end
        GetSpecializationInfoForClassID = function(_, index)
            local rows = {
                [1] = { 577, "Havoc", "", "icon", "DAMAGER" },
                [2] = { 581, "Vengeance", "", "icon", "TANK" },
                [3] = { 1456, "Devourer", "", "icon", "DAMAGER" },
            }
            local row = rows[index]
            if not row then return nil end
            return row[1], row[2], row[3], row[4], row[5]
        end
        C_SpecializationInfo = C_SpecializationInfo or {}
        C_SpecializationInfo.GetSpecialization = function() return 1 end
        GetSpecialization = C_SpecializationInfo.GetSpecialization
    """)

    # Le vrai demarrage : les evenements du client, dans l'ordre.
    step("ADDON_LOADED", 'GEARPROOF_NS.events:Fire("OnEvent", "ADDON_LOADED", "GearProof")')
    if ns.db is None:
        report.error("ADDON_LOADED", "ns.db non pose — la suite ne prouverait rien")
        return report.finish()
    step("PLAYER_LOGIN", 'GEARPROOF_NS.events:Fire("OnEvent", "PLAYER_LOGIN")')

    # L'INVARIANT qui empeche la zone aveugle de revenir. Si un jour la spe simulee ne se
    # resout plus, l'onglet Recommandations retombera sur son etat vide en silence — et
    # tout ce qui suit repassera au vert sans rien avoir teste.
    ns.Spec.Invalidate()
    if not ns.Meta.Available():
        report.error("releve", "aucun releve pour la spe simulee — "
                     "l'onglet Recommandations ne rendrait que son etat vide")

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

    # LES SECTIONS QUI DEPENDENT DU RELEVE LIVRE NE SE RENDENT PAS TOUTES SEULES.
    #
    # `Data/Meta.lua` ne porte pas encore `crafts` ni `trinkets` pour la spe simulee, et la
    # section Bijoux ne s'affiche que pour un TANK ou un SOIGNEUR. Sans forcer les deux,
    # l'onglet Recommandations rendait ses anciennes sections et signalait [ok] — un [ok]
    # sur un ecran ou le code neuf n'a jamais tourne.
    lua.execute("""
        GEARPROOF_NS.Meta.Crafts = function()
            return {
                { id = 237834, slot = "WristSlot", ilvl = 331, count = 11, share = 0.55,
                  name = "Spellbreaker's Bracers" },
                { id = 237846, slot = "MainHandSlot", ilvl = 331, count = 11, share = 0.55,
                  name = "Blood Knight's Warblade" },
            }
        end
        GEARPROOF_NS.Meta.Trinkets = function(mythicOnly)
            if mythicOnly then
                return { { id = 270165, slot = "Trinket1Slot", ilvl = 321, count = 7,
                           share = 0.35, name = "Seething Core" } }
            end
            return { { id = 270175, slot = "Trinket0Slot", ilvl = 334, count = 22,
                       share = 0.55, name = "Voracious Heart" } }
        end
    """)

    # Les TROIS roles, parce que la section Bijoux existe pour deux d'entre eux et pas pour
    # le troisieme : une branche qui ne pose rien est une branche a part entiere.
    for role in ("TANK", "HEALER", "DAMAGER"):
        lua.execute(f'GEARPROOF_NS.Spec.Role = function() return "{role}" end')
        for pass_number in (1, 2):
            step(f"recommandations {role}, passe {pass_number}",
                 "GEARPROOF_NS.UI.Show('reco')")

    # L'ecran doit DIRE quelque chose, pas seulement ne pas lever.
    shown = lua.eval("GEARPROOF_NS.RecoView ~= nil")
    if not shown:
        report.error("recommandations", "la vue n'existe pas")

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
    # Ses DEUX branches se PILOTENT, elles ne se posent pas a la main : poser
    # `db.droptimizer` puis appeler `Refresh()` prouvait que la mise en page tenait, pas
    # que le bouton y menait. C'est exactement ce qui a laisse passer un `Submit` qui
    # fermait la fenetre au lieu de montrer l'etape suivante. Le cadre nomme est une
    # globale, comme dans le client, donc sa zone de saisie est atteignable.
    step("droptimizer, ouverture", "GEARPROOF_NS.Droptimizer.Open()")

    # PARCOURS PAR DEFAUT : le joueur revient de Raidbots avec le CSV, sans avoir jamais
    # colle de lien. L'adresse du fichier se devine, donc plus rien ne l'oblige a revenir.
    lua.globals().GEARPROOF_CSV = CSV_FIXTURE
    step("droptimizer, collage direct du CSV", """
        GearProofDroptimizer.input:SetText(GEARPROOF_CSV)
        GearProofDroptimizer.submit:Fire("OnClick")
    """)
    if not (ns.db.droptimizer and ns.db.droptimizer.stamp):
        report.error("droptimizer, fraicheur",
                     "un CSV importe sans lien ne laisse aucune date")

    # REPLI : le joueur colle un LIEN. La fenetre passe alors a l'etape de l'adresse, une
    # branche qui pose une boite que la premiere cache.
    step("droptimizer, reouverture", "GEARPROOF_NS.Droptimizer.Open()")
    step("droptimizer, collage d'un lien", """
        GearProofDroptimizer.input:SetText(
            "https://www.raidbots.com/simbot/report/7HV5eabh1G1pAQ8n9RS3Pc")
        GearProofDroptimizer.submit:Fire("OnClick")
    """)

    # Un [ok] ne prouve que l'absence d'erreur. Ce qu'on veut savoir est si la fenetre
    # AFFICHE l'adresse du fichier apres un lien : la panne precedente ne levait rien, elle
    # fermait simplement la fenetre sans jamais montrer cette etape.
    shown = lua.eval("GearProofDroptimizer.csvUrl:GetText()") or ""
    if "data.csv" not in shown:
        report.error("droptimizer, etape du fichier",
                     f"apres un lien, l'adresse n'est pas affichee ({shown!r})")

    step("droptimizer, reouverture apres lien", "GEARPROOF_NS.Droptimizer.Open()")

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
