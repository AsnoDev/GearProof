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
            local name, icon
            for _, entryID in ipairs(entryIDs) do
                byEntry[entryID] = nodeID
                if not name then name, icon = entryLabel(configID, entryID) end
            end
            nodes[nodeID] = {
                id = nodeID,
                x = info.posX or 0,
                y = info.posY or 0,
                maxRanks = info.maxRanks or 1,
                type = info.type,
                entryIDs = entryIDs,
                ranksPurchased = info.ranksPurchased or 0,
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
--       1 bit  : partiellement monte ?
--       si oui : 6 bits de rang
--       1 bit  : noeud a choix ?
--       si oui : 2 bits d'index de choix
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

--- Serialise une selection. `reader(nodeID, node)` rend rang et identifiant d'entree.
local function serialize(shot, version, specID, reader)
    local hash = safe(C_Traits.GetTreeHash, shot.treeID)
    if type(hash) ~= "table" or #hash == 0 then return nil end

    local stream = newStream()
    addValue(stream, version, HEADER_BITS)
    addValue(stream, specID, SPEC_BITS)
    for _, byte in ipairs(hash) do addValue(stream, byte, 8) end

    for _, nodeID in ipairs(shot.order) do
        local node = shot.nodes[nodeID]
        local rank, entryID = reader(nodeID, node)
        local selected = (rank or 0) > 0

        addValue(stream, selected and 1 or 0, 1)
        if selected then
            local maxRanks = (node and node.maxRanks) or 1
            local partial = rank ~= maxRanks
            addValue(stream, partial and 1 or 0, 1)
            if partial then addValue(stream, rank, RANK_BITS) end

            local isChoice = node and node.type == (Enum and Enum.TraitNodeType
                and Enum.TraitNodeType.Selection)
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
        if not node or (node.ranksPurchased or 0) <= 0 then return 0 end
        return node.ranksPurchased, node.activeEntry and node.activeEntry.entryID
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

    return serialize(shot, version, specID, function(nodeID)
        local picked = match.selection[nodeID]
        if not picked then return 0 end
        return picked.rank or 1, picked.entryID
    end)
end
