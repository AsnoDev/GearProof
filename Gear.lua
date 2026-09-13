local _, ns = ...

local Gear = {}
ns.Gear = Gear

local L = ns.L

-- L'equipement n'est pas une donnee de combat : le lire reste autorise depuis Midnight.

-- Emplacements verifies, dans l'ordre de lecture de la feuille de personnage.
--
-- `simc` est le nom attendu par SimulationCraft. `hint` precise la NATURE de
-- l'enchantement attendu quand il en manque un — un renfort de jambes n'est pas un
-- enchantement de statistique, et le joueur doit savoir quoi acheter.
--
-- Il y avait ici un champ `enchant`, cense dire quels emplacements doivent porter un
-- enchantement. Il n'etait plus lu par personne, et pour cause : il a ete mesure FAUX
-- dans les deux sens — il reclamait Cape et Poignets, que 0 joueur sur 20 du haut de
-- tableau n'enchante, et ignorait Tete, Epaules et Mains, enchantees a 65-80 %. Seul le
-- releve decide, via `Meta.ExpectsEnchant`. Le champ est retire pour qu'on ne le croie
-- plus vivant.
Gear.SLOTS = {
    { slot = "HeadSlot",          label = "Head",      simc = "head",      hint = "stat enchant" },
    { slot = "NeckSlot",          label = "Neck",      simc = "neck" },
    { slot = "ShoulderSlot",      label = "Shoulders", simc = "shoulder",  hint = "stat enchant" },
    { slot = "BackSlot",          label = "Cloak",     simc = "back",      hint = "stat enchant" },
    { slot = "ChestSlot",         label = "Chest",     simc = "chest",     hint = "stat enchant" },
    { slot = "WristSlot",         label = "Wrists",    simc = "wrist",     hint = "stat enchant" },
    { slot = "HandsSlot",         label = "Hands",     simc = "hands",     hint = "stat enchant" },
    { slot = "WaistSlot",         label = "Waist",     simc = "waist" },
    { slot = "LegsSlot",          label = "Legs",      simc = "legs",      hint = "leg armor" },
    { slot = "FeetSlot",          label = "Feet",      simc = "feet",      hint = "stat enchant" },
    { slot = "Finger0Slot",       label = "Ring 1",    simc = "finger1",   hint = "stat enchant" },
    { slot = "Finger1Slot",       label = "Ring 2",    simc = "finger2",   hint = "stat enchant" },
    { slot = "Trinket0Slot",      label = "Trinket 1", simc = "trinket1" },
    { slot = "Trinket1Slot",      label = "Trinket 2", simc = "trinket2" },
    { slot = "MainHandSlot",      label = "Weapon",    simc = "main_hand", hint = "weapon enchant" },
    { slot = "SecondaryHandSlot", label = "Off hand",  simc = "off_hand",  hint = "weapon enchant" },
}

-- La lecture de GetItemInfo vit dans ItemInfo.lua : un seul endroit ou les dix-sept
-- positions sont nommees, pour tout l'addon.

-- Le decoupage de la chaine d'objet vit dans ItemLink.lua.
local parseLink = function(link) return ns.ItemLink.Parse(link) end

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

--- L'HUILE MANQUANTE EST UNE CORRECTION, pas une remarque.
---
--- Elle s'affichait dans Recommandations, en rouge, avec son taux d'adoption — et
--- l'onglet Equipement annoncait « 2 corrections en attente » sans la compter. Un joueur
--- qui suit la liste des corrections ne la posait donc jamais.
---
--- C'est une propriete de l'ARME, donc le probleme se range sur la main droite : la liste
--- des corrections, son tri et son compte fonctionnent sans rien changer.
---
--- Une huile EXPIRE. C'est la seule correction de cette liste qui reviendra, et c'est
--- exactement pour ca qu'elle merite d'y etre : les autres se font une fois.
local function auditOil(bySlot, summary)
    summary.missingOil = 0

    local main = bySlot.MainHandSlot
    if not main or not main.link or main.ignored then return end

    local oils = ns.Meta.Oils()
    local best = oils and oils[1]
    if not best then return end

    -- `GetWeaponEnchantInfo` est la SEULE source : une huile est un enchantement
    -- temporaire, elle n'est ni dans la chaine d'objet ni dans l'infobulle.
    if type(GetWeaponEnchantInfo) ~= "function" then return end
    local ok, has = pcall(GetWeaponEnchantInfo)
    if not ok or has then return end

    summary.missingOil = 1
    main.missingOil = true
    table.insert(main.problems, L["no weapon oil"])
end

--- Un hors-main vide n'est legitime que si la main droite le justifie.
---
--- La boucle de scan sautait `SecondaryHandSlot` des qu'il etait vide, sans regarder ce
--- qui est porte en face. Un joueur qui dual-wield avec une seule arme equipee perdait
--- donc l'emplacement le plus cher de sa fiche en silence — l'audit affichait « 15 / 15
--- propres » a quelqu'un a qui il manquait une arme.
---
--- Ce qui rend le vide legitime, lu sur l'emplacement d'equipement de la main droite :
--- une deux mains, ou une arme a distance (arc, fusil : elles occupent la main droite et
--- laissent la main gauche vide par construction).
---
--- Volontairement HORS de cette regle : la Poigne du titan, qui porte deux armes a deux
--- mains. La detecter demanderait un test de sort, donc une donnee de patch, pour une
--- seule specialisation — et se tromper signalerait un faux manque a tous les autres
--- porteurs de deux mains du jeu. Mieux vaut ne rien dire que dire faux.
local ONE_HANDED_MAIN = {
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
}

local function auditOffHand(bySlot, summary)
    local main, off = bySlot.MainHandSlot, bySlot.SecondaryHandSlot
    if not main or not off then return end
    if off.link or off.ignored then return end
    if not main.link or not ONE_HANDED_MAIN[main.equipLoc or ""] then return end

    off.skipped = nil
    off.empty = true
    table.insert(off.problems, L["empty slot"])
    summary.emptySlots = summary.emptySlots + 1
end

--- Analyse l'equipement porte. Lecture brute, sans cache : passer par `Gear.Scan`.
--- @return table entries, table summary
local function rawScan()
    local entries = {}
    local summary = {
        missingEnchants = 0,
        missingOil = 0,
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

            local info = ns.ItemInfo.Get(link) or {}
            local parsed = parseLink(link) or { enchantID = 0, gems = {}, bonuses = {}, craftedStats = {} }

            entry.itemLevel = ns.ItemInfo.Level(link)
            entry.name = info.name
            entry.contentTuning = parsed.contentTuning
            entry.craftedStats = parsed.craftedStats
            entry.craftingQuality = parsed.craftingQuality
            entry.quality = info.quality
            -- Sert a la comparaison des sacs : une deux mains portee change ce qu'une
            -- arme a une main veut dire, et ce qu'une deux mains candidate remplace.
            entry.equipLoc = info.equipLoc
            entry.setID = info.setID
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

    -- Apres la boucle : la legitimite d'un hors-main vide se lit sur la main droite, qui
    -- n'est connue qu'une fois toutes les pieces parcourues.
    auditOffHand(bySlot, summary)
    auditWeaponPair(bySlot, summary)
    auditOil(bySlot, summary)

    summary.problems = summary.missingEnchants + summary.emptySockets + summary.emptySlots
        + summary.damaged + summary.weaponPair + (summary.missingOil or 0)

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
--
-- PAS `UPDATE_INVENTORY_DURABILITY` : il se declenche a chaque tick de degats subis. En
-- raid, le cache tombait plusieurs fois par seconde, et le premier appelant venu — une
-- infobulle survolee, l'alerte d'instance — repayait un scan complet a chaque fois. Ce
-- n'est pas un cache annule de temps en temps, c'est un cache qui n'existe plus pendant
-- toute la rencontre, precisement quand le budget d'images est le plus serre.
--
-- La fraicheur de la durabilite est deja assuree : c'est la raison d'etre du TTL de deux
-- secondes ci-dessus. L'abonnement faisait double emploi avec lui.
for _, event in ipairs({
    "PLAYER_EQUIPMENT_CHANGED",
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

--- Resume texte, utilise par la commande /sa gear.
function Gear.PrintReport()
    local entries, summary = Gear.Scan()

    if summary.problems == 0 then
        ns.Print(L["gear complete: %d pieces, everything enchanted and socketed"], summary.checked)
        return
    end

    ns.Print(L["%d gear problem(s):"], summary.problems)
    for _, entry in ipairs(entries) do
        if #entry.problems > 0 and not entry.ignored then
            print(string.format("  |cffe3a45c%s|r — %s%s",
                entry.label,
                table.concat(entry.problems, ", "),
                entry.link and (" " .. entry.link) or ""))
        end
    end
end
