"""Tests des fonctions pures de l'addon, executees en Lua 5.1.

Ce qui est teste ici a un point commun : une erreur ne leve rien. Elle produit un export
SimulationCraft qui decrit un autre personnage, un conseil d'arme inverse, un message de
guilde tronque au milieu d'un nom. Aucune ne se voit a la relecture, et aucune ne se
voyait avec les verificateurs statiques, qui lisent la syntaxe sans jamais executer.

Les fixtures de chaine d'objet sont construites champ par champ (`item_string`) plutot
que recopiees : une chaine recopiee a la main est exactement le genre de donnee dont on
ne sait plus, six mois plus tard, si elle etait juste.

Usage :
    tools\\test_lua.cmd
"""

from __future__ import annotations

import sys

from common import Report, run
from luaenv import ADDON_ROOT, new_runtime


class Suite:
    """Constats de tests, meme sortie que les verificateurs statiques."""

    def __init__(self, report: Report, name: str):
        self.report = report
        self.name = name
        self.count = 0

    def equal(self, label, actual, expected):
        self.count += 1
        if actual != expected:
            self.report.error(f"{self.name}/{label}",
                              f"attendu {expected!r}, obtenu {actual!r}")

    def truthy(self, label, actual):
        self.equal(label, bool(actual), True)

    def falsy(self, label, actual):
        self.equal(label, bool(actual), False)

    def done(self):
        """Compte des cas. Pas un avertissement : rien ne cloche."""
        print(f"       {self.name}: {self.count} cas")


def lua_list(table) -> list:
    """Sequence Lua -> liste Python. `None` pour une table absente."""
    if table is None:
        return []
    return [table[i] for i in range(1, len(table) + 1)]


def item_string(item_id, enchant=0, gems=(), bonuses=(), modifiers=()):
    """Fabrique une chaine d'objet CONFORME au format documente.

    Ordre : itemID, enchantID, gem1..gem4, suffixID, uniqueID, linkLevel,
    specializationID, modifiersMask, itemContext, numBonusIDs[, bonus...],
    numModifiers[, type, valeur...]

    `numBonusIDs` tombe donc en 13e position. C'est le coeur du bug du 2026-08-03 : lu en
    14e, le compteur valait le premier identifiant de bonus.
    """
    gems = list(gems) + [0] * (4 - len(gems))
    fields = [item_id, enchant, *gems, 0, 0, 80, 577, 0, 0, len(bonuses), *bonuses]
    fields += [len(modifiers)]
    for kind, value in modifiers:
        fields += [kind, value]
    return "|cffa335ee|Hitem:" + ":".join(str(f) for f in fields) + "|h[Objet]|h|r"


# --------------------------------------------------------------------- ItemLink

def test_item_link(report: Report) -> None:
    suite = Suite(report, "ItemLink.Parse")
    _, ns, _locals = new_runtime(["ItemLink.lua"])
    parse = ns.ItemLink.Parse

    # Le cas de reference : deux gemmes, six bonus, un modificateur.
    parsed = parse(item_string(212014, enchant=7350, gems=[213743, 213482],
                               bonuses=[6652, 1524, 8767, 8781, 8781, 1],
                               modifiers=[(28, 2164)]))
    suite.equal("itemID", parsed.itemID, 212014)
    suite.equal("enchantID", parsed.enchantID, 7350)
    suite.equal("gemmes", lua_list(parsed.gems), [213743, 213482])
    suite.equal("bonus", lua_list(parsed.bonuses), [6652, 1524, 8767, 8781, 8781, 1])
    suite.equal("content_tuning", parsed.contentTuning, 2164)

    # LA regression du 2026-08-03. Si le compteur est relu en 14e position, le premier
    # bonus disparait et le bloc de modificateurs se retrouve dans la liste.
    parsed = parse(item_string(99, bonuses=[9, 6652, 1524], modifiers=[(28, 777)]))
    suite.equal("compteur en 13e (bonus)", lua_list(parsed.bonuses), [9, 6652, 1524])
    suite.equal("compteur en 13e (modif)", parsed.contentTuning, 777)

    # Aucun bonus, aucun modificateur : le compteur vaut 0 et rien ne deborde.
    parsed = parse(item_string(500))
    suite.equal("sans bonus", lua_list(parsed.bonuses), [])
    suite.equal("sans modificateur", parsed.contentTuning, None)

    # Les gemmes vides ne sont pas des gemmes.
    parsed = parse(item_string(500, gems=[213743, 0, 0, 0]))
    suite.equal("gemme unique", lua_list(parsed.gems), [213743])

    # Statistiques d'artisanat : deux identifiants, ranges ensemble.
    parsed = parse(item_string(500, modifiers=[(29, 40), (30, 49)]))
    suite.equal("crafted_stats", lua_list(parsed.craftedStats), [40, 49])

    # Palier d'artisanat : 1 a 5. Hors plage, on n'ecrit RIEN plutot que d'inventer.
    suite.equal("qualite 3", parse(item_string(500, modifiers=[(38, 3)])).craftingQuality, 3)
    suite.equal("qualite 9 refusee",
                parse(item_string(500, modifiers=[(38, 9)])).craftingQuality, None)

    # Entrees qui ne sont pas des chaines d'objet.
    suite.equal("nil", parse(None), None)
    suite.equal("texte simple", parse("pas un lien"), None)
    suite.equal("lien de sort", parse("|Hspell:12345|h[Sort]|h"), None)

    suite.done()


# ---------------------------------------------------------------------- Weights

def test_weights(report: Report) -> None:
    suite = Suite(report, "Weights.ParsePawn")
    _, ns, _locals = new_runtime(["Weights.lua"])
    parse = ns.Weights.ParsePawn

    # L'ecriture de Pawn et de Raidbots : les secondaires en `...Rating`.
    weights, name = parse(
        '( Pawn: v1: "Havoc": Agility=1, CritRating=0.81, HasteRating=0.94,'
        ' MasteryRating=0.7, Versatility=0.66 )')
    suite.equal("nom", name, "Havoc")
    suite.equal("agilite", weights.agility, 1)
    suite.equal("critique", weights.crit, 0.81)
    suite.equal("hate", weights.haste, 0.94)
    suite.equal("maitrise", weights.mastery, 0.7)
    suite.equal("polyvalence", weights.versatility, 0.66)

    # Le nom court, ecrit a la main ou venu d'une autre source. Il etait ignore en
    # SILENCE : seule `Agility` etait reconnue, et les sacs se classaient sur elle seule.
    weights, _ = parse('( Pawn: v1: "Court": Agility=1, Haste=0.94, CriticalStrike=0.81,'
                       ' Mastery=0.7 )')
    suite.equal("hate, nom court", weights.haste, 0.94)
    suite.equal("critique, nom court", weights.crit, 0.81)
    suite.equal("maitrise, nom court", weights.mastery, 0.7)

    # Sans nom entre guillemets, un defaut plutot qu'un echec.
    weights, name = parse("Intellect=1, Haste=0.5")
    suite.equal("nom par defaut", name, "Pawn")
    suite.equal("intelligence", weights.intellect, 1)

    # Une chaine sans AUCUNE statistique reconnue doit echouer, pas rendre une table
    # vide : des poids vides classeraient tous les objets a egalite, en silence.
    suite.equal("rien de reconnu", parse("( Pawn: v1: \"Vide\": Foo=1, Bar=2 )"), None)
    suite.equal("chaine vide", parse(""), None)
    suite.equal("nil", parse(None), None)

    suite.done()


# ------------------------------------------------------------------------- Meta

def test_weapon_pair(report: Report) -> None:
    suite = Suite(report, "Meta.WeaponPairAdvice")
    lua, ns, _locals = new_runtime(["Spec.lua", "Meta.lua"])

    # Releve minimal : 11 joueurs en paire mixte 7983+8041, 8 en double 8041.
    # C'est la forme reelle mesuree qui a motive l'appariement — la majorite du haut de
    # tableau porte deux enchantements DIFFERENTS.
    # Fixture calquee sur `Data/Meta.lua`, pas inventee : `_stamp.format` a la racine,
    # blocs indexes par « Classe/Spe » portant `specID`, et la table s'appelle `weapons`.
    #
    # Ma premiere version posait `format` a la racine et un `specs = { [577] = ... }` :
    # elle se chargeait sans erreur, et `block()` rendait nil pour une raison qui n'avait
    # rien a voir avec ce que le test pretendait verifier. Une fixture qui ne ressemble
    # pas au fichier reel teste le harnais, pas le code.
    lua.execute("""
        GearProofMeta = {
            _stamp = { format = 2, generatedAt = "2026-01-01", specs = 1 },
            ["DemonHunter/Havoc"] = {
                specID = 577,
                class = "DemonHunter",
                spec = "Havoc",
                sample = 20,
                weapons = {
                    { ids = { 7983, 8041 }, count = 11, share = 0.55 },
                    { ids = { 8041, 8041 }, count = 8, share = 0.40 },
                },
            },
        }
    """)
    ns.Spec.Selected = lua.eval("function() return 577 end")

    advice = ns.Meta.WeaponPairAdvice

    ok, best, mixed = advice(7983, 8041)
    suite.truthy("paire mesuree acceptee", ok)
    suite.equal("meilleure paire rendue", lua_list(best.ids), [7983, 8041])
    # 55 % de paires mixtes : c'est ce chiffre qui justifie de ne pas exiger deux fois le
    # meme enchantement.
    suite.equal("part de paires mixtes", round(mixed, 2), 0.55)

    # L'ordre des mains ne compte pas : la paire est triee avant comparaison.
    suite.truthy("paire inversee acceptee", advice(8041, 7983)[0])
    suite.truthy("paire double acceptee", advice(8041, 8041)[0])
    suite.falsy("paire absente du releve refusee", advice(1111, 2222)[0])

    # Sans releve, on ne tranche pas : `nil` veut dire « je ne sais pas », et l'appelant
    # doit pouvoir le distinguer d'un « non » — c'est ce que `auditWeaponPair` teste avec
    # `if ok == nil then return end` avant de compter un correctif.
    lua.execute("GearProofMeta = { format = 2, sample = 20, specs = {} }")
    suite.equal("sans releve, abstention", advice(7983, 8041)[0], None)

    suite.done()


# ------------------------------------------------------------------------ Guild

def test_chunk_payload(report: Report) -> None:
    suite = Suite(report, "Guild.chunkPayload")
    lua, ns, locals_ = new_runtime(["Guild.lua"], expose={"Guild.lua": ["chunkPayload"]})

    # Un decoupage errone tronque un nom de joueur au milieu, et le destinataire
    # reconstruit un message qui n'a jamais ete envoye.
    chunk = locals_["chunkPayload"]

    payload = "A" * 250
    parts = lua_list(chunk(payload, 100))
    suite.equal("aucune perte", "".join(parts), payload)
    suite.truthy("respecte le budget", all(len(p) <= 100 for p in parts))
    suite.equal("nombre de morceaux", len(parts), 3)

    # Plus court que le budget : un seul morceau, pas de decoupage inutile.
    parts = lua_list(chunk("court", 100))
    suite.equal("message court", parts, ["court"])

    # Exactement le budget : la limite est INCLUSIVE. Un `>` au lieu d'un `>=` produirait
    # ici un morceau vide en trop.
    parts = lua_list(chunk("A" * 100, 100))
    suite.equal("pile le budget", len(parts), 1)

    suite.equal("charge vide", lua_list(chunk("", 100)), [])

    suite.done()


# ------------------------------------------------------------------------- SimC

def test_simc_item_line(report: Report) -> None:
    suite = Suite(report, "SimC.itemLine")
    lua, ns, locals_ = new_runtime(["ItemLink.lua", "SimC.lua"],
                                  expose={"SimC.lua": ["itemLine"]})
    line = locals_["itemLine"]

    parsed = ns.ItemLink.Parse(item_string(212014, enchant=7350, gems=[213743],
                                           bonuses=[6652, 1524], modifiers=[(28, 2164)]))
    text = line("head", parsed)
    suite.truthy("emplacement et identifiant", text.startswith("head=,id=212014"))
    suite.truthy("enchantement", "enchant_id=7350" in text)
    suite.truthy("gemmes", "gem_id=213743" in text)
    suite.truthy("bonus joints par /", "bonus_id=6652/1524" in text)
    suite.truthy("content_tuning", "context=2164" in text or "content_tuning" in text)

    # Sans decoration : ni enchant_id=0, ni gem_id vide. SimulationCraft accepte les deux
    # mais l'export ne doit pas differer d'un export officiel sur du vide.
    text = line("head", ns.ItemLink.Parse(item_string(212014)))
    suite.falsy("pas d'enchant vide", "enchant_id" in text)
    suite.falsy("pas de gemme vide", "gem_id" in text)

    suite.equal("sans donnee", line("head", None), None)

    suite.done()


# ------------------------------------------------------- schema et purge des sims

def test_schema_migration(report: Report) -> None:
    suite = Suite(report, "Core.migrateSchema")
    lua, ns, locals_ = new_runtime(["Core.lua"], expose={"Core.lua": ["migrateSchema"]})
    migrate = locals_["migrateSchema"]

    # Base NEUVE : deja au schema courant, aucune migration ne doit tourner.
    fresh = lua.eval("{}")
    suite.equal("base neuve, 0 etape", migrate(fresh), 0)
    suite.truthy("base neuve estampillee", fresh.schema)

    # Base EXISTANTE sans numero : elle date d'avant le mecanisme, donc schema 1.
    legacy = lua.eval("{ theme = 'dark' }")
    migrate(legacy)
    suite.equal("base ancienne -> 1", legacy.schema, 1)
    suite.equal("reglage preserve", legacy.theme, "dark")

    # Base ecrite par une version PLUS RECENTE : on ne touche a rien. Deviner une
    # transformation inverse detruirait des reglages qu'on ne sait pas relire.
    future = lua.eval("{ schema = 99, theme = 'minimal' }")
    suite.equal("base future, 0 etape", migrate(future), 0)
    suite.equal("base future intacte", future.schema, 99)
    suite.equal("reglage future intact", future.theme, "minimal")

    suite.done()


def test_prune_reports(report: Report) -> None:
    suite = Suite(report, "Sim.pruneReports")
    lua, ns, locals_ = new_runtime(["Sim.lua"], expose={"Sim.lua": ["pruneReports"]})
    prune = locals_["pruneReports"]

    # Six rapports du personnage connecte : les quatre plus recents restent.
    lua.execute("""
        GEARPROOF_NS.db = { sim = {} }
        for i = 1, 6 do
            GEARPROOF_NS.db.sim["rapport" .. i] = { player = "Testeur", stamp = i, items = {} }
        end
    """)
    prune()
    kept = sorted(dict(ns.db.sim).keys())
    suite.equal("quatre gardes", len(kept), 4)
    suite.equal("les plus recents", kept, ["rapport3", "rapport4", "rapport5", "rapport6"])

    # Les rapports d'un AUTRE personnage ne sont pas purges par celui-ci : il n'a aucune
    # idee de ce que l'autre a de plus recent.
    lua.execute("""
        GEARPROOF_NS.db = { sim = {} }
        for i = 1, 6 do
            GEARPROOF_NS.db.sim["autre" .. i] = { player = "Quelquun", stamp = i, items = {} }
        end
    """)
    prune()
    suite.equal("autre personnage intact", len(dict(ns.db.sim)), 6)

    suite.done()


# ------------------------------------------- le raid en cours, et lui seul

def test_by_encounter_season(report: Report) -> None:
    """L'onglet Raid montre-t-il encore les boss d'une saison finie ?

    La situation exacte rencontree en jeu : le dossier de jeu portait un `Data/Sim.lua`
    ecrit hors du jeu la saison precedente — instances 1307/1308, sans aucune date, et
    conserve au deploiement parce que c'est la donnee du joueur. Un nouveau droptimizer
    colle ne le remplacait pas : `ByEncounter` fusionnait les deux, et le tri se faisant
    sur le GAIN, un +15,6 % de l'an dernier passait devant les boss du raid courant. La
    rencontre selectionnee etant persistante, elle restait collee sur un boss mort et
    l'onglet avait l'air de ne pas se mettre a jour. Deux symptomes, une cause.

    Le test verifie aussi le seau `-97` : la rencontre « sans boss » de Raidbots, presente
    sur le rapport reel du joueur, qui produisait une ligne de boss sans nom.
    """
    suite = Suite(report, "Sim.ByEncounter/saison")
    lua, ns, _ = new_runtime(["Spec.lua", "Sim.lua"])
    lua.globals().GEARPROOF_NS = ns
    lua.globals().GEARPROOF_TEST_TIME = 100000

    lua.execute("""
        -- Le fichier de la saison passee : AUCUNE date, comme le generateur l'ecrit.
        GearProofSim = {
            ["ancien"] = { baseline = 24059, player = "Testeur", items = {
                [249966] = { percent = 15.62, ilvl = 272, slot = "wrist",
                             encounter = 2733, instance = 1307 },
                [249326] = { percent = 4.57, ilvl = 272, slot = "wrist",
                             encounter = 2795, instance = 1308 },
            } },
        }
        -- Le collage de cette semaine : le raid en cours, avec un gain PLUS PETIT que
        -- celui de l'an dernier. C'est ce qui faisait remonter les vieux boss.
        GEARPROOF_NS.db = { sim = {
            ["7HV5eabh1G1pAQ8n9RS3Pc"] = {
                baseline = 55672, player = "Testeur", stamp = 99000, items = {
                    [268213] = { percent = 4.25, ilvl = 344, slot = "main_hand",
                                 encounter = 2883, instance = 1320 },
                    [270175] = { percent = 2.10, ilvl = 344, slot = "trinket1",
                                 encounter = 2895, instance = 1320 },
                    -- Le seau « sans rencontre » de Raidbots.
                    [271444] = { percent = 0.92, ilvl = 318, slot = "shoulder",
                                 encounter = -97, instance = 1320 },
                },
            },
        } }
    """)

    groups = ns.Sim.ByEncounter()
    suite.truthy("des groupes", groups is not None)
    seen = sorted(int(groups[i]["encounter"]) for i in range(1, len(groups) + 1))
    suite.equal("le raid en cours, et lui seul", seen, [2883, 2895])
    suite.falsy("saison precedente ecartee", 2733 in seen or 2795 in seen)
    suite.falsy("seau sans rencontre ecarte", -97 in seen)

    # La date affichee vient du rapport le plus recent, pas du fichier sans date.
    suite.equal("date du plus recent", ns.Sim.NewestStamp(), 99000)

    # `Sim.Percent` n'est PAS filtre, et c'est voulu : la question qu'elle repond est
    # « que vaut CET objet a CE niveau », qui ne depend pas du raid ou il tombe. Un objet
    # de la saison passee garde donc son chiffre dans les sacs et les infobulles.
    suite.equal("gain d'un objet ancien conserve", ns.Sim.Percent(249966, 272), 15.62)

    # SANS collage, le fichier seul reste la seule source : il ne faut pas que le filtre
    # vide l'onglet de qui n'a jamais rien colle.
    lua.execute("GEARPROOF_NS.db = { sim = {} }")
    groups = ns.Sim.ByEncounter()
    seen = sorted(int(groups[i]["encounter"]) for i in range(1, len(groups) + 1))
    suite.equal("fichier seul : rien n'est filtre", seen, [2733, 2795])

    suite.done()


# --------------------------------------------------- fraicheur du droptimizer

def test_csv_freshness(report: Report) -> None:
    """Un CSV colle SANS lien laisse-t-il quand meme une trace de fraicheur ?

    Depuis que l'adresse du fichier de donnees se devine — adresse du rapport + /data.csv,
    documente par Raidbots — le parcours par defaut ne fait plus coller de LIEN du tout.
    Or c'etait le collage du lien, et lui seul, qui posait `ns.db.droptimizer`. Un joueur
    qui suivait le parcours court importait donc ses gains correctement et se voyait
    compter « aucun droptimizer » par l'appel de guilde, sans que rien ne le signale : les
    gains, eux, s'affichaient.

    Le test tient sur l'invariant qui compte : importer des gains AVANCE la fraicheur,
    qu'un lien ait ete colle ou non.
    """
    suite = Suite(report, "Sim.ImportCSV/fraicheur")
    lua, ns, _ = new_runtime(["Sim.lua"])
    lua.globals().GEARPROOF_NS = ns
    lua.globals().GEARPROOF_TEST_TIME = 5000

    # Le format reel : une ligne sans separateur (le personnage nu, la baseline), puis
    # des profilesets zone/rencontre/difficulte/objet/ilvl/enchant/emplacement.
    # L'adresse du CSV est celle du RAPPORT plus le nom du fichier — la forme documentee
    # par Raidbots, celle que son menu « Raw Files » fabrique, et celle que l'etape 2 de la
    # fenetre dit au joueur de composer lui-meme. Les trois doivent coincider au caractere
    # pres, sinon l'interface enseigne une adresse et en affiche une autre.
    REPORT = "https://www.raidbots.com/simbot/report/7HV5eabh1G1pAQ8n9RS3Pc"
    url, ident = ns.Sim.ReportCSVURL(REPORT)
    suite.equal("adresse documentee", url, REPORT + "/data.csv")
    suite.equal("identifiant extrait", ident, "7HV5eabh1G1pAQ8n9RS3Pc")
    # Elle doit se relire elle-meme : le joueur recolle souvent l'adresse, pas le lien.
    suite.equal("stable par aller-retour", ns.Sim.ReportCSVURL(url)[0], url)
    suite.equal("identifiant seul accepte",
                ns.Sim.ReportCSVURL("7HV5eabh1G1pAQ8n9RS3Pc")[0], REPORT + "/data.csv")

    csv = "\n".join([
        "name,dps_mean,dps_min,dps_max,dps_std_dev,dps_mean_std_dev",
        "Testeur,100000.00,0,0,0,0",
        "1273/2607/raid-heroic/212014/639/0/finger1///,104250.00,0,0,0,0",
        "1273/2607/raid-heroic/212020/626/0/finger2///,101100.00,0,0,0,0",
    ])

    # 1. Collage DIRECT : aucun lien n'a jamais ete pose, `reference` est vide.
    lua.execute("GEARPROOF_NS.db = { sim = {} }")
    ok, count = ns.Sim.ImportCSV(csv, "")
    suite.equal("import accepte", ok, True)
    suite.equal("deux objets", count, 2)
    stored = ns.db.droptimizer
    suite.truthy("droptimizer pose", stored is not None)
    suite.equal("date posee", stored and stored.stamp, 5000)
    suite.falsy("aucun identifiant invente", stored and stored.id)

    # 2. Avec un lien de rapport : l'identifiant est conserve, la date avance.
    lua.execute("GEARPROOF_NS.db = { sim = {} }")
    lua.globals().GEARPROOF_TEST_TIME = 6000
    ns.Sim.ImportCSV(csv, "https://www.raidbots.com/simbot/report/7HV5eabh1G1pAQ8n9RS3Pc")
    stored = ns.db.droptimizer
    suite.equal("identifiant conserve", stored and stored.id, "7HV5eabh1G1pAQ8n9RS3Pc")
    suite.equal("date avancee", stored and stored.stamp, 6000)
    suite.truthy("rapport classe sous l'identifiant",
                 ns.db.sim["7HV5eabh1G1pAQ8n9RS3Pc"] is not None)

    suite.done()


def test_roster_freshness(report: Report) -> None:
    """La colonne DROPTIMIZER compte-t-elle une fraicheur, ou la possession d'un lien ?

    Un membre qui a colle son CSV sans jamais coller de lien n'a AUCUN identifiant a
    diffuser. Le classer « aucun droptimizer » dirait le contraire de ce qu'il vient de
    faire — et l'invariant des partitions rendait l'erreur invisible : les comptes
    sommaient toujours juste, ils comptaient simplement la mauvaise chose.
    """
    suite = Suite(report, "Guild.RosterState/fraicheur")
    lua, ns, locals_ = new_runtime(["Spec.lua", "Sim.lua", "Guild.lua"],
                                   expose={"Guild.lua": ["roster"]})
    lua.globals().GEARPROOF_NS = ns
    lua.globals().GEARPROOF_ROSTER = locals_["roster"]
    lua.execute("""
        GEARPROOF_NS.db = { sim = {} }
        local people = {
            -- CSV colle sans lien : pas d'identifiant, mais une simulation d'hier.
            { name = "Sanslien", spec = "Givre", ilvl = 660, fixes = 0, sim = "",    simAge = 1 },
            -- Lien colle il y a longtemps : identifiant present, simulation perimee.
            { name = "Vieux",    spec = "Ombre", ilvl = 660, fixes = 0, sim = "abc", simAge = 30 },
            -- Rien du tout.
            { name = "Rien",     spec = "Feu",   ilvl = 660, fixes = 0, sim = "",    simAge = -1 },
        }
        for _, card in ipairs(people) do
            card.encounters, card.gains = {}, {}
            GEARPROOF_ROSTER[card.name] = card
        end
    """)

    state = ns.Guild.RosterState()
    suite.equal("trois membres", state.total, 3)
    suite.equal("frais sans lien", state.sim.fresh, 1)
    suite.equal("perime", state.sim.stale, 1)
    suite.equal("absent", state.sim.missing, 1)
    suite.equal("partition complete",
                state.sim.fresh + state.sim.stale + state.sim.missing, state.total)

    suite.done()


# ------------------------------------------------------------ format du canal guilde

def test_guild_payload(report: Report) -> None:
    """Aller-retour de la charge utile de guilde : encodage, decoupage, reconstruction.

    C'est un FORMAT DE FIL. Deux clients de versions differentes se parlent dessus, et une
    derive silencieuse ne se voit pas : le membre disparait du tableau, ou ses chiffres
    sont faux sans que rien ne le signale.

    Il a deja derive une fois. L'instance et la difficulte n'etaient pas transmises, donc
    l'onglet Guilde interrogeait le journal des aventures sans savoir dans quel raid
    chercher : aucun lien, et l'infobulle affichait le niveau du modele d'objet — 44 sur
    une piece de raid — a cote du niveau simule, correct, de la meme ligne.
    """
    suite = Suite(report, "Guild.payload")
    lua, ns, locals_ = new_runtime(
        ["Spec.lua", "Sim.lua", "Guild.lua"], expose={"Guild.lua": ["absorb", "chunkPayload"]})
    lua.globals().GEARPROOF_NS = ns
    lua.execute("GEARPROOF_NS.db = { shareWithGuild = true, sim = {} }")

    # Deux rencontres du meme raid, en heroique.
    lua.execute("""
        GearProofSim = { r1 = { baseline = 100000, player = "Testeur", stamp = 1, items = {
            [212014] = { percent=4.25, ilvl=639, encounter=2607, instance=1273, difficulty="raid-heroic" },
            [212020] = { percent=1.10, ilvl=626, encounter=2607, instance=1273, difficulty="raid-heroic" },
            [212099] = { percent=2.75, ilvl=639, encounter=2611, instance=1273, difficulty="raid-heroic" },
        } } }
    """)

    payload = ns.Guild.SimPayload()
    suite.truthy("l'instance voyage", ".1273." in payload)
    suite.truthy("la difficulte voyage", ".15:" in payload)

    absorb = locals_["absorb"]

    # Un seul morceau : le cas courant.
    gains = absorb("Bob", 1, 1, payload)
    suite.truthy("charge utile reconstruite", gains is not None)
    if gains is not None:
        block = gains[2607]
        suite.equal("instance rendue", block.instance, 1273)
        suite.equal("difficulte rendue", block.difficulty, 15)
        suite.equal("gain d'un objet", round(block["items"][212014].percent, 2), 4.25)
        suite.equal("niveau d'un objet", block["items"][212014].ilvl, 639)

    # Decoupe en morceaux, comme sur le canal reel : le resultat doit etre identique.
    chunks = locals_["chunkPayload"](payload, 40)
    count = len(chunks)
    suite.truthy("decoupe en plusieurs morceaux", count > 1)
    for index in range(1, count + 1):
        rebuilt = absorb("Alice", index, count, chunks[index])
    suite.truthy("reconstruction apres decoupe", rebuilt is not None)
    if rebuilt is not None:
        suite.equal("instance apres decoupe", rebuilt[2607].instance, 1273)
        suite.equal("objets apres decoupe", rebuilt[2611]["items"][212099].ilvl, 639)

    # ANCIEN format, sans instance ni difficulte. Un membre reste au moins une session sur
    # sa version precedente : sa fiche doit se lire, pas disparaitre.
    old = absorb("Carol", 1, 1, "2607:212014.425.639,212020.110.626")
    suite.truthy("ancien format accepte", old is not None)
    if old is not None:
        suite.equal("ancien format, instance absente", old[2607].instance, None)
        suite.equal("ancien format, gains lus", round(old[2607]["items"][212014].percent, 2), 4.25)

    # Conversion de difficulte, dans les deux sens.
    suite.equal("heroique -> 15", ns.Sim.DifficultyID("raid-heroic"), 15)
    suite.equal("identifiant deja numerique", ns.Sim.DifficultyID(15), 15)
    suite.equal("inconnue -> mythique", ns.Sim.DifficultyID(None), 16)

    suite.done()


# ------------------------------------------------------ chargement de tout le .toc

def test_all_files_load(report: Report) -> None:
    """Chaque fichier livre se compile ET s'execute, dans l'ordre du .toc.

    C'est le test qui aurait coute le moins cher et rapporte le plus. Trois des pires
    pannes de ce depot etaient des erreurs de CHARGEMENT, pas de logique :

      - un retour a la ligne litteral dans une chaine — WoW refusait le fichier entier,
        `luaparser` l'acceptait, et l'onglet Raid est reste noir deux commits durant ;
      - un champ de table utilise avant d'etre cree ;
      - un `local` de portee fichier declare apres la fermeture qui l'ecrit.

    Un vrai `loadstring` Lua 5.1 rejette la premiere exactement comme le client. Les deux
    autres deviennent visibles des que le fichier s'execute.

    L'ordre vient du .toc, pas d'une liste tenue ici : c'est l'ordre du client, et une
    dependance posee trop tard doit echouer ici avant d'echouer en jeu.
    """
    suite = Suite(report, "chargement")

    toc = (ADDON_ROOT / "GearProof.toc").read_text(encoding="utf-8")
    files = [line.strip().replace("\\", "/") for line in toc.splitlines()
             if line.strip().lower().endswith(".lua")]

    suite.truthy("le .toc liste des fichiers", files)
    for name in files:
        suite.truthy(f"{name} existe", (ADDON_ROOT / name).is_file())

    # `locale=False` : pas de `ns.L` de complaisance. Locale.lua est dans la liste et doit
    # le fournir lui-meme, a sa place dans l'ordre — sinon on validerait un ordre de
    # chargement que le client, lui, refuserait.
    try:
        new_runtime(files, locale=False)
    except Exception as error:  # noqa: BLE001
        report.error("chargement", f"{type(error).__name__}: {error}")

    suite.done()


def main() -> int:
    report = Report("tests Lua")
    for test in (test_all_files_load,
                 test_item_link, test_weights, test_weapon_pair, test_chunk_payload,
                 test_guild_payload, test_simc_item_line, test_schema_migration,
                 test_prune_reports, test_csv_freshness, test_roster_freshness,
                 test_by_encounter_season):
        try:
            test(report)
        except Exception as error:  # noqa: BLE001 — un test qui casse est un constat
            report.error(test.__name__, f"{type(error).__name__}: {error}")
    return report.finish()


run(main)
