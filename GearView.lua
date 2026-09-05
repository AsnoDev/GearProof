local _, ns = ...

local GearView = {}
ns.GearView = GearView

-- Onglet Equipement, en deux colonnes : les cartes d'action a gauche, la note et la
-- repartition des statistiques a droite.

local COLORS = setmetatable({}, {
    __index = function(_, key)
        local map = { critical = "critical", major = "bis", good = "good",
                      accent = "link", minor = "muted" }
        return ns.Theme.RGB[map[key] or key] or { 1, 1, 1 }
    end,
})


local L = ns.L

local view, pools, selectedSlot
local layoutUpgrades, layoutGems
-- Declaration en amont : `GearView.Create` construit les pools et a donc besoin des
-- fabriques, dont celle-ci est definie plus bas. Sans ca, `local function newPanel`
-- creerait un nouveau nom et le pool capturerait nil.
local newPanel

local function hex(color)
    return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

-- --------------------------------------------------------------------- pooling
--
-- Les pools sont crees dans `GearView.Create`, une fois `view` disponible : les fabriques
-- ancrent leurs cadres sur `view.content`.

local function resetPools()
    ns.Pool.ResetAll(pools)
end

local function acquire(kind)
    return pools[kind]:Acquire()
end

-- Hauteur d'une carte de correctif : UNE ligne.
--
-- Elle en faisait trois — titre, corps, gestes — pour 58 px minimum. Cinq correctifs
-- occupaient donc 290 px de la colonne centrale, et il fallait faire defiler pour voir la
-- liste que l'onglet est cense montrer d'un coup.
--
-- Le corps etait la redondance : `issueTitle` ecrit deja « Cape : Glissement du Void
-- manquant », et `entry.problems` redisait « enchantement manquant » juste en dessous. Ce
-- qui reste tient sur une ligne : marqueur, icone, titre a gauche, geste a droite.
--
-- Le geste reste PERMANENT, pas au survol. Il etait invisible avant qu'on l'affiche, et
-- personne ne devinait le clic droit ; il change juste de place, pas de statut.
local ISSUE_HEIGHT = 28

--- Carte d'un probleme : bandeau colore, icone, titre, geste.
local function newIssueCard()
    local card = CreateFrame("Button", nil, view.content, "BackdropTemplate")
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    card.accent = card:CreateTexture(nil, "ARTWORK")
    card.accent:SetPoint("TOPLEFT")
    card.accent:SetPoint("BOTTOMLEFT")
    card.accent:SetWidth(3)

    card:SetHeight(ISSUE_HEIGHT)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(18, 18)
    card.icon:SetPoint("LEFT", 9, 0)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.marker = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.marker:SetPoint("LEFT", card.icon, "RIGHT", 6, 0)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.title:SetPoint("LEFT", card.marker, "RIGHT", 5, 0)
    card.title:SetJustifyH("LEFT")
    card.title:SetWordWrap(false)

    -- Geste, aligne a droite sur la meme ligne. Permanent : il ne depend ni du survol ni
    -- de la presence d'un releve.
    card.hint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.hint:SetPoint("RIGHT", -10, 0)
    card.hint:SetJustifyH("RIGHT")
    card.hint:SetWordWrap(false)

    return card
end

-- ------------------------------------------------------------------ colonnes

local function issueTitle(entry)
    if entry.empty then return string.format(L["%s: empty slot"], L[entry.label]) end
    if entry.missingEnchant then
        local advice = ns.Recommendations.Enchant(entry.slot, entry.link)
        return string.format("%s: %s%s|r %s", L[entry.label],
            hex(COLORS.accent), advice or L["enchant"], advice and "" or L["missing"])
    end
    if (entry.emptySockets or 0) > 0 then
        local advice = ns.Recommendations.Gem(entry.slot)
        return string.format("%s: %s%s|r %s", L[entry.label],
            hex(COLORS.accent), advice or L["gem"], L["missing"])
    end
    if entry.damaged then return string.format(L["%s: damaged"], L[entry.label]) end
    return entry.label
end

-- Panneau de detail de la piece selectionnee. Il affiche l'infobulle du client mot pour mot
-- (`Meta.ItemTooltipLines`) plutot que de reassembler armure, statistiques et chasses depuis
-- les API : le texte est deja formate, deja traduit, et il porte la ligne d'enchantement et
-- la durabilite. Reconstruire tout ca serait plus fragile et moins fidele.
--
-- Il remplace l'infobulle au survol, qui disparaissait des qu'on bougeait la souris.
local function newDetail()
    local card = CreateFrame("Frame", nil, view.content, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(34, 34)
    card.icon:SetPoint("TOPLEFT", 10, -10)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.heading = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.heading:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -4)
    card.heading:SetJustifyH("LEFT")

    card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.body:SetPoint("TOPLEFT", 10, -52)
    card.body:SetJustifyH("LEFT")
    card.body:SetJustifyV("TOP")
    card.body:SetSpacing(2)

    card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
    card.close:SetSize(24, 24)
    card.close:SetPoint("TOPRIGHT", 0, 0)
    card.close:SetScript("OnClick", function() GearView.Select(nil) end)

    return card
end

--- Carte des gemmes : la reponse d'abord, le detail ensuite.
---
--- Elle ne reutilise pas `newPanel` parce qu'elle porte une ICONE et deux lignes de tete
--- de tailles differentes : la gemme a poser doit se voir sans etre lue.
local function newGemCard()
    local card = CreateFrame("Button", nil, view.content, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.title:SetPoint("TOPLEFT", 12, -8)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(24, 24)
    card.icon:SetPoint("TOPLEFT", 12, -26)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.headline = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.headline:SetPoint("LEFT", card.icon, "RIGHT", 8, 0)
    card.headline:SetJustifyH("LEFT")
    card.headline:SetWordWrap(false)

    card.count = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.count:SetPoint("RIGHT", -12, 0)
    card.count:SetPoint("TOP", card.icon, "TOP", 0, -6)
    card.count:SetJustifyH("RIGHT")
    card.count:SetWordWrap(false)

    card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.body:SetPoint("TOPLEFT", 12, -56)
    card.body:SetJustifyH("LEFT")
    card.body:SetJustifyV("TOP")
    card.body:SetSpacing(3)

    -- Survol : l'infobulle REELLE de la gemme. Un nom seul ne dit pas ce qu'elle donne.
    card:SetScript("OnEnter", function(self)
        if not self.gemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if not pcall(GameTooltip.SetItemByID, GameTooltip, self.gemID) then
            GameTooltip:AddLine("item:" .. self.gemID)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return card
end

--- Pose le panneau de detail. Retourne le nouveau haut.
local function layoutDetail(top, width, entry)
    if not entry or not entry.link then return top end

    local card = acquire("detail")
    card:SetParent(view.content)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, top)
    card:SetWidth(width)
    ns.Theme.ApplyCard(card)

    card.icon:SetTexture(entry.slotID and GetInventoryItemTexture("player", entry.slotID)
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.heading:SetWidth(width - 90)
    card.heading:SetText(hex(COLORS.accent) .. L[entry.label] .. "|r")

    local lines = ns.Meta.ItemTooltipLines(entry.link)
    local text = {}
    for _, line in ipairs(lines or {}) do
        -- Chaque ligne garde la couleur que le client lui a donnee : la qualite, le vert des
        -- enchantements, le gris des mentions. La recolorer perdrait de l'information.
        table.insert(text, string.format("|cff%02x%02x%02x%s|r",
            line.r * 255, line.g * 255, line.b * 255, line.text))
    end

    if #text == 0 then
        table.insert(text, hex(COLORS.muted)
            .. L["Item data not loaded yet — click again in a moment."] .. "|r")
    end

    card.body:SetWidth(width - 20)
    card.body:SetText(table.concat(text, "\n"))
    card:SetHeight(58 + card.body:GetStringHeight() + 12)

    return top - card:GetHeight() - 10
end

-- Un seul OnLeave pour toutes les lignes qui n'ouvrent qu'une infobulle.

-- Gestionnaires des cartes de correctif, poses UNE fois.
--
-- Ils etaient trois closures construites a l'interieur de `layoutIssue`, donc trois
-- fermetures neuves par carte et par rendu. Sur un audit charge, ouvrir l'onglet en
-- produisait une trentaine, toutes identiques sauf la piece capturee — du ramassage de
-- miettes gratuit a chaque rafraichissement, y compris pendant une rencontre.
--
-- L'etat voyage sur le widget (`card.entry`), pose juste avant. C'est deja la convention
-- de `RecoView.resetRow`, qui les remet a nil au retour au pool.
local function issueOnEnter(self)
    local entry = self.entry
    if not entry then return end
    ns.Armory.Highlight(entry.slot, true)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    -- Infobulle de L'ENCHANTEMENT, pas de la piece.
    --
    -- WoW n'a pas de type de lien pour un enchantement : impossible de lui demander une
    -- infobulle. Le seul endroit ou le client decrit un enchantement, c'est l'infobulle
    -- de l'objet qui le porte. On affiche donc ce que l'enchantement y ajoute, mot pour
    -- mot — texte du client, deja formate et deja traduit.
    local enchantID = entry.missingEnchant and ns.Meta.Enchant(entry.slot)
    if enchantID then
        local name = ns.Meta.EnchantName(entry.link, enchantID)
        GameTooltip:AddLine(name or ("Enchant #" .. enchantID), 0, 0.9, 0.46)

        local points, lines = ns.Gear.EnchantPoints(entry.link, entry.slot, enchantID)
        for _, line in ipairs(lines or {}) do
            -- Une ligne qui ne fait que repeter le nom sans porter de chiffre n'ajoute
            -- rien au titre deja affiche.
            local repeatsName = name and line.text:find(name, 1, true) and not line.text:find("%d")
            if not repeatsName then
                GameTooltip:AddLine(line.text, line.r, line.g, line.b, true)
            end
        end

        if points > 0 then
            GameTooltip:AddLine(string.format(L["%d stat points"], points), 0.54, 0.54, 0.54)
        end

        GameTooltip:AddLine(" ")
    else
        GameTooltip:AddLine(L[entry.label], 0.91, 0.91, 0.91)
        for _, problem in ipairs(entry.problems) do
            GameTooltip:AddLine(problem, 0.81, 0.79, 0.87, true)
        end
        GameTooltip:AddLine(" ")
    end

    -- LES DEUX GESTES, sur toutes les cartes.
    --
    -- La carte n'en montre plus qu'un : la place d'une seconde mention y valait le titre.
    -- Mais l'infobulle ne s'ouvrait qu'en presence d'un enchantement releve, et sortait
    -- donc en meme temps que la ligne « clic droit : ignorer » — un geste que personne ne
    -- devine et qu'aucun autre ecran ne mentionne. Elle s'ouvre desormais toujours.
    GameTooltip:AddLine(entry.missingEnchant and enchantID
        and L["click to copy the name"] or L["left-click: details"], 0, 0.69, 1)
    GameTooltip:AddLine(entry.ignored and L["right-click: un-ignore"]
        or L["right-click: ignore"], 0.54, 0.54, 0.54)
    GameTooltip:Show()
end

local function issueOnLeave(self)
    if self.entry then ns.Armory.Highlight(self.entry.slot, false) end
    GameTooltip:Hide()
end

local function issueOnClick(self, button)
    local entry = self.entry
    if not entry then return end

    if button == "RightButton" then
        ns.Gear.SetIgnored(entry.slot, not entry.ignored)
        ns.UI.RefreshNow()
        return
    end

    -- Clic gauche : le nom seul dans un champ copiable, pour l'hotel des ventes. Quand il
    -- n'y a pas de nom a copier, la piece s'ouvre dans le panneau de detail — la meme
    -- surface que le clic sur une tuile, au lieu d'une seconde fenetre flottante.
    local name = entry.missingEnchant
        and ns.Meta.EnchantName(entry.link, ns.Meta.Enchant(entry.slot))
    if name then
        ns.Copy.Show(L["Search this in the auction house"], name)
    else
        GearView.Select(entry.slot)
    end
end

local function layoutIssue(entry, width, top, color)
    local card = acquire("issue")
    card:SetParent(view.content)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, top)
    card:SetWidth(width)

    card:SetHeight(ISSUE_HEIGHT)

    ns.Theme.ApplyCard(card, color)
    card.accent:SetColorTexture(color[1], color[2], color[3], 1)
    card.marker:SetText(hex(color) .. "!|r")

    local texture = entry.slotID and GetInventoryItemTexture("player", entry.slotID)
    card.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- UN geste sur la carte : celui du clic gauche, qui varie selon la piece. Le clic
    -- droit « ignorer » est le meme partout, il vit dans l'infobulle et dans l'onglet
    -- Aide — le repeter sur chaque ligne prenait la place du titre.
    local hint = (entry.missingEnchant and ns.Meta.Enchant(entry.slot))
        and L["left-click: copy the enchant name"] or L["left-click: details"]
    card.hint:SetText("|cff5A5A5A" .. hint .. "|r")

    -- Le titre prend ce que le geste laisse. Mesure REELLE de la largeur du geste : la
    -- reserver en dur donnerait un titre tronque en francais et un blanc en anglais.
    local hintWidth = math.ceil(card.hint:GetStringWidth() or 0)
    card.title:SetWidth(math.max(60, width - hintWidth - 60))

    -- `issueTitle` porte deja le nom de l'emplacement et ce qui manque. Ce que la liste
    -- des problemes ajoute vraiment — un compte de chasses, une piece ignoree — est
    -- accole ; le reste redisait le titre mot pour mot sur une deuxieme ligne.
    local title = issueTitle(entry)
    if (entry.emptySockets or 0) > 1 then
        title = title .. string.format("|cff8A8A8A  (%d)|r", entry.emptySockets)
    end
    if entry.ignored then
        title = title .. "|cff8b6bff  " .. L["ignored"] .. "|r"
    end
    card.title:SetText(title)

    card.entry = entry
    card:SetScript("OnEnter", issueOnEnter)
    card:SetScript("OnLeave", issueOnLeave)
    card:SetScript("OnClick", issueOnClick)

    return top - ISSUE_HEIGHT - 4
end


-- ------------------------------------------------------------------ public

function GearView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- Les cartes de probleme portent des textes et des scripts qui ne sont pas tous
    -- reecrits par chaque usage : la carte « Rien a corriger » n'en pose que deux. Sans
    -- remise a neuf, elle heritait de la ligne de gestes de son occupant precedent.
    --
    -- Cette fonction touchait encore `card.body`, retire quand les cartes sont passees a
    -- une ligne. Elle ne s'execute qu'au RECYCLAGE d'une carte : la fenetre s'ouvrait donc
    -- normalement sur un equipement complet, et tombait des le premier correctif a
    -- afficher. Toute suppression de widget doit passer par ici.
    local function resetIssueCard(card)
        card.entry = nil
        card.marker:SetText("")
        card.title:SetText("")
        card.hint:SetText("")
        card:SetScript("OnEnter", nil)
        card:SetScript("OnLeave", nil)
        card:SetScript("OnClick", nil)
    end

    pools = {
        issue = ns.Pool.New(newIssueCard, resetIssueCard),
        panel = ns.Pool.New(newPanel),
        detail = ns.Pool.New(newDetail),
        gems = ns.Pool.New(newGemCard),
    }

    -- Le verdict, en tete : UNE ligne qui repond « est-ce que je suis pret ».
    --
    -- L'onglet s'ouvrait sur « 2 enchantements manquants · 1 chasse vide · 1 piece
    -- abimee » : une enumeration, donc quelque chose a additionner soi-meme avant de
    -- savoir si on peut entrer en raid. Le detail reste, il passe simplement dessous.
    --
    -- Le verdict COMPTE, il ne note pas — meme regle que la jauge. « Pret » veut dire
    -- zero correctif en attente, pas « bon equipement » : l'addon n'a aucun moyen de
    -- juger la seconde chose, et pretendre le contraire serait la note sur 100 qu'on a
    -- refusee partout ailleurs.
    -- Largeur SUIVIE, jusqu'au bord de la colonne de droite. Une largeur figee tronquait
    -- l'enumeration de correctifs des que la traduction s'allongeait — le francais y met
    -- une bonne moitie de plus que l'anglais.
    local headerRight = -(ns.GearSide.WIDTH + 150)

    view.verdict = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.verdict:SetPoint("TOPLEFT", 2, -2)
    view.verdict:SetPoint("RIGHT", view, "RIGHT", headerRight, 0)
    view.verdict:SetJustifyH("LEFT")
    view.verdict:SetWordWrap(false)

    view.summary = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.summary:SetPoint("TOPLEFT", view.verdict, "BOTTOMLEFT", 0, -3)
    view.summary:SetPoint("RIGHT", view, "RIGHT", headerRight, 0)
    view.summary:SetJustifyH("LEFT")
    view.summary:SetWordWrap(false)

    -- « Tout reactiver » vit SUR la bande d'entete, aligne a droite, et non plus sous le
    -- resume. Empile, il poussait la grille vers le bas — mais seulement quand il etait
    -- visible, donc la mise en page changeait selon qu'on avait ignore une piece ou non.
    -- Ici il n'interagit avec la hauteur de rien.
    view.reset = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.reset:SetSize(110, 20)
    view.reset:SetPoint("TOPRIGHT", view, "TOPRIGHT", -(ns.GearSide.WIDTH + 30), -4)
    ns.Localize(view.reset, "Re-enable all")
    view.reset:SetScript("OnClick", function()
        -- Passe par Gear : ecrire `ns.db.ignoredSlots` en direct laissait le cache
        -- d'audit intact et la vue se redessinait sur l'ancien etat.
        ns.Gear.ResetIgnored()
        ns.UI.RefreshNow()
    end)

    -- Colonne 1 : la grille compacte, dans l'onglet et non plus dans la fenetre.
    view.grid = ns.Armory.Create(view)
    -- Ancre RELATIVE au resume, pas un -26 en dur : l'entete est passee a deux lignes et
    -- le decalage constant l'aurait recouverte. Le moteur de mise en page resout la
    -- position, on n'a aucune hauteur a mesurer ni a deviner.
    view.grid:SetPoint("TOPLEFT", view.summary, "BOTTOMLEFT", -2, -10)

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", view.grid, "TOPRIGHT", 16, 0)
    view.scroll:SetPoint("BOTTOMRIGHT", -(ns.GearSide.WIDTH + 30), 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(360, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    -- La colonne de droite vit dans GearSide.lua : jauge, statistiques,
    -- priorite relevee, ensemble de classe, bloc droptimizer. Elle ne partage rien
    -- avec le reste de l'onglet, donc elle ne passe rien non plus.
    view.side = ns.GearSide.Create(view)

    return view
end

--- Carte simple, titre + corps de texte, pour les blocs sans interaction.
newPanel = function()
    local card = CreateFrame("Frame", nil, view.content, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 12, -10)

    card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.body:SetPoint("TOPLEFT", 12, -30)
    card.body:SetJustifyH("LEFT")
    card.body:SetJustifyV("TOP")
    card.body:SetSpacing(3)

    return card
end

--- Le gemmage, emplacement par emplacement, selon les chasses reellement disponibles.
---
--- Une piece sans chasse n'apparait pas : le bloc ne liste que ce sur quoi tu peux agir.
--- Le releve donne la gemme par RANG de chasse (chasse 1, chasse 2), jamais par couleur —
--- la couleur de la chasse n'est pas dans les donnees de Warcraft Logs.
layoutGems = function(width, top, entries)
    -- LA question du joueur est « quelle gemme je pose ». Ce bloc y repondait par un pave
    -- organise par emplacement PUIS par rang de chasse : « Tete + Eclat de Vide · Cou !
    -- vide -> Eclat de Vide · Anneau 2 ~ Autre gemme », suivi d'une legende de trois
    -- glyphes et d'une ligne de provenance. Tout y etait, et rien ne repondait.
    --
    -- Il est desormais construit dans l'ordre de la question :
    --   1. LA gemme a poser, en gros, avec son icone ;
    --   2. dans combien de chasses, et LESQUELLES ;
    --   3. seulement ensuite, ce qui est deja serti et differe du releve.
    --
    -- L'ordre par rang de chasse a disparu avec le reste : ou poser quelle gemme est une
    -- decision de joueur, c'est deja la regle de l'onglet Recommandations.
    local bestID, bestShare = ns.Meta.Gem()
    local emptySlots, differing = {}, {}
    local missing = 0

    for _, entry in ipairs(entries) do
        if entry.link and (entry.sockets or 0) > 0 then
            local worn = entry.gemIDs or {}
            local holes = entry.sockets - #worn
            if holes > 0 then
                missing = missing + holes
                table.insert(emptySlots, { label = entry.label, holes = holes })
            end
            for _, gemID in ipairs(worn) do
                if gemID ~= bestID then
                    table.insert(differing, { label = entry.label, id = gemID })
                end
            end
        end
    end

    -- Rien a dire : ni chasse vide, ni releve. On n'occupe pas la colonne pour ca.
    if missing == 0 and not bestID then return top end

    local card = acquire("gems")
    card:SetParent(view.content)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, top - 6)
    card:SetWidth(width)
    ns.Theme.ApplyCard(card, missing > 0 and COLORS.critical or nil)

    card.title:SetText(hex(COLORS.accent) .. L["GEMS"] .. "|r")

    local icon
    if bestID then
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        if getIcon then
            local ok, value = pcall(getIcon, bestID)
            if ok then icon = value end
        end
    end
    card.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Gem_Variety_01")
    card.icon:SetShown(bestID ~= nil)

    -- La reponse, en toutes lettres.
    card.gemID = bestID
    if bestID then
        card.headline:SetText(string.format("%s%s|r", hex(COLORS.accent),
            ns.Meta.GemName(bestID) or ("gem #" .. bestID)))
        card.count:SetText(missing > 0
            and string.format("%s%s|r", hex(COLORS.critical),
                string.format(L["to socket in %d slot(s)"], missing))
            or string.format("%s%s|r", hex(COLORS.good), L["every socket is filled"]))
    else
        card.headline:SetText(hex(COLORS.minor) .. L["No gem recorded yet."] .. "|r")
        card.count:SetText("")
    end

    -- OU les poser. C'est ce qui manquait pour agir sans revenir a la grille.
    local body = {}
    if #emptySlots > 0 then
        local names = {}
        for _, slot in ipairs(emptySlots) do
            table.insert(names, L[slot.label] .. (slot.holes > 1 and (" x" .. slot.holes) or ""))
        end
        table.insert(body, string.format("%s!|r  %s", hex(COLORS.critical),
            table.concat(names, "  ·  ")))
    end

    -- Ce qui est deja serti mais differe : une remarque, pas une alerte. Le releve dit ce
    -- que le haut de tableau pose le plus, pas ce qui est faux.
    if #differing > 0 then
        local names = {}
        for _, item in ipairs(differing) do
            table.insert(names, string.format("%s (%s)", L[item.label],
                ns.Meta.GemName(item.id) or ("#" .. item.id)))
        end
        table.insert(body, string.format("%s~|r  %s%s : %s|r", hex(COLORS.minor),
            hex(COLORS.minor), L["other than measured"], table.concat(names, "  ·  ")))
    end

    if bestShare and bestShare > 0 then
        table.insert(body, string.format("%s%d%% %s|r", hex(COLORS.minor),
            bestShare * 100 + 0.5,
            string.format(L["of gems on %d top players"], ns.Meta.Sample())))
    end

    card.body:SetWidth(width - 24)
    card.body:SetText(table.concat(body, "\n"))
    card:SetHeight(46 + card.body:GetStringHeight() + 12)

    return top - card:GetHeight() - 8
end

--- Ce que tu transportes et qui vaut mieux que ce que tu portes.
layoutUpgrades = function(width, top)
    local simmed, unrated, _, estimated = ns.Bags.Compare()
    if #simmed == 0 and #unrated == 0 and #estimated == 0 then return top end

    local card = acquire("panel")
    card:SetParent(view.content)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, top - 6)
    card:SetWidth(width)
    ns.Theme.ApplyCard(card)

    card.title:SetText(hex(COLORS.accent) .. L["IN YOUR BAGS"] .. "|r")

    -- Deux blocs, deux unites, jamais dans la meme colonne. Un « +1,2 % » simule est un
    -- pourcentage de DPS ; un gain estime est une somme de points ponderes. Les afficher dans
    -- la meme colonne laissait croire qu'ils sont comparables.
    local lines = {}

    if #simmed > 0 then
        table.insert(lines, hex(COLORS.accent) .. L["simulated (% DPS)"] .. "|r")
        for index = 1, math.min(4, #simmed) do
            local entry = simmed[index]
            table.insert(lines, string.format("%s%+.2f%%|r  %s  %s|cff8A8A8Ai%d, %+d ilvl|r",
                hex(COLORS.good), entry.dps, L[entry.label], entry.link or "?",
                entry.itemLevel or 0, entry.levelDelta or 0))
        end
    end

    if #estimated > 0 then
        if #lines > 0 then table.insert(lines, "") end
        table.insert(lines, hex(COLORS.accent) .. L["estimated (stat points)"] .. "|r")
        for index = 1, math.min(4, #estimated) do
            local entry = estimated[index]
            table.insert(lines, string.format("%s%+d pts|r  %s  %s|cff8A8A8Ai%d, %+d ilvl|r",
                hex(COLORS.good), entry.gain, L[entry.label], entry.link or "?",
                entry.itemLevel or 0, entry.levelDelta or 0))
        end
    end

    for index = 1, math.min(3, #unrated) do
        local entry = unrated[index]
        table.insert(lines, string.format("%s?|r     %s  %s|cff615c73%s|r",
            hex(COLORS.major), L[entry.label], entry.link or "?",
            L[ns.Bags.REASON_TEXT[entry.reason] or ns.Bags.REASON_TEXT.weights]))
    end

    if #lines == 0 then return top end

    card.title:SetWidth(width - 24)
    card.body:SetWidth(width - 24)
    card.body:SetText(table.concat(lines, "\n"))
    local height = 34 + card.body:GetStringHeight() + 12
    card:SetHeight(height)

    return top - height - 14
end

--- Ouvre une piece dans le panneau de detail. `nil` referme le panneau.
--- Recliquer la meme case referme aussi : c'est le geste attendu d'une selection.
function GearView.Select(slotName)
    selectedSlot = (slotName ~= selectedSlot) and slotName or nil
    -- RefreshNow, pas Refresh : un clic sur une tuile doit ouvrir le panneau tout de
    -- suite, pas un quart de seconde plus tard.
    if ns.UI and ns.UI.RefreshNow then ns.UI.RefreshNow() end
end

function GearView.Refresh()
    if not view then return end

    local entries, summary = ns.Gear.Scan()
    ns.Armory.Refresh()
    resetPools()

    -- « Equipement complet » et non « pret pour le raid » : zero correctif en attente est
    -- un fait compte, la seconde formule serait un jugement que l'addon n'a pas les moyens
    -- de porter — c'est la note sur 100 refusee partout ailleurs, en trois mots.
    if summary.problems == 0 then
        view.verdict:SetText(hex(COLORS.good) .. L["Gear complete"] .. "|r")
        view.summary:SetText(hex(COLORS.minor) .. string.format(
            L["%d slots checked, nothing to fix"], summary.checked or 0) .. "|r")
    else
        local parts = {}
        if summary.missingEnchants > 0 then table.insert(parts, string.format(L["%d missing enchant(s)"], summary.missingEnchants)) end
        if summary.emptySockets > 0 then table.insert(parts, string.format(L["%d empty socket(s)"], summary.emptySockets)) end
        if summary.emptySlots > 0 then table.insert(parts, string.format(L["%d empty slot(s)"], summary.emptySlots)) end
        if summary.damaged > 0 then table.insert(parts, string.format(L["%d damaged piece(s)"], summary.damaged)) end
        if (summary.weaponPair or 0) > 0 then table.insert(parts, L["weapon enchant combination"]) end

        -- Ce que ca COUTE de ne rien faire, a cote du compte. Le chiffre existait deja
        -- sous la grille, ou il repond a une question qu'on ne se pose qu'apres avoir lu
        -- le verdict — et la grille est dans l'autre colonne.
        --
        -- Le `≥` a le meme sens qu'ailleurs : tous les correctifs n'ont pas de valeur
        -- mesurable, donc le total est un plancher, jamais un montant exact.
        local stat, measured, fixes = ns.Gear.Recoverable()
        local cost = ""
        if stat > 0 then
            local shown = BreakUpLargeNumbers and BreakUpLargeNumbers(stat) or tostring(stat)
            cost = string.format("|cff8A8A8A  ·  %s%s %s|r",
                measured < fixes and "≥ " or "", shown, L["stat"])
        end

        view.verdict:SetText(string.format("%s%s|r%s", hex(COLORS.major),
            string.format(L["%d fix(es) pending"], summary.problems), cost))
        view.summary:SetText(hex(COLORS.minor) .. table.concat(parts, "  ·  ") .. "|r")
    end

    view.reset:SetShown(summary.ignored > 0)

    -- La zone de defilement connait sa largeur reelle : on aligne le contenu dessus
    -- avant toute mesure de texte, sinon les cartes sont trop etroites ou trop larges.
    local scrollWidth = view.scroll:GetWidth()
    if scrollWidth and scrollWidth > 120 then
        view.content:SetWidth(scrollWidth - 6)
    end

    local width = view.content:GetWidth()
    if width < 120 then width = 360 end

    local top = 0
    local shown = 0

    -- La piece selectionnee passe en tete : c'est ce qu'on vient de cliquer.
    top = layoutDetail(top, width, selectedSlot and summary.bySlot[selectedSlot] or nil)

    -- Ordre de la liste : le plus urgent d'abord.
    --
    -- Elle suivait l'ordre de `Gear.SLOTS`, c'est-a-dire l'ordre de la feuille de
    -- personnage. Un enchantement de jambes a 4 000 points se retrouvait donc sous une
    -- durabilite a 34 %, et une piece ignoree au milieu des actives. Trois rangs, dans
    -- l'ordre ou un joueur veut agir : les ignorees en dernier, les problemes bloquants
    -- en tete, et a rang egal le plus gros gain en premier.
    local pending = {}
    for index, entry in ipairs(entries) do
        if not entry.skipped and #entry.problems > 0 then
            local critical = entry.empty or entry.damaged
                or (entry.missingEnchant and (entry.slot == "MainHandSlot" or entry.slot == "SecondaryHandSlot"))
            table.insert(pending, {
                entry = entry,
                order = index,
                critical = critical,
                rank = entry.ignored and 3 or (critical and 1 or 2),
                -- Points recuperables sur cette piece. Zero quand l'enchantement n'est
                -- pas mesurable : le tri retombe alors sur l'ordre d'origine.
                value = entry.missingEnchant
                    and (ns.Gear.EnchantPoints(entry.link, entry.slot)) or 0,
            })
        end
    end

    table.sort(pending, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.value ~= b.value then return a.value > b.value end
        return a.order < b.order
    end)

    for _, item in ipairs(pending) do
        local color = item.entry.ignored and COLORS.minor
            or (item.critical and COLORS.critical or COLORS.major)
        top = layoutIssue(item.entry, width, top, color)
        shown = shown + 1
    end

    if shown == 0 then
        -- Meme carte d'une ligne que les correctifs, meme champs. Elle posait encore
        -- `card.body`, le second texte retire avec la densification : l'onglet Equipement
        -- tombait donc sur un equipement PARFAIT, exactement le cas ou il n'a rien a dire.
        -- La phrase de detail passe dans le champ de droite, qui est libre ici.
        local card = acquire("issue")
        card:SetParent(view.content)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, 0)
        card:SetWidth(width)
        card:SetHeight(ISSUE_HEIGHT)
        ns.Theme.ApplyCard(card, COLORS.good)
        card.accent:SetColorTexture(COLORS.good[1], COLORS.good[2], COLORS.good[3], 1)
        card.marker:SetText(hex(COLORS.good) .. "+|r")
        card.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        card.hint:SetText("|cff5A5A5A" .. L["Everything is enchanted, socketed and in shape."] .. "|r")
        card.title:SetWidth(math.max(60, width - math.ceil(card.hint:GetStringWidth() or 0) - 60))
        card.title:SetText(L["Nothing to fix"])
        top = -(ISSUE_HEIGHT + 8)
    end

    top = layoutGems(width, top, entries)
    top = layoutUpgrades(width, top)

    local height = math.max(1, -top + 10)
    view.content:SetHeight(height)

    -- La position de defilement se conserve. Elle etait remise a zero a chaque
    -- rafraichissement : ignorer une piece en bas de liste renvoyait le joueur en haut,
    -- a chaque clic. On se contente de la ramener dans les bornes du nouveau contenu.
    local visible = view.scroll:GetHeight() or 0
    local maximum = math.max(0, height - visible)
    if view.scroll:GetVerticalScroll() > maximum then
        view.scroll:SetVerticalScroll(maximum)
    end

    ns.GearSide.Refresh(summary)
end
