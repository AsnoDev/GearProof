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
    -- Armes a distance. Leur absence signifiait qu'un arc superieur dormant dans les
    -- sacs d'un chasseur n'etait jamais propose : l'emplacement n'etait pas resolu, donc
    -- l'objet n'existait pas pour la comparaison.
    INVTYPE_RANGED = { "MainHandSlot" },
    INVTYPE_RANGEDRIGHT = { "MainHandSlot" },
    INVTYPE_THROWN = { "MainHandSlot" },
}

local UNRATED = { Trinket0Slot = true, Trinket1Slot = true }

-- Pourquoi une piece n'est pas chiffree. Une seule table, lue par toutes les vues :
-- l'ancienne version testait `reason == "trinket"` et retombait sur « piece
-- d'ensemble » pour TOUT le reste, y compris pour la raison la plus frequente.
Bags.REASON_TEXT = {
    trinket = "proc — sim required",
    set     = "set piece — sim required",
    pair    = "needs a second weapon — sim required",
    weights = "no stat weights — paste a Pawn string to rank bag items",
}

-- Emplacements dont l'armure porte une classe restreinte par la classe jouee.
--
-- La cape en est ABSENTE volontairement : toutes les capes sont de sous-classe Tissu,
-- pour tout le monde. Collier, anneaux et bijoux sont en sous-classe Divers. Filtrer
-- ces quatre-la sur la classe d'armure bloquerait des objets parfaitement portables.
local ARMOR_SLOTS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
    INVTYPE_ROBE = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
}

-- Sous-classe d'armure maitrisee, par jeton de classe.
-- Enum.ItemArmorSubclass : 1 = Tissu, 2 = Cuir, 3 = Mailles, 4 = Plaques.
-- DONNEE DE PATCH : verifiee contre 12.0.7, PAS ENCORE REVUE pour 12.1.0, a revoir si Blizzard change une maitrise
-- d'armure ou introduit une classe.
local ARMOR_BY_CLASS = {
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    ROGUE = 2, MONK = 2, DRUID = 2, DEMONHUNTER = 2,
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
}

local ARMOR_CLASS_ID = 4
local ARMOR_SUBCLASS_CLOTH, ARMOR_SUBCLASS_PLATE = 1, 4

--- Emplacements de la feuille de personnage pour un type d'objet equipable.
--- Expose pour l'integration infobulle, qui doit resoudre un objet quelconque et non
--- seulement ceux des sacs.
function Bags.SLOTS_FOR(equipLoc)
    return EQUIP_TO_SLOTS[equipLoc or ""]
end

--- L'objet est-il portable par ce personnage ?
---
--- Il n'y avait AUCUN controle : la resolution se faisait sur le seul emplacement
--- d'equipement. Un plastron de plaques dans les sacs d'un mage remontait donc comme
--- amelioration, avec un gain chiffre, parce que « INVTYPE_CHEST » correspond bien a
--- l'emplacement torse.
---
--- Deux niveaux, du moins cher au plus cher :
---
---   1. la classe d'armure, deterministe et sans lecture d'infobulle ;
---   2. la ligne ROUGE de l'infobulle du client, qui couvre tout le reste — maitrise
---      d'arme, niveau requis, restriction de classe, unique-equipe deja porte. La
---      maitrise d'arme n'est exposee par aucune API ; le client, lui, la connait et
---      peint la ligne en rouge. On lit sa couleur, pas son texte : aucune dependance
---      a la langue.
local usableCache = {}

local function armorFits(equipLoc, link)
    if not ARMOR_SLOTS[equipLoc] then return true end

    local instant = C_Item and C_Item.GetItemInfoInstant
    if not instant then return true end

    -- GetItemInfoInstant rend, dans cet ordre :
    --   itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subclassID
    -- soit sept valeurs, donc classID en 7e position derriere le booleen de pcall.
    -- Compter ces positions a la main a deja produit un decalage de deux dans ce
    -- depot : on ecrit la signature en clair a cote de la destructuration.
    local ok, _, _, _, _, _, classID, subclassID = pcall(instant, link)
    if not ok or classID ~= ARMOR_CLASS_ID then return true end
    if not subclassID or subclassID < ARMOR_SUBCLASS_CLOTH or subclassID > ARMOR_SUBCLASS_PLATE then
        return true
    end

    local _, classFile = UnitClass("player")
    local worn = ARMOR_BY_CLASS[classFile or ""]
    -- Classe inconnue de la table : on ne bloque pas. Se tromper en bloquant coute une
    -- amelioration invisible, ce qui est pire que de proposer une piece de trop.
    if not worn then return true end
    return subclassID == worn
end

local function tooltipAllows(link)
    local lines = ns.Meta.ItemTooltipLines(link)
    if not lines then return true end
    for _, line in ipairs(lines) do
        if line.r and line.r > 0.9 and line.g < 0.2 and line.b < 0.2 then
            return false
        end
    end
    return true
end

function Bags.CanUse(link, equipLoc)
    if not link then return false end
    local itemID = link:match("item:(%d+)")
    if not itemID then return true end

    local cached = usableCache[itemID]
    if cached ~= nil then return cached end

    local usable = armorFits(equipLoc, link) and tooltipAllows(link)
    usableCache[itemID] = usable
    return usable
end

-- Monter de niveau debloque des objets : le verdict precedent ne vaut plus.
ns.On("PLAYER_LEVEL_UP", function()
    usableCache = {}
    Bags.Invalidate()
end)

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


-- Index itemID -> chaine d'objet, pour ce que le joueur a deja.
--
-- POURQUOI IL EXISTE. Les onglets Objets et Recommandations nomment des objets que le
-- joueur ne possede pas forcement, et construisent leur infobulle avec `SetItemByID` quand
-- le journal des aventures ne rend rien. Or `SetItemByID` ne connait que le MODELE : sur
-- un objet CRAFTE, cela donne « niveau 44 » et des lignes « Random Stat 1 / Random Stat 2 »
-- — des valeurs de gabarit qui n'existent sur aucun exemplaire reel.
--
-- Et un objet crafte n'est dans AUCUNE table de butin : le journal ne le rendra jamais. Le
-- seul exemplaire vrai a portee est celui que le joueur porte ou transporte. Vu en jeu :
-- l'addon affichait « Spellbreaker's Bracers, niveau 44 » a cote de la meme piece equipee
-- au niveau 331.
local ownedCache
-- Index SACS SEULS, distinct de `ownedCache` qui compte aussi l'equipement.
local bagOnlyCache

--- L'objet est-il DANS LES SACS — pas porte, pas en banque ?
---
--- `Bags.OwnedLink` repond a « je le possede », equipement compris. Ce n'est pas la meme
--- question : une gemme deja sertie compterait comme disponible, et la tournee de guilde
--- dirait « il peut corriger tout de suite » a quelqu'un qui n'a rien sous la main.
---
--- La banque est exclue volontairement : ce qui y dort ne sera pas serti avant le pull.
--- @return boolean
function Bags.InBags(itemID)
    if not itemID then return false end

    if not bagOnlyCache then
        bagOnlyCache = {}
        for _, bag in ipairs(candidateBags()) do
            for slot = 1, containerSlots(bag) do
                local link = containerLink(bag, slot)
                local id = link and ns.ItemInfo.ID(link)
                if id then bagOnlyCache[id] = true end
            end
        end
    end

    return bagOnlyCache[itemID] == true
end

--- Chaine d'objet d'un exemplaire que le joueur POSSEDE : porte, ou dans ses sacs.
---
--- L'equipement d'abord : c'est l'exemplaire qu'il a choisi de monter, donc le plus
--- representatif quand il en a plusieurs.
---
--- L'index est memoise avec le reste du module et tombe aux memes evenements — un objet
--- ramasse ou equipe change la reponse.
--- @return string|nil
function Bags.OwnedLink(itemID)
    if not itemID then return nil end

    if not ownedCache then
        ownedCache = {}
        for _, entry in ipairs(ns.Gear.Scan() or {}) do
            if entry.itemID and entry.link and not ownedCache[entry.itemID] then
                ownedCache[entry.itemID] = entry.link
            end
        end
        for _, bag in ipairs(candidateBags()) do
            for slot = 1, containerSlots(bag) do
                local link = containerLink(bag, slot)
                local id = link and ns.ItemInfo.ID(link)
                if id and not ownedCache[id] then ownedCache[id] = link end
            end
        end
    end

    return ownedCache[itemID]
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
--- Seuls les objets que ce personnage peut REELLEMENT porter sont retenus.
function Bags.Candidates()
    local found = {}

    for _, bag in ipairs(candidateBags()) do
        for slot = 1, containerSlots(bag) do
            local link = containerLink(bag, slot)
            if link then
                -- Detailed, pas Get : la comparaison a besoin du niveau EFFECTIF, bonus
                -- compris. Le niveau du modele vaut 44 sur une piece de raid.
                local facts = ns.ItemInfo.Detailed(link)
                local targets = facts and EQUIP_TO_SLOTS[facts.equipLoc or ""]
                if targets and Bags.CanUse(link, facts.equipLoc) then
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

--- Compare les candidats aux pieces portees. Calcul brut : passer par `Bags.Compare`.
--- @return table simmed (% DPS), table unrated (ilvl seul), table summary, table estimated (points)
local function rawCompare()
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

    local offHand = summary.bySlot and summary.bySlot.SecondaryHandSlot
    local offHandScore = (offHand and offHand.link)
        and ns.Weights.Score(offHand.link, weights) or 0
    local mainHand = summary.bySlot and summary.bySlot.MainHandSlot
    local wearsTwoHander = mainHand and mainHand.equipLoc == "INVTYPE_2HWEAPON"

    for _, entry in ipairs(entries) do
        local list = candidates[entry.slot]
        if list then
            local baseScore = entry.link and ns.Weights.Score(entry.link, weights) or 0
            local currentLevel = entry.itemLevel or 0

            for _, candidate in ipairs(list) do
                local equipLoc = candidate.facts.equipLoc
                local score = ns.Weights.Score(candidate.link, weights)
                local levelDelta = (candidate.facts.itemLevel or 0) - currentLevel

                -- Une deux mains LIBERE la main gauche : son gain se mesure contre la
                -- somme des deux armes portees, pas contre la seule main droite. La
                -- version precedente ignorait la perte et surevaluait chaque deux mains
                -- proposee a un porteur d'arme et bouclier.
                local currentScore = baseScore
                if equipLoc == "INVTYPE_2HWEAPON" and entry.slot == "MainHandSlot" then
                    currentScore = baseScore + offHandScore
                end

                local gain = score - currentScore

                -- Une valeur simulee tranche : elle prime sur l'estimation lineaire et
                -- rend chiffrables les bijoux et pieces d'ensemble.
                local itemID = candidate.link:match("|Hitem:(%d+)")
                local simulated = ns.Sim.Percent(tonumber(itemID), candidate.facts.itemLevel)

                -- L'ordre compte. `not weights` etait teste EN PREMIER : sans chaine
                -- Pawn — l'etat normal d'une installation neuve — tout objet sortait
                -- avec la raison « weights », et la vue, qui ne connaissait que deux
                -- raisons, affichait « piece d'ensemble » sur un bijou. Les cas
                -- specifiques d'abord, le cas generique en dernier.
                local blocked
                if simulated then
                    blocked = nil
                elseif UNRATED[entry.slot] then
                    -- Un bijou vaut son proc, avec ou sans poids de statistiques.
                    blocked = "trinket"
                elseif entry.setID or candidate.facts.setID then
                    -- Perdre le 4 pieces annule tout gain de statistique.
                    blocked = "set"
                elseif wearsTwoHander and entry.slot == "MainHandSlot"
                    and (equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND") then
                    -- Une main a la place d'une deux mains : il faudrait une seconde
                    -- arme pour que la comparaison ait un sens, et on ne sait pas
                    -- laquelle. On le dit plutot que de chiffrer a cote.
                    blocked = "pair"
                elseif not weights then
                    -- Aucune chaine Pawn : plus de poids derives du releve, donc rien a
                    -- ponderer. La piece se classe par ilvl, marquee comme non chiffrable.
                    blocked = "weights"
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

-- Cache de comparaison.
--
-- `Bags.Compare` parcourt tous les sacs, resout chaque objet equipable, puis calcule
-- une somme ponderee par piece portee ET par candidat. Il etait appele deux fois par
-- rafraichissement de l'onglet Equipement, et une fois de plus a chaque survol d'une
-- tuile de la grille — le geste le plus frequent de l'interface.
--
-- Meme regle que pour `Gear.Scan` : les listes rendues ne sont mutees par personne.
local cachedCompare, compareAt = nil, 0
local COMPARE_TTL = 2

function Bags.Invalidate()
    cachedCompare, compareAt = nil, 0
    ownedCache = nil
    bagOnlyCache = nil
end

function Bags.Compare()
    local now = GetTime()
    if not cachedCompare or (now - compareAt) >= COMPARE_TTL then
        cachedCompare = { rawCompare() }
        compareAt = now
    end
    local result = cachedCompare
    return result[1], result[2], result[3], result[4]
end

-- Le contenu des sacs, l'equipement porte et l'ouverture de la banque changent la liste
-- des candidats. Les poids de statistiques et l'import d'un droptimizer changent leur
-- classement : ces deux-la invalident depuis leur propre module.
for _, event in ipairs({
    "BAG_UPDATE_DELAYED",
    "PLAYER_EQUIPMENT_CHANGED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
}) do
    ns.On(event, Bags.Invalidate)
end
