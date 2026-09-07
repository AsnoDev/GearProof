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

-- Palier d'extension d'une instance, retenu une fois trouve.
--
-- `EJ_SelectInstance` ne trouve une instance que dans le palier COURANT du journal. Rien
-- ne le disait ici : `Journal.Read` capturait et restaurait le palier, mais ne le reglait
-- jamais. Tant que le joueur etait sur le palier de la saison en cours et que le
-- droptimizer couvrait cette meme saison, ca marchait par coincidence.
--
-- Au changement de saison, la coincidence tombe : le journal s'ouvre sur le nouveau
-- palier, le droptimizer decrit l'ancien, `EJ_SelectInstance` echoue en silence — aucune
-- erreur, juste une table de butin vide. `Sim.LootLink` rend alors nil, l'infobulle
-- retombe sur `SetItemByID` qui ne connait que le modele, et affiche « niveau 44 » sur une
-- piece de raid. C'est le bug du 44, et il revient a chaque saison.
local tierOfInstance = {}

local function findTier(instanceID)
    local cached = tierOfInstance[instanceID]
    if cached then return cached end

    if type(EJ_GetNumTiers) ~= "function" or type(EJ_SelectTier) ~= "function" then
        return nil
    end

    local ok, count = pcall(EJ_GetNumTiers)
    if not ok or not count then return nil end

    -- Du plus RECENT au plus ancien : la saison en cours est le cas courant, et une
    -- recherche qui commence par le bon palier ne coute qu'une iteration.
    for tier = count, 1, -1 do
        pcall(EJ_SelectTier, tier)
        local index = 1
        while true do
            local fine, id = pcall(EJ_GetInstanceByIndex, index, true)
            if not fine or not id then break end
            if id == instanceID then
                tierOfInstance[instanceID] = tier
                return tier
            end
            index = index + 1
        end
    end
    return nil
end

local function selectInstance(instanceID)
    if not instanceID or instanceID <= 0 then return end
    if type(EJ_SelectInstance) ~= "function" then return end

    -- Le palier D'ABORD, l'instance ensuite : dans l'autre ordre, la selection porte sur
    -- un palier qui ne contient pas l'instance et ne fait rien.
    local tier = findTier(instanceID)
    if tier and type(EJ_SelectTier) == "function" then
        pcall(EJ_SelectTier, tier)
    end
    pcall(EJ_SelectInstance, instanceID)
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
    -- Meme ordre qu'a la pose, et pour la meme raison : l'instance porte la difficulte.
    -- Dans l'autre sens on rendait au joueur son instance avec la difficulte par defaut.
    selectInstance(state.instance)
    setDifficulty(state.difficulty)
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

    -- L'ORDRE : palier, instance, difficulte, rencontre.
    --
    -- `EJ_SetDifficulty` porte sur l'instance SELECTIONNEE, et selectionner une instance
    -- remet sa difficulte par defaut. Regler la difficulte d'abord la posait donc sur
    -- l'instance precedente, et la selection suivante l'effacait : on lisait la table de
    -- butin de la difficulte par defaut en croyant lire celle du droptimizer. C'est la
    -- meme lecon qu'un cran plus haut dans ce fichier — « le palier D'ABORD, l'instance
    -- ensuite » — appliquee un cran plus bas.
    selectInstance(instanceID)
    setDifficulty(difficultyID)
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

local raidCache, encounterCache, lootCache, portraitCache = nil, {}, {}, {}
local dungeonCache, sourceCache, linkCache = nil, nil, nil

--- Portrait d'un boss, comme le journal l'affiche.
---
--- Vivait en local dans `RaidView`. L'onglet Guilde en a besoin pour la meme chose : ce
--- fichier est par convention le SEUL acces au journal des aventures, et un second lecteur
--- aurait porte son propre cache et sa propre facon de rater.
---
--- Mis en cache par rencontre. La version d'origine reglait le journal a CHAQUE boss et a
--- CHAQUE rafraichissement — une dizaine de changements d'etat par ouverture d'onglet, sur
--- une interface partagee avec le joueur. Un portrait ne change pas.
--- @return string|nil chemin de texture
function Journal.Portrait(instanceID, encounterID)
    if not encounterID then return nil end

    local cached = portraitCache[encounterID]
    if cached then return cached end

    if type(EJ_GetCreatureInfo) ~= "function" then return nil end

    local portrait = Journal.Read(instanceID, nil, nil, function()
        -- EJ_GetCreatureInfo : id, nom, description, displayInfo, iconImage.
        local results = { pcall(EJ_GetCreatureInfo, 1, encounterID) }
        return results[1] and results[1 + 5] or nil
    end)

    -- SEUL un succes est mis en cache.
    --
    -- Memoriser l'echec sous forme de `false` pour ne pas relire a chaque rendu condamnait
    -- le portrait pour toute la session : `Journal.Read` rend nil dans deux cas
    -- parfaitement temporaires — journal pas encore initialise, ou joueur qui l'a ouvert,
    -- auquel cas on s'abstient de toucher a sa selection. C'est la cause des points
    -- d'interrogation a la place des boss.
    if portrait then portraitCache[encounterID] = portrait end
    return portrait
end

--- Instances de l'extension en cours, raids ou donjons.
---
--- `EJ_GetInstanceByIndex(index, isRaid)` est le meme appel pour les deux : le second
--- argument decide. Ecrire deux fonctions presque identiques est exactement la duplication
--- qui a le plus coute dans ce depot — deux lecteurs du journal divergeant sur un detail
--- invisible.
--- @param isRaid boolean
--- @return table { { id, name }, ... }
local function instancesOfTier(isRaid)
    if type(EJ_GetInstanceByIndex) ~= "function" then return {} end

    return Journal.Read(nil, nil, nil, function()
        local list = {}
        -- Le journal se positionne sur le palier courant : sans ca, il rend le palier
        -- que le joueur regardait, qui peut etre une extension d'il y a dix ans.
        if type(EJ_SelectTier) == "function" and type(EJ_GetNumTiers) == "function" then
            local ok, count = pcall(EJ_GetNumTiers)
            if ok and count then pcall(EJ_SelectTier, count) end
        end

        for index = 1, 40 do
            local ok, instanceID, name = pcall(EJ_GetInstanceByIndex, index, isRaid)
            if not ok or not instanceID then break end
            table.insert(list, { id = instanceID, name = name })
        end
        return list
    end) or {}
end

--- Donjons de l'extension en cours.
---
--- Ils ne servent pas a lister du contenu : ils servent a savoir D'OU TOMBE un objet.
--- Voir `Journal.ItemSource`.
function Journal.Dungeons()
    if dungeonCache then return dungeonCache end
    local found = instancesOfTier(false)
    if #found > 0 then dungeonCache = found end
    return found
end

--- Raids de l'extension en cours.
---
--- Un echec n'est PAS mis en cache : le journal peut ne pas etre initialise au premier
--- affichage, ou le joueur peut l'avoir ouvert — deux etats parfaitement temporaires.
--- @return table { { id, name }, ... }
function Journal.Raids()
    if raidCache then return raidCache end
    local found = instancesOfTier(true)
    if #found > 0 then raidCache = found end
    return found
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

    -- La CLASSE fait partie de la cle : sans elle, une lecture filtree et une lecture
    -- non filtree partagent la meme entree et la premiere arrivee decide pour l'autre.
    local key = table.concat({ encounterID, difficultyID or 0, classID or 0, specID or 0 }, ":")
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

    -- Comme pour `Sim.LootLink` : un resultat VIDE n'est pas un resultat. Le journal
    -- charge son butin de facon asynchrone, et la premiere lecture apres selection rend
    -- toujours zero. Le mettre en cache figerait « ce boss ne donne rien ».
    if found and next(found) then lootCache[key] = found end
    return found or {}
end

--- Butin de tout un RAID, sans passer par une rencontre.
---
--- Le journal a deux niveaux de table de butin : celle d'un boss, et celle de l'instance
--- entiere — l'onglet « Butin » du journal, quand aucune rencontre n'est ouverte. Les
--- deux ne contiennent pas la meme chose : une piece d'ensemble de CLASSE peut ne pas
--- etre rattachee a un boss, et n'apparaitre que dans la table de l'instance. C'est la
--- piste qui restait apres avoir corrige l'ordre de selection : une piece mythique
--- retombait sur son modele — niveau 219 pour un objet qui tombe a 344 — parce qu'aucun
--- lien ne sortait de la table du boss.
---
--- MEME PRUDENCE que `Journal.Loot` : un resultat vide n'est pas mis en cache, le journal
--- chargeant son butin de facon asynchrone.
--- @return table { { id, link, slot, armorType }, ... }
function Journal.InstanceLoot(instanceID, difficultyID, classID, specID)
    if not instanceID or instanceID <= 0 then return {} end

    local key = table.concat({ "i", instanceID, difficultyID or 0, classID or 0, specID or 0 }, ":")
    if lootCache[key] then return lootCache[key] end

    local found = Journal.Read(instanceID, difficultyID, nil, function()
        if classID and type(EJ_SetLootFilter) == "function" then
            pcall(EJ_SetLootFilter, classID, specID or 0)
            -- Le filtre ne s'applique qu'a la prochaine selection : on repose l'instance.
            if type(EJ_SelectInstance) == "function" then
                pcall(EJ_SelectInstance, instanceID)
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

    if found and next(found) then lootCache[key] = found end
    return found or {}
end

--- D'OU TOMBE un objet : "raid", "dungeon", ou nil quand on ne sait pas.
---
--- LA QUESTION QUE LE RELEVE NE PEUT PAS TRANCHER. Warcraft Logs dit ce que les meilleurs
--- PORTENT, pas d'ou l'objet vient. Or un raideur porte son bijou de raid en donjon : une
--- liste « bijoux vus en mythique+ » melangeait donc des objets obtenables en cle et des
--- objets qui n'y tombent jamais. Pour un joueur qui ne raide pas, c'est le contraire
--- d'une reponse.
---
--- Le client, lui, sait : le journal des aventures porte la table de butin de chaque
--- instance. On construit l'index UNE fois, a la demande, et sans filtre de classe — la
--- provenance d'un objet ne depend pas de qui le regarde.
---
--- PRUDENCE DE LECTURE, la meme que partout ici : le journal charge son butin de facon
--- asynchrone. Un index qui ne trouve RIEN n'est pas mis en cache, sinon la premiere
--- consultation de la session figerait « aucune provenance connue » jusqu'au /reload.
--- @return string|nil
function Journal.ItemSource(itemID)
    if not itemID then return nil end

    if not sourceCache then
        local index, links, found = {}, {}, false

        -- Le RAID d'abord : en cas de doublon, un objet qui tombe des deux cotes est
        -- annonce comme butin de donjon, qui est le contenu le plus accessible. Dire a un
        -- joueur qu'il doit raider pour un objet qu'une cle lui donne serait le seul sens
        -- ou l'erreur coute quelque chose.
        local function absorb(instances, label)
            for _, instance in ipairs(instances) do
                for _, loot in ipairs(Journal.InstanceLoot(instance.id, nil, nil, nil)) do
                    if loot.id then
                        index[loot.id], found = label, true
                        -- Le LIEN du journal en meme temps que la provenance : il porte
                        -- les identifiants de bonus, donc le vrai niveau et les vraies
                        -- statistiques. Sans lui, l'infobulle d'un bijou retombe sur
                        -- `SetItemByID`, qui ne connait que le modele — « niveau 28 » et
                        -- « +7 Agilite » sur un objet qui tombe a 321.
                        if loot.link then links[loot.id] = loot.link end
                    end
                end
            end
        end

        absorb(Journal.Raids(), "raid")
        absorb(Journal.Dungeons(), "dungeon")

        if not found then return nil end
        sourceCache, linkCache = index, links
    end

    return sourceCache[itemID]
end

--- Lien complet d'un objet, s'il figure dans une table de butin du palier courant.
---
--- Meme index que `Journal.ItemSource`, et donc meme prudence : construit a la demande,
--- jamais mis en cache tant qu'il est vide.
--- @return string|nil
function Journal.ItemLink(itemID)
    if not itemID then return nil end
    -- Force la construction de l'index si elle n'a pas encore eu lieu.
    Journal.ItemSource(itemID)
    return linkCache and linkCache[itemID] or nil
end

--- Oublie tout ce qui a ete lu. Le butin depend de la difficulte et de la spe.
function Journal.Invalidate()
    raidCache, encounterCache, lootCache = nil, {}, {}
    dungeonCache, sourceCache, linkCache = nil, nil, nil
end

ns.On("ACTIVE_TALENT_GROUP_CHANGED", Journal.Invalidate)
