local _, ns = ...

-- Table de recommandations, editable a la main.
--
-- L'addon sait dire ce qui MANQUE (il le lit sur l'objet). Il ne sait pas quel produit
-- poser : le meilleur enchantement et la meilleure gemme changent a chaque patch et selon
-- la spe, et aucune API du jeu ne les expose. Plutot que d'embarquer une liste qui sera
-- fausse dans trois semaines, ce fichier est vide par defaut et se remplit en deux minutes
-- depuis ton guide de spe.
--
-- Exemple :
--   Recommendations.enchants.BackSlot = "Enchantement de cape : Glissement du Vide"
--   Recommendations.gems.default      = "Gemme Hate + Maitrise"
--   Recommendations.trinkets[219314]  = "S"

local Recommendations = {
    -- Par emplacement, le texte affiche quand l'enchantement manque.
    enchants = {
        -- BackSlot = "…",
        -- ChestSlot = "…",
        -- WristSlot = "…",
        -- LegsSlot = "…",
        -- FeetSlot = "…",
        -- Finger0Slot = "…",
        -- Finger1Slot = "…",
        -- MainHandSlot = "…",
        -- SecondaryHandSlot = "…",
    },

    -- Gemme conseillee : `default` sert a tous les emplacements, une cle
    -- d'emplacement prend le dessus.
    gems = {
        -- default = "…",
    },

    -- Classement de bijou par identifiant d'objet : "S", "A", "B"…
    trinkets = {
        -- [219314] = "S",
    },

    -- Repartition visee des statistiques secondaires, en fraction du budget total.
    -- L'addon affiche un repere sur la jauge quand une cible existe. Sans cible, il se
    -- contente de montrer la repartition reelle : il n'invente pas d'ideal.
    statTargets = {
        -- haste = 0.35, mastery = 0.40, crit = 0.20, versatility = 0.05,
    },
}

ns.Recommendations = Recommendations

--- Texte conseille pour l'enchantement d'un emplacement, ou nil.
--- La table manuelle prime ; sinon on se rabat sur le releve des logs.
function Recommendations.Enchant(slotName, referenceLink)
    return Recommendations.enchants[slotName] or ns.Meta.EnchantAdvice(slotName, referenceLink)
end

--- Texte conseille pour la gemme d'un emplacement, ou nil.
function Recommendations.Gem(slotName)
    return Recommendations.gems[slotName] or Recommendations.gems.default or ns.Meta.GemAdvice()
end

--- Classement d'un bijou, ou nil.
--- Sans appelant depuis le retrait de l'onglet Recommandations, qui sera restaure.
function Recommendations.Trinket(itemID)
    return itemID and Recommendations.trinkets[itemID]
end

--- Part visee d'une statistique secondaire (0 a 1), ou nil.
--- La cible manuelle prime ; sinon on prend la moyenne relevee sur le haut de tableau.
function Recommendations.StatTarget(key)
    return Recommendations.statTargets[key] or ns.Meta.StatTarget(key)
end
