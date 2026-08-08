local _, ns = ...

local Weights = {}
ns.Weights = Weights

local L = ns.L

-- Poids de statistiques, utilises pour estimer un gain d'objet.
--
-- Deux sources, dans cet ordre :
--   1. une chaine Pawn collee par le joueur, issue de sa propre simulation Raidbots ;
--   2. a defaut, une approximation derivee de la repartition moyenne du haut de tableau.
--
-- L'estimation est LINEAIRE. Elle est fiable sur une piece d'armure sans proc, et fausse
-- sur un bijou ou une piece d'ensemble : on refuse de chiffrer ces deux cas.

-- Correspondance entre les cles de C_Item.GetItemStats et nos statistiques.
Weights.STAT_KEYS = {
    ITEM_MOD_INTELLECT_SHORT = "intellect",
    ITEM_MOD_AGILITY_SHORT = "agility",
    ITEM_MOD_STRENGTH_SHORT = "strength",
    ITEM_MOD_HASTE_RATING_SHORT = "haste",
    ITEM_MOD_CRIT_RATING_SHORT = "crit",
    ITEM_MOD_MASTERY_RATING_SHORT = "mastery",
    ITEM_MOD_VERSATILITY = "versatility",
}

-- Synonymes acceptes dans une chaine Pawn.
local PAWN_KEYS = {
    intellect = "intellect",
    agility = "agility",
    strength = "strength",
    hasterating = "haste",
    critrating = "crit",
    masteryrating = "mastery",
    versatility = "versatility",
}


--- Analyse une chaine Pawn : ( Pawn: v1: "Nom": Intellect=1, HasteRating=0.9, ... )
--- @return table|nil weights, string|nil name
function Weights.ParsePawn(text)
    if not text or text == "" then return nil end

    local name = text:match('"(.-)"') or "Pawn"
    local weights = {}
    local found = false

    for key, value in text:gmatch("(%a[%w]*)%s*=%s*([%d%.]+)") do
        local mapped = PAWN_KEYS[key:lower()]
        local number = tonumber(value)
        if mapped and number then
            weights[mapped] = number
            found = true
        end
    end

    if not found then return nil end
    return weights, name
end

--- Enregistre des poids venant d'une chaine Pawn.
function Weights.SetFromPawn(text)
    local weights, name = Weights.ParsePawn(text)
    if not weights then return false end

    ns.db.weights = {
        values = weights,
        name = name,
        source = "pawn",
        stamp = time(),
    }
    -- De nouveaux poids reclassent tout le contenu des sacs : le cache de comparaison
    -- ne decrit plus la realite.
    if ns.Bags then ns.Bags.Invalidate() end
    return true, name
end

function Weights.Clear()
    ns.db.weights = nil
    if ns.Bags then ns.Bags.Invalidate() end
end

--- Poids actifs et leur provenance.
--- @return table weights, string source, number|nil stamp
function Weights.Current()
    local stored = ns.db.weights
    if stored and stored.values and next(stored.values) then
        return stored.values, stored.source or "pawn", stored.stamp
    end

    -- Il y avait ici un repli qui derivait les poids de la part du budget relevee chez le
    -- haut de tableau : weights[key] = share / best * 0.85. Il est supprime, parce qu'il
    -- etait ANTI-CORRELE avec ce qu'il pretendait mesurer.
    --
    -- Une part de budget n'est pas une valeur par point. Elle reflete ce qui a drop, et
    -- surtout la forme des rendements decroissants que cet addon embarque lui-meme dans
    -- Stats.DIMINISHING : plus tu accumules une statistique, plus sa part grossit et moins
    -- son point suivant vaut. Le repli poussait donc vers la statistique deja saturee.
    --
    -- Sans chaine Pawn, on ne rend rien. Une piece se classe alors par ilvl, marquee « il
    -- faut une simulation » — le meme traitement que les bijoux et les pieces d'ensemble.
    return nil, "none", nil
end

--- Age des poids en jours, ou nil.
function Weights.AgeInDays()
    local stored = ns.db.weights
    if not stored or not stored.stamp then return nil end
    return math.floor((time() - stored.stamp) / 86400)
end

--- Somme ponderee des statistiques d'un objet.
function Weights.Score(link, weights)
    if not link then return 0 end
    weights = weights or Weights.Current()
    -- Sans poids, il n'y a pas de score. On retourne zero et l'appelant doit avoir verifie
    -- `Weights.Current()` avant de classer quoi que ce soit.
    if not weights then return 0 end

    local stats
    if C_Item and C_Item.GetItemStats then
        local ok, result = pcall(C_Item.GetItemStats, link)
        if ok then stats = result end
    end
    if type(stats) ~= "table" then return 0 end

    local total = 0
    for key, value in pairs(stats) do
        local mapped = Weights.STAT_KEYS[key]
        if mapped and weights[mapped] then
            total = total + (tonumber(value) or 0) * weights[mapped]
        end
    end
    return total
end

--- Description courte de la source des poids, pour l'interface.
function Weights.Describe()
    local stored = ns.db.weights
    if stored and stored.values then
        local age = Weights.AgeInDays()
        return string.format(L["weights: %s (%d days)"], stored.name or "Pawn", age or 0),
            (age or 0) >= 7
    end
    -- Plus de repli derive du releve : sans chaine Pawn, on le dit et on ne classe pas.
    return L["no stat weights — paste a Pawn string to rank bag items"], true
end
