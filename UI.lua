local _, ns = ...

local UI = {}
ns.UI = UI

local COLORS = {
    gold   = "|cffffd24f",
    accent = "|cff8b6bff",
    good   = "|cff74c69d",
    major  = "|cffe3a45c",
    muted  = "|cff9d95b6",
    title  = "|cffd6c9ff",
    reset  = "|r",
}

local TABS = {
    { key = "gear",  label = "Equipment" },
    { key = "raid",  label = "Raid" },
    { key = "guild", label = "Guild" },
    { key = "help",  label = "Help" },
}

local WIDTH, HEIGHT = 1040, 660
local CONTENT_LEFT = 16

local L = ns.L

local frame, hosts, tabButtons, characterLine, metaStatus, weightStatus, specButton, specMenu
local activeTab = "gear"

-- Declaration en amont : le menu de specialisation est defini avant `refresh` et l'appelle.
-- Sans ca, la fermeture capturerait un global inexistant au lieu de la fonction locale.
local refresh

-- ----------------------------------------------------------------- entete

local function updateCharacterLine()
    if not characterLine then return end

    local name = UnitName("player") or "?"
    local specName = ns.Spec.Name(ns.Spec.Selected())
    local _, equipped = GetAverageItemLevel()

    -- Regarder une autre spe que la sienne doit se voir : sinon l'audit ressemble a un
    -- verdict sur l'equipement porte alors qu'il repond a une question hypothetique.
    local suffix = ""
    if ns.Spec.IsPreview() then
        suffix = string.format("  ·  %s%s|r", ns.Theme.C("bis"), L["Preview: %s"]:format(specName or "?"))
        specName = nil
    end

    characterLine:SetText(string.format("%s%s%s%s",
        name,
        specName and ("  ·  " .. specName) or "",
        equipped and ("  ·  ilvl " .. math.floor(equipped + 0.5)) or "",
        suffix))
end

--- Liste deroulante maison. Les API de menu de Blizzard ont change plusieurs fois et je ne
--- peux rien verifier en jeu depuis ici : quelques lignes de cadre et de boutons ne peuvent
--- pas se casser au prochain patch.
local function toggleSpecMenu()
    if not specMenu then return end
    if specMenu:IsShown() then
        specMenu:Hide()
        return
    end

    local list = ns.Spec.List()
    local active = ns.Spec.Active()
    local selected = ns.Spec.Selected()

    for index, entry in ipairs(list) do
        local item = specMenu.items[index]
        if not item then
            item = CreateFrame("Button", nil, specMenu, "BackdropTemplate")
            item:SetSize(188, 22)
            item:SetPoint("TOPLEFT", 3, -3 - (index - 1) * 23)
            item:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })

            item.text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            item.text:SetPoint("LEFT", 8, 0)
            item.text:SetJustifyH("LEFT")

            item:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 1, 1, 0.10) end)
            item:SetScript("OnLeave", function(self)
                self:SetBackdropColor(1, 1, 1, self.chosen and 0.06 or 0)
            end)
            specMenu.items[index] = item
        end

        item.chosen = entry.id == selected
        item:SetBackdropColor(1, 1, 1, item.chosen and 0.06 or 0)
        item.text:SetText(((entry.id == selected) and ns.Theme.C("link") or ns.Theme.C("text"))
            .. entry.name .. "|r"
            .. ((entry.id == active) and ("  " .. ns.Theme.C("muted") .. L["your spec"] .. "|r") or ""))
        item:SetScript("OnClick", function()
            ns.Spec.Select(entry.id)
            specMenu:Hide()
            refresh()
        end)
        item:Show()
    end

    for index = #list + 1, #specMenu.items do
        specMenu.items[index]:Hide()
    end

    specMenu:SetHeight(6 + #list * 23)
    specMenu:Show()
end

local function updateSpecButton()
    if not specButton then return end

    local list = ns.Spec.List()
    if #list < 2 then
        specButton:Hide()
        return
    end

    specButton:Show()
    local selected = ns.Spec.Selected()
    local label = ns.Spec.Name(selected) or "?"
    if not ns.Spec.IsPreview() then
        label = label .. "  ·  " .. L["your spec"]
    end
    specButton:SetText(label)
end

--- Fraicheur des deux jeux de donnees dont depend l'audit.
local function updateReferences()
    if not metaStatus then return end

    if ns.Meta.Available() then
        -- La provenance nomme la SPE relevee : un releve de Havoc ne doit jamais passer
        -- pour une reference de Devourer. `Source()` est un nom de rencontre, on l'ecrit
        -- comme tel.
        local fights = ns.Meta.Fights()
        local where = (#fights > 0 and table.concat(fights, ", ")) or ns.Meta.Source() or "?"
        metaStatus:SetText(string.format("%s%s%s",
            COLORS.muted, string.format(L["meta reference: %s (%d players)"],
                where, ns.Meta.Sample()), COLORS.reset))
    elseif ns.Meta.AnyAvailable() then
        -- Nuance qui compte : des donnees sont installees, mais pas pour cette spe.
        metaStatus:SetText(COLORS.major
            .. L["no top-build reference for this spec yet"] .. COLORS.reset)
    else
        metaStatus:SetText(COLORS.major .. L["no meta reference loaded"] .. COLORS.reset)
    end

    local description, stale = ns.Weights.Describe()
    weightStatus:SetText((stale and COLORS.major or COLORS.muted) .. description .. COLORS.reset)
end

-- --------------------------------------------------------------- affichage

function refresh()
    if not frame then return end

    updateCharacterLine()
    updateSpecButton()
    updateReferences()

    for _, button in ipairs(tabButtons) do
        local selected = button.key == activeTab
        button.background:SetColorTexture(1, 0.82, 0.31, selected and 0.12 or 0.03)
        button.border:SetBackdropBorderColor(1, 0.82, 0.31, selected and 0.75 or 0.12)
        button.label:SetTextColor(selected and 1 or 0.68, selected and 0.82 or 0.66, selected and 0.31 or 0.76)
    end

    for key, host in pairs(hosts) do
        host:SetShown(key == activeTab)
    end

    if activeTab == "gear" then
        ns.GearView.Refresh()
    elseif activeTab == "raid" then
        ns.RaidView.Refresh()
    elseif activeTab == "guild" then
        ns.GuildView.Refresh()
    else
        ns.HelpView.Refresh()
    end

    ns.MinimapButton.Refresh()
end

local function selectTab(key)
    activeTab = key
    refresh()
end

local function createTabButton(parent, index, definition)
    -- La rangee d'onglets doit s'arreter avant la case "Log automatique" en haut a droite.
    local width, gap = 124, 6
    local total = #TABS * width + (#TABS - 1) * gap
    local available = WIDTH - CONTENT_LEFT - 210
    local startX = CONTENT_LEFT + math.max(0, (available - total) / 2)

    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 28)
    button:SetPoint("TOPLEFT", startX + (index - 1) * (width + gap), -52)
    button.key = definition.key

    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()

    button.border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.border:SetAllPoints()
    button.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("CENTER")
    button.label:SetText(L[definition.label])

    button:SetScript("OnEnter", function()
        if button.key ~= activeTab then button.label:SetTextColor(1, 1, 1) end
    end)
    button:SetScript("OnLeave", function()
        if button.key ~= activeTab then button.label:SetTextColor(0.68, 0.66, 0.76) end
    end)
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        selectTab(definition.key)
    end)

    return button
end

local function createHost(name)
    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", CONTENT_LEFT, -92)
    host:SetPoint("BOTTOMRIGHT", -16, 40)
    host:Hide()
    hosts[name] = host
    return host
end

local function createFrame()
    frame = CreateFrame("Frame", "SpecAnalyserFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    -- Sans strata explicite, les barres d'action et les autres addons passent devant.
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self) self:Raise() end)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if title then title:SetText("SpecAnalyser") end

    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 18, -30)
    heading:SetText(COLORS.title .. "SpecAnalyser" .. COLORS.reset)

    characterLine = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    characterLine:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -3)
    characterLine:SetJustifyH("LEFT")

    -- L'audit repose sur deux jeux de donnees externes : leur fraicheur se lit d'un coup
    -- d'oeil plutot que de se deviner.
    metaStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaStatus:SetPoint("TOPRIGHT", -26, -32)
    metaStatus:SetJustifyH("RIGHT")

    weightStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    weightStatus:SetPoint("TOPRIGHT", metaStatus, "BOTTOMRIGHT", 0, -3)
    weightStatus:SetJustifyH("RIGHT")

    -- Actions permanentes de l'entete : elles ne dependent pas de l'onglet ouvert.
    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshButton:SetSize(90, 20)
    refreshButton:SetPoint("TOPRIGHT", -26, -68)
    refreshButton:SetText(L["Refresh"])
    refreshButton:SetScript("OnClick", refresh)

    -- Ancre sur la bande vide de l'entete, a droite du titre. Sous le bouton Refresh, il
    -- occupait y -92..-112 alors que TOUS les hotes d'onglet commencent a -92 : il recouvrait
    -- l'origine de la jauge dans Equipement et le titre de la carte FAQ dans Aide — l'onglet
    -- qui s'ouvre au premier lancement. Geometrie deterministe, pas un cas limite.
    specButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    specButton:SetSize(190, 20)
    specButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 300, -34)
    specButton:SetScript("OnClick", toggleSpecMenu)

    specMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    specMenu:SetWidth(194)
    specMenu:SetPoint("TOPLEFT", specButton, "BOTTOMLEFT", 0, -2)
    specMenu:SetFrameStrata("DIALOG")
    specMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    specMenu:SetBackdropColor(0.07, 0.07, 0.07, 0.98)
    specMenu:SetBackdropBorderColor(0, 0.69, 1, 0.5)
    specMenu.items = {}
    specMenu:Hide()
    specButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Preview another spec"])
        GameTooltip:AddLine(L["The audit recomputes enchants, gems and stat targets for the spec you pick. Your gear does not change."],
            0.8, 0.8, 0.9, true)
        GameTooltip:Show()
    end)
    specButton:SetScript("OnLeave", function() GameTooltip:Hide() end)


    tabButtons = {}
    for index, definition in ipairs(TABS) do
        tabButtons[index] = createTabButton(frame, index, definition)
    end

    -- La grille d'equipement vit dans son onglet, pas dans le cadre de la fenetre :
    -- elle n'a rien a faire derriere l'analyse ou l'historique.
    hosts = {}
    ns.GearView.Create(createHost("gear"))
    ns.RaidView.Create(createHost("raid"))
    ns.GuildView.Create(createHost("guild"))
    ns.HelpView.Create(createHost("help"))

    local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 18, 16)
    footer:SetText(L["/sa to open  ·  minimap icon  ·  right click a tile to mute its alert"])

    local themeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    themeButton:SetSize(90, 20)
    themeButton:SetPoint("BOTTOMRIGHT", -18, 12)
    themeButton:SetText(L["Skin"])
    themeButton:SetScript("OnClick", function()
        -- Toggle reprend tous les cadres enregistres, pop-ups comprises.
        ns.Theme.Toggle()
        refresh()
    end)

    local reloadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reloadButton:SetSize(90, 20)
    reloadButton:SetPoint("RIGHT", themeButton, "LEFT", -6, 0)
    reloadButton:SetText(L["Reload UI"])
    reloadButton:SetScript("OnClick", ReloadUI)
    reloadButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Reload UI"])
        GameTooltip:AddLine(L["A freshly generated analysis is only read at load."], 0.8, 0.8, 0.9, true)
        GameTooltip:Show()
    end)
    reloadButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.Theme.Apply(frame)
    tinsert(UISpecialFrames, "SpecAnalyserFrame")
end

--- Affiche la fenetre puis redessine une fois de plus au tick suivant.
--- Au tout premier affichage, les largeurs de cadres ne sont pas encore resolues :
--- la chronologie et la courbe seraient dessinees sur une largeur par defaut.
local function showFrame()
    refresh()
    frame:Show()
    frame:Raise()
    C_Timer.After(0, function()
        if frame and frame:IsShown() then refresh() end
    end)
end

function UI.Toggle()
    if not frame then createFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        showFrame()
    end
end

function UI.Show(tab)
    if not frame then createFrame() end
    if tab then activeTab = tab end
    showFrame()
end


function UI.Refresh()
    if frame and frame:IsShown() then refresh() end
end

ns.On("PLAYER_LOGIN", function()
    local count = #((SpecAnalyserData and SpecAnalyserData.reports) or {})
    if count > 0 and SpecAnalyserData.generatedAt then
        ns.Print("%d analyse(s) disponible(s). |cff9d95b6/sa|r pour les consulter.", count)
    end
end)

-- Un changement d'equipement invalide le mannequin, l'onglet Equipement et la pastille.
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    if frame then
        ns.Armory.Refresh()
        if frame:IsShown() and activeTab == "gear" then ns.GearView.Refresh() end
    end
    ns.MinimapButton.Refresh()
end)
