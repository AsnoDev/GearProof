local _, ns = ...

local GuildView = {}
ns.GuildView = GuildView

local L = ns.L

-- Tableau de la guilde : une ligne par membre equipe de l'addon.

local ROW_HEIGHT = 22
-- Bande de chiffres de tete, a droite du tableau.
local SUMMARY_WIDTH = 190

-- UN modele de colonnes, pour le tableau ET pour son entete.
--
-- Il y en avait trois : les largeurs posees a la creation de la ligne, celles reposees par
-- `layoutRosterRow`, celles reposees par `layoutRaidRow` — et une quatrieme, implicite,
-- dans l'entete, qui etait une chaine bourree d'espaces
-- (« name            spec          ilvl    fixes     last sim ») censee tomber en face.
-- Le commentaire de `ROSTER_WIDTH` l'assumait : « les changer sans changer celle-ci fait
-- chevaucher les colonnes ». Quatre sources pour une meme grille, dont une non calculable.
--
-- Les colonnes de droite ont une largeur FIXE — elles portent des nombres, dont la place
-- ne depend pas de la fenetre. Le nom prend ce qui reste : c'est la seule colonne dont
-- l'allongement sert a quelque chose. Le tableau suit donc la largeur reelle du cadre au
-- lieu de s'arreter a 560 px avec un vide a droite.
local COLUMNS = {
    { key = "spec",  width = 150, justify = "LEFT" },
    { key = "ilvl",  width = 62,  justify = "LEFT" },
    { key = "fixes", width = 76,  justify = "LEFT" },
    { key = "sim",   width = 128, justify = "LEFT" },
}
local NAME_MIN = 90
local ROW_PADDING = 8

local view, rows
local guildMode = "roster"

--- Pose les cinq colonnes d'une ligne. Sert aussi a l'entete, qui a les memes champs.
--- @param widths table|nil largeurs de remplacement, par cle (sous-vue Raid)
local function layoutColumns(row, width, widths)
    local fixed = 0
    for _, column in ipairs(COLUMNS) do
        fixed = fixed + ((widths and widths[column.key]) or column.width)
    end

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", ROW_PADDING, 0)
    row.name:SetWidth(math.max(NAME_MIN, width - fixed - ROW_PADDING * 2))
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    local offset = ROW_PADDING + math.max(NAME_MIN, width - fixed - ROW_PADDING * 2)
    for _, column in ipairs(COLUMNS) do
        local field = row[column.key]
        local columnWidth = (widths and widths[column.key]) or column.width
        field:ClearAllPoints()
        field:SetPoint("LEFT", offset, 0)
        field:SetWidth(columnWidth)
        field:SetJustifyH(column.justify)
        field:SetWordWrap(false)
        offset = offset + columnWidth
    end
end

-- Declarations en amont. Ces trois fonctions sont definies plus bas, avec la sous-vue Raid,
-- mais `GuildView.Refresh` les appelle : sans cette declaration, un `local function` place
-- apres l'appelant n'est pas en portee et l'appel part chercher un global inexistant. C'est
-- exactement ce qui a casse le bouton de tournee.
local layoutRaidRow, layoutRosterRow, itemName, setHeader, columnHeadings

local function hex(key)
    return ns.Theme.C(key)
end

-- Gestionnaires de lignes, poses UNE fois.
--
-- Les lignes sont reutilisees d'un rafraichissement a l'autre, mais leurs gestionnaires
-- etaient reconstruits a chaque fois : une tournee de guilde a trente membres en
-- fabriquait trente, et la sous-vue Raid deux par objet convoite. L'etat voyage sur la
-- ligne (`row.card`, `row.item`, `row.encounter`).

local function hideTooltip()
    GameTooltip:Hide()
end

local function memberOnClick(self)
    local card = self.card
    if card and card.sim ~= "" then
        ns.Copy.Show(card.name, "https://www.raidbots.com/simbot/report/" .. card.sim)
    end
end

local function needOnEnter(self)
    local item = self.item
    if not item then return end

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    -- Le lien du journal des aventures porte les identifiants de bonus, donc le vrai
    -- niveau. `SetItemByID` ne connait que le modele.
    local link = ns.Sim.LootLink(self.encounter, item.id, item.difficulty)
    local shown = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not shown and not pcall(GameTooltip.SetItemByID, GameTooltip, item.id) then
        GameTooltip:AddLine("item:" .. item.id)
    end

    if item.ilvl and item.ilvl > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["simulated at ilvl"], tostring(item.ilvl),
            0, 0.69, 1, 0.91, 0.91, 0.91)
        if not shown then
            GameTooltip:AddLine(L["the item level above is the base template, not the drop"],
                0.54, 0.54, 0.54, true)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Guild ranking"], 0, 0.69, 1)
    for rank, member in ipairs(item.members) do
        if rank > 12 then
            GameTooltip:AddLine(string.format("+%d…", #item.members - 12), 0.54, 0.54, 0.54)
            break
        end
        GameTooltip:AddDoubleLine(
            string.format("%d. %s", rank, member.name),
            string.format("%+.2f%%", member.percent),
            0.91, 0.91, 0.91, 0, 0.9, 0.46)
    end
    GameTooltip:Show()
end

--- Remet une ligne a neuf : etat ET gestionnaires.
---
--- Les memes lignes servent la liste des membres et la sous-vue Raid. Chaque vue ne
--- posait que les gestionnaires dont ELLE avait besoin, sans retirer ceux de l'autre :
--- une ligne qui avait affiche un objet convoite gardait son OnEnter, et survoler la
--- liste des membres apres avoir consulte la sous-vue Raid sortait l'infobulle d'un objet
--- appartenant a l'affichage precedent. La remise a neuf est ici, une fois, pour les deux.
local function resetRow(row)
    row.card, row.item, row.encounter = nil, nil, nil
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    return row
end

local function acquireRow(index)
    if rows[index] then return resetRow(rows[index]) end

    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    -- Aucune position ni largeur ici : `layoutColumns` les pose au rendu, quand la largeur
    -- du cadre est connue. Les fixer a la creation, c'etait la premiere des quatre sources
    -- de verite.
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.spec = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.fixes = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sim = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    rows[index] = row
    return row
end

function GuildView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    rows = {}

    view.title = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.title:SetPoint("TOPLEFT", 2, -2)
    ns.Localize(view.title, "Guild audit")

    view.hint = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.hint:SetPoint("TOPLEFT", 2, -26)
    view.hint:SetPoint("RIGHT", view, "RIGHT", -(SUMMARY_WIDTH + 40), 0)
    view.hint:SetJustifyH("LEFT")
    ns.Localize(view.hint, "Members running GearProof answer the roll call. Nothing is sent unless sharing is on.")

    view.request = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.request:SetSize(150, 22)
    view.request:SetPoint("TOPLEFT", 0, -50)
    ns.Localize(view.request, "Roll call")
    view.request:SetScript("OnClick", function()
        if ns.Guild.Request() then GuildView.Refresh() end
    end)

    view.export = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.export:SetSize(150, 22)
    view.export:SetPoint("LEFT", view.request, "RIGHT", 6, 0)
    ns.Localize(view.export, "Copy for Discord")
    view.export:SetScript("OnClick", function()
        ns.Copy.Show(L["Guild audit"], ns.Guild.Export())
    end)

    view.share = CreateFrame("CheckButton", "GearProofShareToggle", view, "UICheckButtonTemplate")
    view.share:SetSize(22, 22)
    view.share:SetPoint("LEFT", view.export, "RIGHT", 16, 0)
    view.share.text = view.share:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.share.text:SetPoint("LEFT", view.share, "RIGHT", 2, 0)
    ns.Localize(view.share.text, "Share my data")
    view.share:SetScript("OnClick", function(self)
        ns.db.shareWithGuild = self:GetChecked() and true or false
    end)

    -- Deux sous-vues : le tableau du roster, et la couverture par rencontre. Les boutons
    -- restent des boutons plats maison, pas des onglets Blizzard : la fenetre a deja une
    -- rangee d'onglets et en empiler une seconde brouillerait la hierarchie.
    view.modes = {}
    for index, mode in ipairs({
        { key = "roster", label = "Roster" },
        { key = "raid",   label = "Raid" },
    }) do
        local button = CreateFrame("Button", nil, view, "BackdropTemplate")
        button:SetSize(96, 20)
        button:SetPoint("TOPLEFT", (index - 1) * 100, -78)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetPoint("CENTER")
        button.key = mode.key
        button.label = mode.label
        button:SetScript("OnClick", function(self)
            guildMode = self.key
            GuildView.Refresh()
        end)
        view.modes[index] = button
    end

    -- Bandeau de fraicheur : la reponse a « qui a un droptimizer, et depuis quand ».
    view.coverage = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.coverage:SetPoint("TOPLEFT", 210, -78)
    view.coverage:SetJustifyH("LEFT")

    -- L'entete est une LIGNE, avec les memes champs qu'une ligne de donnees, posee par le
    -- meme `layoutColumns`. C'etait une seule chaine bourree d'espaces censee tomber en
    -- face des colonnes : elle ne pouvait s'aligner avec aucune d'elles — la police n'est
    -- pas a chasse fixe — et il fallait la retoucher a la main a chaque changement de
    -- largeur. Elle ne peut plus deriver : elle EST le modele.
    view.header = CreateFrame("Frame", nil, view)
    view.header:SetHeight(ROW_HEIGHT)
    view.header:SetPoint("TOPLEFT", 0, -100)

    for _, key in ipairs({ "name", "spec", "ilvl", "fixes", "sim" }) do
        view.header[key] = view.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    end

    -- Bande de chiffres de tete, a droite.
    --
    -- C'est la meilleure idee des croquis : « combien sont prets, combien de gain le raid
    -- a devant lui, combien de gens ont encore quelque chose a corriger » repond en un
    -- coup d'oeil a la seule question d'un officier a vingt minutes du pull. La liste,
    -- elle, demande de parcourir ligne a ligne.
    view.summary = CreateFrame("Frame", nil, view, "BackdropTemplate")
    view.summary:SetWidth(SUMMARY_WIDTH)
    view.summary:SetPoint("TOPRIGHT", -26, -102)
    view.summary:SetPoint("BOTTOM", view, "BOTTOM", 0, 4)
    view.summary:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    ns.Theme.Track(view.summary)

    view.summaryValue = view.summary:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    view.summaryValue:SetPoint("TOP", view.summary, "TOP", 0, -16)

    view.summaryLabel = view.summary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.summaryLabel:SetPoint("TOP", view.summaryValue, "BOTTOM", 0, -2)

    view.summaryBody = view.summary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.summaryBody:SetPoint("TOPLEFT", view.summary, "TOPLEFT", 12, -66)
    view.summaryBody:SetWidth(SUMMARY_WIDTH - 24)
    view.summaryBody:SetJustifyH("LEFT")
    view.summaryBody:SetSpacing(6)

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", 0, -118)
    view.scroll:SetPoint("BOTTOMRIGHT", -(SUMMARY_WIDTH + 38), 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(ROSTER_WIDTH, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    -- L'etat vide s'arrete avant la bande de chiffres, comme la zone de defilement :
    -- sinon son texte centre passe dessous.
    view.empty = CreateFrame("Frame", nil, view)
    view.empty:SetPoint("TOPLEFT", 0, -118)
    view.empty:SetPoint("BOTTOMRIGHT", -(SUMMARY_WIDTH + 38), 0)
    view.empty:Hide()

    view.emptyTitle = view.empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.emptyTitle:SetPoint("TOP", view.empty, "TOP", 0, -40)

    view.emptyBody = view.empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.emptyBody:SetPoint("TOP", view.emptyTitle, "BOTTOM", 0, -10)
    -- Largeur SUIVIE, pas figee : deux ancres horizontales font que le retour a la
    -- ligne se recalcule quand la fenetre est redimensionnee. Un `SetWidth` en dur
    -- laissait le texte a sa largeur d'origine, centre dans un vide de plus en plus
    -- large — ou tronque si la fenetre retrecissait.
    view.emptyBody:SetPoint("LEFT", view.empty, "LEFT", 40, 0)
    view.emptyBody:SetPoint("RIGHT", view.empty, "RIGHT", -40, 0)
    view.emptyBody:SetJustifyH("CENTER")
    view.emptyBody:SetSpacing(3)

    return view
end

function GuildView.Refresh()
    if not view then return end

    view.share:SetChecked(ns.db.shareWithGuild == true)

    for _, row in pairs(rows) do row:Hide() end

    for _, button in ipairs(view.modes) do
        local active = button.key == guildMode
        if active then
            ns.Theme.ApplyCard(button, ns.Theme.RGB.link)
        else
            ns.Theme.ApplyCard(button)
        end
        button.text:SetText((active and hex("link") or hex("text")) .. L[button.label] .. "|r")
    end

    -- Chiffres de tete. Le gros nombre est le compte de PRETS : c'est celui qu'on lit de
    -- loin. Les trois autres le qualifient, en plus petit.
    local summary = ns.Guild.Summary()
    view.summaryValue:SetText(string.format("%s%d|r",
        summary.ready == summary.total and hex("good") or hex("bis"), summary.ready))
    view.summaryLabel:SetText(hex("muted")
        .. string.format(L["ready of %d"], summary.total) .. "|r")

    local lines = {}
    if summary.bestSum > 0 then
        table.insert(lines, string.format("%s%s|r\n%s+%.2f%%|r",
            hex("muted"), L["Total gain on the table"], hex("good"), summary.bestSum))
        table.insert(lines, string.format("%s%s|r\n%s+%.2f%%|r",
            hex("muted"), L["Average per member"], hex("text"), summary.bestAverage))
    else
        table.insert(lines, hex("muted") .. L["No shared droptimizer yet"] .. "|r")
    end
    table.insert(lines, string.format("%s%s|r\n%s%d / %d|r",
        hex("muted"), L["Members with fixes pending"],
        summary.withFixes > 0 and hex("bis") or hex("good"),
        summary.withFixes, summary.total))
    view.summaryBody:SetText(table.concat(lines, "\n\n"))

    -- Fraicheur des droptimizers, toujours visible : c'est la question qu'un officier pose
    -- avant un soir de raid.
    local counts = ns.Guild.Droptimizers()
    view.coverage:SetText(string.format("%s%d %s|r   %s%d %s|r   %s%d %s|r",
        hex("good"), counts.ready, L["ready"],
        hex("bis"), counts.stale, L["stale"],
        hex("critical"), counts.missing, L["no droptimizer"]))

    if guildMode == "raid" then
        GuildView.RefreshRaid()
        return
    end

    -- Les deux sous-vues partagent les memes FontStrings : chacune pose SA largeur, a
    -- chaque fois. Le roster restait auparavant a 560 px en dur, ce qui laissait un vide a
    -- droite sur une fenetre agrandie ; il prend maintenant la largeur reelle, comme la
    -- sous-vue Raid.
    local width = math.max(420, (view.scroll:GetWidth() or 700) - 8)
    view.content:SetWidth(width)
    setHeader(width, columnHeadings())

    local list = ns.Guild.Roster()
    local offset = 0

    for index, card in ipairs(list) do
        local row = acquireRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -offset)
        layoutRosterRow(row, width)

        row.name:SetText(card.name)
        row.spec:SetText(card.spec ~= "" and card.spec or "-")
        row.ilvl:SetText(card.ilvl > 0 and tostring(card.ilvl) or "-")

        row.fixes:SetText(card.fixes > 0
            and string.format("%s%d|r", hex("critical"), card.fixes)
            or string.format("%sok|r", hex("good")))

        if card.sim ~= "" then
            local stale = card.simAge < 0 or card.simAge >= 7
            row.sim:SetText(string.format("%s%s (%dd)|r",
                stale and hex("bis") or hex("good"), card.sim, math.max(0, card.simAge)))
        else
            row.sim:SetText(hex("bis") .. L["no sim"] .. "|r")
        end

        row.card = card
        row:SetScript("OnClick", memberOnClick)

        row:Show()
        offset = offset + ROW_HEIGHT
    end

    -- Etat vide, pas page noire. Une ligne grise en haut d'un onglet entierement vide se
    -- lit comme un addon casse, pas comme « il manque une action ».
    if #list <= 1 then
        setHeader(width, nil)
        view.empty:Show()
        view.emptyTitle:SetText(hex("text") .. L["Nobody has answered yet."] .. "|r")
        view.emptyBody:SetText(hex("muted") .. L["Run the roll call: every guild member running GearProof answers with their spec, item level and pending fixes. Nothing is sent from your client unless you tick sharing."] .. "|r")
    else
        view.empty:Hide()
        setHeader(width, columnHeadings())
    end

    view.content:SetHeight(math.max(1, offset))
end

--- Sous-vue Raid : la couverture de la guilde, rencontre par rencontre.
---
--- Meme lecture que l'onglet Raid du joueur — instance, boss, portrait — mais la colonne de
--- droite repond a une autre question. Aucun pourcentage ne circule sur le canal de guilde,
--- donc on ne classe pas les joueurs par gain : on montre QUI est pret pour ce boss et depuis
--- quand son droptimizer date.
-- Les colonnes du roster sont calibrees pour des noms de personnage. Un nom d'objet fait deux
-- a trois fois cette longueur et passait donc a la ligne, ce qui rendait la liste illisible.
--
-- La sous-vue Raid garde donc le meme modele mais RETRECIT les colonnes de droite : le nom
-- recupere ce qu'elles rendent. C'est un remplacement de largeurs, pas une seconde grille —
-- les positions restent calculees au meme endroit.
local RAID_WIDTHS = { spec = 150, ilvl = 70, fixes = 70, sim = 80 }

layoutRaidRow = function(row, width)
    row:SetWidth(width)
    layoutColumns(row, width, RAID_WIDTHS)
    row.sim:SetJustifyH("RIGHT")
end

--- Colonnes du roster : le modele commun, sans remplacement.
layoutRosterRow = function(row, width)
    row:SetWidth(width)
    layoutColumns(row, width)
end

--- Libelles de colonnes du roster.
columnHeadings = function()
    return {
        name = L["name"], spec = L["spec"], ilvl = L["ilvl"],
        fixes = L["fixes"], sim = L["last sim"],
    }
end

--- Pose l'entete. Avec `headings`, une ligne de colonnes ; sans, un simple bandeau.
---
--- Un seul chemin pour les deux : la sous-vue Raid s'en sert comme d'une phrase, le roster
--- comme d'un entete de tableau, et l'un ne doit pas laisser de texte derriere lui quand
--- l'autre prend la main.
setHeader = function(width, headings, banner)
    local fields = { "name", "spec", "ilvl", "fixes", "sim" }

    if headings then
        layoutColumns(view.header, width)
        for _, key in ipairs(fields) do
            view.header[key]:SetText(hex("muted") .. (headings[key] or "") .. "|r")
        end
        return
    end

    for _, key in ipairs(fields) do
        view.header[key]:SetText("")
    end
    if banner then
        view.header.name:ClearAllPoints()
        view.header.name:SetPoint("LEFT", ROW_PADDING, 0)
        view.header.name:SetWidth(math.max(200, width - ROW_PADDING * 2))
        view.header.name:SetWordWrap(false)
        view.header.name:SetText(hex("muted") .. banner .. "|r")
    end
end

itemName = function(itemID)
    return ns.ItemInfo.ColoredName(itemID)
end

function GuildView.RefreshRaid()
    local groups = ns.Guild.LootByEncounter()
    if not groups then
        setHeader(math.max(420, (view.scroll:GetWidth() or 700) - 8), nil,
            L["No droptimizer shared yet. Run the roll call, and ask members to enable sharing."])
        view.content:SetHeight(1)
        return
    end

    setHeader(math.max(420, (view.scroll:GetWidth() or 700) - 8), nil,
        L["Loot per boss, ranked by the best gain in the guild. Hover an item for the ranking."])

    -- Toute la largeur du panneau, pas les 560 px du tableau du roster.
    -- La zone de defilement s'arrete deja avant la bande de chiffres : on prend sa
    -- largeur reelle, sans plancher a 560 qui la ferait deborder dessous.
    local width = math.max(420, (view.scroll:GetWidth() or 700) - 8)
    view.content:SetWidth(width)

    local offset = 0
    local index = 0

    for _, group in ipairs(groups) do
        index = index + 1
        local header = acquireRow(index)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 0, -offset)
        layoutRaidRow(header, width)

        header.name:SetText(hex("link")
            .. (group.name or string.format(L["encounter %d"], group.encounter)) .. "|r")
        header.spec:SetText(hex("muted")
            .. string.format(L["%d items"], #group.items) .. "|r")
        header.ilvl:SetText("")
        header.fixes:SetText("")
        header.sim:SetText(string.format("%s%+.2f%%|r", hex("good"), group.best))
        header:SetScript("OnEnter", nil)
        header:SetScript("OnLeave", nil)
        header:SetScript("OnClick", nil)
        header:Show()
        offset = offset + ROW_HEIGHT

        for _, item in ipairs(group.items) do
            index = index + 1
            local row = acquireRow(index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 16, -offset)
            layoutRaidRow(row, width - 16)

            -- Le lien du journal, quand il existe, porte le nom colore ET le vrai niveau.
            -- La difficulte n'est pas diffusee : on prend celle du releve local, sinon
            -- mythique — c'est la difficulte d'un droptimizer de progression.
            local link = ns.Sim.LootLink(group.encounter, item.id, item.difficulty)
            row.name:SetText(link
                or itemName(item.id)
                or (hex("muted") .. "item:" .. item.id .. "|r"))
            -- Le premier du classement est l'information utile a la repartition du butin.
            local top = item.members[1]
            row.spec:SetText(top and (hex("text") .. top.name .. "|r") or "")
            -- Le niveau SIMULE, pas celui du modele d'objet : sans les identifiants de bonus,
            -- le client rend le niveau de base, qui peut etre absurde (44 sur une piece de
            -- raid). Notre chiffre vient du droptimizer, il est juste.
            row.ilvl:SetText(item.ilvl and item.ilvl > 0
                and (hex("muted") .. "ilvl " .. item.ilvl .. "|r") or "")
            row.fixes:SetText(hex("muted") .. string.format(L["%d need"], #item.members) .. "|r")
            row.sim:SetText(string.format("%s%+.2f%%|r", hex("good"), item.best))

            -- Au survol : l'infobulle de l'objet, puis le classement complet de la guilde.
            row.item = item
            row.encounter = group.encounter
            row:SetScript("OnEnter", needOnEnter)
            row:SetScript("OnLeave", hideTooltip)
            row:SetScript("OnClick", nil)
            row:Show()
            offset = offset + ROW_HEIGHT
        end

        offset = offset + 6
    end

    view.content:SetHeight(math.max(1, offset))
end
