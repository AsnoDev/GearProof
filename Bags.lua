local _, ns = ...

local Bags = {}
ns.Bags = Bags

-- Compare ce que tu portes a ce que tu transportes.
--
-- L'estimation est lineaire : somme ponderee des statistiques. Elle vaut pour une piece
-- d'armure ordinaire. Elle ne vaut PAS pour un bijou (le proc ne se reduit pas a des
-- points) ni pour une piece d'ensemble (perdre le 4 pieces annule tout gain de stat).
-- Ces deux cas sont marques comme non chiffrables plutot que chiffres a tort.

-- Emplacement d'equipement renvoye par GetItemInfo -> emplacements de la feuille.
local EQUIP_TO_SLOTS = {
    INVTYPE_HEAD = { "HeadSlot" },
    INVTYPE_NECK = { "NeckSlot" },
    INVTYPE_SHOULDER = { "ShoulderSlot" },
    INVTYPE_CLOAK = { "BackSlot" },
    INVTYPE_CHEST = { "ChestSlot" },
    INVTYPE_ROBE = { "ChestSlot" },
    INVTYPE_WRIST = { "WristSlot" },
    INVTYPE_HAND = { "HandsSlot" },
    INVTYPE_WAIST = { "WaistSlot" },
    INVTYPE_LEGS = { "LegsSlot" },
    INVTYPE_FEET = { "FeetSlot" },
    INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
    INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
    INVTYPE_WEAPON = { "MainHandSlot", "SecondaryHandSlot" },
    INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
    INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
    INVTYPE_2HWEAPON = { "MainHandSlot" },
    INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
    INVTYPE_SHIELD = { "SecondaryHandSlot" },
}

local UNRATED = { Trinket0Slot = true, Trinket1Slot = true }

--- Emplacements de la feuille de personnage pour un type d'objet equipable.
--- Expose pour l'integration infobulle, qui doit resoudre un objet quelconque et non
--- seulement ceux des sacs.
function Bags.SLOTS_FOR(equipLoc)
    return EQUIP_TO_SLOTS[equipLoc or ""]
end

local function containerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function containerLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    return nil
end

local function itemFacts(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end

    local results = { pcall(getInfo, link) }
    if not results[1] then return nil end

    local level
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, value = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok then level = value end
    end

    return {
        name = results[2],
        quality = results[4],
        equipLoc = results[10],
        setID = results[17],
        itemLevel = level or results[5],
    }
end

--- Sacs du personnage, plus la banque si elle est ouverte.
local function candidateBags()
    local bags = { 0, 1, 2, 3, 4, 5 }
    if BankFrame and BankFrame:IsShown() then
        for bag = 6, 12 do table.insert(bags, bag) end
        table.insert(bags, -1)
    end
    return bags
end

--- Parcourt les sacs et retourne les pieces equipables, classees par emplacement.
function Bags.Candidates()
    local found = {}

    for _, bag in ipairs(candidateBags()) do
        for slot = 1, containerSlots(bag) do
            local link = containerLink(bag, slot)
            if link then
                local facts = itemFacts(link)
                local targets = facts and EQUIP_TO_SLOTS[facts.equipLoc or ""]
                if targets then
                    for _, target in ipairs(targets) do
                        found[target] = found[target] or {}
                        table.insert(found[target], { link = link, facts = facts })
                    end
                end
            end
        end
    end

    return found
end

--- Compare les candidats aux pieces portees.
--- @return table simmed (% DPS), table unrated (ilvl seul), table summary, table estimated (points)
function Bags.Compare()
    local entries, summary = ns.Gear.Scan()
    local weights = ns.Weights.Current()
    local candidates = Bags.Candidates()

    -- Reference : la somme ponderee de tout l'equipement porte. Sert de denominateur
    -- pour exprimer un gain en pourcentage plutot qu'en points bruts.
    local baseline = 0
    for _, entry in ipairs(entries) do
        if entry.link then
            baseline = baseline + ns.Weights.Score(entry.link, weights)
        end
    end
    baseline = math.max(1, baseline)

    -- Trois listes, trois unites, jamais melangees :
    --   simmed    : pourcentage de DPS, mesure par un droptimizer
    --   estimated : points de statistique ponderes, estimation lineaire
    --   unrated   : non chiffrable (bijou, piece d'ensemble) — ilvl seulement
    local simmed, estimated, unrated = {}, {}, {}

    for _, entry in ipairs(entries) do
        local list = candidates[entry.slot]
        if list then
            local currentScore = entry.link and ns.Weights.Score(entry.link, weights) or 0
            local currentLevel = entry.itemLevel or 0

            for _, candidate in ipairs(list) do
                local score = ns.Weights.Score(candidate.link, weights)
                local gain = score - currentScore
                local levelDelta = (candidate.facts.itemLevel or 0) - currentLevel

                -- Une valeur simulee tranche : elle prime sur l'estimation lineaire et
                -- rend chiffrables les bijoux et pieces d'ensemble.
                local itemID = candidate.link:match("|Hitem:(%d+)")
                local simulated = ns.Sim.Percent(tonumber(itemID), candidate.facts.itemLevel)

                local blocked
                if simulated then
                    blocked = nil
                elseif not weights then
                    -- Aucune chaine Pawn : plus de poids derives du releve, donc rien a
                    -- ponderer. La piece se classe par ilvl, marquee comme non chiffrable.
                    blocked = "weights"
                elseif UNRATED[entry.slot] then
                    blocked = "trinket"
                elseif entry.setID or candidate.facts.setID then
                    blocked = "set"
                end

                if simulated then
                    -- Pourcentage de DPS, issu d'un vrai droptimizer.
                    table.insert(simmed, {
                        slot = entry.slot,
                        label = entry.label,
                        link = candidate.link,
                        itemLevel = candidate.facts.itemLevel,
                        levelDelta = levelDelta,
                        dps = simulated,
                    })
                elseif blocked then
                    if levelDelta > 0 then
                        table.insert(unrated, {
                            slot = entry.slot,
                            label = entry.label,
                            link = candidate.link,
                            itemLevel = candidate.facts.itemLevel,
                            levelDelta = levelDelta,
                            reason = blocked,
                        })
                    end
                elseif gain > 0 then
                    -- Points de statistique ponderes. Ce N'EST PAS un pourcentage de DPS et
                    -- ne doit jamais etre compare a un : deux unites dans une meme colonne
                    -- « % » laissaient croire qu'un +1,2 % estime valait un +1,2 % simule.
                    table.insert(estimated, {
                        slot = entry.slot,
                        label = entry.label,
                        link = candidate.link,
                        itemLevel = candidate.facts.itemLevel,
                        levelDelta = levelDelta,
                        gain = gain,
                    })
                end
            end
        end
    end

    -- Chaque liste est triee dans SON unite. Aucun tri ne traverse les unites.
    table.sort(simmed, function(a, b) return a.dps > b.dps end)
    table.sort(estimated, function(a, b) return a.gain > b.gain end)
    table.sort(unrated, function(a, b) return a.levelDelta > b.levelDelta end)

    return simmed, unrated, summary, estimated
end
