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

TABS = ["gear", "reco", "talent", "items", "raid", "guild", "help"]

# Toutes les commandes du gestionnaire de `Core.lua`. Une commande qui leve est une
# fonctionnalite morte que rien d'autre ne signale.
COMMANDS = ["", "gear", "bags", "reco", "talents", "items", "guild", "simc", "simcdiag",
            "droptimizer", "theme", "options", "help", "minimap", "lang", "weights",
            "alerts", "debug"]

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

    # UNE CLE D'ONGLET INCONNUE DOIT ETRE REFUSEE.
    #
    # Elle etait acceptee en silence, et le resultat etait pire qu'une erreur : aucun hote
    # ne correspond donc aucun n'est affiche — fenetre vide — pendant que le dispatch
    # rafraichit l'Aide qu'on ne voit pas. Une faute de frappe dans une commande donnait
    # une fenetre blanche, et aucun test ne pouvait l'attraper puisque toutes les cles
    # « marchaient ». C'est exactement ce qu'une regression volontaire a revele : elle
    # n'avait rien casse.
    lua.execute("GEARPROOF_OK_TAB = GEARPROOF_NS.UI.Show('reco')")
    lua.execute("GEARPROOF_BAD_TAB = GEARPROOF_NS.UI.Show('talnet')")
    if not lua.globals().GEARPROOF_OK_TAB:
        report.error("onglets", "une cle connue est refusee")
    if lua.globals().GEARPROOF_BAD_TAB:
        report.error("onglets", "une cle inconnue est acceptee — la fenetre serait vide")

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
        GEARPROOF_NS.Meta.Trinkets = function()
            return {
                { id = 270175, slot = "Trinket0Slot", ilvl = 334, count = 22, share = 0.55,
                  name = "Voracious Heart" },
                { id = 270165, slot = "Trinket1Slot", ilvl = 321, count = 7, share = 0.35,
                  name = "Seething Core" },
                { id = 111111, slot = "Trinket0Slot", ilvl = 300, count = 3, share = 0.15,
                  name = "Provenance inconnue" },
            }
        end
    """)

    # TROIS ETATS DE PROVENANCE, et les trois comptent.
    #
    # Le journal des aventures charge son butin de facon asynchrone : « rien de classe »
    # est un etat REEL, celui de la premiere ouverture d'onglet, et il emprunte une
    # branche entierement differente — la liste non separee, avec son avertissement. Un
    # onglet ne se teste pas sur un seul jeu de donnees.
    # `Journal.ItemLevel` est override en meme temps que `ItemSource` : les deux vues
    # affichent le niveau lu au journal QUAND il existe, et retombent sur le niveau observe
    # du relevé sinon. Sans le second cas, la branche de repli — la seule qui tourne tant
    # que le journal n'a pas repondu — ne serait jamais exercee.
    SOURCES = {
        "provenances connues, niveaux connus":
            'GEARPROOF_NS.Journal.ItemSource = function(id) '
            'if id == 270175 then return "raid" end '
            'if id == 270165 then return "dungeon" end return nil end '
            'GEARPROOF_NS.Journal.ItemLevel = function(id) '
            'if id == 270175 then return 340, "raid" end '
            'if id == 270165 then return 320, "dungeon" end return nil end',
        "provenances connues, niveaux inconnus":
            'GEARPROOF_NS.Journal.ItemSource = function(id) '
            'if id == 270175 then return "raid" end '
            'if id == 270165 then return "dungeon" end return nil end '
            'GEARPROOF_NS.Journal.ItemLevel = function() return nil end',
        "que du raid":
            'GEARPROOF_NS.Journal.ItemSource = function() return "raid" end '
            'GEARPROOF_NS.Journal.ItemLevel = function() return 340, "raid" end',
        "journal muet":
            'GEARPROOF_NS.Journal.ItemSource = function() return nil end '
            'GEARPROOF_NS.Journal.ItemLevel = function() return nil end',
    }

    for label, setup in SOURCES.items():
        lua.execute(setup)
        # Les TROIS roles : la phrase des bijoux change avec le role, et une branche qui
        # ne pose rien est une branche a part entiere.
        for role in ("TANK", "HEALER", "DAMAGER"):
            lua.execute(f'GEARPROOF_NS.Spec.Role = function() return "{role}" end')
            for pass_number in (1, 2):
                for tab in ("reco", "items"):
                    step(f"{tab}, {label}, {role}, passe {pass_number}",
                         f"GEARPROOF_NS.UI.Show('{tab}')")

    # L'onglet Talents a DEUX contenus, derriere deux boutons. `UI.Show` n'en montre
    # qu'un : le defaut. C'est exactement la ou se cachait la derniere panne en date.
    for pass_number in (1, 2):
        step(f"talents, mythique+ passe {pass_number}",
             'GEARPROOF_NS.TalentView.Create(nil).modes[2]:Fire("OnClick")')
        step(f"talents, raid passe {pass_number}",
             'GEARPROOF_NS.TalentView.Create(nil).modes[1]:Fire("OnClick")')

    # L'ARBRE DE TALENTS, ET SES QUATRE ETATS.
    #
    # Sans `C_Traits`, `layoutTree` rend nil et la page retombe sur sa liste : l'onglet
    # signalerait [ok] sans qu'une seule ligne du dessin ait tourne. C'est exactement la
    # zone aveugle deja trouvee sur l'onglet Recommandations, un cran plus loin.
    #
    # Le faux arbre est minuscule mais porte les trois formes qui comptent : un noeud
    # simple, un noeud a rangs multiples, un noeud a choix. Les positions sont dans le
    # repere de plusieurs milliers d'unites que rend le client, pour exercer la mise a
    # l'echelle et pas seulement le placement.
    lua.execute("""
        Enum = Enum or {}
        Enum.TraitNodeType = { Single = 0, Tiered = 1, Selection = 2 }

        -- `visibleEdges` DOIT etre la : sans elle, la boucle qui dessine les liaisons
        -- n'a aucun tour a faire et le code des traits n'est jamais execute. Trois
        -- noeuds relies en chaine couvrent les deux cas — une liaison dont les deux
        -- bouts sont pris, et une dont un seul l'est.
        local NODES = {
            [10] = { posX = 1000, posY = 1000, maxRanks = 1, type = 0, entryIDs = { 100 },
                     ranksPurchased = 1, activeEntry = { entryID = 100, rank = 1 },
                     visibleEdges = { { targetNode = 20 } } },
            [20] = { posX = 4000, posY = 2600, maxRanks = 3, type = 1, entryIDs = { 200 },
                     ranksPurchased = 2, activeEntry = { entryID = 200, rank = 2 },
                     visibleEdges = { { targetNode = 30 } } },
            [30] = { posX = 7400, posY = 5200, maxRanks = 1, type = 2,
                     entryIDs = { 300, 301 }, ranksPurchased = 0,
                     visibleEdges = {} },
            -- DEUX ARBRES DE HEROS, dont un seul est joue. C'est la situation reelle : une
            -- spe en propose plusieurs, le build en prend un. Celui que personne ne prend
            -- ne doit pas remplir la page de noeuds eteints.
            [40] = { posX = 2000, posY = 9000, maxRanks = 1, type = 0, entryIDs = { 400 },
                     ranksPurchased = 1, activeEntry = { entryID = 400, rank = 1 },
                     subTreeID = 5, visibleEdges = { { targetNode = 41 } } },
            [41] = { posX = 2600, posY = 9600, maxRanks = 1, type = 0, entryIDs = { 410 },
                     ranksPurchased = 1, activeEntry = { entryID = 410, rank = 1 },
                     subTreeID = 5, visibleEdges = {} },
            [50] = { posX = 2000, posY = 9000, maxRanks = 1, type = 0, entryIDs = { 500 },
                     ranksPurchased = 0, subTreeID = 6, visibleEdges = {} },
            -- UN `subTreeID` DE ZERO, et c'est le piege. En Lua zero est VRAI : un test
            -- « si le noeud a un subTree » le rangerait parmi les heros. Si le client rend
            -- 0 pour un noeud ordinaire — rien ne l'interdit — l'arbre principal se
            -- viderait et la page afficherait « le client n'a pas rendu d'arbre ».
            [60] = { posX = 5600, posY = 3800, maxRanks = 1, type = 0, entryIDs = { 600 },
                     ranksPurchased = 0, subTreeID = 0, visibleEdges = {} },
            -- UN NOEUD QUE LE CLIENT NE SAIT PAS DECRIRE : sa definition ne rend rien.
            -- Il appartient a une autre specialisation de la classe. Il ne doit pas etre
            -- dessine — sinon on retrouve la grille de points d'interrogation.
            [70] = { posX = 6200, posY = 4400, maxRanks = 1, type = 0, entryIDs = { 700 },
                     ranksPurchased = 0, visibleEdges = {} },
        }

        C_ClassTalents = C_ClassTalents or {}
        C_ClassTalents.GetActiveConfigID = function() return 7 end

        C_Traits = C_Traits or {}
        C_Traits.GetConfigInfo = function() return { treeIDs = { 42 } } end
        C_Traits.GetTreeNodes = function() return { 10, 20, 30, 40, 41, 50, 60, 70 } end
        C_Traits.GetSubTreeInfo = function(_, subTreeID)
            return { name = "Heros " .. tostring(subTreeID) }
        end
        C_Traits.GetNodeInfo = function(_, nodeID) return NODES[nodeID] end
        C_Traits.GetEntryInfo = function(_, entryID) return { definitionID = entryID } end
        C_Traits.GetDefinitionInfo = function(definitionID)
            -- 700 : aucune definition. C'est ainsi que le client repond pour un noeud
            -- d'une autre specialisation.
            if definitionID == 700 then return nil end
            return { overrideName = "Talent " .. definitionID,
                     overrideIcon = "Interface\\Icons\\INV_Misc_QuestionMark" }
        end
        C_Traits.GetTreeHash = function()
            return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
        end

        -- Le relevé parle en NOEUDS ici. L'autre espace — les entrees — est couvert plus
        -- bas : c'est `Traits.Match` qui tranche, et les deux branches comptent.
        -- `import` vient de Raider.IO toute faite ; `distinct`/`sample` disent a quel
        -- point l'arbre publie fait consensus. Ni l'un ni l'autre n'existait quand le
        -- relevé venait de Warcraft Logs.
        GEARPROOF_NS.Meta.Builds = function()
            return { { nodes = { 10, 1, 20, 2, 40, 1, 41, 1 },
                       import = "CHAINE-DU-RELEVE", distinct = 17, sample = 20 } }
        end
        GEARPROOF_NS.Meta.ConsumableSample = function() return 20 end
        -- L'echantillon des GEMMES est distinct : il compte les porteurs de gemme, et les
        -- parts s'y rapportent sans totaliser cent.
        GEARPROOF_NS.Meta.GemSample = function() return 17 end
        -- PAIRE D'ARMES DONT UNE MAIN NE PORTE RIEN. `{ 0, 8689 }` apparait 17 fois dans
        -- le relevé reel : un bouclier ne prend pas d'enchantement d'arme. Zero n'est pas
        -- un identifiant, et `EnchantName(0)` ne rend rien.
        GEARPROOF_NS.Meta.WeaponPairs = function()
            return { { ids = { 0, 8689 }, count = 12, share = 0.60 },
                     { ids = { 8689, 8689 }, count = 5, share = 0.25 } }
        end

        -- HUILES : le second enchantement de l'arme. Sans elles la ligne ne rend pas, et
        -- sans `GetWeaponEnchantInfo` la branche « le joueur en a une » reste morte.
        GEARPROOF_NS.Meta.Oils = function()
            return { { id = 8052, count = 15, share = 0.75 },
                     { id = 7905, count = 3,  share = 0.15 } }
        end
        GEARPROOF_NS.Meta.OilSample = function() return 18 end
        GEARPROOF_NS.Meta.EnchantItem = function(id) return id == 8159 and 244641 or nil end
        GEARPROOF_NS.Meta.Talents = function()
            return { { id = 10, count = 20, share = 1.0 },
                     { id = 20, count = 12, share = 0.6 } }
        end
    """)
    # LES DEUX BRANCHES DE LA SECTION CONSOMMABLES, et ce n'est pas un cas limite contre un
    # cas normal : mesure sur le relevé reel des quarante specialisations, le flacon de tete
    # depasse 40 % PARTOUT, mais la rune d'augmentation de tete fait 15 % de mediane et ne
    # les depasse NULLE PART. Une categorie sur deux passe donc par « le choix est partage ».
    #
    # Les deux jeux couvrent aussi le suffixe d'adoption : « rune d'augmentation — 25 % en
    # prennent une » n'apparait que sous 90 %, donc jamais sur le flacon ni la nourriture.
    CONSUMABLES = {
        "consensus": """
            -- Deux runes de Vantus : la categorie en a une PAR BOSS, donc la tete y devance
            -- rarement de beaucoup, et c'est la que l'ecart de 10 points se joue.
            GEARPROOF_NS.Meta.Consumables = function()
                return {
                    { id = 1235111, kind = "flask", count = 19, share = 0.95,
                      name = "Flask of the Shattered Sun" },
                    { id = 1285644, kind = "food", count = 18, share = 0.90,
                      name = "Hearty Well Fed" },
                    { id = 1234969, kind = "augment", count = 14, share = 0.70,
                      name = "Ethereal Augmentation" },
                    { id = 1303187, kind = "vantus", count = 9, share = 0.45,
                      name = "Vantus Rune: Ula'tek" },
                    { id = 1303171, kind = "vantus", count = 7, share = 0.35,
                      name = "Vantus Rune: Tides" },
                }
            end
        """,
        "choix partage": """
            -- Deux flacons a 50/50 : au-dessus du plancher, mais sans ecart. Et une rune
            -- d'augmentation a 15 %, sous le plancher. Aucune ligne ne doit etre nommee.
            GEARPROOF_NS.Meta.Consumables = function()
                return {
                    { id = 1235111, kind = "flask", count = 10, share = 0.50, name = "A" },
                    { id = 1235110, kind = "flask", count = 10, share = 0.50, name = "B" },
                    { id = 1234969, kind = "augment", count = 3, share = 0.15, name = "C" },
                }
            end
        """,
    }
    for label, setup in CONSUMABLES.items():
        lua.execute(setup)
        for pass_number in (1, 2):
            step(f"consommables ({label}), passe {pass_number}",
                 "GEARPROOF_NS.UI.Show('reco')")
    # On repart du jeu qui nomme : les etapes suivantes ne testent pas les consommables et
    # doivent voir le cas le plus riche.
    lua.execute(CONSUMABLES["consensus"])

    # Chaine du client. Sans elle, la correction de l'en-tete d'infobulle ne peut pas
    # reconnaitre la ligne de niveau, donc ne tourne jamais sous test.
    GEARPROOF_BUILDS_SAME = (
        "GEARPROOF_NS.Meta.Builds = function() "
        "return { { nodes = { 10, 1, 20, 2, 40, 1, 41, 1 }, "
        "import = 'CHAINE-DU-RELEVE', distinct = 17, sample = 20 } } end"
    )
    lua.execute('ITEM_LEVEL = "Item Level %d"')
    lua.execute("GEARPROOF_META_IMPORT = GEARPROOF_NS.Meta.BuildImport")
    lua.execute("GEARPROOF_META_CONTENTS = GEARPROOF_NS.Meta.Contents")
    GEARPROOF_NS_TRAITS_RESET = "GEARPROOF_NS.Traits.Invalidate()"
    lua.execute(GEARPROOF_NS_TRAITS_RESET)

    for pass_number in (1, 2):
        for label, mode in (("raid", 1), ("mythique+", 2)):
            step(f"arbre {label}, passe {pass_number}",
                 f'GEARPROOF_NS.TalentView.Create(nil).modes[{mode}]:Fire("OnClick")')

    # L'ARBRE A-T-IL VRAIMENT ETE DESSINE ? Un [ok] ne prouve que l'absence d'erreur, et la
    # page a un repli qui, lui, ne leve jamais. On verifie la correspondance elle-meme.
    lua.execute("""
        GEARPROOF_MATCH = GEARPROOF_NS.Traits.Match({ 10, 1, 20, 2, 40, 1, 41, 1 })
        GEARPROOF_HERO = GEARPROOF_NS.Traits.SubTreeName(5)
        GEARPROOF_ENTRY = GEARPROOF_NS.Traits.Match({ 100, 1, 301, 1 })
    """)
    match = lua.globals().GEARPROOF_MATCH
    if not match or match["mode"] != "node" or int(match["matched"]) != 4:
        report.error("arbre, correspondance par noeud",
                     "le relevé en identifiants de noeud n'est pas reconnu")

    # L'AUTRE ESPACE D'IDENTIFIANTS. Une entree designe la branche PRISE sur un noeud a
    # choix, ce que l'identifiant de noeud ne dit pas : les deux se resolvent, et c'est
    # `Match` qui doit trancher, pas une supposition ecrite en dur.
    entry = lua.globals().GEARPROOF_ENTRY
    if not entry or entry["mode"] != "entry" or int(entry["matched"]) != 2:
        report.error("arbre, correspondance par entree",
                     "le relevé en identifiants d'entree n'est pas reconnu")
    elif entry["selection"][30]["entryID"] != 301:
        report.error("arbre, noeud a choix",
                     "la branche prise sur un noeud a choix n'est pas retenue")

    # L'ARBRE DE HEROS EST-IL RECONNU ? Son nom vient du client, et sans lui le bloc
    # s'afficherait sous un titre generique sans que rien ne le signale.
    if str(lua.globals().GEARPROOF_HERO) != "Heros 5":
        report.error("arbre de heros", "nom non resolu : "
                     + str(lua.globals().GEARPROOF_HERO))


    # LES SURVOLS, ET POURQUOI ILS N'ETAIENT PAS TESTES.
    #
    # Les infobulles se construisent dans un `OnEnter`. Poser le gestionnaire n'appelle
    # rien : les onglets rendaient leurs lignes, signalaient [ok], et pas une infobulle
    # n'avait jamais ete construite. C'est exactement la que vivait le dernier bug vu en
    # jeu — un objet crafte affiche « niveau 44 » avec des « Random Stat » de gabarit.
    #
    # Les vues gardent leurs lignes dans des pools prives. Le seul chemin depuis
    # l'exterieur passe par les ENFANTS du cadre de contenu, que le stub peuple maintenant
    # comme le client.
    def hover_rows(label, view_name):
        lua.execute(f"GEARPROOF_VIEW = GEARPROOF_NS.{view_name}.Create(nil)")
        view = lua.globals().GEARPROOF_VIEW
        if view is None or view["content"] is None:
            report.error(f"{label}, survol", "la vue n'expose pas son contenu")
            return
        lua.execute("GEARPROOF_ROWS = GEARPROOF_VIEW.content:Children()")
        rows = lua.globals().GEARPROOF_ROWS
        count = len(rows) if rows is not None else 0
        if count == 0:
            report.error(f"{label}, survol", "aucune ligne a survoler")
            return
        for index in range(1, count + 1):
            step(f"{label}, survol de la ligne {index}",
                 f'local row = GEARPROOF_ROWS[{index}] '
                 f'if row.GetScript and row:GetScript("OnEnter") then '
                 f'row:Fire("OnEnter") row:Fire("OnLeave") end')

    # TROIS ETATS DE LIEN, et les trois empruntent une branche differente de l'infobulle :
    # le journal repond, le joueur possede l'objet, personne n'a rien. Le troisieme est
    # celui qui pose l'avertissement « niveau du modele ».
    LINKS = {
        # Provenance CONNUE et aucun lien : c'est le seul cas ou l'avertissement
        # « niveau du modele » doit sortir.
        "journal et sacs muets, provenance connue":
            'GEARPROOF_NS.Journal.ItemLink = function() return nil end '
            'GEARPROOF_NS.Bags.OwnedLink = function() return nil end '
            'GEARPROOF_NS.Journal.ItemSource = function() return "raid" end',
        # Aucune provenance : un objet CRAFTE. Le repli sur le modele est ici le cas
        # NORMAL, et « ce n'est pas le niveau du drop » n'aurait aucun sens — il n'y a
        # pas de drop. Deux branches, et la seconde n'existait pas au premier essai.
        "journal et sacs muets, sans provenance":
            'GEARPROOF_NS.Journal.ItemLink = function() return nil end '
            'GEARPROOF_NS.Bags.OwnedLink = function() return nil end '
            'GEARPROOF_NS.Journal.ItemSource = function() return nil end',
        "le journal repond":
            'GEARPROOF_NS.Journal.ItemLink = function() return "|cffa335ee|Hitem:212014::::::::80:577::::|h[J]|h|r" end '
            'GEARPROOF_NS.Bags.OwnedLink = function() return nil end',
        "seul le sac repond":
            'GEARPROOF_NS.Journal.ItemLink = function() return nil end '
            'GEARPROOF_NS.Bags.OwnedLink = function() return "|cffa335ee|Hitem:212014::::::::80:577::::|h[S]|h|r" end',
    }
    for label, setup in LINKS.items():
        lua.execute(setup)
        lua.execute("GEARPROOF_NS.UI.Show('items')")
        hover_rows(f"objets ({label})", "ItemsView")
        lua.execute("GEARPROOF_NS.UI.Show('reco')")
        hover_rows(f"recommandations ({label})", "RecoView")

    # Les noeuds de l'arbre ont eux aussi une infobulle, et elle nomme la branche PRISE
    # sur un noeud a choix — une donnee qui n'existe que la.
    lua.execute("GEARPROOF_NS.UI.Show('talent')")
    hover_rows("talents", "TalentView")

    # L'EXPORT NE SERIALISE PLUS RIEN. La chaine vient du relevé, telle que Raider.IO la
    # publie. Il n'y a donc plus de « format non reconnu » a diagnostiquer : soit le relevé
    # porte la chaine, soit il ne la porte pas, et les deux cas se disent.
    #
    # On intercepte `Copy.Show` plutot que de se fier a l'absence d'erreur : un bouton qui
    # ne plante pas mais n'ouvre rien passerait pour bon.
    lua.execute("""
        GEARPROOF_COPIED = nil
        GEARPROOF_NS.Copy.Show = function(_, value) GEARPROOF_COPIED = value end
    """)
    lua.execute("GEARPROOF_NS.UI.Show('talent')")
    step("export de la chaine d'import",
         'GEARPROOF_NS.TalentView.Create(nil).export:Fire("OnClick")')
    if str(lua.globals().GEARPROOF_COPIED or "") != "CHAINE-DU-RELEVE":
        report.error("export", "la chaine du relevé n'est pas celle proposee a la copie : "
                     + str(lua.globals().GEARPROOF_COPIED))

    # Relevé SANS chaine : le bouton doit le dire, pas ouvrir une fenetre vide.
    lua.execute("""
        GEARPROOF_COPIED = nil
        GEARPROOF_NS.Meta.BuildImport = function() return nil end
    """)
    step("export sans chaine dans le relevé",
         'GEARPROOF_NS.TalentView.Create(nil).export:Fire("OnClick")')
    if lua.globals().GEARPROOF_COPIED is not None:
        report.error("export", "propose une copie alors que le relevé ne porte pas de chaine")
    lua.execute("GEARPROOF_NS.Meta.BuildImport = GEARPROOF_META_IMPORT")

    # L'INFOBULLE D'UN CONSOMMABLE A DEUX CHEMINS, et le second n'est pas un cas d'erreur.
    # L'objet porte le meme nom que le buff et donne la vraie infobulle ; quand il n'est pas
    # dans le cache du client, on compose la notre plutot que de rendre l'infobulle de SORT,
    # qui affiche les valeurs de base de l'aura — « hate +38 » pour un flacon qui en donne
    # des milliers.
    for label, stub in (
        ("objet en cache",
         'C_Item.GetItemInfo = function(name) return name, "|cffitem|h[" .. name .. "]|h|r" end'),
        ("objet absent du cache", "C_Item.GetItemInfo = function() return nil end"),
        ("API absente", "C_Item.GetItemInfo = nil"),
    ):
        lua.execute(stub)
        for pass_number in (1, 2):
            step(f"infobulle de consommable ({label}), passe {pass_number}",
                 "GEARPROOF_NS.UI.Show('reco')")
        hover_rows(f"consommables ({label})", "RecoView")

    # Une arme EQUIPEE, sans quoi l'audit de l'huile sort avant d'avoir rien fait : le
    # dernier etat applique par la boucle d'equipement est « aucun equipement ».
    lua.execute(STATES["equipement complet"])

    # L'HUILE DU JOUEUR, ou son absence. `GetWeaponEnchantInfo` est la SEULE facon de
    # savoir si une huile est posee en ce moment — l'infobulle de l'arme ne le dit pas, et
    # c'est le propre d'une huile d'expirer. Les deux etats sont des branches distinctes.
    for label, stub in (
        ("huile posee, la bonne",
         "GetWeaponEnchantInfo = function() return true, 600, 5, 8052 end"),
        ("huile posee, une autre",
         "GetWeaponEnchantInfo = function() return true, 600, 5, 7905 end"),
        ("aucune huile",
         "GetWeaponEnchantInfo = function() return false end"),
        ("API absente", "GetWeaponEnchantInfo = nil"),
    ):
        lua.execute(stub)
        # L'onglet EQUIPEMENT autant que Recommandations : l'audit de l'huile vit dans
        # `Gear.Scan`, et une huile absente doit compter comme une correction en attente.
        # La boucle ne montrait que Recommandations, donc l'audit ne tournait jamais.
        lua.execute("if GEARPROOF_NS.Gear.Invalidate then GEARPROOF_NS.Gear.Invalidate() end")
        for pass_number in (1, 2):
            for tab in ("reco", "gear"):
                step(f"huile d'arme ({label}), onglet {tab}, passe {pass_number}",
                     f"GEARPROOF_NS.UI.Show('{tab}')")
    lua.execute("GetWeaponEnchantInfo = function() return true, 600, 5, 8052 end")

    # L'ARBRE DESSINE DOIT SE PERIMER. `Traits.Snapshot` met en cache, et son invalidateur
    # n'avait AUCUN appelant : un point deplace laissait l'ancien arbre a l'ecran jusqu'a la
    # prochaine connexion. Un arbre perime ressemble a un arbre a jour, donc rien ne le
    # signalait — on verifie donc que la photo change vraiment, pas seulement que
    # l'evenement ne plante pas.
    lua.execute("""
        GEARPROOF_SHOT_A = GEARPROOF_NS.Traits.Snapshot()
        GEARPROOF_SHOT_B = GEARPROOF_NS.Traits.Snapshot()
    """)
    if lua.eval("GEARPROOF_SHOT_A ~= GEARPROOF_SHOT_B"):
        report.error("traits", "la photo de l'arbre n'est pas mise en cache")

    step("TRAIT_CONFIG_UPDATED",
         'GEARPROOF_NS.events:Fire("OnEvent", "TRAIT_CONFIG_UPDATED")')
    lua.execute("GEARPROOF_SHOT_C = GEARPROOF_NS.Traits.Snapshot()")
    if lua.eval("GEARPROOF_SHOT_A == GEARPROOF_SHOT_C"):
        report.error("traits", "un changement de talents ne perime pas l'arbre dessine")

    # L'ECART AVEC TON ARBRE, ET SON ABSENCE. Le personnage simule joue EXACTEMENT
    # l'arbre publie — c'est un etat valide, et c'est celui qui rend « identique ». Mais
    # tant qu'il etait le seul, ni le marquage des noeuds ni la liste des differences ne
    # tournaient : deux sections entieres jamais executees.
    DIVERGENT = (
        "GEARPROOF_NS.Meta.Builds = function() "
        # 10 absent chez eux (a rendre), 30 present chez eux et pas chez moi (a prendre),
        # 20 a un autre rang, 41 sur une autre branche que la mienne.
        "return { { nodes = { 30, 1, 20, 3, 41, 1 }, import = 'CHAINE-DU-RELEVE', "
        "distinct = 17, sample = 20 } } end"
    )
    for label, setup in (("ecart", DIVERGENT), ("identique", GEARPROOF_BUILDS_SAME)):
        lua.execute(setup)
        lua.execute(GEARPROOF_NS_TRAITS_RESET)
        for pass_number in (1, 2):
            step(f"arbre compare ({label}), passe {pass_number}",
                 "GEARPROOF_NS.UI.Show('talent')")

    # LE SELECTEUR SUIT LE RELEVE. Un seul contenu disponible : pas de selecteur, car un
    # bouton unique ne selectionne rien. Les deux etats sont des branches distinctes.
    for label, contents in (("un seul contenu", '{ "mythic" }'),
                            ("deux contenus", '{ "raid", "mythic" }')):
        lua.execute(f"GEARPROOF_NS.Meta.Contents = function() return {contents} end")
        for pass_number in (1, 2):
            step(f"selecteur de contenu ({label}), passe {pass_number}",
                 "GEARPROOF_NS.UI.Show('talent')")
    lua.execute("GEARPROOF_NS.Meta.Contents = GEARPROOF_META_CONTENTS")

    # LES QUATRE RAISONS DE NE PAS DESSINER, une par une : chacune emprunte une branche
    # differente, et chacune doit rendre la page lisible plutot que vide.
    FAILURES = {
        "sans arbre client": "C_ClassTalents.GetActiveConfigID = function() return nil end",
        "sans arbre dans le relevé":
            "GEARPROOF_NS.Meta.Builds = function() return { { distinct = 17, sample = 20 } } end",
        "identifiants inconnus":
            "GEARPROOF_NS.Meta.Builds = function() "
            "return { { distinct = 17, sample = 20, nodes = { 999, 1, 998, 1 } } } end",
    }
    for label, setup in FAILURES.items():
        lua.execute(setup)
        lua.execute(GEARPROOF_NS_TRAITS_RESET)
        for pass_number in (1, 2):
            step(f"arbre indisponible ({label}), passe {pass_number}",
                 "GEARPROOF_NS.UI.Show('talent')")

    # Un [ok] sur un ecran VIDE ne prouve rien : on verifie que la separation par
    # provenance rend DEUX listes quand le journal repond, et que l'inconnu n'est range
    # nulle part.
    lua.execute(SOURCES["provenances connues, niveaux connus"])
    # `select(1, a, b)` rend a ET b : lupa en fait un tuple de deux, et `len()` mesurait
    # le nombre de valeurs de retour au lieu du contenu de la liste. On passe donc par des
    # globales, ou chaque table reste une table.
    lua.execute("GEARPROOF_RAID, GEARPROOF_DUNGEON = GEARPROOF_NS.Meta.TrinketsBySource()")
    raid, dungeon = lua.globals().GEARPROOF_RAID, lua.globals().GEARPROOF_DUNGEON
    if len(raid) != 1 or len(dungeon) != 1:
        report.error("bijoux, provenance",
                     f"{len(raid)} en raid et {len(dungeon)} en donjon, attendu 1 et 1")

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

        -- LE DETAIL DES CORRECTIFS, sous ses TROIS etats. Sans eux, l'infobulle ne rend
        -- que l'ancien resume et tout le dispositif de detente d'index reste mort.
        --
        --   Ashaya  : spe connue du relevé  -> lignes NOMMEES, avec leur taux
        --   Morwen  : spe inconnue          -> emplacements, sans conseil invente
        --   Ysmir   : relevé d'un autre format -> AUCUNE ligne, et la raison
        GEARPROOF_ROSTER["Ashaya"].specID = 1467
        GEARPROOF_ROSTER["Ashaya"].stamp = { format = 2, generatedAt = "2026-09-13" }
        GEARPROOF_ROSTER["Ashaya"].detail = {
            { slot = 4, kind = "enchant", qty = 1 },
            { slot = 9, kind = "sockets", qty = 2 },
            { slot = 15, kind = "oil", qty = 1 },
            { slot = 6, kind = "durability", qty = 1 },
        }
        GEARPROOF_ROSTER["Morwen"].specID = 99999
        GEARPROOF_ROSTER["Morwen"].stamp = { format = 2, generatedAt = "2026-09-13" }
        GEARPROOF_ROSTER["Morwen"].detail = { { slot = 1, kind = "empty", qty = 1 } }
        GEARPROOF_ROSTER["Ysmir"].specID = 1467
        GEARPROOF_ROSTER["Ysmir"].stamp = { format = 99, generatedAt = "2030-01-01" }
        GEARPROOF_ROSTER["Ysmir"].detail = { { slot = 2, kind = "enchant", qty = 1 } }

        GEARPROOF_NS.Meta.Stamp = function()
            return { format = 2, generatedAt = "2026-09-13" }
        end
        -- Le NOMMAGE est teste ailleurs (Meta.EnchantName, scan d'infobulle) : ici on
        -- eprouve la DETENTE d'un index, donc on rend le nommage deterministe.
        GEARPROOF_NS.Meta.EnchantName = function(_, id) return "ENCH" .. tostring(id) end
        GEARPROOF_NS.Meta.GemName = function(id) return "GEM" .. tostring(id) end
        GEARPROOF_NS.Meta.For = function(specID)
            if specID ~= 1467 then return nil end
            return {
                Enchant = function() return 7991, 0.62 end,
                Gem = function() return 240983, 0.55 end,
                Oil = function() return 8052, 0.60 end,
                Sample = function() return 20 end,
            }
        end
    """)

    # L'ANNONCE SPONTANEE : elle part quand on colle un droptimizer frais, pas quand on
    # la demande. Les trois refus comptent autant que le cas passant.
    for label, setup in (
        ("partage actif", "GEARPROOF_NS.db.shareWithGuild = true"),
        ("partage coupe", "GEARPROOF_NS.db.shareWithGuild = false"),
    ):
        lua.execute(setup)
        step(f"annonce de guilde ({label})", "GEARPROOF_ANNOUNCED = GEARPROOF_NS.Guild.Announce()")
    lua.execute("GEARPROOF_NS.db.shareWithGuild = true")

    # Sans guilde, la tournee entiere sort avant d'avoir rien fait : `IsInGuild` garde
    # `Request`, `Announce` et `Headcount`, et il n'etait stubbe nulle part — le
    # denominateur ne pouvait donc jamais s'afficher sous test.
    lua.execute("IsInGuild = function() return true end")

    # LE DENOMINATEUR, sous ses trois etats. Le client ne remplit son roster de guilde que
    # sur demande : juste apres la connexion il rend ZERO, et un denominateur faux vaut
    # moins que pas de denominateur du tout.
    for label, stub in (
        ("roster connu", "GetNumGuildMembers = function() return 45, 31, 33 end"),
        ("roster pas encore arrive", "GetNumGuildMembers = function() return 0, 0, 0 end"),
        ("API absente", "GetNumGuildMembers = nil"),
    ):
        lua.execute(stub)
        for pass_number in (1, 2):
            step(f"denominateur ({label}), passe {pass_number}",
                 "GEARPROOF_NS.UI.Show('guild')")
    lua.execute("GetNumGuildMembers = function() return 45, 31, 33 end")

    # LES LIGNES DE MEMBRES SE SURVOLENT. C'est la seule facon d'atteindre l'infobulle, et
    # donc la detente des index en texte nomme — le coeur du dispositif. Sans ce survol, le
    # detail voyageait, arrivait, et n'etait jamais lu.
    lua.execute("GEARPROOF_NS.UI.Show('guild')")
    hover_rows("guilde, roster", "GuildView")

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
