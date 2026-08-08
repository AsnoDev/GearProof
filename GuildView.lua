local _, ns = ...

local GuildView = {}
ns.GuildView = GuildView

local L = ns.L

-- Tableau de la guilde : une ligne par membre equipe de l'addon.

local ROW_HEIGHT = 22
local view, rows
local guildMode = "roster"

-- Declarations en amont. Ces trois fonctions sont definies plus bas, avec la sous-vue Raid,
-- mais `GuildView.Refresh` les appelle : sans cette declaration, un `local function` place
-- apres l'appelant n'est pas en portee et l'appel part chercher un global inexistant. C'est
-- exactement ce qui a casse le bouton de tournee.
local layoutRaidRow, layoutRosterRow, itemName

local function hex(key)
    return ns.Theme.C(key)
end

local function acquireRow(index)
    if rows[index] then return rows[index] end

    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(130)
    row.name:SetJustifyH("LEFT")

    row.spec = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.spec:SetPoint("LEFT", 142, 0)
    row.spec:SetWidth(110)
    row.spec:SetJustifyH("LEFT")

    row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.ilvl:SetPoint("LEFT", 256, 0)
    row.ilvl:SetWidth(60)
    row.ilvl:SetJustifyH("LEFT")

    row.fixes = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.fixes:SetPoint("LEFT", 320, 0)
    row.fixes:SetWidth(90)
    row.fixes:SetJustifyH("LEFT")

    row.sim = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sim:SetPoint("LEFT", 414, 0)
    row.sim:SetJustifyH("LEFT")

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
    view.hint:SetWidth(600)
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

    view.header = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.header:SetPoint("TOPLEFT", 8, -102)

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", 0, -118)
    view.scroll:SetPoint("BOTTOMRIGHT", -26, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(560, 1)
    view.scroll:SetScrollChild(view.content)

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

    view.header:SetText(L["name            spec          ilvl    fixes     last sim"])

    local list = ns.Guild.Roster()
    local offset = 0

    for index, card in ipairs(list) do
        local row = acquireRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -offset)
        layoutRosterRow(row, 560)

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

        row:SetScript("OnClick", function()
            if card.sim ~= "" then
                ns.Copy.Show(card.name, "https://www.raidbots.com/simbot/report/" .. card.sim)
            end
        end)

        row:Show()
        offset = offset + ROW_HEIGHT
    end

    if #list <= 1 then
        view.header:SetText(hex("muted") .. L["Only you so far — ask your guild to run the roll call."] .. "|r")
    else
        view.header:SetText(L["name            spec          ilvl    fixes     last sim"])
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
-- La sous-vue Raid reancre les memes FontStrings sur toute la largeur disponible.
layoutRaidRow = function(row, width)
    row:SetWidth(width)

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(width - 400)
    row.name:SetWordWrap(false)

    row.spec:ClearAllPoints()
    row.spec:SetPoint("LEFT", width - 384, 0)
    row.spec:SetWidth(150)
    row.spec:SetWordWrap(false)

    row.ilvl:ClearAllPoints()
    row.ilvl:SetPoint("LEFT", width - 226, 0)
    row.ilvl:SetWidth(70)

    row.fixes:ClearAllPoints()
    row.fixes:SetPoint("LEFT", width - 150, 0)
    row.fixes:SetWidth(70)

    row.sim:ClearAllPoints()
    row.sim:SetPoint("RIGHT", -8, 0)
    row.sim:SetWidth(74)
    row.sim:SetJustifyH("RIGHT")
end

--- Rend les ancres d'origine, pour que le tableau du roster reste intact.
layoutRosterRow = function(row, width)
    row:SetWidth(width)

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(130)

    row.spec:ClearAllPoints()
    row.spec:SetPoint("LEFT", 142, 0)
    row.spec:SetWidth(110)

    row.ilvl:ClearAllPoints()
    row.ilvl:SetPoint("LEFT", 256, 0)
    row.ilvl:SetWidth(60)

    row.fixes:ClearAllPoints()
    row.fixes:SetPoint("LEFT", 320, 0)
    row.fixes:SetWidth(60)

    row.sim:ClearAllPoints()
    row.sim:SetPoint("LEFT", 384, 0)
    row.sim:SetWidth(170)
    row.sim:SetJustifyH("LEFT")
end

itemName = function(itemID)
    return ns.ItemInfo.ColoredName(itemID)
end

function GuildView.RefreshRaid()
    local groups = ns.Guild.LootByEncounter()
    if not groups then
        view.header:SetText(hex("muted")
            .. L["No droptimizer shared yet. Run the roll call, and ask members to enable sharing."] .. "|r")
        view.content:SetHeight(1)
        return
    end

    view.header:SetText(hex("muted")
        .. L["Loot per boss, ranked by the best gain in the guild. Hover an item for the ranking."] .. "|r")

    -- Toute la largeur du panneau, pas les 560 px du tableau du roster.
    local width = math.max(560, (view.scroll:GetWidth() or 960) - 8)
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
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                -- Le lien du journal des aventures porte les identifiants de bonus, donc le
                -- vrai niveau. `SetItemByID` ne connait que le modele.
                local link = ns.Sim.LootLink(group.encounter, item.id, item.difficulty)
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
                        GameTooltip:AddLine(string.format("+%d…", #item.members - 12),
                            0.54, 0.54, 0.54)
                        break
                    end
                    GameTooltip:AddDoubleLine(
                        string.format("%d. %s", rank, member.name),
                        string.format("%+.2f%%", member.percent),
                        0.91, 0.91, 0.91, 0, 0.9, 0.46)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnClick", nil)
            row:Show()
            offset = offset + ROW_HEIGHT
        end

        offset = offset + 6
    end

    view.content:SetHeight(math.max(1, offset))
end
