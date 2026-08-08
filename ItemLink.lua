local _, ns = ...

local ItemLink = {}
ns.ItemLink = ItemLink

-- Lecture d'une chaine d'objet.
--
-- Extrait du fichier Gear.lua, qui cumulait cinq responsabilites. C'est la partie la plus
-- delicate de l'addon et la seule dont un bug ne se voit pas : une chaine mal decoupee ne
-- leve rien, elle produit un export SimulationCraft qui simule un autre personnage.
--
-- Champs de la chaine, dans l'ordre (warcraft.wiki.gg/wiki/ItemString) :
--   itemID, enchantID, gem1..gem4, suffixID, uniqueID, linkLevel, specializationID,
--   modifiersMask, itemContext, numBonusIDs[, bonusID...], numModifiers[, type, valeur...]
--
-- Le compteur de bonus est donc le 13e champ. L'avoir lu au 14e produisait un `bonus_id`
-- ampute de son premier identifiant et pollue par le bloc de modificateurs : le compteur
-- valait 12214 au lieu de 9. C'est la cause du « le SimC ne fonctionne pas » du
-- 2026-08-03. Verifie depuis contre un export officiel, 5 emplacements sur 5 identiques
-- au caractere pres.
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
--- @return table|nil { itemID, enchantID, gems, bonuses, contentTuning, craftedStats, craftingQuality }
function ItemLink.Parse(link)
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

    local quality = modifiers[MOD_CRAFTING_QUALITY] or 0

    return {
        itemID = number(LINK_ITEM_ID),
        enchantID = number(LINK_ENCHANT_ID),
        gems = gems,
        bonuses = bonuses,
        contentTuning = modifiers[MOD_CONTENT_TUNING],
        craftedStats = craftedStats,
        -- La qualite d'artisanat est un palier de 1 a 5 ; hors de cette plage, la valeur
        -- lue n'est pas ce qu'on croit et il vaut mieux ne rien ecrire.
        craftingQuality = (quality >= 1 and quality <= 5) and quality or nil,
    }
end

--- Chaine d'objet dans laquelle le champ d'enchantement a ete remplace.
--- Sert a lire le nom d'un enchantement : WoW n'expose pas d'infobulle propre a un
--- enchantement, seule celle de l'objet qui le porte le decrit.
function ItemLink.WithEnchant(referenceLink, enchantID)
    if not referenceLink or not enchantID then return nil end

    local itemString = referenceLink:match("|Hitem:([%-%d:]+)")
    if not itemString then return nil end

    local parts = { strsplit(":", itemString) }
    parts[LINK_ENCHANT_ID] = tostring(enchantID)
    return "|cffffffff|Hitem:" .. table.concat(parts, ":") .. "|h[x]|h|r"
end
