local _, ns = ...

local Gear = {}
ns.Gear = Gear

local L = ns.L

-- L'equipement n'est pas une donnee de combat : le lire reste autorise depuis Midnight.

-- Emplacements verifies. `enchant = true` signifie "doit porter un enchantement".
-- Si un patch ajoute un emplacement enchantable (rune de tete, epaules...), il suffit
-- d'ajouter une ligne ici. `simc` est le nom attendu par SimulationCraft.
Gear.SLOTS = {
    { slot = "HeadSlot",          label = "Head",        simc = "head" },
    { slot = "NeckSlot",          label = "Neck",     simc = "neck" },
    { slot = "ShoulderSlot",      label = "Shoulders",     simc = "shoulder" },
    { slot = "BackSlot",          label = "Cloak",        simc = "back",      enchant = true,     hint = "stat enchant" },
    { slot = "ChestSlot",         label = "Chest",       simc = "chest",     enchant = true,     hint = "stat enchant" },
    { slot = "WristSlot",         label = "Wrists",   simc = "wrist",     enchant = true,     hint = "stat enchant" },
    { slot = "HandsSlot",         label = "Hands",       simc = "hands" },
    { slot = "WaistSlot",         label = "Waist",    simc = "waist" },
    { slot = "LegsSlot",          label = "Legs",      simc = "legs",      enchant = true,     hint = "leg armor" },
    { slot = "FeetSlot",          label = "Feet",      simc = "feet",      enchant = true,     hint = "stat enchant" },
    { slot = "Finger0Slot",       label = "Ring 1",    simc = "finger1",   enchant = true,     hint = "stat enchant" },
    { slot = "Finger1Slot",       label = "Ring 2",    simc = "finger2",   enchant = true,     hint = "stat enchant" },
    { slot = "Trinket0Slot",      label = "Trinket 1",     simc = "trinket1" },
    { slot = "Trinket1Slot",      label = "Trinket 2",     simc = "trinket2" },
    { slot = "MainHandSlot",      label = "Weapon",        simc = "main_hand", enchant = true,     hint = "weapon enchant" },
    { slot = "SecondaryHandSlot", label = "Off hand", simc = "off_hand",  enchant = "weapon", hint = "weapon enchant" },
}

-- Seuils de rendement decroissant, en points de statistique (patch 12.0.7).
-- Ce sont des donnees de patch : a revoir a chaque extension.
Gear.DIMINISHING = {
    haste       = { 1320, 1760, 2200 },
    mastery     = { 1380, 1840, 2300 },
    crit        = { 1380, 1840, 2300 },
    versatility = { 1620, 2160, 2700 },
}

Gear.STATS = {
    { key = "haste",       label = "Haste" },
    { key = "crit",        label = "Crit" },
    { key = "mastery",     label = "Mastery" },
    { key = "versatility", label = "Versatility" },
}

-- GetItemInfo renvoie 17 valeurs ; on ne garde que la 1re, la 3e, la 9e et la 16e.
-- Compter les positions a la main est une source d'erreur : on passe par une table.
local ITEM_INFO_NAME, ITEM_INFO_QUALITY, ITEM_INFO_EQUIPLOC, ITEM_INFO_SETID = 1, 3, 9, 16

local function itemInfo(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo or not link then return nil end

    -- results[1] est le booleen de pcall : les valeurs de GetItemInfo commencent a 2.
    -- On indexe directement plutot que de retirer l'element : un nil au milieu creerait
    -- un trou dans la table et decalerait tout.
    local results = { pcall(getInfo, link) }
    if not results[1] then return nil end

    return {
        name = results[1 + ITEM_INFO_NAME],
        quality = results[1 + ITEM_INFO_QUALITY],
        equipLoc = results[1 + ITEM_INFO_EQUIPLOC],
        setID = results[1 + ITEM_INFO_SETID],
    }
end

-- Champs de la chaine d'objet, dans l'ordre (warcraft.wiki.gg/wiki/ItemString) :
--   itemID, enchantID, gem1..gem4, suffixID, uniqueID, linkLevel, specializationID,
--   modifiersMask, itemContext, numBonusIDs[, bonusID...], numModifiers[, type, valeur...]
-- Le compteur de bonus est donc le 13e champ. L'avoir lu au 14e produisait un
-- `bonus_id` amputé de son premier identifiant et pollué par le bloc de modificateurs,
-- ce qui suffisait a fausser une simulation.
local LINK_ITEM_ID, LINK_ENCHANT_ID = 1, 2
local LINK_GEM_FIRST, LINK_GEM_LAST = 3, 6
local LINK_BONUS_COUNT = 13

-- Garde-fou : si le decoupage derape, un compteur absurde arrete la lecture au lieu de
-- balayer toute la chaine.
local MAX_LIST = 32

-- Modificateurs que SimulationCraft attend nommement.
local MOD_CONTENT_TUNING = 28
local MOD_CRAFTED_STAT_1, MOD_CRAFTED_STAT_2 = 29, 30
local MOD_CRAFTING_QUALITY = 38

--- Extrait enchantement, gemmes, bonus et modificateurs de la chaine d'objet.
local function parseLink(link)
    local itemString = link and link:match("|Hitem:([%-%d:]+)")
    if not itemString then return nil end

    local parts = { strsplit(":", itemString) }
    local function number(index)
        return tonumber(parts[index]) or 0
    end

    local gems = {}
    for index = LINK_GEM_FIRST, LINK_GEM_LAST do
        local gem = number(index)
        if gem > 0 then table.insert(gems, gem) end
    end

    local bonuses = {}
    local bonusCount = number(LINK_BONUS_COUNT)
    if bonusCount < 0 or bonusCount > MAX_LIST then bonusCount = 0 end
    for index = LINK_BONUS_COUNT + 1, LINK_BONUS_COUNT + bonusCount do
        local bonus = tonumber(parts[index])
        if bonus then table.insert(bonuses, bonus) end
    end

    -- Le bloc de modificateurs suit les identifiants de bonus, par paires (type, valeur).
    local modifiers = {}
    local countIndex = LINK_BONUS_COUNT + bonusCount + 1
    local modifierCount = number(countIndex)
    if modifierCount > 0 and modifierCount <= MAX_LIST then
        for pair = 0, modifierCount - 1 do
            local kind = tonumber(parts[countIndex + 1 + pair * 2])
            local value = tonumber(parts[countIndex + 2 + pair * 2])
            if kind and value then modifiers[kind] = value end
        end
    end

    local craftedStats = {}
    for _, key in ipairs({ MOD_CRAFTED_STAT_1, MOD_CRAFTED_STAT_2 }) do
        if modifiers[key] then table.insert(craftedStats, modifiers[key]) end
    end

    return {
        itemID = number(LINK_ITEM_ID),
        enchantID = number(LINK_ENCHANT_ID),
        gems = gems,
        bonuses = bonuses,
        contentTuning = modifiers[MOD_CONTENT_TUNING],
        craftedStats = craftedStats,
        -- La qualite d'artisanat est un palier de 1 a 5 ; hors de cette plage, la valeur
        -- lue n'est pas ce qu'on croit et il vaut mieux ne rien ecrire.
        craftingQuality = (modifiers[MOD_CRAFTING_QUALITY] or 0) >= 1
            and (modifiers[MOD_CRAFTING_QUALITY] or 0) <= 5
            and modifiers[MOD_CRAFTING_QUALITY] or nil,
    }
end

--- Meme lecture, pour un objet qui n'est pas porte (sacs, banque).
function Gear.ParseLink(link)
    return parseLink(link)
end

local function socketCount(link)
    local stats
    if C_Item and C_Item.GetItemStats then
        local ok, result = pcall(C_Item.GetItemStats, link)
        if ok then stats = result end
    end
    if not stats and type(GetItemStats) == "function" then
        local ok, result = pcall(GetItemStats, link)
        if ok then stats = result end
    end
    if type(stats) ~= "table" then return 0 end

    local total = 0
    for key, value in pairs(stats) do
        if type(key) == "string" and key:find("EMPTY_SOCKET", 1, true) then
            total = total + (tonumber(value) or 0)
        end
    end
    return total
end

local function itemLevel(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and level then return level end
    end
    return nil
end

local function durability(slotID)
    local ok, current, maximum = pcall(GetInventoryItemDurability, slotID)
    if ok and current and maximum and maximum > 0 then
        return current / maximum
    end
    return nil
end

function Gear.IsIgnored(slotName)
    ns.db.ignoredSlots = ns.db.ignoredSlots or {}
    return ns.db.ignoredSlots[slotName] == true
end

function Gear.SetIgnored(slotName, ignored)
    ns.db.ignoredSlots = ns.db.ignoredSlots or {}
    ns.db.ignoredSlots[slotName] = ignored and true or nil
    Gear.Invalidate()
end

--- Reactive toutes les alertes ignorees.
--- Passe par ici plutot que d'ecrire `ns.db.ignoredSlots` en direct : le cache d'audit
--- doit tomber en meme temps que le reglage, sinon la vue se redessine sur l'ancien.
function Gear.ResetIgnored()
    ns.db.ignoredSlots = {}
    Gear.Invalidate()
end

--- Verifie les deux armes ENSEMBLE, pas chacune de son cote.
---
--- Un releve par emplacement dit « 8041 en main droite chez 16 des 20 meilleurs, 12 en main
--- gauche » et laisse croire a un enchantement unique. Par joueur, la meme mesure donne 11
--- paires mixtes 7983+8041 contre 8 doubles 8041 : 60 % en portent deux DIFFERENTS. Exiger
--- le meme des deux cotes serait donc faux pour la majorite.
---
--- On ne signale rien si une arme n'a pas d'enchantement du tout : c'est deja compte par
--- emplacement, et le dire deux fois gonflerait la liste de correctifs.
local function auditWeaponPair(bySlot, summary)
    summary.weaponPair = 0

    local main, off = bySlot.MainHandSlot, bySlot.SecondaryHandSlot
    if not main or not off or not main.link or not off.link then return end
    if main.ignored or off.ignored then return end

    local ok, best, mixed = ns.Meta.WeaponPairAdvice(main.enchantID, off.enchantID)
    if ok == nil then return end

    local info = { ok = ok, best = best, mixed = mixed }
    main.weaponPair, off.weaponPair = info, info

    -- Les deux enchantements manquent-ils ? Alors le probleme est ailleurs.
    if (main.enchantID or 0) == 0 or (off.enchantID or 0) == 0 then return end
    if ok then return end

    summary.weaponPair = 1
    main.pairMismatch = true
    table.insert(main.problems, string.format(L["weapon enchant combination not in the top %d"],
        ns.Meta.Sample()))
end

--- Analyse l'equipement porte. Lecture brute, sans cache : passer par `Gear.Scan`.
--- @return table entries, table summary
local function rawScan()
    local entries = {}
    local summary = {
        missingEnchants = 0,
        emptySockets = 0,
        emptySlots = 0,
        damaged = 0,
        ignored = 0,
        checked = 0,
        sets = {},
    }

    for _, definition in ipairs(Gear.SLOTS) do
        local slotID = GetInventorySlotInfo(definition.slot)
        local link = slotID and GetInventoryItemLink("player", slotID)
        local ignored = Gear.IsIgnored(definition.slot)

        local entry = {
            slot = definition.slot,
            slotID = slotID,
            label = definition.label,
            simc = definition.simc,
            link = link,
            ignored = ignored,
            problems = {},
        }

        if not link then
            if definition.slot ~= "SecondaryHandSlot" then
                entry.empty = true
                table.insert(entry.problems, L["empty slot"])
                if not ignored then summary.emptySlots = summary.emptySlots + 1 end
            else
                entry.skipped = true
            end
        else
            summary.checked = summary.checked + 1

            local info = itemInfo(link) or {}
            local parsed = parseLink(link) or { enchantID = 0, gems = {}, bonuses = {}, craftedStats = {} }

            entry.itemLevel = itemLevel(link)
            entry.name = info.name
            entry.contentTuning = parsed.contentTuning
            entry.craftedStats = parsed.craftedStats
            entry.craftingQuality = parsed.craftingQuality
            entry.quality = info.quality
            entry.setID = (info.setID and info.setID > 0) and info.setID or nil
            entry.enchantID = parsed.enchantID
            entry.gems = #parsed.gems
            entry.gemIDs = parsed.gems
            entry.bonuses = parsed.bonuses
            entry.itemID = parsed.itemID
            entry.sockets = socketCount(link)
            entry.durability = durability(slotID)

            if entry.setID then
                summary.sets[entry.setID] = (summary.sets[entry.setID] or 0) + 1
            end

            -- Seul le releve decide. La table `enchant` de Gear.SLOTS ne sert plus de repli :
            -- elle a ete mesuree FAUSSE dans les deux sens — elle reclamait Cape et Poignets,
            -- que 0 joueur sur 20 du haut de tableau n'enchante, et ignorait Tete, Epaules et
            -- Mains, enchantees a 65-80 %. Sans releve, on ne reclame RIEN plutot que de
            -- reclamer a cote.
            local expected, known = ns.Meta.ExpectsEnchant(definition.slot)
            entry.needsEnchant = known and expected or false
            local needsEnchant = entry.needsEnchant

            if needsEnchant and entry.enchantID == 0 then
                entry.missingEnchant = true
                table.insert(entry.problems, L["missing enchant"] ..
                    (definition.hint and (" (" .. L[definition.hint] .. ")") or ""))
                if not ignored then summary.missingEnchants = summary.missingEnchants + 1 end
            end

            entry.emptySockets = math.max(0, entry.sockets - entry.gems)
            if entry.emptySockets > 0 then
                table.insert(entry.problems, entry.emptySockets == 1
                    and string.format(L["%d empty socket"], 1)
                    or string.format(L["%d empty sockets"], entry.emptySockets))
                if not ignored then summary.emptySockets = summary.emptySockets + entry.emptySockets end
            end

            if entry.durability and entry.durability < 0.35 then
                entry.damaged = true
                table.insert(entry.problems, string.format(L["durability %d%%"], entry.durability * 100))
                if not ignored then summary.damaged = summary.damaged + 1 end
            end
        end

        if ignored and #entry.problems > 0 then
            summary.ignored = summary.ignored + 1
        end

        table.insert(entries, entry)
    end

    -- Ensemble de classe : le plus grand groupe d'objets partageant un identifiant de set.
    local bestSet, bestCount = nil, 0
    for setID, count in pairs(summary.sets) do
        if count > bestCount then bestSet, bestCount = setID, count end
    end
    summary.setID, summary.setPieces = bestSet, bestCount

    local bySlot = {}
    for _, entry in ipairs(entries) do
        bySlot[entry.slot] = entry
    end
    summary.bySlot = bySlot

    auditWeaponPair(bySlot, summary)

    summary.problems = summary.missingEnchants + summary.emptySockets + summary.emptySlots
        + summary.damaged + summary.weaponPair

    return entries, summary
end

-- Cache d'audit.
--
-- `Gear.Scan` est appele depuis douze endroits, dont cinq fois pour UN SEUL
-- rafraichissement de l'onglet Equipement et une fois par infobulle d'objet survolee.
-- Un scan coute une centaine d'appels d'API : seize liens d'objet, autant de
-- GetItemInfo, de GetDetailedItemLevelInfo, de GetItemStats et de durabilites.
-- Survoler l'hotel des ventes revenait a scanner l'equipement complet par ligne.
--
-- Les tables rendues ne sont mutees par aucun appelant — seul `rawScan` les remplit —
-- donc les partager est sans risque.
--
-- Le TTL n'est pas le mecanisme, c'est le garde-fou : la durabilite baisse en combat
-- sans qu'aucun evenement ne le dise, et une valeur figee mentirait.
local cachedEntries, cachedSummary, cachedAt = nil, nil, 0
local SCAN_TTL = 2

function Gear.Invalidate()
    cachedEntries, cachedSummary, cachedAt = nil, nil, 0
end

--- Analyse l'equipement porte, mise en cache.
--- @return table entries, table summary
function Gear.Scan()
    local now = GetTime()
    if cachedEntries and (now - cachedAt) < SCAN_TTL then
        return cachedEntries, cachedSummary
    end
    cachedEntries, cachedSummary = rawScan()
    cachedAt = now
    return cachedEntries, cachedSummary
end

-- Tout ce qui rend l'audit faux fait tomber le cache, et rien d'autre.
for _, event in ipairs({
    "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_INVENTORY_DURABILITY",
    "SOCKET_INFO_CLOSE",
    "ACTIVE_TALENT_GROUP_CHANGED",
}) do
    ns.On(event, Gear.Invalidate)
end

--- Somme des statistiques brutes d'un objet ou d'une chaine forgee.
local function rawStats(link)
    local stats
    if C_Item and C_Item.GetItemStats then
        local ok, result = pcall(C_Item.GetItemStats, link)
        if ok then stats = result end
    end
    if type(stats) ~= "table" then return 0 end

    local total = 0
    for key, value in pairs(stats) do
        if ns.Weights.STAT_KEYS[key] then
            total = total + (tonumber(value) or 0)
        end
    end
    return total
end

--- Ce qu'un enchantement apporte : ses lignes d'infobulle et leur total en points.
---
--- La source est l'infobulle du client (`Meta.EnchantTooltipLines`) et non
--- `C_Item.GetItemStats` : cette derniere ne rend que les statistiques intrinseques de
--- l'objet et ignore l'enchantement. Comparer ses tables avant/apres retournait donc
--- toujours zero — c'est ce qui laissait l'infobulle sans chiffres et le bloc « a
--- recuperer » sans total.
---
--- Seuls les nombres immediatement suivis d'un mot sont comptes : « +2895 Mastery » oui,
--- « +3.5% » non — un pourcentage ou une duree n'est pas un point de statistique. Les
--- separateurs de milliers, virgule comme espace, sont tolerees.
---
--- Si le client formate autrement (espace insecable de la locale francaise, par exemple),
--- le total retombe a zero et l'interface n'affiche rien : mieux vaut pas de chiffre qu'un
--- chiffre faux.
--- @return number points, table|nil lignes brutes du client
---
--- Mise en cache permanente : le resultat ne depend que du couple (objet, enchantement),
--- et un enchantement ne change pas de valeur en cours de session. Sans cache, deux
--- lectures d'infobulle par enchantement manquant etaient refaites a chaque
--- `Armory.Refresh` — donc a chaque changement de piece et a chaque survol.
local enchantPointsCache = {}

function Gear.EnchantPoints(link, slot, enchantID)
    enchantID = enchantID or ns.Meta.Enchant(slot)
    if not link or not enchantID then return 0, nil end

    -- L'itemID suffit a identifier l'objet : deux exemplaires du meme objet rendent la
    -- meme infobulle d'enchantement, quels que soient leurs bonus.
    local itemID = link:match("|Hitem:(%d+)") or link
    local key = itemID .. ":" .. enchantID

    local hit = enchantPointsCache[key]
    if hit then return hit.points, hit.lines end

    local lines = ns.Meta.EnchantTooltipLines(link, enchantID)
    if not lines then
        -- Un echec vient presque toujours d'un objet pas encore en cache cote client :
        -- on ne memorise pas, la prochaine tentative reussira.
        return 0, nil
    end

    local points = 0
    for _, line in ipairs(lines) do
        for amount in line.text:gmatch("%+(%d[%d,%s]*)%a") do
            points = points + (tonumber((amount:gsub("[^%d]", ""))) or 0)
        end
    end

    enchantPointsCache[key] = { points = points, lines = lines }
    return points, lines
end

local function enchantValue(link, slot)
    if not link then return 0 end
    return (Gear.EnchantPoints(link, slot))
end

--- Points de statistique d'une gemme conseillee.
local function gemValue()
    local gemID = ns.Meta.Gem()
    if not gemID then return 0 end
    return rawStats("item:" .. gemID)
end

--- Ce que l'equipement laisse sur la table.
--- @return number stat, number measured, number fixes
function Gear.Recoverable()
    local entries = Gear.Scan()
    local stat, measured, fixes = 0, 0, 0

    local gem = gemValue()

    for _, entry in ipairs(entries) do
        if not entry.skipped and not entry.ignored then
            if entry.missingEnchant then
                fixes = fixes + 1
                local value = enchantValue(entry.link, entry.slot)
                if value > 0 then
                    stat = stat + value
                    measured = measured + 1
                end
            end

            local sockets = entry.emptySockets or 0
            if sockets > 0 then
                fixes = fixes + sockets
                if gem > 0 then
                    stat = stat + gem * sockets
                    measured = measured + sockets
                end
            end

            if entry.empty or entry.damaged then
                fixes = fixes + 1
            end
        end
    end

    return math.floor(stat), measured, fixes
end

--- Statistiques secondaires courantes, avec leur palier de rendement decroissant.
function Gear.Stats()
    local function rating(id)
        local ok, value = pcall(GetCombatRating, id)
        return (ok and value) or 0
    end
    local function percent(fn, ...)
        if type(fn) ~= "function" then return 0 end
        local ok, value = pcall(fn, ...)
        return (ok and value) or 0
    end

    local values = {
        haste = {
            rating = rating(CR_HASTE_SPELL or 20),
            percent = percent(GetHaste),
        },
        crit = {
            rating = rating(CR_CRIT_SPELL or 11),
            percent = math.max(percent(GetCritChance), percent(GetSpellCritChance, 2)),
        },
        mastery = {
            rating = rating(CR_MASTERY or 26),
            percent = percent(GetMasteryEffect),
        },
        versatility = {
            rating = rating(CR_VERSATILITY_DAMAGE_DONE or 29),
            percent = percent(GetCombatRatingBonus, CR_VERSATILITY_DAMAGE_DONE or 29),
        },
    }

    for key, entry in pairs(values) do
        local thresholds = Gear.DIMINISHING[key] or {}
        entry.tier = 0
        for index, threshold in ipairs(thresholds) do
            if entry.rating >= threshold then entry.tier = index end
        end
        entry.nextThreshold = thresholds[entry.tier + 1]
    end

    return values
end

--- Resume texte, utilise par la commande /sa gear.
function Gear.PrintReport()
    local entries, summary = Gear.Scan()

    if summary.problems == 0 then
        ns.Print("equipement complet : %d pieces, tout est enchante et serti.", summary.checked)
        return
    end

    ns.Print("%d probleme(s) d'equipement :", summary.problems)
    for _, entry in ipairs(entries) do
        if #entry.problems > 0 and not entry.ignored then
            print(string.format("  |cffe3a45c%s|r — %s%s",
                entry.label,
                table.concat(entry.problems, ", "),
                entry.link and (" " .. entry.link) or ""))
        end
    end
end
