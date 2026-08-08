local _, ns = ...

local ItemInfo = {}
ns.ItemInfo = ItemInfo

-- Lecteur unique de GetItemInfo.
--
-- Il y en avait cinq : Gear.lua, Bags.lua, Tooltip.lua, RaidView.lua et GuildView.lua.
-- Un seul nommait ses positions ; les quatre autres indexaient a la main —
-- `results[10]`, `results[17]` — parce que compter les valeurs de retour marche, jusqu'au
-- jour ou Blizzard en insere une.
--
-- Ce jour est deja arrive dans ce depot : un decalage de deux positions sur equipLoc et
-- setID, et un compteur de bonus lu au 14e champ au lieu du 13e qui amputait chaque
-- export SimulationCraft de son premier identifiant. Une table de constantes, un seul
-- appelant : le prochain patch ne casse qu'un endroit.

-- GetItemInfo, dans l'ordre (warcraft.wiki.gg/wiki/API_GetItemInfo) :
local FIELD = {
    name              = 1,
    link              = 2,
    quality           = 3,
    baseLevel         = 4,   -- niveau du MODELE, indifferent aux bonus. Voir Level().
    minLevel          = 5,
    type              = 6,
    subType           = 7,
    stackCount        = 8,
    equipLoc          = 9,
    texture           = 10,
    sellPrice         = 11,
    classID           = 12,
    subclassID        = 13,
    bindType          = 14,
    expacID           = 15,
    setID             = 16,
    isCraftingReagent = 17,
}

--- Faits d'un objet, par nom de champ.
---
--- `identifier` accepte ce que GetItemInfo accepte : chaine d'objet, identifiant
--- numerique, ou nom. Retourne nil tant que le client n'a pas charge l'objet — c'est un
--- etat normal, pas une erreur : le meme appel reussira quelques frames plus tard.
---
--- @return table|nil { name, link, quality, equipLoc, setID, classID, subclassID, ... }
function ItemInfo.Get(identifier)
    if not identifier then return nil end

    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(getInfo) ~= "function" then return nil end

    -- results[1] est le booleen de pcall : les valeurs commencent a 2. On indexe
    -- directement plutot que de retirer l'element — un nil au milieu creerait un trou
    -- dans la table et decalerait tout ce qui suit.
    local results = { pcall(getInfo, identifier) }
    if not results[1] or not results[1 + FIELD.name] then return nil end

    local facts = {}
    for key, position in pairs(FIELD) do
        facts[key] = results[1 + position]
    end

    -- setID vaut 0 sur un objet hors ensemble : autant dire nil, que les appelants
    -- testent deja.
    if facts.setID == 0 then facts.setID = nil end

    return facts
end

--- Niveau d'objet EFFECTIF, bonus et surclassement compris.
---
--- A ne jamais confondre avec `baseLevel` : ce dernier est le niveau du modele, qui vaut
--- 44 sur une piece de raid. Sans `GetDetailedItemLevelInfo`, on ne devine pas — on rend
--- nil, et l'appelant s'abstient de comparer.
function ItemInfo.Level(identifier)
    if not identifier then return nil end
    if not C_Item or not C_Item.GetDetailedItemLevelInfo then return nil end
    local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, identifier)
    return (ok and level and level > 0) and level or nil
end

--- Faits d'un objet, niveau effectif inclus. La forme attendue par les comparaisons.
function ItemInfo.Detailed(identifier)
    local facts = ItemInfo.Get(identifier)
    if not facts then return nil end
    facts.itemLevel = ItemInfo.Level(identifier) or facts.baseLevel
    return facts
end

--- Code couleur de qualite, `|cffXXXXXX`, avec un repli neutre.
function ItemInfo.QualityColor(quality)
    local colors = ITEM_QUALITY_COLORS or {}
    local entry = quality and colors[quality]
    return (entry and entry.hex) or "|cffE8E8E8"
end

--- Nom colore a la qualite, ou nil si l'objet n'est pas encore charge.
function ItemInfo.ColoredName(identifier)
    local facts = ItemInfo.Get(identifier)
    if not facts or not facts.name then return nil end
    return ItemInfo.QualityColor(facts.quality) .. facts.name .. "|r"
end

--- Identifiant numerique porte par une chaine d'objet.
function ItemInfo.ID(link)
    if type(link) ~= "string" then return tonumber(link) end
    return tonumber(link:match("item:(%d+)"))
end
