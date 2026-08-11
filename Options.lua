local _, ns = ...

local Options = {}
ns.Options = Options

-- Panneau de reglages, dans les Options d'interface du client.
--
-- Il n'y en avait aucun : habillage, langue, alertes et icone de minicarte n'etaient
-- atteignables que par des commandes slash, et `db.tooltip` n'etait meme atteignable par
-- rien du tout — il etait lu une fois a la connexion et ecrit nulle part.
--
-- C'est le premier endroit ou un joueur va chercher, avant meme de savoir qu'un addon a
-- des commandes.

local PANEL_NAME = "GearProof"

local function label(parent, text, anchor, gapY, font)
    local line = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gapY or -8)
    line:SetJustifyH("LEFT")
    line:SetText(text)
    return line
end

--- Case a cocher liee a un champ de la base sauvegardee.
--- @param default boolean valeur quand le champ est nil
--- @param onChange function|nil appelee apres l'ecriture
local function checkbox(parent, anchor, key, text, tip, default, onChange)
    local button = CreateFrame("CheckButton", nil, parent, "InterfaceCheckButtonTemplate")
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, -6)
    button:SetSize(26, 26)

    button.caption = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    button.caption:SetPoint("LEFT", button, "RIGHT", 2, 0)
    ns.Localize(button.caption, text)

    button:SetScript("OnShow", function(self)
        local value = ns.db and ns.db[key]
        if value == nil then value = default end
        self:SetChecked(value and true or false)
    end)
    button:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        ns.db[key] = checked
        if onChange then onChange(checked) end
    end)

    if tip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ns.L[text])
            GameTooltip:AddLine(ns.L[tip], 0.8, 0.8, 0.9, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return button
end

--- Bouton qui fait defiler une liste de valeurs, plutot qu'un menu deroulant.
--- Les API de menu de Blizzard ont change plusieurs fois ; un bouton ne peut pas casser.
local function cycler(parent, anchor, values, get, set, caption)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(160, 22)
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)

    button.caption = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    button.caption:SetPoint("LEFT", button, "RIGHT", 8, 0)
    ns.Localize(button.caption, caption)

    local function render()
        button:SetText(tostring(get()))
    end

    button:SetScript("OnClick", function()
        local current = get()
        local index = 1
        for position, value in ipairs(values) do
            if value == current then index = position end
        end
        set(values[(index % #values) + 1])
        render()
    end)
    button:SetScript("OnShow", render)

    return button
end

function Options.Create()
    if Options.panel then return Options.panel end

    local panel = CreateFrame("Frame")
    panel.name = PANEL_NAME
    Options.panel = panel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PANEL_NAME .. "  |cff8A8A8A" .. (ns.version or "?") .. "|r")

    local intro = label(panel, "", title, -8, "GameFontHighlightSmall")
    intro:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    ns.Localize(intro, "Nothing needs configuring: the measured reference ships with the addon.")

    local anchor = intro

    anchor = cycler(panel, anchor, ns.LANGUAGES,
        function() return (ns.db and ns.db.language) or "auto" end,
        function(value)
            ns.db.language = value
            ns.ApplyLanguage()
            if ns.UI and ns.UI.RefreshNow then ns.UI.RefreshNow() end
        end,
        "Language")

    anchor = cycler(panel, anchor, { "dark", "minimal", "blizzard" },
        function() return ns.Theme.Current() end,
        function(value)
            ns.Theme.Set(value)
            if ns.UI and ns.UI.RefreshNow then ns.UI.RefreshNow() end
        end,
        "Skin")

    anchor = checkbox(panel, anchor, "gearAlerts",
        "Warn me when I enter a dungeon or raid with incomplete gear",
        "Checks enchants, sockets, empty slots and durability a few seconds after the loading screen.",
        true)

    anchor = checkbox(panel, anchor, "tooltip",
        "Add measured lines to item tooltips",
        "Simulated gain, item level against what you wear, and the enchant measured for that slot. Nothing estimated.",
        true)

    anchor = checkbox(panel, anchor, "minimapShown",
        "Show the minimap icon",
        nil, true,
        function(shown) ns.MinimapButton.SetShown(shown) end)

    anchor = checkbox(panel, anchor, "shareWithGuild",
        "Share my data with the guild",
        "Answer the roll call with your spec, item level, pending fixes and droptimizer id. Nothing leaves your client while this is off.",
        false)

    anchor = checkbox(panel, anchor, "debug", "Debug messages", nil, false)

    local reference = label(panel, "", anchor, -18, "GameFontDisableSmall")
    reference:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    reference:SetJustifyH("LEFT")
    ns.Localize(reference,
        "Reference measured from Warcraft Logs rankings, outside the game, and shipped with the addon")

    -- Deux API coexistent selon la version du client : la moderne d'abord, l'ancienne en
    -- repli. Le tout sous pcall — un panneau d'options absent ne doit pas empecher
    -- l'addon de fonctionner.
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, PANEL_NAME)
        if ok and category then
            category.ID = PANEL_NAME
            pcall(Settings.RegisterAddOnCategory, category)
            Options.category = category
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panel)
    end

    return panel
end

--- Ouvre le panneau. Utilise par `/sa options`.
function Options.Open()
    Options.Create()
    if Settings and Settings.OpenToCategory and Options.category then
        pcall(Settings.OpenToCategory, Options.category.ID or Options.category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Deux fois : la premiere ouverture atterrissait sur la mauvaise categorie sur
        -- les anciens clients.
        pcall(InterfaceOptionsFrame_OpenToCategory, PANEL_NAME)
        pcall(InterfaceOptionsFrame_OpenToCategory, PANEL_NAME)
    end
end

ns.On("PLAYER_LOGIN", Options.Create)
