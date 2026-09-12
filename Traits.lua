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
        -- ON NE DESSINE QUE CE QUE LE CLIENT SAIT NOMMER.
        --
        -- `GetTreeNodes` rend TOUT l'arbre de la classe : mesure sur un cas reel, 210
        -- noeuds la ou une specialisation en montre une centaine. Les autres appartiennent
        -- aux deux autres specialisations et aux arbres de heros qu'on ne joue pas. Le
        -- client ne leur donne ni nom ni icone, et l'onglet les dessinait quand meme —
        -- d'ou la grille de points d'interrogation au milieu de la page, la ou le jeu,
        -- lui, place l'arbre de heros.
        --
        -- « Le client sait-il le decrire ? » est le seul critere qui ne suppose rien : si
        -- la definition manque, Blizzard ne le dessine pas non plus.
        if node and node.name then
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

--- ECART entre l'arbre publie et celui que le joueur joue REELLEMENT.
---
--- C'est la question que l'onglet ne repondait pas. Il dessinait l'arbre du haut de tableau
--- et coloriait les noeuds par adoption, mais le joueur devait comparer de tete, icone par
--- icone, avec sa propre fenetre de talents ouverte a cote. Une liste de differences se lit
--- en trois secondes.
---
--- LES NOEUDS ACCORDES SONT IGNORES : un rang actif sans rang achete est une propriete de
--- l'arbre, pas un choix. Les compter afficherait des dizaines de fausses differences
--- identiques chez tout le monde.
---
--- @param match resultat de `Traits.Match`
--- @return table|nil { { id, name, icon, kind, mine, theirs } }, trie par nature d'ecart
function Traits.Compare(match)
    local shot = Traits.Snapshot()
    if not shot or not match or not match.selection then return nil end

    local byEntry = match.mode == "entry"
    local found = {}

    for _, nodeID in ipairs(shot.order) do
        local node = shot.nodes[nodeID]
        local want = match.selection[nodeID]
        if node and node.name then
            local mine = node.ranksPurchased or 0
            local theirs = want and (want.rank or 1) or 0
            local granted = (node.activeRank or 0) > mine and mine == 0

            if not granted and (mine > 0 or theirs > 0) then
                local kind
                if theirs > 0 and mine == 0 then
                    kind = "take"
                elseif mine > 0 and theirs == 0 then
                    kind = "drop"
                elseif mine ~= theirs then
                    kind = "rank"
                elseif byEntry and want.entryID then
                    -- MEME NOEUD, AUTRE BRANCHE. Un noeud a choix donne un talent sur
                    -- deux ; deux joueurs peuvent l'avoir « pris » tous les deux et ne
                    -- pas jouer la meme chose. C'est l'ecart le plus facile a rater.
                    local picked = node.activeEntry and node.activeEntry.entryID
                    if picked and picked ~= want.entryID then kind = "swap" end
                end

                if kind then
                    table.insert(found, {
                        id = nodeID,
                        name = node.name,
                        icon = node.icon,
                        kind = kind,
                        mine = mine,
                        theirs = theirs,
                    })
                end
            end
        end
    end

    if #found == 0 then return nil end

    -- « A prendre » d'abord : c'est ce sur quoi on agit. « A retirer » ensuite, parce que
    -- c'est ce qui paie les points. Les rangs et les branches ferment la liste.
    local ORDER = { take = 1, swap = 2, rank = 3, drop = 4 }
    table.sort(found, function(a, b)
        if ORDER[a.kind] ~= ORDER[b.kind] then return ORDER[a.kind] < ORDER[b.kind] end
        return (a.name or "") < (b.name or "")
    end)
    return found
end

-- LE SERIALISEUR A ETE SUPPRIME ICI, ET C'EST UNE BONNE NOUVELLE.
--
-- L'addon fabriquait lui-meme la chaine d'import des talents : format binaire reconstitue
-- en comparant deux chaines reelles du client, bit de « noeud achete » trouve a la main,
-- garde-fou `SelfCheck` qui comparait notre sortie a celle du jeu pour refuser d'exporter
-- quand les deux differaient. Cela marchait, et cela restait la piece la plus fragile de
-- l'addon : un bit d'ecart et le jeu refusait tout.
--
-- Le relevé porte desormais la chaine TELLE QUE RAIDER.IO LA PUBLIE, deja construite par
-- ceux qui l'ont lue chez Blizzard. `Meta.BuildImport` la rend, la vue la recopie. Il n'y
-- a plus de format a deviner, donc plus de format a verifier.
--
-- Ce qui reste ici sert a DESSINER l'arbre, pas a l'exporter : la photo de l'arbre du
-- client, sa separation en arbre de classe et arbre de heros, et la correspondance entre
-- les identifiants du relevé et ceux du client.
