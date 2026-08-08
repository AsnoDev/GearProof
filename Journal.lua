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
    return state
end

local function restore(state)
    if not state then return end
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
