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
--- Statistiques de SURVIE, lues sur la feuille de personnage.
---
--- Elles ne font pas partie du budget secondaire et n'entrent dans aucune part : les
--- additionner aux quatre autres fausserait tous les pourcentages. Elles sont affichees a
--- part, et seulement pour un tank — c'est la seule chose que la colonne de droite lui
--- disait de faux jusqu'ici, en lui montrant la meme repartition qu'a un DPS sans jamais
--- mentionner ce qui le maintient en vie.
---
--- Pas de comparaison au haut de tableau : le releve ne porte ni endurance ni armure, et
--- ces deux valeurs dependent du niveau d'objet bien plus que d'un choix. Un chiffre brut
--- que le joueur reconnait, pas un verdict invente.
--- @return table|nil { stamina = { value }, armor = { value } }
function Stats.Survival()
    local function stat(index)
        if type(UnitStat) ~= "function" then return nil end
        local ok, base, total = pcall(UnitStat, "player", index)
        if not ok then return nil end
        return total or base
    end

    local armor
    if type(UnitArmor) == "function" then
        -- UnitArmor rend base, effectif, armure, posture, temporaire selon les versions :
        -- la 2e valeur est l'armure effective sur Retail.
        local results = { pcall(UnitArmor, "player") }
        if results[1] then armor = results[3] or results[2] end
    end

    local stamina = stat(3)
    if not stamina and not armor then return nil end

    return {
        stamina = stamina and { value = stamina } or nil,
        armor = armor and { value = armor } or nil,
    }
end

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
