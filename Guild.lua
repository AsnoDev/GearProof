local _, ns = ...

local Guild = {}
ns.Guild = Guild

local L = ns.L

-- Onglet Guilde : qui a simule, qui a des enchantements manquants.
--
-- Comment ca marche
-- -----------------
-- Chaque membre equipe de l'addon annonce une fiche compacte sur le canal addon de la
-- guilde : nom, spe, ilvl, nombre de correctifs d'equipement, identifiant de son dernier
-- droptimizer et sa date. Un officier demande la tournee, chacun repond, le tableau se
-- remplit.
--
-- Ce que l'addon NE fait PAS : lire les resultats de simulation. Raidbots est hors du jeu ;
-- l'addon partage l'identifiant du rapport, pas son contenu. L'agregation des resultats se
-- fait cote outil Python, qui sait interroger Raidbots.
--
-- Le partage est explicite : rien ne sort tant que `shareWithGuild` est faux.

local PREFIX = "SPECANALYSER"
local REQUEST = "REQ"
local REPLY = "REP"
local ITEMS = "ITM"
local THROTTLE = 5

-- Un message d'addon est plafonne a 255 octets par le client. Les gains par objet depassent
-- ce plafond, donc ils partent dans des messages distincts, decoupes sur des frontieres de
-- separateur pour qu'un morceau reste analysable seul.
--
-- A dire clairement, parce que la question s'est posee : ces messages passent par
-- `C_ChatInfo.SendAddonMessage` sur le canal "GUILD", qui est un canal de DONNEES. Rien
-- n'apparait dans le chat de guilde, ni pour l'emetteur ni pour les autres, et un joueur sans
-- l'addon ne voit rien du tout.
local CHUNK = 200

local roster, lastRequest = {}, 0
local incoming = {}

local function encode(value)
    return tostring(value or ""):gsub("[|~]", "")
end

--- Fiche du personnage courant, en une ligne compacte.
function Guild.LocalCard()
    local _, summary = ns.Gear.Scan()
    local _, equipped = GetAverageItemLevel()

    -- L'age du DROPTIMIZER, pas celui des poids de statistiques. Le champ s'appelait `simAge`
    -- et portait `Weights.AgeInDays()` : le tableau de guilde affichait donc la fraicheur
    -- d'une chaine Pawn en pretendant parler de simulation.
    local age = ns.SimC.DroptimizerAge()

    -- Rencontres couvertes par le droptimizer local. Ce sont des identifiants de journal, pas
    -- des resultats : aucun pourcentage ne quitte le poste, conformement a la consigne.
    local encounters = {}
    for _, group in ipairs(ns.Sim.ByEncounter() or {}) do
        if group.encounter and group.encounter > 0 then
            table.insert(encounters, group.encounter)
        end
    end
    table.sort(encounters)

    local specName = ""
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if getSpec and getInfo then
        local ok, index = pcall(getSpec)
        if ok and index then
            local fine, _, label = pcall(getInfo, index)
            if fine then specName = label or "" end
        end
    end

    return {
        name = UnitName("player") or "?",
        spec = specName,
        ilvl = equipped and math.floor(equipped + 0.5) or 0,
        fixes = summary.problems or 0,
        sim = (ns.db.droptimizer and ns.db.droptimizer.id) or "",
        simAge = age or -1,
        encounters = encounters,
    }
end

local function serialize(card)
    return table.concat({
        REPLY, encode(card.name), encode(card.spec), card.ilvl,
        card.fixes, encode(card.sim), card.simAge,
        table.concat(card.encounters or {}, "."),
    }, "~")
end

local function deserialize(message)
    local parts = { strsplit("~", message) }
    if parts[1] ~= REPLY then return nil end

    -- Le 8e champ est apparu apres coup : une fiche plus ancienne n'a pas de rencontres, ce
    -- qui doit rester lisible plutot que rejete.
    local encounters = {}
    for id in tostring(parts[8] or ""):gmatch("%d+") do
        table.insert(encounters, tonumber(id))
    end

    return {
        name = parts[2] or "?",
        spec = parts[3] or "",
        ilvl = tonumber(parts[4]) or 0,
        fixes = tonumber(parts[5]) or 0,
        sim = parts[6] or "",
        simAge = tonumber(parts[7]) or -1,
        encounters = encounters,
    }
end

--- Gains simules locaux, groupes par rencontre, en une chaine compacte.
---
--- Format : `encounter:itemID.centiemes.ilvl,...;encounter:...`
--- Les centiemes evitent le point decimal et l'ambiguite de locale : 4,25 % s'ecrit 425.
--- Le niveau voyage avec : sans lui, l'interface retombe sur le niveau du modele d'objet, qui
--- ignore les identifiants de bonus et peut valoir 44 sur une piece de raid.
function Guild.SimPayload()
    local groups = ns.Sim.ByEncounter()
    if not groups then return "" end

    local blocks = {}
    for _, group in ipairs(groups) do
        local items = {}
        for _, item in ipairs(group.items) do
            table.insert(items, string.format("%d.%d.%d",
                item.id, math.floor((item.percent or 0) * 100 + 0.5), item.ilvl or 0))
        end
        if #items > 0 then
            table.insert(blocks, group.encounter .. ":" .. table.concat(items, ","))
        end
    end
    return table.concat(blocks, ";")
end

--- Decoupe une charge utile sur des frontieres de separateur.
local function chunkPayload(payload)
    local chunks = {}
    while #payload > CHUNK do
        -- On coupe au dernier separateur avant la limite : un morceau tronque au milieu d'un
        -- couple objet/valeur produirait un nombre faux, pas une erreur visible.
        local cut = payload:sub(1, CHUNK):match(".*[,;]")
        cut = cut and #cut or CHUNK
        table.insert(chunks, payload:sub(1, cut))
        payload = payload:sub(cut + 1)
    end
    if #payload > 0 then table.insert(chunks, payload) end
    return chunks
end

local function sendSim(card)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end

    local payload = Guild.SimPayload()
    if payload == "" then return end

    local chunks = chunkPayload(payload)
    for index, chunk in ipairs(chunks) do
        pcall(C_ChatInfo.SendAddonMessage, PREFIX,
            table.concat({ ITEMS, encode(card.name), index, #chunks, chunk }, "~"), "GUILD")
    end
end

--- Reconstruit les gains d'un membre a partir de ses morceaux.
local function absorb(name, index, total, chunk)
    local pending = incoming[name]
    if not pending or pending.total ~= total then
        pending = { total = total, parts = {}, seen = 0 }
        incoming[name] = pending
    end

    if not pending.parts[index] then
        pending.parts[index] = chunk
        pending.seen = pending.seen + 1
    end
    if pending.seen < total then return nil end

    local payload = table.concat(pending.parts)
    incoming[name] = nil

    local byEncounter = {}
    for encounter, list in payload:gmatch("(%d+):([^;]+)") do
        local items = {}
        for itemID, centiemes, ilvl in list:gmatch("(%d+)%.(%d+)%.(%d+)") do
            items[tonumber(itemID)] = { percent = tonumber(centiemes) / 100, ilvl = tonumber(ilvl) }
        end
        byEncounter[tonumber(encounter)] = items
    end
    return byEncounter
end

--- Demande a la guilde de se declarer.
function Guild.Request()
    if not IsInGuild() then
        ns.Print(L["you are not in a guild"])
        return false
    end
    if GetTime() - lastRequest < THROTTLE then return false end
    lastRequest = GetTime()

    roster = {}
    incoming = {}
    local card = Guild.LocalCard()
    -- Ses propres gains sont lus directement, sans passer par le canal.
    card.gains = {}
    for _, group in ipairs(ns.Sim.ByEncounter() or {}) do
        local items = {}
        for _, item in ipairs(group.items) do
            items[item.id] = { percent = item.percent, ilvl = item.ilvl }
        end
        card.gains[group.encounter] = items
    end
    roster[card.name] = card

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, REQUEST, "GUILD")
    end
    return true
end

function Guild.Roster()
    local list = {}
    for _, card in pairs(roster) do table.insert(list, card) end
    table.sort(list, function(a, b)
        if a.fixes ~= b.fixes then return a.fixes > b.fixes end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- Age au-dela duquel un droptimizer ne decrit plus l'equipement actuel. Seuil d'AFFICHAGE :
-- un reset hebdomadaire suffit a perimer une simulation.
local STALE_DAYS = 7

--- Etat des droptimizers de la guilde. Repond a « qui en a un, et depuis quand ».
--- @return table { ready, stale, missing, total }, table lignes triees
function Guild.Droptimizers()
    local counts = { ready = 0, stale = 0, missing = 0, total = 0 }
    local list = {}

    for _, card in pairs(roster) do
        counts.total = counts.total + 1

        local state
        if card.sim == "" or card.simAge < 0 then
            state = "missing"
        elseif card.simAge >= STALE_DAYS then
            state = "stale"
        else
            state = "ready"
        end
        counts[state] = counts[state] + 1

        table.insert(list, {
            name = card.name, spec = card.spec, state = state,
            age = card.simAge, sim = card.sim,
            encounters = card.encounters or {},
        })
    end

    -- Manquants d'abord, puis perimes, puis du plus ancien au plus recent : l'ordre dans
    -- lequel un officier veut lire la liste.
    local RANK = { missing = 1, stale = 2, ready = 3 }
    table.sort(list, function(a, b)
        if RANK[a.state] ~= RANK[b.state] then return RANK[a.state] < RANK[b.state] end
        if a.age ~= b.age then return a.age > b.age end
        return (a.name or "") < (b.name or "")
    end)

    return counts, list
end


--- Table de butin par rencontre, avec le classement des membres pour chaque objet.
---
--- Le classement descend du gain simule de chacun. Ces valeurs circulent sur le canal de
--- DONNEES de la guilde, invisible dans le chat : rien n'est affiche a personne qui n'ait
--- l'addon, et le partage reste opt-in.
--- @return table|nil { { encounter, name, items = { { id, best, members = { { name, spec, percent } } } } } }
function Guild.LootByEncounter()
    local groups, order = {}, {}

    for _, card in pairs(roster) do
        for encounter, items in pairs(card.gains or {}) do
            local group = groups[encounter]
            if not group then
                group = { encounter = encounter, name = ns.Sim.EncounterName(encounter),
                    items = {}, index = {} }
                groups[encounter] = group
                table.insert(order, group)
            end

            for itemID, gain in pairs(items) do
                local item = group.index[itemID]
                if not item then
                    item = { id = itemID, members = {}, best = 0, ilvl = gain.ilvl }
                    group.index[itemID] = item
                    table.insert(group.items, item)
                end
                item.ilvl = item.ilvl or gain.ilvl
                table.insert(item.members,
                    { name = card.name, spec = card.spec, percent = gain.percent })
                if gain.percent > item.best then item.best = gain.percent end
            end
        end
    end

    for _, group in ipairs(order) do
        group.index = nil
        group.best = 0
        for _, item in ipairs(group.items) do
            table.sort(item.members, function(a, b) return a.percent > b.percent end)
            if item.best > group.best then group.best = item.best end
        end
        -- Objets par meilleur gain de la guilde : ce qu'il faut viser en priorite.
        table.sort(group.items, function(a, b) return a.best > b.best end)
    end

    table.sort(order, function(a, b) return a.best > b.best end)
    return #order > 0 and order or nil
end

--- Resume texte du roster, pret a coller dans Discord.
function Guild.Export()
    local lines = { "SpecAnalyser — guild audit", "" }
    for _, card in ipairs(Guild.Roster()) do
        local sim = card.sim ~= "" and card.sim or "no sim"
        local age = card.simAge >= 0 and (card.simAge .. "d") or "-"
        table.insert(lines, string.format("%-16s %-12s ilvl %d  %d fix  sim %s (%s)",
            card.name, card.spec, card.ilvl, card.fixes, sim, age))
    end
    return table.concat(lines, "\n")
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

ns.On("CHAT_MSG_ADDON", function(prefix, message, _, sender)
    if prefix ~= PREFIX then return end

    if message == REQUEST then
        -- On ne repond que si le partage est explicitement autorise.
        if ns.db.shareWithGuild ~= true then return end
        local card = Guild.LocalCard()
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            pcall(C_ChatInfo.SendAddonMessage, PREFIX, serialize(card), "GUILD")
        end
        sendSim(card)
        return
    end

    -- Morceau de gains par objet.
    if message:sub(1, #ITEMS + 1) == ITEMS .. "~" then
        local _, name, index, total, chunk = strsplit("~", message, 5)
        local gains = absorb(name or "?", tonumber(index) or 1, tonumber(total) or 1, chunk or "")
        if gains and roster[name] then
            roster[name].gains = gains
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        elseif gains then
            -- Les gains sont arrives avant la fiche : on les garde pour elle.
            incoming[name] = { resolved = gains, total = 0, parts = {}, seen = 0 }
        end
        return
    end

    local card = deserialize(message)
    if card then
        card.sender = sender
        -- Des gains arrives avant la fiche sont recuperes ici.
        local pending = incoming[card.name]
        if pending and pending.resolved then
            card.gains = pending.resolved
            incoming[card.name] = nil
        end
        roster[card.name] = card
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end
end)
