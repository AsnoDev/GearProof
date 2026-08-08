local _, ns = ...

local GearView = {}
ns.GearView = GearView

-- Onglet Equipement, en deux colonnes : les cartes d'action a gauche, la note et la
-- repartition des statistiques a droite.

local SIDE_WIDTH = 236
local COLORS = setmetatable({}, {
    __index = function(_, key)
        local map = { critical = "critical", major = "bis", good = "good",
                      accent = "link", minor = "muted" }
        return ns.Theme.RGB[map[key] or key] or { 1, 1, 1 }
    end,
})

local STAT_COLORS = {
    haste       = { 0.45, 0.78, 0.62 },
    crit        = { 0.89, 0.64, 0.36 },
    mastery     = { 0.55, 0.42, 1.00 },
    versatility = { 0.36, 0.62, 0.89 },
}


local L = ns.L

local view, pools, selectedSlot
local layoutUpgrades, layoutGems

local function hex(color)
    return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

-- --------------------------------------------------------------------- pooling

local function resetPools()
    for _, pool in pairs(pools) do
        for _, widget in ipairs(pool.items) do widget:Hide() end
        pool.used = 0
    end
end

local function acquire(kind, factory)
    local pool = pools[kind]
    pool.used = pool.used + 1
    local widget = pool.items[pool.used]
    if not widget then
        widget = factory()
        pool.items[pool.used] = widget
    end
    widget:Show()
    return widget
end

--- Carte d'un probleme : bandeau colore, icone, titre, conseil.
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

    card.marker = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.marker:SetPoint("TOPLEFT", 10, -8)
    card.marker:SetText("[!]")

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(18, 18)
    card.icon:SetPoint("TOPLEFT", 12, -26)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 34, -8)
    card.title:SetJustifyH("LEFT")

    card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.body:SetPoint("TOPLEFT", 34, -26)
    card.body:SetJustifyH("LEFT")
    card.body:SetJustifyV("TOP")
    card.body:SetSpacing(2)

    -- Ligne de gestes, permanente : elle ne depend ni du survol ni de la presence d'un releve.
    card.hint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.hint:SetPoint("TOPLEFT", card.body, "BOTTOMLEFT", 0, -4)
    card.hint:SetJustifyH("LEFT")

    return card
end

-- Une ligne de statistique secondaire.
--
-- L'ancienne version montrait quatre nombres dans trois unites differentes : la hate reelle
-- (« 18.7% »), les points bruts, la part de ton propre budget (« 40% of yours ») et la part
-- du haut de tableau (« top 43% ») — plus un badge signe sans colonne fixe. Deux
-- pourcentages qui se ressemblent et ne veulent pas dire la meme chose, cote a cote.
--
-- Ici la soustraction est faite pour le lecteur : un seul nombre par ligne, toujours signe,
-- toujours en POINTS, toujours dans le meme champ a droite. La barre ne fait que redire ce
-- meme fait — sens, couleur, longueur — pour que la ligne se lise sans lire les chiffres.
--
-- Une ligne de statistique secondaire : nom a gauche, barre au milieu, valeur a droite. Une
-- seule ligne, un seul nombre, une seule unite.
--
-- Trois versions ont precede celle-ci. La premiere empilait quatre nombres dans quatre unites
-- dont aucune n'etait la reponse ; la deuxieme et la troisieme ajoutaient un ecart signe, un
-- repere de cible, une colonne d'unite et un tri qui deplacait les lignes d'une session a
-- l'autre. Trop de machinerie dans une colonne de 228 px. La comparaison au haut de tableau
-- vit maintenant dans la ligne de priorite, en dessous, ecrite une fois.
local ROW_HEIGHT, BAR_HEIGHT = 20, 10
local LABEL_WIDTH, VALUE_WIDTH = 76, 46

local function newStatRow()
    local row = CreateFrame("Frame", nil, view.side)
    row:SetHeight(ROW_HEIGHT)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(LABEL_WIDTH)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- Largeur explicite : un FontString justifie a droite se recale sinon sur sa propre
    -- longueur, et la colonne danse d'une ligne a l'autre.
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetPoint("RIGHT", 0, 0)
    row.value:SetWidth(VALUE_WIDTH)
    row.value:SetJustifyH("RIGHT")

    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetHeight(BAR_HEIGHT)
    row.track:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + 4, 0)
    row.track:SetPoint("RIGHT", row, "RIGHT", -(VALUE_WIDTH + 6), 0)
    row.track:SetColorTexture(0.10, 0.10, 0.11, 1)

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetHeight(BAR_HEIGHT)
    row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)

    return row
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

--- Pose le panneau de detail. Retourne le nouveau haut.
local function layoutDetail(top, width, entry)
    if not entry or not entry.link then return top end

    local card = acquire("detail", newDetail)
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

local function layoutIssue(entry, width, top, color)
    local card = acquire("issue", newIssueCard)
    card:SetParent(view.content)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, top)
    card:SetWidth(width)

    ns.Theme.ApplyCard(card, color)
    card.accent:SetColorTexture(color[1], color[2], color[3], 1)
    card.marker:SetText(hex(color) .. "[!]|r")
    card.title:SetWidth(width - 46)
    card.title:SetText(issueTitle(entry))

    local texture = entry.slotID and GetInventoryItemTexture("player", entry.slotID)
    card.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    local details = {}
    for _, problem in ipairs(entry.problems) do
        table.insert(details, "|cffcfc9dd" .. problem .. "|r")
    end
    if entry.ignored then table.insert(details, "|cff8b6bff" .. L["ignored"] .. "|r") end
    card.body:SetWidth(width - 46)
    card.body:SetText(table.concat(details, "\n"))

    card:SetScript("OnEnter", function(self)
        ns.Armory.Highlight(entry.slot, true)

        -- Infobulle de L'ENCHANTEMENT, pas de la piece.
        --
        -- WoW n'a pas de type de lien pour un enchantement : impossible de lui demander
        -- une infobulle. Le seul endroit ou le client decrit un enchantement, c'est
        -- l'infobulle de l'objet qui le porte. On affiche donc ce que l'enchantement y
        -- ajoute, mot pour mot — texte du client, deja formate et deja traduit.
        if not entry.missingEnchant then return end

        local enchantID, share = ns.Meta.Enchant(entry.slot)
        if not enchantID then return end

        local name = ns.Meta.EnchantName(entry.link, enchantID)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
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
        -- Le chiffre d'adoption sans le rappel de la source : elle est nommee dans l'entete
        -- de la fenetre et en pied du bloc gemmes, une fois chacune.
        GameTooltip:AddLine(string.format(L["%d%% adoption"],
            (share or 0) * 100 + 0.5), 0.54, 0.54, 0.54)
        GameTooltip:AddLine(L["click to copy the name"], 0, 0.69, 1)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function()
        ns.Armory.Highlight(entry.slot, false)
        GameTooltip:Hide()
    end)
    card:SetScript("OnClick", function(self, button)
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
    end)

    -- Les gestes disponibles, ecrits sur la carte. Ils etaient invisibles : l'indication de
    -- copie ne s'affichait que dans une infobulle elle-meme conditionnee a la presence d'un
    -- releve, et le clic droit n'etait mentionne que dans une fenetre qu'on ne pouvait
    -- atteindre qu'en devinant le clic gauche.
    local hints = { entry.ignored and L["right-click: un-ignore"] or L["right-click: ignore"] }
    if entry.missingEnchant and ns.Meta.Enchant(entry.slot) then
        table.insert(hints, 1, L["left-click: copy the enchant name"])
    else
        table.insert(hints, 1, L["left-click: details"])
    end
    card.hint:SetWidth(width - 46)
    card.hint:SetText("|cff5A5A5A" .. table.concat(hints, "  ·  ") .. "|r")

    local height = 34 + card.body:GetStringHeight() + card.hint:GetStringHeight() + 14
    card:SetHeight(math.max(58, height))
    return top - math.max(58, height) - 8
end

local function layoutSide(summary)
    local stats = ns.Gear.Stats()

    -- Emplacements propres : ceux qu'on a verifies moins ceux qui portent un probleme. Deux
    -- nombres comptes, pas une note ponderee par des penalites inventees.
    local flagged = 0
    for _, entry in pairs(summary.bySlot or {}) do
        if not entry.skipped and #entry.problems > 0 then flagged = flagged + 1 end
    end
    local checked = math.max(1, summary.checked or 1)

    local _, equipped = GetAverageItemLevel()
    ns.Gauge.SetValue(view.gauge, summary.problems, checked - flagged, checked,
        equipped and ("ilvl " .. math.floor(equipped + 0.5)) or "")

    -- Repartition : part de chaque statistique dans le budget secondaire total.
    local total = 0
    for _, definition in ipairs(ns.Gear.STATS) do
        total = total + (stats[definition.key] and stats[definition.key].rating or 0)
    end

    local WIDTH = SIDE_WIDTH - 8
    local TRACK_WIDTH = WIDTH - LABEL_WIDTH - VALUE_WIDTH - 10

    view.statsTitle:SetText(hex(COLORS.accent) .. L["SECONDARY STATS"] .. "|r")

    -- La colonne de droite s'empile : jauge (haut, 108 px) → verdict → titre a -152 →
    -- lignes. Demarrer les lignes plus haut les fait passer sous la jauge.
    local top = -172

    -- Ordre fixe, celui de la feuille de personnage. Trier par ecart deplacait les lignes
    -- d'une session a l'autre et coutait la memoire du geste.
    for _, definition in ipairs(ns.Gear.STATS) do
        local data = stats[definition.key] or { rating = 0, percent = 0, tier = 0 }
        local share = total > 0 and ((data.rating or 0) / total) or 0
        local color = STAT_COLORS[definition.key] or COLORS.accent

        local row = acquire("statrow", newStatRow)
        row:SetParent(view.side)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, top)
        row:SetWidth(WIDTH)
        row:SetHeight(ROW_HEIGHT)

        row.label:SetText(hex(color) .. L[definition.label] .. "|r")
        row.value:SetText(string.format("|cffE8E8E8%.1f%%|r", data.percent or 0))

        -- La barre montre la part de cette statistique dans ton budget secondaire. La
        -- comparaison au haut de tableau n'est pas ici : elle est dans la ligne de priorite,
        -- ecrite une fois, au lieu d'un repere par ligne a decoder.
        row.fill:SetColorTexture(color[1], color[2], color[3], 1)
        row.fill:SetWidth(math.max(1, share * TRACK_WIDTH))

        -- Le detail chiffre reste accessible, sans encombrer la ligne.
        local rating, tier = data.rating or 0, data.tier or 0
        local target = ns.Recommendations.StatTarget(definition.key)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L[definition.label], 0.91, 0.91, 0.91)
            GameTooltip:AddDoubleLine(L["yours"],
                string.format("%d pts · %.0f%% " .. L["of yours"], rating, share * 100),
                0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
            if target then
                -- On n'affiche que la PART relevee. Ecrire « top 20 : N pts » en multipliant
                -- leur composition par TON budget donnait un nombre qui ne decrit ni eux ni
                -- toi. Leur moyenne absolue existe dans le fichier de donnees, mais elle
                -- n'est comparable qu'a niveau d'objet egal — donc on ne la melange pas ici.
                GameTooltip:AddDoubleLine(string.format(L["top %d"], ns.Meta.Sample()),
                    string.format("%.0f%% " .. L["of their budget"], target * 100),
                    0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
            end
            if tier > 0 then
                GameTooltip:AddLine(string.format(L["diminishing tier %d"], tier), 1, 0.76, 0.03)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        top = top - ROW_HEIGHT
    end

    -- Priorite : l'ordre releve chez les joueurs du haut de tableau, part a l'appui. C'est
    -- ici que vivent desormais les parts du haut de tableau, une fois chacune, au lieu d'un
    -- « top 43% » repete sur chaque ligne a cote d'un « 40% of yours » qui lui ressemble.
    local priority = ns.Meta.StatPriority()
    view.priority:ClearAllPoints()
    view.priority:SetPoint("TOPLEFT", view.side, "TOPLEFT", 0, top - 8)
    if priority then
        local parts = {}
        for _, entry in ipairs(priority) do
            table.insert(parts, string.format("%s (%d%%)", L[entry.label], entry.share * 100 + 0.5))
        end
        view.priority:SetText(string.format("%s%s|r\n|cffE8E8E8%s|r",
            hex(COLORS.accent), L["PRIORITY"], table.concat(parts, "  →  ")))
        top = top - 34
    else
        view.priority:SetText("|cff615c73" .. L["no top-build reference for this spec yet"] .. "|r")
        top = top - 28
    end

    view.simc:ClearAllPoints()
    view.simc:SetPoint("TOPLEFT", view.side, "TOPLEFT", 0, top - 12)

    view.simcCopy:ClearAllPoints()
    view.simcCopy:SetPoint("TOPLEFT", view.simc, "BOTTOMLEFT", 0, -4)

    view.paste:ClearAllPoints()
    view.paste:SetPoint("TOPLEFT", view.simcCopy, "BOTTOMLEFT", 0, -4)

    local description, stale = ns.Weights.Describe()
    view.droptimizer:ClearAllPoints()
    view.droptimizer:SetPoint("TOPLEFT", view.paste, "BOTTOMLEFT", 0, -6)
    view.droptimizer:SetText(string.format("%s%s|r\n|cff615c73raidbots.com/simbot/droptimizer|r",
        stale and hex(COLORS.major) or "|cff615c73", description))
end

-- ------------------------------------------------------------------ public

function GearView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    pools = {
        issue = { items = {}, used = 0 },
        statrow = { items = {}, used = 0 },
        panel = { items = {}, used = 0 },
        detail = { items = {}, used = 0 },
    }

    view.summary = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.summary:SetPoint("TOPLEFT", 2, -2)
    view.summary:SetWidth(300)
    view.summary:SetJustifyH("LEFT")

    view.reset = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.reset:SetSize(110, 20)
    view.reset:SetPoint("TOPLEFT", view.summary, "BOTTOMLEFT", 0, -2)
    view.reset:SetText(L["Re-enable all"])
    view.reset:SetScript("OnClick", function()
        -- Passe par Gear : ecrire `ns.db.ignoredSlots` en direct laissait le cache
        -- d'audit intact et la vue se redessinait sur l'ancien etat.
        ns.Gear.ResetIgnored()
        ns.UI.RefreshNow()
    end)

    -- Colonne 1 : la grille compacte, dans l'onglet et non plus dans la fenetre.
    view.grid = ns.Armory.Create(view)
    view.grid:SetPoint("TOPLEFT", 0, -26)

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", ns.Armory.WIDTH + 16, -26)
    view.scroll:SetPoint("BOTTOMRIGHT", -(SIDE_WIDTH + 30), 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(360, 1)
    view.scroll:SetScrollChild(view.content)

    view.side = CreateFrame("Frame", nil, view)
    view.side:SetPoint("TOPRIGHT", 0, -4)
    view.side:SetWidth(SIDE_WIDTH)
    view.side:SetPoint("BOTTOM", view, "BOTTOM", 0, 0)

    view.gauge = ns.Gauge.Create(view.side, 108)
    view.gauge:SetPoint("TOP", view.side, "TOP", 0, -4)

    view.statsTitle = view.side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.statsTitle:SetPoint("TOPLEFT", view.side, "TOPLEFT", 0, -152)
    view.statsTitle:SetText(hex(COLORS.accent) .. L["SECONDARY STATS"] .. "|r")

    view.priority = view.side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.priority:SetJustifyH("LEFT")
    view.priority:SetWidth(SIDE_WIDTH - 8)
    view.priority:SetSpacing(3)

    view.simc = CreateFrame("Button", nil, view.side, "UIPanelButtonTemplate")
    view.simc:SetSize(SIDE_WIDTH - 8, 24)
    view.simc:SetText(L["Droptimizer link"])
    view.simc:SetScript("OnClick", function() ns.SimC.ShowDroptimizer() end)

    -- Bloc de simulation : la chaine part vers Raidbots, les poids reviennent a la main.
    view.droptimizer = view.side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.droptimizer:SetJustifyH("LEFT")
    view.droptimizer:SetWidth(SIDE_WIDTH - 8)

    -- Copie de la chaine SimC : c'est ce qu'on colle DANS le droptimizer.
    view.simcCopy = CreateFrame("Button", nil, view.side, "UIPanelButtonTemplate")
    view.simcCopy:SetSize(SIDE_WIDTH - 8, 22)
    view.simcCopy:SetText(L["Droptimizer Copy"])
    view.simcCopy:SetScript("OnClick", function() ns.SimC.Show() end)

    view.paste = CreateFrame("Button", nil, view.side, "UIPanelButtonTemplate")
    view.paste:SetSize(SIDE_WIDTH - 8, 22)
    view.paste:SetText(L["Paste droptimizer link"])
    view.paste:SetScript("OnClick", function()
        ns.Copy.Prompt(L["Droptimizer report"],
            L["Paste the Raidbots report link, or a Pawn string"],
            function(text)
                if ns.SimC.SetDroptimizer(text) then
                    ns.Print(L["droptimizer report stored"])
                elseif ns.Weights.SetFromPawn(text) then
                    ns.Print(L["stat weights saved (%s)"], "Pawn")
                else
                    ns.Print(L["nothing readable in that paste"])
                end
                ns.UI.RefreshNow()
            end)
    end)

    return view
end

--- Carte simple, titre + corps de texte, pour les blocs sans interaction.
local function newPanel()
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
    local lines = {}
    local missing = 0

    for _, entry in ipairs(entries) do
        if entry.link and (entry.sockets or 0) > 0 then
            local sockets = ns.Meta.SocketGems(entry.slot)
            local parts = {}

            for index = 1, entry.sockets do
                local worn = entry.gemIDs and entry.gemIDs[index]
                local best = sockets and sockets[index] and sockets[index][1]

                -- Un glyphe double la couleur. Sans lui, l'etat d'une chasse etait porte par
                -- la teinte seule : un daltonien deutan ne distingue pas « conforme au
                -- releve » de « chasse vide ».
                if worn then
                    local name = ns.Meta.GemName(worn) or ("#" .. worn)
                    local ok = best and worn == best.id
                    table.insert(parts, string.format("%s%s %s|r",
                        ok and hex(COLORS.good) or hex(COLORS.minor),
                        ok and "+" or "~", name))
                else
                    missing = missing + 1
                    local advice = best and (ns.Meta.GemName(best.id) or ("#" .. best.id))
                    table.insert(parts, string.format("%s! %s|r",
                        hex(COLORS.critical),
                        advice and string.format(L["empty → %s"], advice) or L["empty socket"]))
                end
            end

            table.insert(lines, string.format("|cffE8E8E8%s|r  %s",
                L[entry.label], table.concat(parts, "  ·  ")))
        end
    end

    if #lines == 0 then return top end

    local card = acquire("panel", newPanel)
    card:SetParent(view.content)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", 0, top - 6)
    card:SetWidth(width)
    ns.Theme.ApplyCard(card)

    card.title:SetText(hex(COLORS.accent) .. L["GEMS"] .. "|r"
        .. (missing > 0 and string.format("  %s%d|r", hex(COLORS.critical), missing) or ""))

    -- Legende des glyphes, puis provenance : sans elle, un nom de gemme est un avis.
    table.insert(lines, "")
    table.insert(lines, string.format("|cff5A5A5A%s+|r %s   %s~|r %s   %s!|r %s|cff5A5A5A|r",
        hex(COLORS.good), L["as measured"],
        hex(COLORS.minor), L["different"],
        hex(COLORS.critical), L["empty"]))
    if ns.Meta.Available() then
        table.insert(lines, hex(COLORS.minor)
            .. string.format(L["measured on %d top players"], ns.Meta.Sample()) .. "|r")
    end

    card.body:SetWidth(width - 24)
    card.body:SetText(table.concat(lines, "\n"))
    card:SetHeight(34 + card.body:GetStringHeight() + 12)

    return top - card:GetHeight() - 8
end

--- Ce que tu transportes et qui vaut mieux que ce que tu portes.
layoutUpgrades = function(width, top)
    local simmed, unrated, _, estimated = ns.Bags.Compare()
    if #simmed == 0 and #unrated == 0 and #estimated == 0 then return top end

    local card = acquire("panel", newPanel)
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

    if summary.problems == 0 then
        view.summary:SetText(hex(COLORS.good) .. L["Gear complete"] .. "|r")
    else
        local parts = {}
        if summary.missingEnchants > 0 then table.insert(parts, string.format(L["%d missing enchant(s)"], summary.missingEnchants)) end
        if summary.emptySockets > 0 then table.insert(parts, string.format(L["%d empty socket(s)"], summary.emptySockets)) end
        if summary.emptySlots > 0 then table.insert(parts, string.format(L["%d empty slot(s)"], summary.emptySlots)) end
        if summary.damaged > 0 then table.insert(parts, string.format(L["%d damaged piece(s)"], summary.damaged)) end
        view.summary:SetText(hex(COLORS.major) .. table.concat(parts, "  ·  ") .. "|r")
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

    for _, entry in ipairs(entries) do
        if not entry.skipped and #entry.problems > 0 then
            local critical = entry.empty or entry.damaged
                or (entry.missingEnchant and (entry.slot == "MainHandSlot" or entry.slot == "SecondaryHandSlot"))
            local color = entry.ignored and COLORS.minor or (critical and COLORS.critical or COLORS.major)
            top = layoutIssue(entry, width, top, color)
            shown = shown + 1
        end
    end

    if shown == 0 then
        local card = acquire("issue", newIssueCard)
        card:SetParent(view.content)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, 0)
        card:SetWidth(width)
        card:SetHeight(54)
        ns.Theme.ApplyCard(card, COLORS.good)
        card.accent:SetColorTexture(COLORS.good[1], COLORS.good[2], COLORS.good[3], 1)
        card.marker:SetText(hex(COLORS.good) .. "[ok]|r")
        card.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        card.title:SetWidth(width - 46)
        card.title:SetText(L["Nothing to fix"])
        card.body:SetWidth(width - 46)
        card.body:SetText("|cffcfc9dd" .. L["Everything is enchanted, socketed and in shape."] .. "|r")
        -- La carte sort du pool des cartes de probleme : sans ce vidage, la ligne de
        -- gestes de la carte precedente restait affichee sous « Rien a corriger ».
        card.hint:SetText("")
        card:SetScript("OnEnter", nil)
        card:SetScript("OnLeave", nil)
        card:SetScript("OnClick", nil)
        top = -62
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

    layoutSide(summary)
end
