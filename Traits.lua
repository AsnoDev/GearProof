local _, ns = ...

local Traits = {}
ns.Traits = Traits

-- Acces a l'arbre de talents du client, et fabrication d'une chaine d'import.
--
-- POURQUOI CE FICHIER EXISTE, ET CE QU'IL CORRIGE.
--
-- Le relevé porte des `talentID` venus de Warcraft Logs. L'addon les resolvait avec
-- `C_Spell.GetSpellInfo`, en supposant que c'etaient des identifiants de SORT. Ils ne le
-- sont pas : sur un relevé reel ils vont de 96167 a 137635 avec des rangs 1 ou 2, ce qui
-- est la signature d'un arbre `C_Traits` — noeuds ou entrees de noeud. Le pire est que
-- `GetSpellInfo` rendait quand meme un nom, celui d'un sort sans aucun rapport : la liste
-- de talents affichait donc des noms FAUX mais plausibles, ce qui est pire que rien.
--
-- QUEL ESPACE D'IDENTIFIANTS, EXACTEMENT ? On ne le devine pas, on le MESURE. L'arbre du
-- client donne les deux — identifiants de noeud et identifiants d'entree — et
-- `Traits.Match` compte les correspondances de chaque cote. Celui qui gagne est le bon, et
-- s'il n'y en a pas, la page le dit au lieu d'afficher n'importe quoi.
--
-- L'ARBRE DU CLIENT EST CELUI DE LA SPE ACTIVE. Il n'existe aucun moyen de lire l'arbre
-- d'une autre spe sans y basculer ; l'apercu d'une autre spe se limite donc au relevé, et
-- la page le dit.

local snapshot

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    return results[2]
end

--- Nom et icone d'une entree de noeud, via sa definition.
local function entryLabel(configID, entryID)
    local entry = safe(C_Traits and C_Traits.GetEntryInfo, configID, entryID)
    local definitionID = entry and entry.definitionID
    if not definitionID then return nil, nil end

    local definition = safe(C_Traits and C_Traits.GetDefinitionInfo, definitionID)
    if not definition then return nil, nil end

    local name, icon = definition.overrideName, definition.overrideIcon
    local spellID = definition.spellID
    if spellID and (not name or not icon) then
        local info = safe(C_Spell and C_Spell.GetSpellInfo, spellID)
        if type(info) == "table" then
            name = name or info.name
            icon = icon or info.iconID
        end
        if not icon then
            icon = safe(C_Spell and C_Spell.GetSpellTexture, spellID)
        end
    end
    return name, icon
end

--- Photographie de l'arbre de la spe ACTIVE : positions, noms, icones, ordre.
---
--- L'ORDRE compte autant que le reste : le format d'import de Blizzard encode les noeuds
--- dans l'ordre exact de `C_Traits.GetTreeNodes`, sans les nommer. Un ordre different
--- produit une chaine syntaxiquement valide et semantiquement fausse.
--- @return table|nil
--- Identifiant de la configuration de talents active.
---
--- `C_ClassTalents` a CHANGE DE NOM plusieurs fois : on essaie chaque voie connue plutot
--- que de dependre d'une seule. Cette recherche vivait en double, ici et dans `SimC.lua` —
--- deux lecteurs de la meme donnee divergeant sur un detail invisible, c'est la
--- duplication qui a coute le plus cher dans ce depot. `Traits.lua` est le seul
--- proprietaire de `C_Traits` ; `SimC` passe par lui.
--- @return number|nil
--- ON ITERE SUR DES NOMS, PAS SUR DES FONCTIONS. Une table Lua construite avec un trou —
--- `{ nil, f }` quand la premiere API n'existe pas sur ce client — arrete `ipairs` des le
--- premier nil : la voie de secours n'etait jamais essayee. C'est exactement ce qui rendait
--- le controle de format inoperant, et le bug etait deja present dans la copie de `SimC`.
local CONFIG_GETTERS = {
    { "C_ClassTalents", "GetActiveConfigID" },
    { "C_Traits", "GetActiveConfigID" },
    { "C_SpecializationInfo", "GetActiveConfigID" },
}

function Traits.ConfigID()
    if not C_Traits then return nil end
    for _, path in ipairs(CONFIG_GETTERS) do
        local namespace = _G[path[1]]
        local value = type(namespace) == "table" and safe(namespace[path[2]]) or nil
        if value then return value end
    end
    return nil
end

--- La chaine d'import que LE CLIENT produit pour la configuration du joueur.
---
--- C'EST ELLE QUI MANQUAIT. `Traits.SelfCheck` n'essayait que
--- `C_Traits.GenerateImportString`, qui n'existe pas partout : le controle echouait donc
--- avec « pas de chaine de reference » et le bouton d'export restait masque sans que rien
--- ne dise pourquoi. `SimC.lua` connaissait deja la voie de secours et personne ne l'avait
--- rapprochee.
--- @return string|nil
function Traits.PlayerImportString()
    local configID = Traits.ConfigID()
    if not configID then return nil end

    for _, name in ipairs({ "GenerateInspectImportString", "GenerateImportString" }) do
        local value = safe(C_Traits[name], configID)
        if type(value) == "string" and #value > 20 then return value end
    end

    -- Dernier recours : l'interface de talents de Blizzard fabrique la chaine EN LUA, pas
    -- par une API C. Elle a demenage d'une extension a l'autre, d'ou les deux chemins. On
    -- ne charge rien : si le joueur n'a jamais ouvert sa fenetre de talents, on repond nil
    -- plutot que d'ouvrir une interface qu'il n'a pas demandee.
    for _, path in ipairs({
        { "PlayerSpellsFrame", "TalentsFrame" },
        { "ClassTalentFrame", "TalentsTab" },
    }) do
        local root = _G[path[1]]
        local frame = type(root) == "table" and root[path[2]] or nil
        if type(frame) == "table" and type(frame.GetLoadoutExportString) == "function" then
            local value = safe(frame.GetLoadoutExportString, frame)
            if type(value) == "string" and #value > 20 then return value end
        end
    end

    return nil
end

function Traits.Snapshot()
    if snapshot then return snapshot end
    if not C_Traits then return nil end

    local configID = Traits.ConfigID()
    if not configID then return nil end

    local config = safe(C_Traits.GetConfigInfo, configID)
    local treeIDs = config and config.treeIDs
    local treeID = treeIDs and treeIDs[1]
    if not treeID then return nil end

    local order = safe(C_Traits.GetTreeNodes, treeID)
    if not order or #order == 0 then return nil end

    local nodes, byEntry = {}, {}
    for _, nodeID in ipairs(order) do
        local info = safe(C_Traits.GetNodeInfo, configID, nodeID)
        if info then
            local entryIDs = info.entryIDs or {}
            -- CHAQUE ENTREE porte son nom et son icone, pas seulement la premiere.
            --
            -- Un noeud a choix propose deux sorts differents. N'en garder qu'un affichait
            -- l'icone de la premiere branche meme quand le build prenait la seconde : le
            -- joueur voyait le bon noeud allume et la mauvaise icone dessus.
            local entries = {}
            local name, icon
            for _, entryID in ipairs(entryIDs) do
                byEntry[entryID] = nodeID
                local entryName, entryIcon = entryLabel(configID, entryID)
                entries[entryID] = { name = entryName, icon = entryIcon }
                if not name then name, icon = entryName, entryIcon end
            end

            -- LES LIAISONS. Un arbre sans traits n'est qu'une grille d'icones : c'est
            -- justement ce qui rendait la page « peu claire ». `visibleEdges` dit quel
            -- noeud ouvre quel autre, et c'est ce que le jeu dessine lui aussi.
            local edges = {}
            for _, edge in ipairs(info.visibleEdges or {}) do
                if edge.targetNode then table.insert(edges, edge.targetNode) end
            end

            nodes[nodeID] = {
                id = nodeID,
                x = info.posX or 0,
                y = info.posY or 0,
                -- L'ARBRE DE HEROS EST UN ARBRE A PART, et ses coordonnees ne vivent pas
                -- dans le meme repere que celles de l'arbre principal. Normalisees avec le
                -- reste, elles l'envoyaient en haut a droite, colle a l'arbre de spe. En
                -- jeu il est en bas, au centre. `subTreeID` est ce qui permet de le
                -- reconnaitre — nil sur les noeuds de classe et de spe.
                subTree = info.subTreeID,
                maxRanks = info.maxRanks or 1,
                type = info.type,
                entryIDs = entryIDs,
                entries = entries,
                edges = edges,
                ranksPurchased = info.ranksPurchased or 0,
                -- ACCORDE PAR L'ARBRE : un rang actif sans rang achete. C'est une
                -- propriete de l'ARBRE, pas du build — elle vaut donc aussi pour le build
                -- du relevé, qu'on exporte avec la meme regle.
                activeRank = info.activeRank or 0,
                activeEntry = info.activeEntry,
                name = name,
                icon = icon,
            }
        end
    end

    snapshot = {
        configID = configID,
        treeID = treeID,
        specID = ns.Spec.Active(),
        order = order,
        nodes = nodes,
        byEntry = byEntry,
    }
    return snapshot
end

function Traits.Invalidate()
    snapshot = nil
end

--- Separe les noeuds : l'arbre principal d'un cote, les arbres de HEROS de l'autre.
---
--- Les noeuds de heros vivent dans un repere qui leur est propre. Melanges au reste, ils
--- atterrissent la ou le hasard les met — en haut a droite sur un relevé reel, alors qu'en
--- jeu ils sont en bas, au centre.
---
--- `> 0` ET PAS SEULEMENT « non nil » : en Lua, ZERO EST VRAI. Si le client rend
--- `subTreeID = 0` sur un noeud ordinaire — rien ne l'interdit, et c'est une facon
--- courante de dire « aucun » cote C — un simple test de presence les rangerait TOUS parmi
--- les heros. L'arbre principal serait vide et la page afficherait « le client n'a pas
--- rendu d'arbre » sur un client parfaitement sain.
---
--- Cette regle vivait dans la vue, ou rien ne pouvait la tester : le mauvais classement ne
--- leve aucune erreur, il vide juste un ecran.
--- @return table principal, table { [subTreeID] = { noeuds } }
function Traits.SplitTrees(shot)
    local main, heroes = {}, {}
    if not shot then return main, heroes end

    for _, nodeID in ipairs(shot.order or {}) do
        local node = shot.nodes[nodeID]
        if node then
            if node.subTree and node.subTree > 0 then
                heroes[node.subTree] = heroes[node.subTree] or {}
                table.insert(heroes[node.subTree], node)
            else
                table.insert(main, node)
            end
        end
    end
    return main, heroes
end

--- Nom d'un arbre de heros, quand le client sait le donner.
--- @return string|nil
function Traits.SubTreeName(subTreeID)
    if not subTreeID then return nil end
    local shot = Traits.Snapshot()
    if not shot then return nil end
    local info = safe(C_Traits and C_Traits.GetSubTreeInfo, shot.configID, subTreeID)
    return info and info.name or nil
end

--- Le relevé parle-t-il en NOEUDS ou en ENTREES ? On compte, on ne suppose pas.
---
--- @param flat table liste plate { id, rang, id, rang, ... } venue du relevé
--- @return table|nil { mode, selection = { [nodeID] = { rank, entryID } }, matched, total }
function Traits.Match(flat)
    local shot = Traits.Snapshot()
    if not shot or type(flat) ~= "table" or #flat < 2 then return nil end

    local asNode, asEntry = {}, {}
    local total = 0

    for index = 1, #flat - 1, 2 do
        local id, rank = flat[index], flat[index + 1]
        if id then
            total = total + 1
            if shot.nodes[id] then
                asNode[id] = { rank = rank or 1, sourceID = id }
            end
            local owner = shot.byEntry[id]
            if owner then
                -- L'entree est l'information la PLUS precise : sur un noeud a choix, elle
                -- dit laquelle des deux options a ete prise. L'identifiant de noeud seul
                -- ne le dirait pas.
                asEntry[owner] = { rank = rank or 1, entryID = id, sourceID = id }
            end
        end
    end

    local nodeHits, entryHits = 0, 0
    for _ in next, asNode do nodeHits = nodeHits + 1 end
    for _ in next, asEntry do entryHits = entryHits + 1 end

    if entryHits == 0 and nodeHits == 0 then return nil end

    if entryHits >= nodeHits then
        return { mode = "entry", selection = asEntry, matched = entryHits, total = total }
    end
    return { mode = "node", selection = asNode, matched = nodeHits, total = total }
end

-- --------------------------------------------------------------- chaine d'import
--
-- FORMAT. Blizzard serialise un ensemble de talents en bits, puis encode en base64 :
--
--   version (8 bits) | specID (16 bits) | empreinte de l'arbre (16 octets)
--   puis, POUR CHAQUE NOEUD dans l'ordre de `GetTreeNodes` :
--     1 bit  : noeud pris ?
--     si pris :
--       1 bit  : ACHETE ?
--       si achete :
--         1 bit  : partiellement monte ?
--         si oui : 6 bits de rang
--         1 bit  : noeud a choix ?
--         si oui : 2 bits d'index de choix
--       sinon (ACCORDE par l'arbre) : rien de plus n'est ecrit pour ce noeud
--
-- LE BIT « ACHETE » MANQUAIT, et c'est tout ce qui separait notre chaine de celle du
-- client. Il n'a pas ete devine : un joueur a colle les deux, et la comparaison bit a bit
-- les a departagees. L'entete — version 2, specID 250, seize octets d'empreinte — etait
-- identique ; la divergence commencait trois bits apres, et l'ecart total valait 78 bits
-- pour 76 noeuds pris. Un bit par noeud.
--
-- Restait a savoir ce que ce bit commande a zero. Deux lectures possibles : « on ecrit la
-- suite quand meme », ou « le noeud est accorde par l'arbre et rien d'autre ne suit ».
-- Seule la seconde termine le flux sur du remplissage a zero avec des rangs plausibles :
-- 73 noeuds achetes, 3 accordes, 8 a choix, six bits de remplissage exactement.
--
-- CE FORMAT N'EST PAS UN CONTRAT. Il a change entre extensions et rien ne garantit qu'il
-- ne changera plus. Ecrire une chaine fausse serait pire que de ne rien proposer : le
-- joueur collerait un arbre qui n'est pas celui qu'il a vu.
--
-- D'ou `Traits.SelfCheck` : on serialise le build DU JOUEUR avec ce code, et on compare a
-- la chaine que le client produit lui-meme pour la meme configuration. Si les deux sont
-- identiques au caractere pres, le format est verifie SUR CE CLIENT, et l'export est
-- propose. Sinon il est masque, avec la raison. C'est la seule facon honnete de livrer un
-- serialiseur qu'on ne peut pas tester soi-meme.

local BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local HEADER_BITS, SPEC_BITS, RANK_BITS, CHOICE_BITS = 8, 16, 6, 2

local function newStream()
    return { bits = {} }
end

--- Ajoute `width` bits, du moins significatif au plus significatif.
local function addValue(stream, value, width)
    value = math.floor(value or 0)
    for _ = 1, width do
        table.insert(stream.bits, value % 2)
        value = math.floor(value / 2)
    end
end

local function encode(stream)
    local out = {}
    for index = 1, #stream.bits, 6 do
        local value = 0
        for offset = 0, 5 do
            local bit = stream.bits[index + offset]
            if bit == 1 then value = value + 2 ^ offset end
        end
        out[#out + 1] = BASE64:sub(value + 1, value + 1)
    end
    return table.concat(out)
end

--- Serialise une selection.
--- @param reader function rend `rang, entryID, accorde` pour un noeud donne
local function serialize(shot, version, specID, reader)
    local hash = safe(C_Traits.GetTreeHash, shot.treeID)
    if type(hash) ~= "table" or #hash == 0 then return nil end

    local stream = newStream()
    addValue(stream, version, HEADER_BITS)
    addValue(stream, specID, SPEC_BITS)
    for _, byte in ipairs(hash) do addValue(stream, byte, 8) end

    for _, nodeID in ipairs(shot.order) do
        local node = shot.nodes[nodeID]
        local rank, entryID, granted = reader(nodeID, node)
        local selected = (rank or 0) > 0

        addValue(stream, selected and 1 or 0, 1)
        if selected then
            -- ACHETE, ou accorde par l'arbre. Un noeud accorde ne coute que ces deux
            -- bits : ni rang, ni choix. Ecrire la suite quand meme decalait tout ce qui
            -- venait apres, et c'est exactement ce qui se passait.
            addValue(stream, granted and 0 or 1, 1)

            if not granted then
                local maxRanks = (node and node.maxRanks) or 1
                local partial = rank ~= maxRanks
                addValue(stream, partial and 1 or 0, 1)
                if partial then addValue(stream, rank, RANK_BITS) end

                -- La valeur de reference est lue AVANT la comparaison. Ecrite en ligne,
                -- elle vaut nil quand `Enum.TraitNodeType` n'existe pas, et
                -- `node.type == nil` devient VRAI pour tout noeud sans type : chacun
                -- recevrait alors deux bits d'index de choix et la chaine serait
                -- corrompue. Une comparaison ne doit jamais changer de sens parce qu'un
                -- de ses membres a disparu.
                local selection = Enum and Enum.TraitNodeType and Enum.TraitNodeType.Selection
                local isChoice = selection ~= nil and node ~= nil and node.type == selection
                addValue(stream, isChoice and 1 or 0, 1)
                if isChoice then
                    local index = 0
                    for position, candidate in ipairs((node and node.entryIDs) or {}) do
                        if candidate == entryID then index = position - 1 break end
                    end
                    addValue(stream, index, CHOICE_BITS)
                end
            end
        end
    end

    return encode(stream)
end

--- Notre serialiseur reproduit-il celui du client, sur la configuration du joueur ?
---
--- @return boolean ok, string|nil raison de l'echec
function Traits.SelfCheck()
    local shot = Traits.Snapshot()
    if not shot then return false, "no tree" end

    local expected = Traits.PlayerImportString()
    if type(expected) ~= "string" or expected == "" then
        return false, "no reference string"
    end

    -- La version se lit DANS la chaine du client plutot que d'etre ecrite en dur : c'est
    -- exactement le champ qui change d'une extension a l'autre.
    local first = BASE64:find(expected:sub(1, 1), 1, true)
    local second = BASE64:find(expected:sub(2, 2), 1, true)
    if not first or not second then return false, "unreadable reference" end
    local version = (first - 1) % 64 + ((second - 1) % 4) * 64
    version = version % 256

    local specID = ns.Spec.Active()
    if not specID then return false, "no spec" end

    local ours = serialize(shot, version, specID, function(_, node)
        if not node then return 0 end
        local purchased = node.ranksPurchased or 0
        local active = node.activeRank or 0
        if purchased <= 0 and active <= 0 then return 0 end
        -- Un noeud ACCORDE porte un rang actif sans rang achete.
        if purchased <= 0 then return active, nil, true end
        return purchased, node.activeEntry and node.activeEntry.entryID, false
    end)

    if ours ~= expected then return false, "format mismatch", version, ours, expected end
    return true, nil, version
end

--- Les deux chaines, cote a cote, quand elles ne coincident pas.
---
--- Un « format non reconnu » sans les chaines est un cul-de-sac : personne ne peut le
--- corriger sans voir en quoi elles different. Celle du client est la verite, la notre est
--- ce que ce code a produit — les deux ensemble suffisent a trouver le bit qui bouge.
--- @return string|nil client, string|nil notre
function Traits.Diagnose()
    local _, _, _, ours, expected = Traits.SelfCheck()
    return expected, ours
end

--- Chaine d'import pour une selection venue du relevé, ou nil.
---
--- Rend nil tant que `SelfCheck` n'a pas confirme le format sur ce client : une chaine
--- fausse ferait coller au joueur un arbre qui n'est pas celui qu'il a regarde.
--- @param match table resultat de `Traits.Match`
--- @return string|nil chaine, string|nil raison du refus
function Traits.Export(match)
    local ok, reason, version = Traits.SelfCheck()
    if not ok then return nil, reason end

    local shot = Traits.Snapshot()
    local specID = ns.Spec.Active()
    if not shot or not specID or not match then return nil, "no selection" end

    return serialize(shot, version, specID, function(nodeID, node)
        local picked = match.selection[nodeID]
        if not picked then return 0 end
        -- Un noeud accorde par l'arbre l'est pour TOUT build : on reprend la propriete
        -- telle que le client la rapporte sur la configuration en cours.
        local granted = node and (node.ranksPurchased or 0) <= 0
            and (node.activeRank or 0) > 0
        return picked.rank or 1, picked.entryID, granted
    end)
end
