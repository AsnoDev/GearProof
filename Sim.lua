local _, ns = ...

local Sim = {}
ns.Sim = Sim

-- Gains simules, importes depuis tes propres droptimizers :
--   specanalyser raidbots <lien> --to-addon
--
-- Quand un objet figure dans une simulation, sa valeur remplace l'estimation lineaire.
-- C'est la seule maniere honnete de chiffrer un bijou ou une piece d'ensemble : leur
-- valeur ne se reduit pas a des points de statistique.

function Sim.Available()
    return type(SpecAnalyserSim) == "table" and next(SpecAnalyserSim) ~= nil
end

--- Gain simule d'un objet, en pourcentage, ou nil.
---
--- `itemLevel` n'est pas optionnel par confort : un droptimizer simule une VERSION precise
--- d'un objet. Le releve porte `[250033] = { percent = 0.71, ilvl = 282 }`, et sans
--- verification l'addon collait ce +0,71 % sur la version 272 deja portee — il proposait comme
--- amelioration l'objet qu'on a sur le dos. Un identifiant d'objet ne suffit pas a designer ce
--- qui a ete simule.
---
--- @param itemLevel number|nil niveau de l'objet interroge ; sans lui, on ne repond pas
function Sim.Percent(itemID, itemLevel)
    if not itemID or not Sim.Available() then return nil end

    -- Echec FERME. La version precedente acceptait quand le niveau etait inconnu, et cette
    -- porte de sortie a produit un « +4,25 % » sur un objet de niveau 44 alors que la
    -- simulation portait sur du 289. Une valeur simulee decrit un objet PRECIS a un niveau
    -- PRECIS : sans les deux, on ne repond pas.
    if not itemLevel or itemLevel <= 0 then return nil end

    local best, bestBaseline
    for _, report in pairs(SpecAnalyserSim) do
        local entry = (report.items or {})[itemID]
        local matches = entry and entry.ilvl and entry.ilvl == itemLevel
        if matches and entry.percent then
            -- A egalite, la simulation avec la plus grosse base est la plus recente.
            if not best or (report.baseline or 0) > (bestBaseline or 0) then
                best, bestBaseline = entry.percent, report.baseline or 0
            end
        end
    end
    return best
end

-- Difficultes de Raidbots -> identifiants de difficulte du client. Le journal des aventures
-- ne rend pas le meme butin selon la difficulte : sans ce reglage, on lirait la table LFR.
local DIFFICULTY = {
    ["raid-lfr"] = 17,
    ["raid-normal"] = 14,
    ["raid-heroic"] = 15,
    ["raid-mythic"] = 16,
}

-- Butin du journal, par rencontre et par difficulte. Le journal est un objet a etat et le
-- consulter coute cher : on ne le fait qu'une fois par couple.
local lootCache = {}

--- Lien COMPLET d'un objet de butin, bonus IDs compris, tel que le journal des aventures le
--- connait.
---
--- C'est la reponse a « pourquoi l'Adventure Guide affiche le bon niveau et pas nous » :
--- `GameTooltip:SetItemByID` ne connait que le MODELE de l'objet, donc son niveau de base —
--- 44 sur une piece de raid. Le journal, lui, expose le butin reel de la rencontre pour une
--- difficulte donnee, avec les identifiants de bonus qui portent le vrai niveau.
--- @return string|nil lien d'objet
--- @param instanceID number|nil instance du journal, quand l'appelant la connait.
---   Le journal se positionne d'abord sur l'instance : sans elle, `EJ_SelectEncounter`
---   travaille sur ce qui etait deja selectionne. La cle de cache n'en depend pas — le
---   couple rencontre + difficulte designe deja une table de butin unique.
function Sim.LootLink(encounterID, itemID, difficulty, instanceID)
    if not encounterID or not itemID then return nil end

    local difficultyID = DIFFICULTY[difficulty or ""] or 16
    local key = encounterID .. ":" .. difficultyID

    local table_ = lootCache[key]
    if not table_ then
        -- La lecture passe par Journal.Read : il pose l'etat, lit, puis rend au joueur la
        -- selection qu'il avait. On reglait ici directement, et un joueur avec le journal
        -- ouvert voyait sa selection changer sans avoir rien demande.
        table_ = ns.Journal.Read(instanceID, difficultyID, encounterID, function()
            local found = {}

            local count = 0
            local getNum = (C_EncounterJournal and C_EncounterJournal.GetNumLoot) or EJ_GetNumLoot
            if type(getNum) == "function" then
                local ok, value = pcall(getNum)
                if ok then count = value or 0 end
            end

            local getLoot = (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex)
                or EJ_GetLootInfoByIndex
            for index = 1, count do
                if type(getLoot) ~= "function" then break end
                local ok, info = pcall(getLoot, index)
                -- Selon la version, l'API rend une table ou une suite de valeurs : on accepte
                -- les deux plutot que de parier sur une forme.
                if ok and type(info) == "table" then
                    local id = info.itemID
                    local link = info.itemLink or info.link
                    if id and link then found[id] = link end
                end
            end

            return found
        end)

        -- Le journal peut etre indisponible — ouvert par le joueur, notamment. Un echec
        -- ne se met PAS en cache : la prochaine ouverture reussira, et mettre une table
        -- vide en cache figerait « pas de butin » pour toute la session.
        if not table_ then return nil end
        lootCache[key] = table_
    end

    return table_[itemID]
end

--- Nom d'une rencontre depuis son identifiant de journal, ou nil.
---
--- Les noms de profileset de Raidbots portent l'instance et la rencontre du journal des
--- aventures. Le client sait les traduire : aucune table de boss n'est embarquee, et le nom
--- sort dans la langue du joueur.
function Sim.EncounterName(encounterID)
    if not encounterID or encounterID == 0 then return nil end
    if type(EJ_GetEncounterInfo) ~= "function" then return nil end
    local ok, name = pcall(EJ_GetEncounterInfo, encounterID)
    return (ok and type(name) == "string" and name ~= "") and name or nil
end

function Sim.InstanceName(instanceID)
    if not instanceID or instanceID == 0 then return nil end
    if type(EJ_GetInstanceInfo) ~= "function" then return nil end
    local ok, name = pcall(EJ_GetInstanceInfo, instanceID)
    return (ok and type(name) == "string" and name ~= "") and name or nil
end

--- Gains simules regroupes par rencontre, chaque groupe trie par gain decroissant.
---
--- C'est la base de la vue « table de loot par boss » : l'ensemble des objets qu'un
--- droptimizer a simules POUR une rencontre est sa table de butin, telle que Raidbots l'a
--- vue. On ne fabrique donc aucune liste de butin, on lit celle qui a ete simulee.
---
--- @return table|nil { { encounter, instance, name, items = { { id, percent, slot, ilvl } } } }
function Sim.ByEncounter()
    if not Sim.Available() then return nil end

    local groups, order = {}, {}
    local best = {}

    for _, report in pairs(SpecAnalyserSim) do
        for itemID, entry in pairs(report.items or {}) do
            -- Un objet peut figurer dans plusieurs rapports : on garde le meilleur gain,
            -- comme ailleurs, plutot que le dernier lu.
            local kept = best[itemID]
            if not kept or (entry.percent or 0) > (kept.percent or 0) then
                best[itemID] = { id = itemID, percent = entry.percent or 0,
                    slot = entry.slot, ilvl = entry.ilvl,
                    encounter = entry.encounter or 0, instance = entry.instance or 0,
                    difficulty = entry.difficulty }
            end
        end
    end

    for _, item in pairs(best) do
        local key = item.encounter
        if not groups[key] then
            groups[key] = {
                encounter = key,
                instance = item.instance,
                name = Sim.EncounterName(key),
                items = {},
            }
            table.insert(order, groups[key])
        end
        table.insert(groups[key].items, item)
    end

    for _, group in ipairs(order) do
        table.sort(group.items, function(a, b) return a.percent > b.percent end)
        group.best = group.items[1] and group.items[1].percent or 0
    end

    -- Les rencontres les plus payantes en tete : c'est la question que se pose un raid.
    table.sort(order, function(a, b) return a.best > b.best end)
    return #order > 0 and order or nil
end
