local _, ns = ...

local Meta = {}
ns.Meta = Meta

-- Reference deduite des logs : ce que portent reellement les joueurs les mieux classes
-- de la spe. Le fichier Data/Meta.lua est genere par :
--   specanalyser wcl enchants --encounter <id> --to-addon
--
-- Aucune API du jeu n'expose "le meilleur enchantement du patch". Le classement, lui,
-- est mesurable : on regarde ce qui est pose sur les personnages du haut de tableau.

local scanner

--- Prefixe localise de la ligne "Enchante : X" dans les infobulles.
--- On compare en texte brut plutot qu'avec un motif : echapper les caracteres speciaux
--- d'un modele qui contient deja un groupe de capture est une source d'erreur, et c'est
--- exactement ce qui neutralisait la recherche auparavant.
local function enchantPrefix()
    local template = ENCHANTED_TOOLTIP_LINE or "Enchanted: %s"
    return template:match("^(.-)%%s") or "Enchanted: "
end

local function ensureScanner()
    if scanner then return scanner end
    scanner = CreateFrame("GameTooltip", "SpecAnalyserScanTooltip", nil, "GameTooltipTemplate")
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    return scanner
end

--- Bloc de la specialisation regardee.
---
--- Le fichier genere est indexe par identifiant de specialisation : un releve de Havoc ne
--- doit jamais servir de reference a un Devourer. Un fichier de l'ancien format (un seul
--- bloc a plat, sans dimension de spe) est rattache a la spe active plutot que rejete, pour
--- ne pas casser une installation existante.
local function block()
    if type(SpecAnalyserMeta) ~= "table" then return nil end
    if SpecAnalyserMeta.sample then return SpecAnalyserMeta end
    if not ns.Spec then return nil end

    local specID = ns.Spec.Selected()

    -- Cle de secours, insensible a la langue : l'identifiant Blizzard, quand le releve le
    -- connait. C'est la voie preferee.
    if specID then
        for _, entry in pairs(SpecAnalyserMeta) do
            if type(entry) == "table" and entry.specID == specID then return entry end
        end
    end

    -- Sinon, la cle « slug de classe / slug de spe ». Le jeton de classe ne depend pas de
    -- la langue ; le nom de spe, lui, est traduit, donc cette voie ne vaut que pour un
    -- client anglais. Elle evite d'attendre un /reload pour une spe dont l'identifiant
    -- n'est pas encore connu de l'outil.
    local classSlug = ns.Spec.ClassSlug()
    local specName = ns.Spec.Name(specID)
    if classSlug and specName then
        local slug = specName:gsub("[^%w]", "")
        local entry = SpecAnalyserMeta[classSlug .. "/" .. slug]
        if type(entry) == "table" then return entry end
    end

    return nil
end

Meta.Block = block

function Meta.Available()
    local data = block()
    return data ~= nil and (data.sample or 0) > 0
end

function Meta.Sample()
    local data = block()
    return (data and data.sample) or 0
end

function Meta.Source()
    local data = block()
    return data and data.source or nil
end

--- Rencontres reellement depouillees, dans l'ordre de tirage.
function Meta.Fights()
    local data = block()
    return (data and data.fights) or {}
end

--- Nom de la specialisation telle que le releve la designe.
function Meta.SpecName()
    local data = block()
    return data and data.spec or nil
end

--- Y a-t-il un releve pour au moins une specialisation ?
--- Sert a distinguer « aucune donnee installee » de « pas de donnee pour CETTE spe ».
function Meta.AnyAvailable()
    if type(SpecAnalyserMeta) ~= "table" then return false end
    if SpecAnalyserMeta.sample then return (SpecAnalyserMeta.sample or 0) > 0 end
    for key, entry in pairs(SpecAnalyserMeta) do
        -- `_stamp` decrit le releve, ce n'est pas une specialisation.
        if type(key) ~= "string" or key:sub(1, 1) ~= "_" then
            if type(entry) == "table" and (entry.sample or 0) > 0 then return true end
        end
    end
    return false
end

--- Estampille du releve embarque : nombre de spes et rencontres relevees.
--- @return table|nil { specs, encounters }
function Meta.Stamp()
    if type(SpecAnalyserMeta) ~= "table" then return nil end
    local stamp = SpecAnalyserMeta._stamp
    return type(stamp) == "table" and stamp or nil
end

--- Enchantement de reference d'un emplacement : identifiant et taux d'adoption.
function Meta.Enchant(slot)
    local data = block()
    if not data then return nil end
    local list = (data.enchants or {})[slot]
    local best = list and list[1]
    if not best then return nil end
    return best.id, best.share or 0
end

--- Repartition moyenne des statistiques secondaires chez les joueurs releves.
--- @return table|nil { haste = { share, rating }, ... }
function Meta.StatProfile()
    local data = block()
    if not data then return nil end
    local stats = data.stats
    if type(stats) ~= "table" or not next(stats) then return nil end
    return stats
end

--- Ordre de priorite des statistiques secondaires, du plus au moins joue.
--- @return table|nil { { key, share }, ... }
function Meta.StatPriority()
    local profile = Meta.StatProfile()
    if not profile then return nil end

    local order = {}
    for _, definition in ipairs(ns.Gear.STATS) do
        local entry = profile[definition.key]
        -- Une cle absente n'est pas un zero : le releve ne l'a simplement pas vue.
        if entry then
            table.insert(order, { key = definition.key, label = definition.label, share = entry.share or 0 })
        end
    end

    table.sort(order, function(a, b) return a.share > b.share end)
    return #order > 0 and order or nil
end

--- Part visee pour une statistique, d'apres le releve.
function Meta.StatTarget(key)
    local profile = Meta.StatProfile()
    local entry = profile and profile[key]
    return entry and entry.share or nil
end

--- Gemme la plus posee, tous emplacements confondus.
function Meta.Gem()
    local data = block()
    if not data then return nil end
    local best = (data.gems or {})[1]
    if not best then return nil end
    return best.id, best.share or 0
end

--- Gemmes relevees pour un emplacement, par RANG de chasse.
---
--- Le rang, pas la couleur : l'equipement releve ne porte que les identifiants de gemmes
--- dans l'ordre des chasses de l'objet, jamais la couleur de la chasse. Dire « chasse 1 »
--- est exact ; dire « la chasse jaune » serait une extrapolation.
--- @return table|nil { [rang] = { { id, count, share }, ... } }
function Meta.SocketGems(slot)
    local data = block()
    local sockets = data and data.sockets
    if type(sockets) ~= "table" then return nil end
    local entry = sockets[slot]
    return type(entry) == "table" and entry or nil
end

--- Auras portees au pull par les joueurs releves.
---
--- Ce sont des buffs, pas des consommables : les champs `flask`, `food` et `potion` n'existent
--- pas dans la source, et rien ne distingue un flacon d'une Intelligence arcanique. On liste
--- ce qui est mesure et le titre le dit.
--- @return table|nil liste, number echantillon
function Meta.Auras()
    local data = block()
    local list = data and data.auras
    if type(list) ~= "table" or #list == 0 then return nil, 0 end
    return list, data.auraSample or 0
end

--- Statistiques tertiaires moyennes du releve, en points.
function Meta.Tertiary()
    local data = block()
    local entry = data and data.tertiary
    return type(entry) == "table" and entry or nil
end

--- Combinaisons d'enchantements d'armes relevees, la plus jouee en tete.
--- @return table|nil { { ids = { a, b }, count, share }, ... }
function Meta.WeaponPairs()
    local data = block()
    local pairs_ = data and data.weapons
    return (type(pairs_) == "table" and #pairs_ > 0) and pairs_ or nil
end

--- Les deux armes portent-elles une combinaison relevee ?
---
--- Compter chaque main separement ment : sur Midnight Falls, 16 des 20 meilleurs Devourer
--- portent 8041 en main droite et 12 en main gauche, ce qui laisse croire a un enchantement
--- unique. Par joueur, la verite est 11 paires mixtes 7983+8041, 8 doubles 8041, 1 autre —
--- 60 % portent deux enchantements DIFFERENTS. La paire est la seule unite qui a un sens.
---
--- @return boolean|nil ok, table|nil meilleure paire, number part de paires mixtes
function Meta.WeaponPairAdvice(mainEnchant, offEnchant)
    local list = Meta.WeaponPairs()
    if not list then return nil, nil, 0 end

    local worn = { mainEnchant or 0, offEnchant or 0 }
    table.sort(worn)

    local mixed = 0
    local ok = false
    for _, entry in ipairs(list) do
        local ids = entry.ids or {}
        if #ids > 1 and ids[1] ~= ids[2] then mixed = mixed + (entry.share or 0) end
        if #ids == #worn then
            local same = true
            for index = 1, #ids do
                if ids[index] ~= worn[index] then same = false end
            end
            if same then ok = true end
        end
    end

    return ok, list[1], mixed
end

-- En dessous de ce taux d'adoption, l'enchantement releve tient de l'usage minoritaire
-- (metier, choix personnel) : on le propose sans en faire une alerte.
local MIN_ADOPTION = 0.5

--- Un emplacement doit-il porter un enchantement ? Repond d'apres les logs.
--- C'est ce qui evite de reclamer un enchantement de cape ou de bracelets quand aucun
--- joueur du haut de tableau n'en porte : le patch n'en propose pas.
--- @return boolean expected, boolean known
function Meta.ExpectsEnchant(slot)
    local data = block()
    if not data or (data.sample or 0) <= 0 then return false, false end
    local list = (data.enchants or {})[slot]
    if not list or #list == 0 then return false, true end

    local total = 0
    for _, entry in ipairs(list) do
        total = total + (entry.share or 0)
    end
    return total >= MIN_ADOPTION, true
end

--- Chaine d'objet reelle dans laquelle on a injecte l'enchantement de reference.
--- Sert a lire le nom de l'enchantement et a afficher l'infobulle du jeu.
function Meta.ForgedLink(referenceLink, slot, enchantID)
    enchantID = enchantID or Meta.Enchant(slot)
    if not referenceLink or not enchantID then return nil end

    local itemString = referenceLink:match("|Hitem:([%-%d:]+)")
    if not itemString then return nil end

    local parts = { strsplit(":", itemString) }
    parts[2] = tostring(enchantID)
    return "|cffffffff|Hitem:" .. table.concat(parts, ":") .. "|h[x]|h|r"
end

--- Nom lisible d'un enchantement, lu dans l'infobulle d'un objet reel dont on remplace
--- le champ d'enchantement. Retourne nil si l'objet de reference manque.
function Meta.EnchantName(referenceLink, enchantID)
    local forged = Meta.ForgedLink(referenceLink, nil, enchantID)
    if not forged then return nil end

    local tooltip = ensureScanner()
    tooltip:ClearLines()
    local ok = pcall(tooltip.SetHyperlink, tooltip, forged)
    if not ok then return nil end

    local prefix = enchantPrefix()
    local length = #prefix
    local greenLine

    for index = 2, tooltip:NumLines() do
        local line = _G["SpecAnalyserScanTooltipTextLeft" .. index]
        local text = line and line:GetText()
        if text and text ~= "" then
            -- Cas nominal : la ligne commence par le libelle localise "Enchante : ".
            if length > 0 and text:sub(1, length) == prefix then
                local name = text:sub(length + 1)
                if name ~= "" then return name end
            end

            -- Repli : la ligne d'enchantement est verte. Certains clients ne prefixent
            -- pas, et le libelle localise a deja change de forme par le passe.
            if not greenLine and line.GetTextColor then
                local r, g, b = line:GetTextColor()
                if r and r < 0.3 and g > 0.7 and b < 0.3 and not text:find("^%+") then
                    greenLine = text
                end
            end
        end
    end

    return greenLine
end

--- Toutes les lignes de l'infobulle d'un objet, telles que le client les rend.
---
--- On lit le client plutot que de reassembler les statistiques a la main : le texte est deja
--- formate, deja traduit, et il porte tout — armure, statistiques, chasses, ligne
--- d'enchantement, durabilite. Reconstruire ca depuis les API serait plus fragile et moins
--- fidele.
--- @return table|nil { { text, r, g, b }, ... }
function Meta.ItemTooltipLines(link)
    if not link then return nil end

    local tooltip = ensureScanner()
    tooltip:ClearLines()
    if not pcall(tooltip.SetHyperlink, tooltip, link) then return nil end

    local lines = {}
    for index = 1, tooltip:NumLines() do
        local fontString = _G["SpecAnalyserScanTooltipTextLeft" .. index]
        local text = fontString and fontString:GetText()
        if text then
            local r, g, b = 1, 1, 1
            if fontString.GetTextColor then r, g, b = fontString:GetTextColor() end
            table.insert(lines, { text = text, r = r, g = g, b = b })
        end
    end

    return #lines > 0 and lines or nil
end

--- Ce que l'enchantement ajoute a l'infobulle de l'objet, ligne par ligne.
---
--- WoW n'expose ni lien ni infobulle propre a un enchantement : le seul endroit ou le
--- client decrit un enchantement, c'est l'infobulle de l'objet qui le porte. On lit donc
--- celle de l'objet nu, puis celle du meme objet avec l'identifiant force, et on retient
--- ce qui est apparu. Le texte affiche est celui du client — deja formate, deja traduit.
--- @return table|nil { { text, r, g, b }, ... }
function Meta.EnchantTooltipLines(referenceLink, enchantID)
    if not referenceLink then return nil end

    local forged = Meta.ForgedLink(referenceLink, nil, enchantID)
    if not forged then return nil end

    local tooltip = ensureScanner()

    local function read(link)
        tooltip:ClearLines()
        if not pcall(tooltip.SetHyperlink, tooltip, link) then return nil end

        local lines = {}
        for index = 1, tooltip:NumLines() do
            local fontString = _G["SpecAnalyserScanTooltipTextLeft" .. index]
            local text = fontString and fontString:GetText()
            if text and text ~= "" then
                local r, g, b = 1, 1, 1
                if fontString.GetTextColor then r, g, b = fontString:GetTextColor() end
                table.insert(lines, { text = text, r = r, g = g, b = b })
            end
        end
        return lines
    end

    local bare, enchanted = read(referenceLink), read(forged)
    if not bare or not enchanted then return nil end

    -- On compte les occurrences plutot que de tester l'appartenance : une ligne deja
    -- presente deux fois sur l'objet nu ne doit pas passer pour un apport au troisieme
    -- exemplaire.
    local budget = {}
    for _, line in ipairs(bare) do
        budget[line.text] = (budget[line.text] or 0) + 1
    end

    local added = {}
    for _, line in ipairs(enchanted) do
        local left = budget[line.text] or 0
        if left > 0 then
            budget[line.text] = left - 1
        else
            table.insert(added, line)
        end
    end

    return #added > 0 and added or nil
end

--- Nom d'une gemme depuis son identifiant d'objet.
function Meta.GemName(gemID)
    if not gemID then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    local ok, name = pcall(getInfo, gemID)
    if ok and name then return name end

    -- L'objet n'est pas encore en cache : on le demande pour la prochaine ouverture.
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, gemID)
    end
    return nil
end

--- Texte de conseil pour un emplacement, ou nil.
function Meta.EnchantAdvice(slot, referenceLink)
    local enchantID, share = Meta.Enchant(slot)
    if not enchantID then return nil end

    local name = Meta.EnchantName(referenceLink, enchantID)
    -- L'echantillon n'est plus dans la ligne : il est declare une fois par bloc.
    return string.format("%s  |cff8A8A8A(%s)|r",
        name or ("enchant #" .. enchantID),
        string.format(ns.L["%d%% adoption"], (share or 0) * 100 + 0.5))
end

--- Texte de conseil de gemme, ou nil.
function Meta.GemAdvice()
    local gemID, share = Meta.Gem()
    if not gemID then return nil end

    local name = Meta.GemName(gemID)
    return string.format("%s  |cff8A8A8A(%d%% of gems socketed)|r",
        name or ("gem #" .. gemID),
        (share or 0) * 100 + 0.5)
end
