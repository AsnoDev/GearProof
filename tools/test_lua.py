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


# ------------------------------------------------ serialisation des talents

def test_traits_stream(report: Report) -> None:
    """Le flux de bits d'une chaine d'import, teste sans le client.

    UNE CHAINE FAUSSE EST PIRE QUE PAS DE CHAINE : le joueur collerait un arbre qui n'est
    pas celui qu'il a regarde, et rien ne le lui dirait. Le format de Blizzard ne peut se
    verifier qu'en jeu — `Traits.SelfCheck` compare notre sortie a celle que le client
    produit — mais l'ecriture des bits, elle, est du code pur et se teste ici.

    On relit avec un decodeur INDEPENDANT, ecrit d'apres la description du format, et non
    avec le meme code lu a l'envers : deux implementations qui partagent un bug ne le
    montrent jamais.
    """
    suite = Suite(report, "Traits.stream")
    lua, ns, locals_ = new_runtime(
        ["Spec.lua", "Traits.lua"],
        expose={"Traits.lua": ["BASE64", "addValue", "encode", "serialize"]})

    alphabet = str(locals_["BASE64"])
    add, encode, serialize = locals_["addValue"], locals_["encode"], locals_["serialize"]

    def decode(text):
        """Chaque caractere porte SIX bits, du moins significatif au plus significatif."""
        bits = []
        for char in text:
            value = alphabet.index(char)
            for offset in range(6):
                bits.append((value >> offset) & 1)
        return bits

    def read(bits, start, width):
        return sum(bits[start + i] << i for i in range(width))

    # Un octet seul : 0xB5 = 1011 0101, ecrit du bit de poids faible au bit de poids fort.
    stream = lua.eval("{ bits = {} }")
    add(stream, 0xB5, 8)
    suite.equal("octet ecrit poids faible en tete",
                decode(str(encode(stream)))[:8], [1, 0, 1, 0, 1, 1, 0, 1])

    # Trois valeurs de largeurs differentes, relues dans l'ordre.
    stream = lua.eval("{ bits = {} }")
    add(stream, 2, 8)
    add(stream, 250, 16)
    add(stream, 1, 1)
    bits = decode(str(encode(stream)))
    suite.equal("version relue", read(bits, 0, 8), 2)
    suite.equal("specID relu", read(bits, 8, 16), 250)
    suite.equal("bit suivant", read(bits, 24, 1), 1)
    # 25 bits tiennent sur cinq caracteres de six bits : le remplissage n'ajoute rien de
    # significatif, il complete le dernier caractere.
    suite.equal("longueur en caracteres", len(str(encode(stream))), 5)

    # LA SERIALISATION COMPLETE, sur un arbre fabrique : un noeud simple monte a fond, un
    # noeud partiellement monte, un noeud a choix dont on prend la seconde option.
    lua.execute("""
        Enum = Enum or {}
        Enum.TraitNodeType = { Single = 0, Tiered = 1, Selection = 2 }
        C_Traits = C_Traits or {}
        C_Traits.GetTreeHash = function()
            return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
        end
        GEARPROOF_SHOT = {
            treeID = 1,
            order = { 10, 20, 30 },
            nodes = {
                [10] = { id = 10, maxRanks = 1, type = 0, entryIDs = { 100 } },
                [20] = { id = 20, maxRanks = 3, type = 1, entryIDs = { 200 } },
                [30] = { id = 30, maxRanks = 1, type = 2, entryIDs = { 300, 301 } },
            },
        }
        GEARPROOF_PICK = {
            [10] = { rank = 1 },
            [20] = { rank = 2 },
            [30] = { rank = 1, entryID = 301 },
        }
        GEARPROOF_READER = function(nodeID)
            local picked = GEARPROOF_PICK[nodeID]
            if not picked then return 0 end
            return picked.rank, picked.entryID
        end
        GEARPROOF_EMPTY = function() return 0 end
    """)

    shot = lua.globals().GEARPROOF_SHOT
    text = serialize(shot, 2, 250, lua.globals().GEARPROOF_READER)
    suite.truthy("une chaine est produite", bool(text))

    bits = decode(str(text))
    suite.equal("version", read(bits, 0, 8), 2)
    suite.equal("specID", read(bits, 8, 16), 250)
    hashed = [read(bits, 24 + i * 8, 8) for i in range(16)]
    suite.equal("empreinte de l'arbre", hashed, list(range(1, 17)))

    at = 24 + 16 * 8
    # Noeud 10 : pris, complet (1 sur 1), pas un choix.
    suite.equal("noeud 10 pris", read(bits, at, 1), 1)
    suite.equal("noeud 10 complet", read(bits, at + 1, 1), 0)
    suite.equal("noeud 10 sans choix", read(bits, at + 2, 1), 0)
    at += 3
    # Noeud 20 : pris, PARTIEL (2 sur 3), donc six bits de rang suivent.
    suite.equal("noeud 20 pris", read(bits, at, 1), 1)
    suite.equal("noeud 20 partiel", read(bits, at + 1, 1), 1)
    suite.equal("noeud 20 rang", read(bits, at + 2, 6), 2)
    suite.equal("noeud 20 sans choix", read(bits, at + 8, 1), 0)
    at += 9
    # Noeud 30 : pris, complet, A CHOIX — seconde option, donc index 1.
    suite.equal("noeud 30 pris", read(bits, at, 1), 1)
    suite.equal("noeud 30 complet", read(bits, at + 1, 1), 0)
    suite.equal("noeud 30 a choix", read(bits, at + 2, 1), 1)
    suite.equal("noeud 30 seconde option", read(bits, at + 3, 2), 1)

    # Un noeud NON pris ne coute qu'UN bit. C'est ce qui fait tenir soixante-dix noeuds
    # dans une chaine courte, et un bit de trop decalerait tout ce qui suit.
    short = serialize(shot, 2, 250, lua.globals().GEARPROOF_EMPTY)
    header = 24 + 16 * 8
    useful = header + 3
    suite.equal("trois noeuds vides = trois bits",
                len(str(short)), (useful + 5) // 6)

    suite.done()


def test_traits_selfcheck(report: Report) -> None:
    """L'export n'est propose QUE si notre serialiseur reproduit celui du client.

    Le format d'import de Blizzard n'est pas un contrat : il a change d'une extension a
    l'autre. Ecrire une chaine fausse serait pire que de ne rien proposer — le joueur
    collerait un arbre qui n'est pas celui qu'il a regarde, et rien ne le lui dirait.

    D'ou ce garde-fou : on serialise la configuration DU JOUEUR avec notre code, et on la
    compare a celle que le client produit pour la meme configuration. Identiques au
    caractere pres : le format est verifie sur ce client. Differentes : pas d'export.
    """
    suite = Suite(report, "Traits.SelfCheck")
    lua, ns, locals_ = new_runtime(["Spec.lua", "Traits.lua"],
                                   expose={"Traits.lua": ["serialize"]})
    lua.globals().GEARPROOF_NS = ns

    lua.execute("""
        Enum = Enum or {}
        Enum.TraitNodeType = { Single = 0, Tiered = 1, Selection = 2 }

        local NODES = {
            [10] = { posX = 0, posY = 0, maxRanks = 1, type = 0, entryIDs = { 100 },
                     ranksPurchased = 1, activeEntry = { entryID = 100, rank = 1 } },
            [20] = { posX = 100, posY = 100, maxRanks = 3, type = 1, entryIDs = { 200 },
                     ranksPurchased = 2, activeEntry = { entryID = 200, rank = 2 } },
            [30] = { posX = 200, posY = 200, maxRanks = 1, type = 2, entryIDs = { 300, 301 },
                     ranksPurchased = 1, activeEntry = { entryID = 301, rank = 1 } },
        }
        C_ClassTalents = { GetActiveConfigID = function() return 7 end }
        C_Traits = {
            GetConfigInfo = function() return { treeIDs = { 42 } } end,
            GetTreeNodes = function() return { 10, 20, 30 } end,
            GetNodeInfo = function(_, nodeID) return NODES[nodeID] end,
            GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
            GetDefinitionInfo = function(id) return { overrideName = "T" .. id } end,
            GetTreeHash = function()
                return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
            end,
        }
        GEARPROOF_CONFIG = {
            treeID = 42,
            order = { 10, 20, 30 },
            nodes = {
                [10] = { id = 10, maxRanks = 1, type = 0, entryIDs = { 100 } },
                [20] = { id = 20, maxRanks = 3, type = 1, entryIDs = { 200 } },
                [30] = { id = 30, maxRanks = 1, type = 2, entryIDs = { 300, 301 } },
            },
        }
        GEARPROOF_MINE = function(nodeID)
            local ranks = { [10] = 1, [20] = 2, [30] = 1 }
            local entries = { [10] = 100, [20] = 200, [30] = 301 }
            return ranks[nodeID] or 0, entries[nodeID]
        end
    """)
    ns.Spec.Active = lua.eval("function() return 250 end")

    # La chaine que le client rendrait s'il etait d'accord avec nous : produite par notre
    # propre serialiseur sur la configuration du joueur. C'est la definition meme de
    # l'accord, et la seule fixture qui ne fige pas un format qu'on ne controle pas.
    reference = locals_["serialize"](lua.globals().GEARPROOF_CONFIG, 2, 250,
                                     lua.globals().GEARPROOF_MINE)
    suite.truthy("une chaine de reference existe", bool(reference))

    lua.globals().GEARPROOF_REF = reference
    lua.execute("C_Traits.GenerateImportString = function() return GEARPROOF_REF end")

    # LA VOIE DE SECOURS, ET LE PIEGE QUI LA RENDAIT MORTE.
    #
    # Le client n'expose pas toujours le meme exportateur. La liste etait ecrite comme une
    # table de FONCTIONS — `{ C_Traits.GenerateInspectImportString, C_Traits.GenerateImportString }` —
    # et quand la premiere n'existe pas, la table a un TROU : `ipairs` s'arrete des le
    # premier nil et la seconde n'est jamais essayee. Le controle de format echouait donc
    # avec « pas de chaine de reference » sur un client qui en avait pourtant une, et le
    # bouton d'export restait masque sans que rien ne dise pourquoi.
    lua.execute("""
        C_Traits.GenerateInspectImportString = nil
        C_Traits.GenerateImportString = function() return GEARPROOF_REF end
        GEARPROOF_NS.Traits.Invalidate()
        GEARPROOF_FOUND = GEARPROOF_NS.Traits.PlayerImportString()
    """)
    suite.equal("second exportateur atteint malgre le premier absent",
                str(lua.globals().GEARPROOF_FOUND), str(reference))

    # Et l'inverse : le PREMIER doit gagner quand il existe.
    lua.execute("""
        C_Traits.GenerateInspectImportString = function() return GEARPROOF_REF .. "AA" end
        GEARPROOF_FOUND = GEARPROOF_NS.Traits.PlayerImportString()
    """)
    suite.equal("premier exportateur prioritaire",
                str(lua.globals().GEARPROOF_FOUND), str(reference) + "AA")

    # Aucun des deux, mais la fenetre de talents de Blizzard est ouverte : elle fabrique la
    # chaine en Lua, et c'est le dernier recours.
    lua.execute("""
        C_Traits.GenerateInspectImportString = nil
        C_Traits.GenerateImportString = nil
        PlayerSpellsFrame = { TalentsFrame = {
            GetLoadoutExportString = function() return GEARPROOF_REF end,
        } }
        GEARPROOF_FOUND = GEARPROOF_NS.Traits.PlayerImportString()
    """)
    suite.equal("repli sur l'interface de Blizzard",
                str(lua.globals().GEARPROOF_FOUND), str(reference))
    lua.execute("PlayerSpellsFrame = nil")
    lua.execute("C_Traits.GenerateImportString = function() return GEARPROOF_REF end")

    lua.execute("GEARPROOF_NS.Traits.Invalidate()")
    lua.execute("GEARPROOF_OK, GEARPROOF_WHY = GEARPROOF_NS.Traits.SelfCheck()")
    suite.equal("format reconnu", lua.globals().GEARPROOF_OK, True)

    # ET DANS L'AUTRE SENS. Un seul caractere de difference doit suffire : c'est tout
    # l'interet d'une comparaison exacte plutot que d'un controle de longueur.
    lua.execute("""
        C_Traits.GenerateImportString = function()
            return GEARPROOF_REF:sub(1, #GEARPROOF_REF - 1) .. "Z"
        end
        GEARPROOF_NS.Traits.Invalidate()
        GEARPROOF_OK, GEARPROOF_WHY = GEARPROOF_NS.Traits.SelfCheck()
    """)
    suite.equal("un caractere de trop suffit a refuser", lua.globals().GEARPROOF_OK, False)
    suite.equal("et la raison est dite", str(lua.globals().GEARPROOF_WHY), "format mismatch")

    # Sans chaine de reference du client, on ne DEVINE pas : on refuse.
    lua.execute("""
        C_Traits.GenerateImportString = nil
        GEARPROOF_NS.Traits.Invalidate()
        GEARPROOF_OK, GEARPROOF_WHY = GEARPROOF_NS.Traits.SelfCheck()
    """)
    suite.equal("sans reference, refus", lua.globals().GEARPROOF_OK, False)
    suite.equal("raison dite", str(lua.globals().GEARPROOF_WHY), "no reference string")

    # Et l'export lui-meme se tait tant que le format n'est pas verifie.
    lua.execute("""
        GEARPROOF_MATCH = GEARPROOF_NS.Traits.Match({ 10, 1, 20, 2 })
        GEARPROOF_TEXT, GEARPROOF_REASON = GEARPROOF_NS.Traits.Export(GEARPROOF_MATCH)
    """)
    suite.equal("aucun export sans preuve", lua.globals().GEARPROOF_TEXT, None)

    suite.done()


# --------------------------------------------- crafts et bijoux du releve

def test_crafts_and_trinkets(report: Report) -> None:
    """Deux relevés neufs, et deux questions auxquelles rien ne repondait.

    « Quelles recettes faire ? » — rien en jeu ne distingue un objet fabrique d'un butin
    sans ouvrir sa recette.

    « Quel bijou porter quand on tank ? » — un droptimizer ne mesure QUE des degats, et
    Warcraft Logs n'a pas de classement de survie. Aucun chiffre ne repond, donc l'addon
    ne montre pas un classement : il montre ce que les meilleurs PORTENT.

    Les deux listes de bijoux sont distinctes, et c'est tout l'interet : une liste dominee
    par des bijoux de raid ne nomme, pour qui ne raide pas, que des objets hors d'atteinte.
    """
    suite = Suite(report, "Meta.Crafts/Trinkets")
    lua, ns, _ = new_runtime(["Spec.lua", "Meta.lua"])

    # Fixture calquee sur ce que le generateur ecrit reellement — verifie en executant sa
    # sortie : `_stamp.format` a la racine, bloc indexe par « Classe/Spe ».
    lua.execute("""
        GearProofMeta = {
            _stamp = { format = 2, generatedAt = "2026-09-07", specs = 1 },
            ["DeathKnight/Blood"] = {
                specID = 250, class = "DeathKnight", spec = "Blood",
                role = "tank", sample = 20,
                -- Le MEME relevé, pris en raid et en donjon. Ce ne sont pas les memes
                -- arbres : c'est toute la raison d'etre du selecteur de contenu.
                talents = {
                    { id = 100, count = 20, share = 1.0 },
                    { id = 101, count = 12, share = 0.6 },
                },
                talentsMythic = {
                    { id = 100, count = 20, share = 1.0 },
                    { id = 202, count = 15, share = 0.75 },
                },
                builds = { { n = 5, share = 0.25, differs = { 101 } } },
                buildsMythic = { { n = 7, share = 0.35, differs = { 202 } } },
                crafts = {
                    { id = 237834, slot = "WristSlot", ilvl = 331, count = 11,
                      share = 0.55, name = "Spellbreaker's Bracers" },
                    { id = 237846, slot = "MainHandSlot", ilvl = 331, count = 11,
                      share = 0.55, name = "Blood Knight's Warblade" },
                },
                -- UNE liste, dans l'ordre d'adoption. La separation par provenance se
                -- fait en jeu : le releve ne sait pas d'ou tombe un objet.
                trinkets = {
                    { id = 270175, slot = "Trinket0Slot", ilvl = 334, count = 22,
                      share = 0.55, name = "Voracious Heart" },
                    { id = 270165, slot = "Trinket1Slot", ilvl = 321, count = 7,
                      share = 0.35, name = "Seething Core" },
                    { id = 111111, slot = "Trinket0Slot", ilvl = 300, count = 3,
                      share = 0.15, name = "Provenance inconnue" },
                },
            },
        }
    """)
    ns.Spec.Selected = lua.eval("function() return 250 end")

    crafts = ns.Meta.Crafts()
    suite.truthy("crafts lus", crafts is not None)
    suite.equal("deux recettes", len(crafts), 2)
    suite.equal("la plus portee en tete", int(crafts[1]["id"]), 237834)
    # Le NIVEAU compte autant que l'objet : un craft se monte a une qualite choisie, et
    # sans le niveau la ligne ne dit pas jusqu'ou aller.
    suite.equal("niveau publie", int(crafts[1]["ilvl"]), 331)
    suite.equal("emplacement publie", str(crafts[1]["slot"]), "WristSlot")

    # LE SELECTEUR DE CONTENU. Sans cette verification, un onglet Talents qui ignorerait
    # son propre bouton rendrait le relevé de raid dans les deux cas et rien ne le dirait :
    # les deux ecrans se ressemblent, seule la donnee change.
    raid_talents = ns.Meta.Talents()
    mythic_talents = ns.Meta.Talents("mythic")
    suite.equal("talents de raid", [int(raid_talents[i]["id"]) for i in (1, 2)], [100, 101])
    suite.equal("talents de donjon", [int(mythic_talents[i]["id"]) for i in (1, 2)], [100, 202])
    suite.equal("build de raid", int(ns.Meta.Builds()[1]["n"]), 5)
    suite.equal("build de donjon", int(ns.Meta.Builds("mythic")[1]["n"]), 7)
    # Un contenu inconnu retombe sur le raid plutot que de ne rien rendre : le selecteur
    # n'a que deux positions, mais un appelant fautif ne doit pas vider la page.
    suite.equal("contenu inconnu = raid", int(ns.Meta.Builds("autre")[1]["n"]), 5)

    trinkets = ns.Meta.Trinkets()
    suite.equal("bijoux lus", len(trinkets), 3)
    suite.equal("le plus porte en tete", int(trinkets[1]["id"]), 270175)

    # LA SEPARATION PAR PROVENANCE, qui est le coeur du bloc. Elle ne se fait pas sur la
    # population observee — un raideur porte son bijou de raid en donjon — mais sur ce que
    # le journal des aventures du client sait : d'ou l'objet TOMBE.
    lua.execute("""
        GEARPROOF_NS.Journal = {}
        GEARPROOF_NS.Journal.ItemSource = function(id)
            if id == 270175 then return "raid" end
            if id == 270165 then return "dungeon" end
            return nil
        end
    """)
    raid, dungeon = ns.Meta.TrinketsBySource()
    suite.equal("un bijou de raid", len(raid), 1)
    suite.equal("le bon", int(raid[1]["id"]), 270175)
    suite.equal("un bijou de donjon", len(dungeon), 1)
    suite.equal("le bon aussi", int(dungeon[1]["id"]), 270165)

    # Une provenance INCONNUE ne va nulle part. Le journal charge son butin de facon
    # asynchrone : lui inventer une provenance serait pire que de l'omettre, et l'appel
    # suivant le retrouvera.
    suite.falsy("provenance inconnue rangee nulle part",
                any(int(raid[i]["id"]) == 111111 for i in range(1, len(raid) + 1))
                or any(int(dungeon[i]["id"]) == 111111 for i in range(1, len(dungeon) + 1)))

    # La limite s'applique PAR LISTE : quatre bijoux dans l'onglet Recommandations, c'est
    # deux et deux, pas quatre du meme cote.
    lua.execute('GEARPROOF_NS.Journal.ItemSource = function() return "raid" end')
    raid, dungeon = ns.Meta.TrinketsBySource(2)
    suite.equal("limite par liste", len(raid), 2)
    suite.equal("l'autre liste reste vide", len(dungeon), 0)

    # Une spe sans ces blocs — toutes celles qui ne sont ni tank ni soigneur pour les
    # bijoux — doit rendre nil, pas une table vide : l'appelant saute la section.
    lua.execute("""
        GearProofMeta["DeathKnight/Blood"].crafts = nil
        GearProofMeta["DeathKnight/Blood"].trinkets = nil
    """)
    suite.equal("sans crafts, nil", ns.Meta.Crafts(), None)
    suite.equal("sans bijoux, nil", ns.Meta.Trinkets(), None)

    # Une liste VIDE n'est pas une liste : elle poserait un titre de section sur rien.
    lua.execute('GearProofMeta["DeathKnight/Blood"].crafts = {}')
    suite.equal("liste vide traitee comme absente", ns.Meta.Crafts(), None)

    suite.done()


# ------------------------------------------- le niveau reel d'une piece de butin

def test_known_level(report: Report) -> None:
    """L'infobulle d'un butin dit-elle la verite quand le journal n'a pas rendu le lien ?

    Vu en jeu sur une piece d'ensemble mythique : le journal des aventures ne rend pas
    toujours le lien complet d'une piece de CLASSE sous son boss, l'onglet retombe donc
    sur `SetItemByID` — qui ne connait que le MODELE, niveau 219 pour un objet qui tombe
    a 344. Le crochet d'infobulle lisait ce 219 et en tirait deux mensonges dans la meme
    infobulle : « -73 ilvl contre l'equipe » sur un objet reellement a +52, et AUCUN gain
    simule, parce que `Sim.Percent(id, 219)` refuse a juste titre de repondre pour un
    niveau qui n'est pas celui simule. La liste juste derriere affichait +3,56 %.

    Le droptimizer, lui, sait le niveau. Le test verifie qu'il fait autorite.
    """
    suite = Suite(report, "Tooltip.SetKnownLevel")
    lua, ns, _ = new_runtime(["ItemLink.lua", "ItemInfo.lua", "Spec.lua", "Sim.lua",
                              "Tooltip.lua"])
    lua.globals().GEARPROOF_NS = ns
    lua.globals().GEARPROOF_TEST_TIME = 1

    # Le strict necessaire autour de `LinesFor` : l'equipement porte, la resolution
    # d'emplacement, et de quoi ne rien conseiller cote enchantements.
    lua.execute("""
        GEARPROOF_NS.db = { sim = { ["r"] = {
            baseline = 55672, player = "Testeur", stamp = 1, items = {
                [268222] = { percent = 3.56, ilvl = 344, slot = "chest",
                             encounter = 2883, instance = 1320 },
            },
        } } }
        GEARPROOF_NS.Bags = { SLOTS_FOR = function() return { "ChestSlot" } end }
        GEARPROOF_NS.Gear = { Scan = function()
            return {}, { bySlot = { ChestSlot = { itemLevel = 292 } } }
        end }
        GEARPROOF_NS.Meta = { ExpectsEnchant = function() return nil, false end }
        GEARPROOF_NS.Weights = { Current = function() return nil end }

        -- Le MODELE : c'est ce que rend `SetItemByID`, et c'est ce que le crochet lit.
        GEARPROOF_TEMPLATE = "|cffa335ee|Hitem:268222::::::::80:250::::|h[Plastron]|h|r"
        GetItemInfo = function()
            return "Plastron", GEARPROOF_TEMPLATE, 4, 219, 80, "", "", 1,
                "INVTYPE_CHEST", "", 0, 4, 1, nil, nil, nil, nil
        end
        C_Item.GetDetailedItemLevelInfo = function() return 219, false, 219 end
    """)

    def lines_for():
        out = ns.Tooltip.LinesFor(lua.globals().GEARPROOF_TEMPLATE)
        return [str(out[i]["text"]) for i in range(1, len(out) + 1)] if out else []

    # SANS contexte : le modele decide, et il a tort sur les deux lignes.
    ns.Tooltip.SetKnownLevel(None, None)
    plain = lines_for()
    suite.truthy("sans contexte, ecart negatif", any("-73" in text for text in plain))
    suite.falsy("sans contexte, aucun gain simule",
                any("%" in text and "3.56" in text for text in plain))

    # AVEC le niveau du droptimizer : le signe s'inverse et le gain apparait.
    ns.Tooltip.SetKnownLevel(268222, 344)
    fixed = lines_for()
    suite.truthy("ecart calcule sur le vrai niveau", any("+52" in text for text in fixed))
    suite.falsy("plus d'ecart negatif", any("-73" in text for text in fixed))
    suite.truthy("gain simule affiche", any("3.56" in text for text in fixed))

    # Le contexte ne vaut QUE pour l'objet annonce : un autre objet garde son modele.
    ns.Tooltip.SetKnownLevel(999999, 344)
    other = lines_for()
    suite.truthy("contexte limite a son objet", any("-73" in text for text in other))

    ns.Tooltip.SetKnownLevel(None, None)
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
                 test_by_encounter_season, test_known_level,
                 test_crafts_and_trinkets, test_traits_stream,
                 test_traits_selfcheck):
        try:
            test(report)
        except Exception as error:  # noqa: BLE001 — un test qui casse est un constat
            report.error(test.__name__, f"{type(error).__name__}: {error}")
    return report.finish()


run(main)
