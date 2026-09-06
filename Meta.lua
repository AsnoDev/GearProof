local _, ns = ...

local Meta = {}
ns.Meta = Meta

-- Reference deduite des logs : ce que portent reellement les joueurs les mieux classes
-- de la spe. Le fichier Data/Meta.lua est genere par :
--   specanalyser wcl enchants --encounter <id> --to-addon
--
-- Aucune API du jeu n'expose "le meilleur enchantement du patch". Le classement, lui,
-- est mesurable : on regarde ce qui est pose sur les personnages du haut de tableau.

-- Retrocompatibilite du nom de la table generee.
--
-- L'outil Python ecrivait `SpecAnalyserMeta`. Un fichier deja installe reste lisible :
-- refuser une donnee parfaitement valide au motif qu'elle porte l'ancien nom obligerait
-- a regenerer avant de pouvoir ouvrir l'addon.
local function reference()
    if type(GearProofMeta) == "table" then return GearProofMeta end
    if type(SpecAnalyserMeta) == "table" then return SpecAnalyserMeta end
    return nil
end

-- Version du format de `Data/Meta.lua`.
--
-- Le fichier est genere par un outil qui evolue de son cote ; le lecteur, lui, ne le
-- savait pas. Un fichier produit par une version plus recente etait lu a l'aveugle : au
-- mieux des champs ignores, au pire des conseils faux, dans les deux cas en silence.
--
-- 1 : format d'origine, sans estampille de version. Accepte — c'est ce qui est installe
--     aujourd'hui, et le refuser casserait toutes les installations existantes.
-- 2 : `_stamp.format` et `_stamp.generatedAt` presents.
local FORMAT_SUPPORTED = 2
local formatWarned = false

--- Le relevé installe est-il lisible par cette version de l'addon ?
--- Un format INCONNU est refuse, une fois, avec un message actionnable — plutot que lu
--- de travers sans que rien ne le dise.
local function formatIsReadable()
    local data = reference()
    if not data then return false end

    local stamp = data._stamp
    local format = (type(stamp) == "table" and stamp.format) or 1
    if format <= FORMAT_SUPPORTED then return true end

    if not formatWarned then
        formatWarned = true
        ns.Print("%s%s|r", ns.Theme.C("critical"),
            string.format(ns.L["the shipped reference is in format %d, this addon reads up to %d — update the addon"],
                format, FORMAT_SUPPORTED))
    end
    return false
end

-- Trois lecteurs ont ete retires ici : `Auras` (buffs au pull), `Tertiary` et
-- `SocketGems` — ce dernier rendait la gemme la plus posee par RANG DE CHASSE. Le bloc
-- gemmes de l'onglet Equipement s'en servait pour dire « chasse 1 de la Tete : X, chasse
-- 1 du Cou : Y », soit une quarantaine de lignes pour repondre a une question qui en
-- demande une : quelle gemme poser. Ou la poser appartient au joueur — c'est deja la
-- regle de l'onglet Recommandations. La table `sockets` reste generee et livree. Ils
-- alimentaient deux categories de l'onglet Recommandations jugees sans valeur a l'usage.
-- Les donnees `auras`, `auraSample` et `tertiary` sont donc toujours generees et livrees
-- pour les 40 specialisations sans etre lues : le generateur peut cesser de les emettre,
-- ou ces lecteurs revenir. C'est un choix a faire, pas un oubli.

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
    scanner = CreateFrame("GameTooltip", "GearProofScanTooltip", nil, "GameTooltipTemplate")
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
    if not formatIsReadable() then return nil end
    local data = reference()
    if data.sample then return data end
    if not ns.Spec then return nil end

    local specID = ns.Spec.Selected()

    -- Cle de secours, insensible a la langue : l'identifiant Blizzard, quand le releve le
    -- connait. C'est la voie preferee.
    if specID then
        for _, entry in pairs(data) do
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
        local entry = data[classSlug .. "/" .. slug]
        if type(entry) == "table" then return entry end
    end

    return nil
end

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

--- Y a-t-il un releve pour au moins une specialisation ?
--- Sert a distinguer « aucune donnee installee » de « pas de donnee pour CETTE spe ».
function Meta.AnyAvailable()
    local data = reference()
    if not data then return false end
    if data.sample then return (data.sample or 0) > 0 end
    for key, entry in pairs(data) do
        -- `_stamp` decrit le releve, ce n'est pas une specialisation.
        if type(key) ~= "string" or key:sub(1, 1) ~= "_" then
            if type(entry) == "table" and (entry.sample or 0) > 0 then return true end
        end
    end
    return false
end

--- Estampille du releve embarque : format, date, nombre de spes, rencontres relevees.
--- @return table|nil { format, generatedAt, specs, encounters }
function Meta.Stamp()
    local data = reference()
    if not data then return nil end
    local stamp = data._stamp
    return type(stamp) == "table" and stamp or nil
end

--- Age du releve en jours, ou nil quand il ne porte pas de date.
---
--- L'interface annoncait la taille de l'echantillon sans jamais dire de QUAND il date.
--- Un releve de six semaines decrit un patch qui n'existe plus.
function Meta.AgeInDays()
    local stamp = Meta.Stamp()
    local generated = stamp and stamp.generatedAt
    if type(generated) ~= "string" then return nil end

    local year, month, day = generated:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if not year then return nil end

    local ok, then_ = pcall(time, {
        year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = 12, min = 0, sec = 0,
    })
    if not ok or not then_ then return nil end

    return math.max(0, math.floor((time() - then_) / 86400))
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
    for _, definition in ipairs(ns.Stats.LIST) do
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

--- Classement des gemmes posees, tous emplacements confondus, la plus jouee en tete.
---
--- C'est la forme UTILE de la donnee. L'onglet Recommandations la presentait par
--- emplacement et par rang de chasse — une quarantaine de lignes pour dire ce que trois
--- suffisent a dire. Ou poser quelle gemme est une decision de joueur ; ce que l'addon
--- peut apporter, c'est le classement mesure et le nombre de chasses vides.
--- @return table|nil { { id, count, share }, ... }
function Meta.GemRanking()
    local data = block()
    local list = data and data.gems
    return (type(list) == "table" and #list > 0) and list or nil
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

--- Deux ecoles dans une meme specialisation, quand le releve en detecte.
---
--- C'est la donnee la plus interessante du releve, et elle n'a jamais eu de lecteur.
--- Le generateur teste si la repartition d'une statistique est BIMODALE : deux groupes
--- separes plutot qu'un nuage autour d'une moyenne. Quand c'est le cas, la moyenne ne
--- decrit AUCUN des deux — dire « vise 27 % de maitrise » a une spe qui joue soit 21 %
--- soit 38 % est un conseil que personne ne suit.
---
--- Le seuil de 8 points d'ecart et de 3 joueurs par groupe est un seuil d'AFFICHAGE :
--- en dessous, deux groupes proches ne racontent rien qu'une moyenne ne dise deja.
---
--- @return table|nil { { key, label, low, lowN, high, highN, gap, side } }
--- Role releve pour cette specialisation : "tank", "healer" ou "dps".
---
--- Celui du RELEVE, pas celui du client. Il dit sur quelle metrique le haut de tableau a
--- ete classe — et donc si le releve decrit bien la population qu'on croit.
--- @return string|nil
function Meta.Role()
    local data = block()
    return data and data.role or nil
end

--- Taux d'adoption par TALENT, du plus pris au moins pris.
---
--- La vue robuste sur les builds. Le regroupement par arbre exact plafonne autour de 25 %
--- — le haut de tableau ne partage presque jamais un arbre au point pres — alors que
--- « 19 des 20 meilleurs prennent ce talent » se lit comme le releve d'enchantements que
--- l'addon montre deja, et se compare a ce que le joueur a reellement pris.
--- @return table|nil { { id, count, share }, ... }
function Meta.Talents()
    local data = block()
    local list = data and data.talents
    return (type(list) == "table" and #list > 0) and list or nil
end

--- Groupes de joueurs partageant un arbre de talents IDENTIQUE.
---
--- Complementaire du precedent : le tally dit quels CHOIX font consensus, les groupes
--- disent quels ENSEMBLES existent reellement — et chacun porte sa propre repartition de
--- statistiques. C'est ce qui manquait pour donner un sens a `Meta.Modes()` : il disait
--- « la maitrise se joue a 21 % ou a 38 % » sans dire quel build etait derriere.
--- @return table|nil { { n, share, differs, stats }, ... }
function Meta.Builds()
    local data = block()
    local list = data and data.builds
    return (type(list) == "table" and #list > 0) and list or nil
end

--- Fourchette interquartile d'une statistique : p25, p75, ecart.
---
--- Genere depuis toujours, jamais lu. C'est pourtant ce qui distingue une cible d'une
--- fourchette : « critique 55 %, ecart 8 points » veut dire serre, donc vise ; « ecart 30 »
--- veut dire que le haut de tableau ne s'accorde pas, donc ne t'inquiete pas. Une priorite
--- sans dispersion se lit comme un ordre alors que c'est parfois un intervalle.
--- @return number|nil p25, number|nil p75, number|nil spread
function Meta.StatRange(key)
    local profile = Meta.StatProfile()
    local entry = profile and profile[key]
    if type(entry) ~= "table" then return nil end
    return entry.p25, entry.p75, entry.spread
end

---   `side` dit de quel cote TU es, "low" ou "high".
local MODE_MIN_GAP = 0.08
local MODE_MIN_GROUP = 3

function Meta.Modes()
    local data = block()
    local modes = data and data.modes
    if type(modes) ~= "table" then return nil end

    local stats = ns.Stats.Current()
    local total = 0
    for _, definition in ipairs(ns.Stats.LIST) do
        total = total + ((stats[definition.key] or {}).rating or 0)
    end

    local found = {}
    for _, definition in ipairs(ns.Stats.LIST) do
        local entry = modes[definition.key]
        if type(entry) == "table" and (entry.gap or 0) >= MODE_MIN_GAP
            and (entry.lowN or 0) >= MODE_MIN_GROUP and (entry.highN or 0) >= MODE_MIN_GROUP then

            -- De quel cote es-tu ? On compare TA part de budget aux deux centres, et on
            -- prend le plus proche. Pas de verdict : la ou tu te situes, rien de plus.
            local side
            if total > 0 then
                local share = ((stats[definition.key] or {}).rating or 0) / total
                side = math.abs(share - (entry.low or 0)) <= math.abs(share - (entry.high or 0))
                    and "low" or "high"
            end

            table.insert(found, {
                key = definition.key, label = definition.label,
                low = entry.low or 0, lowN = entry.lowN or 0,
                high = entry.high or 0, highN = entry.highN or 0,
                gap = entry.gap or 0, side = side,
            })
        end
    end

    table.sort(found, function(a, b) return a.gap > b.gap end)
    return #found > 0 and found or nil
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
    -- Le decoupage vit dans ItemLink : la position du champ d'enchantement etait ecrite
    -- ici en dur (`parts[2]`) alors qu'elle est nommee la-bas.
    return ns.ItemLink.WithEnchant(referenceLink, enchantID)
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
        local line = _G["GearProofScanTooltipTextLeft" .. index]
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
        local fontString = _G["GearProofScanTooltipTextLeft" .. index]
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
            local fontString = _G["GearProofScanTooltipTextLeft" .. index]
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

    local facts = ns.ItemInfo.Get(gemID)
    if facts and facts.name then return facts.name end

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

    -- Le NOM, rien d'autre.
    --
    -- La part etait accolee entre parentheses a chaque titre de carte, a chaque infobulle
    -- d'objet et a chaque ligne de l'onglet Recommandations : le meme « 35 % » repete
    -- partout finit par ne plus rien vouloir dire, et il vole la place du nom — la seule
    -- information dont le joueur a besoin pour aller chez l'enchanteur. Le chiffre survit
    -- a UN seul endroit, l'onglet Recommandations, ou il classe.
    return Meta.EnchantName(referenceLink, enchantID) or ("enchant #" .. enchantID)
end

--- Texte de conseil de gemme, ou nil.
function Meta.GemAdvice()
    local gemID, share = Meta.Gem()
    if not gemID then return nil end

    -- Le nom seul, comme pour les enchantements : le titre de carte doit dire QUOI poser.
    return Meta.GemName(gemID) or ("gem #" .. gemID)
end
