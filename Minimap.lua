local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

-- Bouton de minicarte maison : l'addon ne depend d'aucune librairie externe.

local RADIUS = 80
local button

-- math.atan2 existe dans le Lua 5.1 du client, mais on ne parie pas dessus.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function updatePosition()
    if not button then return end
    local angle = math.rad(ns.db.minimapAngle or 200)
    button:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle))
end

local function onUpdateDrag(self)
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    ns.db.minimapAngle = math.deg(atan2(py - my, px - mx))
    updatePosition()
end

local function buildTooltip()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("SpecAnalyser")
    GameTooltip:AddLine(" ")

    -- Il y avait ici un compte de fichiers d'analyse lu dans `SpecAnalyserData`, une
    -- table que plus rien ne definit depuis le retrait de l'analyse hors-jeu.
    GameTooltip:AddLine(ns.L["gear audit"], 0.8, 0.8, 0.9)

    local _, summary = ns.Gear.Scan()
    if summary.problems > 0 then
        GameTooltip:AddLine(string.format(ns.L["%d gear issue(s)"], summary.problems),
            0.89, 0.64, 0.36)
    else
        GameTooltip:AddLine(ns.L["Gear complete"], 0.45, 0.78, 0.62)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.L["Left click: open"], 0, 0.69, 1)
    GameTooltip:AddLine(ns.L["Right click: gear"], 0, 0.69, 1)
    GameTooltip:AddLine(ns.L["Drag: move the icon"], 0, 0.69, 1)
    GameTooltip:Show()
end

function MinimapButton.Create()
    if button then return button end

    button = CreateFrame("Button", "SpecAnalyserMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Pastille d'etat : verte si tout est en place, orange si un enchantement ou une
    -- gemme manque, rouge si une piece est absente ou abimee.
    button.dot = button:CreateTexture(nil, "OVERLAY")
    button.dot:SetSize(9, 9)
    button.dot:SetPoint("BOTTOMRIGHT", -2, 3)
    button.dot:SetTexture("Interface\\Buttons\\WHITE8X8")

    button:SetScript("OnEnter", buildTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onUpdateDrag)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.UI.Show("gear")
        else
            ns.UI.Toggle()
        end
    end)

    updatePosition()
    MinimapButton.Refresh()
    return button
end

--- Met la pastille a jour selon l'etat de l'equipement.
function MinimapButton.Refresh()
    if not button or not button.dot then return end

    local _, summary = ns.Gear.Scan()
    if summary.emptySlots > 0 or summary.damaged > 0 then
        button.dot:SetColorTexture(1, 0.42, 0.42, 1)
    elseif summary.problems > 0 then
        button.dot:SetColorTexture(0.89, 0.64, 0.36, 1)
    else
        button.dot:SetColorTexture(0.29, 0.72, 0.51, 1)
    end
end

function MinimapButton.SetShown(shown)
    ns.db.minimapShown = shown and true or false
    if shown then
        MinimapButton.Create():Show()
    elseif button then
        button:Hide()
    end
end

ns.On("PLAYER_LOGIN", function()
    if ns.db.minimapShown == false then return end
    MinimapButton.Create()
end)
