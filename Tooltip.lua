local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

-- Integration dans l'infobulle des objets : sacs, hotel des ventes, butin, marchand.
--
-- C'est la surface la plus precieuse d'un addon WoW, et elle etait vide. Ouvrir une fenetre
-- pour savoir si la piece qu'on vient de ramasser vaut mieux que la sienne est une friction
-- que Pawn a supprimee il y a dix ans.
--
-- On n'ajoute que ce qui est MESURE :
--   * le gain simule, quand un droptimizer couvre l'objet
--   * l'ecart de niveau d'objet, qui ne demande aucune donnee
--   * l'enchantement releve pour cet emplacement, avec son taux d'adoption
-- Rien d'estime n'est affiche ici : une infobulle est lue en une seconde, sans le contexte
-- qui permettrait de relativiser un chiffre approximatif.

local ADDED = "|cff00B0FFSpecAnalyser|r"

--- Emplacements de la feuille de personnage pour un type d'objet equipable.
local function slotsFor(equipLoc)
    if not ns.Bags or not ns.Bags.SLOTS_FOR then return nil end
    return ns.Bags.SLOTS_FOR(equipLoc)
end

local function itemFacts(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo or not link then return nil end

    local results = { pcall(getInfo, link) }
    if not results[1] then return nil end

    local level
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, value = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok then level = value end
    end

    -- Le niveau EFFECTIF, pas le niveau de base : `results[5]` est le niveau de reference de
    -- l'objet, indifferent aux bonus et au surclassement. Le confondre avec le niveau reel
    -- fausse toute comparaison. Sans GetDetailedItemLevelInfo, on ne devine pas.
    return {
        equipLoc = results[10],
        itemLevel = level,
        itemID = tonumber(link:match("Hitem:(%d+)")),
    }
end

--- Lignes que SpecAnalyser ajoute pour un objet donne.
--- @return table|nil { { text, r, g, b }, ... }
function Tooltip.LinesFor(link)
    local facts = itemFacts(link)
    if not facts or not facts.equipLoc or facts.equipLoc == "" then return nil end

    local targets = slotsFor(facts.equipLoc)
    if not targets or #targets == 0 then return nil end

    local lines = {}

    -- Gain simule : la seule valeur qui chiffre honnetement un bijou ou une piece
    -- d'ensemble, parce qu'elle vient d'une simulation et non de poids de statistiques.
    local simulated = facts.itemID and facts.itemLevel
        and ns.Sim.Percent(facts.itemID, facts.itemLevel)
    if simulated then
        table.insert(lines, {
            text = string.format("%+.2f%% %s", simulated, ns.L["simulated (% DPS)"]),
            r = 0, g = 0.9, b = 0.46,
        })
    end

    -- Ecart de niveau d'objet contre la piece portee. Ne demande aucune donnee externe.
    local _, summary = ns.Gear.Scan()
    local best
    for _, slot in ipairs(targets) do
        local worn = (summary.bySlot or {})[slot]
        local level = worn and worn.itemLevel or nil
        if level and (not best or level < best) then best = level end
    end
    if best and facts.itemLevel then
        local delta = facts.itemLevel - best
        if delta ~= 0 then
            table.insert(lines, {
                text = string.format("%+d %s", delta, ns.L["ilvl vs equipped"]),
                r = 0.54, g = 0.54, b = 0.54,
            })
        end
    end

    -- Un objet tres en dessous de l'equipe n'a rien a nous faire dire de plus : le conseil
    -- d'enchantement sur une piece de niveau 44 est du bruit.
    if best and facts.itemLevel and facts.itemLevel < best - 30 then
        return #lines > 0 and lines or nil
    end

    -- Enchantement releve pour cet emplacement, si l'objet en attend un.
    for _, slot in ipairs(targets) do
        local expected, known = ns.Meta.ExpectsEnchant(slot)
        if known and expected then
            local enchantID, share = ns.Meta.Enchant(slot)
            local name = enchantID and ns.Meta.EnchantName(link, enchantID)
            if name then
                -- Le pourcentage seul. Que la reference soit le haut de tableau est deja
                -- porte par le nom de l'addon en tete d'infobulle ; le repeter a chaque
                -- ligne coute de la largeur sans rien apprendre. Le CHIFFRE reste, lui :
                -- il dit si le choix est unanime ou dispute, ce qu'aucun autre mot ne dit.
                table.insert(lines, {
                    text = string.format("%s  |cff8A8A8A%s|r", name,
                        string.format(ns.L["%d%% adoption"], (share or 0) * 100 + 0.5)),
                    r = 1, g = 0.76, b = 0.03,
                })
            end
            break
        end
    end

    return #lines > 0 and lines or nil
end

--- Branche l'addon sur les infobulles d'objets.
function Tooltip.Register()
    if ns.db and ns.db.tooltip == false then return end

    -- TooltipDataProcessor est l'unique point d'entree depuis Dragonflight ; les anciens
    -- crochets GameTooltip:SetScript n'ont plus d'effet. Tout est sous pcall : une API qui
    -- change de nom ne doit pas empecher le reste de l'addon de fonctionner.
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then return end
    if not Enum or not Enum.TooltipDataType or not Enum.TooltipDataType.Item then return end

    local function decorate(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

        local link = data and data.hyperlink
        if not link and tooltip.GetItem then
            local ok, _, fromTooltip = pcall(tooltip.GetItem, tooltip)
            if ok then link = fromTooltip end
        end
        if not link then return end

        local ok, lines = pcall(Tooltip.LinesFor, link)
        if not ok or not lines then return end

        tooltip:AddLine(" ")
        for index, line in ipairs(lines) do
            tooltip:AddDoubleLine(index == 1 and ADDED or " ", line.text,
                0.54, 0.54, 0.54, line.r, line.g, line.b)
        end
    end

    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, decorate)
end
