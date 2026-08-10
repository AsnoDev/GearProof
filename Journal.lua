local _, ns = ...

local Journal = {}
ns.Journal = Journal

-- Acces au journal des aventures.
--
-- Le journal est un objet a ETAT, et cet etat est celui du JOUEUR : l'instance choisie,
-- la difficulte, la rencontre ouverte. Trois fichiers le reglaient directement pour lire
-- une table de butin ou un portrait de boss — `Sim.LootLink`, `RaidView.bossPortrait`,
-- ce dernier a chaque boss et a chaque rafraichissement. Un joueur qui avait le journal
-- ouvert voyait sa selection sauter sous ses yeux.
--
-- Tout passe maintenant par ici, et ce qui a ete trouve est remis en place.

local function selectInstance(instanceID)
    if instanceID and instanceID > 0 and type(EJ_SelectInstance) == "function" then
        pcall(EJ_SelectInstance, instanceID)
    end
end

local function selectEncounter(encounterID)
    if encounterID and encounterID > 0 and type(EJ_SelectEncounter) == "function" then
        pcall(EJ_SelectEncounter, encounterID)
    end
end

local function setDifficulty(difficultyID)
    if difficultyID and type(EJ_SetDifficulty) == "function" then
        pcall(EJ_SetDifficulty, difficultyID)
    end
end

--- Etat courant du journal, pour pouvoir le rendre.
--- @return table|nil
local function capture()
    local state = {}
    if type(EJ_GetCurrentInstance) == "function" then
        local ok, instanceID = pcall(EJ_GetCurrentInstance)
        if ok then state.instance = instanceID end
    end
    if type(EJ_GetDifficulty) == "function" then
        local ok, difficultyID = pcall(EJ_GetDifficulty)
        if ok then state.difficulty = difficultyID end
    end
    -- Le FILTRE de butin fait partie de l'etat que le joueur a regle. Lire le butin
    -- d'une spe en particulier le change ; ne pas le rendre reviendrait a decider a sa
    -- place de ce qu'il voit dans son propre journal.
    if type(EJ_GetLootFilter) == "function" then
        local ok, classID, specID = pcall(EJ_GetLootFilter)
        if ok then state.filterClass, state.filterSpec = classID, specID end
    end
    if type(EJ_GetCurrentTier) == "function" then
        local ok, tier = pcall(EJ_GetCurrentTier)
        if ok then state.tier = tier end
    end
    return state
end

local function restore(state)
    if not state then return end
    if state.tier and type(EJ_SelectTier) == "function" then
        pcall(EJ_SelectTier, state.tier)
    end
    if state.filterClass and type(EJ_SetLootFilter) == "function" then
        pcall(EJ_SetLootFilter, state.filterClass, state.filterSpec)
    end
    setDifficulty(state.difficulty)
    selectInstance(state.instance)
end

--- Le joueur a-t-il le journal sous les yeux ?
---
--- Quand c'est le cas on ne touche a rien du tout : meme restauree, une selection qui
--- part et revient produit un scintillement, et la restauration ne rend pas la RENCONTRE
--- ouverte — aucune API publique ne la lit.
local function playerIsLooking()
    local frame = _G.EncounterJournal
    return frame and frame.IsShown and frame:IsShown() and true or false
end

--- Regle le journal, lit, puis remet ce qui etait en place.
---
--- @param reader function appelee une fois le journal positionne
--- @return any resultat de `reader`, ou nil si le journal est occupe ou l'appel echoue
function Journal.Read(instanceID, difficultyID, encounterID, reader)
    if playerIsLooking() then return nil end
    if type(reader) ~= "function" then return nil end

    local previous = capture()

    setDifficulty(difficultyID)
    selectInstance(instanceID)
    selectEncounter(encounterID)

    local ok, result = pcall(reader)

    -- Restauration inconditionnelle : `reader` a le droit d'echouer, pas de laisser
    -- l'interface du joueur dans un etat qu'il n'a pas demande.
    restore(previous)

    return ok and result or nil
end

-- ------------------------------------------------------ lecture des raids
--
-- Ce que le jeu sait deja, et que l'addon n'exploitait pas.
--
-- L'onglet Raid ne montrait rien tant qu'un droptimizer n'avait pas ete importe — donc
-- rien du tout pour qui n'a pas l'outil Python. Or le client CONNAIT la table de butin
-- de chaque boss : c'est ce que le journal des aventures affiche. `Sim.LootLink` s'en
-- servait deja, uniquement pour decorer des lignes venues d'ailleurs.
--
-- Tout passe par `Journal.Read` : etat pose, lu, rendu. Et tout est mis en cache — le
-- journal est un objet a etat, le consulter coute cher, et une table de butin ne change
-- pas en cours de session.

local raidCache, encounterCache, lootCache = nil, {}, {}

--- Raids de l'extension en cours.
--- @return table { { id, name }, ... }
function Journal.Raids()
    if raidCache then return raidCache end
    if type(EJ_GetInstanceByIndex) ~= "function" then return {} end

    local found = Journal.Read(nil, nil, nil, function()
        local list = {}
        -- Le journal se positionne sur le palier courant : sans ca, il rend le palier
        -- que le joueur regardait, qui peut etre une extension d'il y a dix ans.
        if type(EJ_SelectTier) == "function" and type(EJ_GetNumTiers) == "function" then
            local ok, count = pcall(EJ_GetNumTiers)
            if ok and count then pcall(EJ_SelectTier, count) end
        end

        for index = 1, 40 do
            local ok, instanceID, name = pcall(EJ_GetInstanceByIndex, index, true)
            if not ok or not instanceID then break end
            table.insert(list, { id = instanceID, name = name })
        end
        return list
    end)

    -- Un echec n'est PAS mis en cache : le journal peut ne pas etre initialise au
    -- premier affichage, ou le joueur peut l'avoir ouvert.
    if found and #found > 0 then raidCache = found end
    return found or {}
end

--- Rencontres d'un raid, dans l'ordre du journal.
--- @return table { { id, name }, ... }
function Journal.Encounters(instanceID)
    if not instanceID then return {} end
    if encounterCache[instanceID] then return encounterCache[instanceID] end
    if type(EJ_GetEncounterInfoByIndex) ~= "function" then return {} end

    local found = Journal.Read(instanceID, nil, nil, function()
        local list = {}
        for index = 1, 30 do
            local ok, name, _, encounterID = pcall(EJ_GetEncounterInfoByIndex, index, instanceID)
            if not ok or not encounterID then break end
            table.insert(list, { id = encounterID, name = name })
        end
        return list
    end)

    if found and #found > 0 then encounterCache[instanceID] = found end
    return found or {}
end

--- Butin d'une rencontre, filtre sur la specialisation jouee.
---
--- `EJ_SetLootFilter` est ce qui evite de proposer des plaques a un mage : le client
--- connait deja les restrictions de classe et d'armure, il n'y a rien a redevelopper.
--- @return table { { id, link, slot, armorType }, ... }
function Journal.Loot(instanceID, encounterID, difficultyID, classID, specID)
    if not encounterID then return {} end

    local key = table.concat({ encounterID, difficultyID or 0, specID or 0 }, ":")
    if lootCache[key] then return lootCache[key] end

    local found = Journal.Read(instanceID, difficultyID, encounterID, function()
        if classID and type(EJ_SetLootFilter) == "function" then
            pcall(EJ_SetLootFilter, classID, specID or 0)
            -- Le filtre ne s'applique qu'a la prochaine selection.
            if type(EJ_SelectEncounter) == "function" then
                pcall(EJ_SelectEncounter, encounterID)
            end
        end

        local count = 0
        local getNum = (C_EncounterJournal and C_EncounterJournal.GetNumLoot) or EJ_GetNumLoot
        if type(getNum) == "function" then
            local ok, value = pcall(getNum)
            if ok then count = value or 0 end
        end

        local getLoot = (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex)
            or EJ_GetLootInfoByIndex
        if type(getLoot) ~= "function" then return {} end

        local list = {}
        for index = 1, count do
            local ok, info = pcall(getLoot, index)
            if ok and type(info) == "table" and info.itemID then
                table.insert(list, {
                    id = info.itemID,
                    link = info.itemLink or info.link,
                    slot = info.slot,
                    armorType = info.armorType,
                })
            end
        end
        return list
    end)

    if found then lootCache[key] = found end
    return found or {}
end

--- Oublie tout ce qui a ete lu. Le butin depend de la difficulte et de la spe.
function Journal.Invalidate()
    raidCache, encounterCache, lootCache = nil, {}, {}
end

ns.On("ACTIVE_TALENT_GROUP_CHANGED", Journal.Invalidate)
