local _, ns = ...

local Stats = {}
ns.Stats = Stats

-- Statistiques secondaires du personnage.
--
-- Extrait de Gear.lua : lire une feuille de personnage et auditer un equipement sont deux
-- sujets differents, qui ne changent ni au meme rythme ni pour les memes raisons.

Stats.LIST = {
    { key = "haste",       label = "Haste" },
    { key = "crit",        label = "Crit" },
    { key = "mastery",     label = "Mastery" },
    { key = "versatility", label = "Versatility" },
}

-- Seuils de rendement decroissant, en points de statistique.
--
-- DONNEE DE PATCH : verifiee contre 12.0.7, PAS ENCORE REVUE pour 12.1.0, a revoir a chaque extension. Aucune API ne
-- les expose ; ils viennent de la table de courbes du client, lue hors du jeu. S'ils
-- deviennent faux, le palier affiche dans l'infobulle devient faux avec eux — c'est un
-- indicateur, jamais une entree de calcul.
Stats.DIMINISHING = {
    haste       = { 1320, 1760, 2200 },
    mastery     = { 1380, 1840, 2300 },
    crit        = { 1380, 1840, 2300 },
    versatility = { 1620, 2160, 2700 },
}

--- Statistiques secondaires courantes, avec leur palier de rendement decroissant.
--- @return table { haste = { rating, percent, tier, nextThreshold }, ... }
function Stats.Current()
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
        local thresholds = Stats.DIMINISHING[key] or {}
        entry.tier = 0
        for index, threshold in ipairs(thresholds) do
            if entry.rating >= threshold then entry.tier = index end
        end
        entry.nextThreshold = thresholds[entry.tier + 1]
    end

    return values
end
