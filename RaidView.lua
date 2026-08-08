local _, ns = ...

local RaidView = {}
ns.RaidView = RaidView

local L = ns.L

-- Vue par raid et par boss, sur le modele du journal des aventures : liste de rencontres a
-- gauche avec le portrait du boss, table de butin a droite.
--
-- La table de butin n'est PAS fabriquee. L'ensemble des objets qu'un droptimizer a simules
-- pour une rencontre est sa table de butin, telle que Raidbots l'a vue. Un boss absent de tes
-- rapports n'apparait pas : il n'y a rien a en dire.
--
-- Les identifiants viennent des noms de profileset de Raidbots et sont ceux du journal : le
-- client rend les noms traduits et les portraits, donc rien n'est embarque et rien ne perime.

local LIST_WIDTH = 268
local BOSS_HEIGHT = 46
local PORTRAIT = 38
local LOOT_HEIGHT = 34

local view, pools, selected

local function hex(key)
    return ns.Theme.C(key)
end

-- Pooling partage : voir Pool.lua. Cette vue en avait sa propre copie, identique au
-- caractere pres a celle de GearView.

local function resetPools()
    ns.Pool.ResetAll(pools)
end

local function acquire(kind)
    return pools[kind]:Acquire()
end

--- Seuils d'AFFICHAGE. Ils ne pretendent pas qu'un gain de 2 % « compte » et qu'un gain de
--- 1,9 % « ne compte pas » : ils donnent une couleur, pas un verdict.
local function tint(percent)
    if percent >= 2 then return "good" end
    if percent >= 0.5 then return "bis" end
    return "muted"
end

--- Portrait d'un boss, comme le journal l'affiche.
---
--- Mis en cache par rencontre. La version precedente reglait le journal a CHAQUE boss et
--- a CHAQUE rafraichissement — donc une dizaine de changements d'etat par ouverture de
--- l'onglet, sur une interface partagee avec le joueur. Un portrait ne change pas.
local portraitCache = {}

local function bossPortrait(instanceID, encounterID)
    if not encounterID then return nil end

    local cached = portraitCache[encounterID]
    if cached ~= nil then return cached or nil end

    if type(EJ_GetCreatureInfo) ~= "function" then return nil end

    local portrait = ns.Journal.Read(instanceID, nil, nil, function()
        -- EJ_GetCreatureInfo : id, nom, description, displayInfo, iconImage.
        local results = { pcall(EJ_GetCreatureInfo, 1, encounterID) }
        return results[1] and results[1 + 5] or nil
    end)

    -- `false` marque un echec deja constate : on ne relance pas la lecture a chaque
    -- rendu. `nil` voudrait dire « pas encore essaye ».
    portraitCache[encounterID] = portrait or false
    return portrait
end

-- La lecture d'objet passe par ItemInfo.lua : nom, qualite et code couleur.

-- --------------------------------------------------------------------- widgets

local function newBoss()
    local button = CreateFrame("Button", nil, view.list, "BackdropTemplate")
    button:SetSize(LIST_WIDTH - 8, BOSS_HEIGHT)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    button.portrait = button:CreateTexture(nil, "ARTWORK")
    button.portrait:SetSize(PORTRAIT, PORTRAIT)
    button.portrait:SetPoint("LEFT", 4, 0)
    button.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.name:SetPoint("TOPLEFT", button.portrait, "TOPRIGHT", 8, -3)
    button.name:SetWidth(LIST_WIDTH - PORTRAIT - 78)
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)

    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.count:SetPoint("BOTTOMLEFT", button.portrait, "BOTTOMRIGHT", 8, 4)
    button.count:SetJustifyH("LEFT")

    button.best = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.best:SetPoint("RIGHT", -8, 0)
    button.best:SetWidth(58)
    button.best:SetJustifyH("RIGHT")

    return button
end

local function newLoot()
    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(LOOT_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.slot:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.slot:SetJustifyH("LEFT")

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetPoint("RIGHT", -8, 0)
    row.value:SetWidth(76)
    row.value:SetJustifyH("RIGHT")

    return row
end

local function newHeader()
    local text = view.list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    return text
end

-- ------------------------------------------------------------------- public

function RaidView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- Les lignes de butin et les boutons de boss portent des scripts de survol qui ne
    -- sont pas tous reecrits d'un rendu a l'autre : le pool les vide.
    local function resetRow(row)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:SetScript("OnClick", nil)
    end

    pools = {
        boss = ns.Pool.New(newBoss, resetRow),
        loot = ns.Pool.New(newLoot, resetRow),
        header = ns.Pool.New(newHeader),
    }

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 2, -2)
    view.intro:SetJustifyH("LEFT")

    -- Colonne des rencontres, comme le volet gauche du journal.
    view.listScroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.listScroll:SetPoint("TOPLEFT", 0, -26)
    view.listScroll:SetPoint("BOTTOMLEFT", 0, 0)
    view.listScroll:SetWidth(LIST_WIDTH)

    view.list = CreateFrame("Frame", nil, view.listScroll)
    view.list:SetSize(LIST_WIDTH - 8, 1)
    view.listScroll:SetScrollChild(view.list)

    -- Table de butin de la rencontre choisie.
    view.lootTitle = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.lootTitle:SetPoint("TOPLEFT", LIST_WIDTH + 24, -26)
    view.lootTitle:SetJustifyH("LEFT")

    view.lootNote = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.lootNote:SetPoint("TOPLEFT", view.lootTitle, "BOTTOMLEFT", 0, -2)
    view.lootNote:SetJustifyH("LEFT")

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", LIST_WIDTH + 24, -68)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(400, 1)
    view.scroll:SetScrollChild(view.content)

    return view
end

function RaidView.Refresh()
    if not view then return end
    resetPools()

    view.intro:SetWidth(math.max(200, (view:GetWidth() or 600) - 8))

    local groups = ns.Sim.ByEncounter()
    if not groups then
        view.intro:SetText(hex("muted")
            .. L["No droptimizer imported yet. Paste a report link in the Equipment tab."] .. "|r")
        view.lootTitle:SetText("")
        view.lootNote:SetText("")
        view.list:SetHeight(1)
        view.content:SetHeight(1)
        return
    end

    view.intro:SetText(hex("muted")
        .. L["Each boss shows the items your droptimizer actually simulated, best gain first."] .. "|r")

    -- Selection persistante d'un affichage a l'autre, et repli sur la rencontre la plus
    -- payante quand la precedente a disparu du releve.
    local chosen
    for _, group in ipairs(groups) do
        if group.encounter == selected then chosen = group end
    end
    chosen = chosen or groups[1]
    selected = chosen.encounter

    -- ------------------------------------------------------ volet des rencontres
    local top = 0
    local instanceShown = {}

    for _, group in ipairs(groups) do
        local instanceName = ns.Sim.InstanceName(group.instance)
        if instanceName and not instanceShown[group.instance] then
            instanceShown[group.instance] = true
            local title = acquire("header")
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", 4, top - 4)
            title:SetText(hex("link") .. instanceName:upper() .. "|r")
            top = top - 22
        end

        local button = acquire("boss")
        button:SetParent(view.list)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, top)

        local active = group.encounter == selected
        button:SetBackdropColor(1, 1, 1, active and 0.07 or 0.02)
        button:SetBackdropBorderColor(0, 0.69, 1, active and 0.6 or 0.08)

        button.portrait:SetTexture(bossPortrait(group.instance, group.encounter)
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.name:SetText((active and hex("link") or hex("text"))
            .. (group.name or string.format(L["encounter %d"], group.encounter)) .. "|r")
        button.count:SetText(hex("muted") .. string.format(L["%d items simulated"], #group.items) .. "|r")
        button.best:SetText(string.format("%s%+.2f%%|r", hex(tint(group.best)), group.best))

        button:SetScript("OnClick", function()
            selected = group.encounter
            RaidView.Refresh()
        end)

        top = top - BOSS_HEIGHT - 4
    end

    view.list:SetHeight(math.max(1, -top + 8))

    -- ------------------------------------------------------------ table de butin
    view.lootTitle:SetText(hex("text")
        .. (chosen.name or string.format(L["encounter %d"], chosen.encounter)) .. "|r")
    view.lootNote:SetText(hex("muted") .. string.format(L["%d items simulated by your droptimizer"],
        #chosen.items) .. "|r")

    local width = math.max(320, (view.scroll:GetWidth() or 480) - 8)
    view.content:SetWidth(width)

    local lootTop = 0
    for _, item in ipairs(chosen.items) do
        local row = acquire("loot")
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, lootTop)
        row:SetWidth(width)
        row.name:SetWidth(width - 130)
        row.slot:SetWidth(width - 130)

        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        local icon
        if getIcon then
            local ok, value = pcall(getIcon, item.id)
            if ok then icon = value end
        end
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Le lien du journal porte deja le nom colore a la qualite : quand il est la, on
        -- l'affiche tel quel plutot que de reconstruire.
        local link = ns.Sim.LootLink(item.encounter, item.id, item.difficulty, item.instance)
        if link then
            row.name:SetText(link)
        else
            row.name:SetText(ns.ItemInfo.ColoredName(item.id)
                or (hex("muted") .. "item:" .. item.id .. "|r"))
        end

        local detail = {}
        if item.slot and item.slot ~= "" then table.insert(detail, item.slot) end
        if item.ilvl and item.ilvl > 0 then table.insert(detail, "ilvl " .. item.ilvl) end
        row.slot:SetText(hex("muted") .. table.concat(detail, "  ·  ") .. "|r")

        row.value:SetText(string.format("%s%+.2f%%|r", hex(tint(item.percent)), item.percent))

        -- Au survol : l'infobulle reelle du jeu, puis ce que l'objet t'apporte. « Le besoin »
        -- est ton gain simule ; aucune donnee d'un autre joueur ne circule.
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()

            -- Le lien du journal d'abord : il porte les identifiants de bonus, donc le VRAI
            -- niveau. `SetItemByID` ne connait que le modele et affichait 44 sur une piece de
            -- raid — c'est pour ca que l'Adventure Guide, lui, avait juste.
            local link = ns.Sim.LootLink(item.encounter, item.id, item.difficulty, item.instance)
            local shown = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            if not shown and not pcall(GameTooltip.SetItemByID, GameTooltip, item.id) then
                GameTooltip:AddLine("item:" .. item.id)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine(L["simulated (% DPS)"],
                string.format("%+.2f%%", item.percent), 0.54, 0.54, 0.54, 0, 0.9, 0.46)
            if item.ilvl and item.ilvl > 0 then
                GameTooltip:AddDoubleLine(L["simulated at ilvl"], tostring(item.ilvl),
                    0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
                -- L'avertissement ne sert que si l'on a du retomber sur le modele.
                if not shown then
                    GameTooltip:AddLine(L["the item level above is the base template, not the drop"],
                        0.54, 0.54, 0.54, true)
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        lootTop = lootTop - LOOT_HEIGHT - 2
    end

    view.content:SetHeight(math.max(1, -lootTop + 8))
end
