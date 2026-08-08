local _, ns = ...

local Copy = {}
ns.Copy = Copy

-- Fenetre de copie partagee : WoW n'accede pas au presse-papier, on presente donc un
-- champ de saisie deja selectionne pour un Ctrl+C.

local popup

local function ensurePopup()
    if popup then return popup end

    popup = CreateFrame("Frame", "SpecAnalyserCopyPopup", UIParent, "BasicFrameTemplateWithInset")
    popup:SetSize(360, 120)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:Hide()

    popup.header = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    popup.header:SetPoint("TOPLEFT", 16, -30)

    popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.hint:SetPoint("TOPLEFT", 16, -48)
    popup.hint:SetText("Ctrl+A puis Ctrl+C pour copier")

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -68)
    scroll:SetPoint("BOTTOMRIGHT", -32, 14)

    -- L'habillage masque les textures du modele, dont le fond de l'inset. Sans ce cadre,
    -- la zone de saisie se poserait a plat sur le fond, sans aucune delimitation.
    local well = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    well:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 6)
    well:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 6, -6)
    well:SetFrameLevel(math.max(0, scroll:GetFrameLevel() - 1))
    well:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    popup.themeCards = { well }

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() popup:Hide() end)
    scroll:SetScrollChild(edit)
    popup.edit = edit
    popup.scroll = scroll

    tinsert(UISpecialFrames, "SpecAnalyserCopyPopup")

    -- Meme habillage que la fenetre principale : une pop-up au cadre du client par-dessus
    -- une interface sombre se voit immediatement.
    ns.Theme.Apply(popup)
    return popup
end

--- Redimensionne la fenetre selon le contenu : un nom d'enchantement n'a pas besoin
--- du meme cadre qu'une chaine SimulationCraft de cinquante lignes.
local function fitToContent(frame, text)
    local lines, longest = 1, 0
    for line in tostring(text or ""):gmatch("[^\n]*") do
        lines = lines + 1
        longest = math.max(longest, #line)
    end
    lines = math.max(1, lines - 1)

    local width = math.min(620, math.max(320, longest * 7 + 90))
    local height = math.min(420, math.max(112, lines * 14 + 92))

    frame:SetSize(width, height)
    frame.edit:SetWidth(width - 74)
end

--- Demande une saisie a l'utilisateur (collage d'une chaine).
--- `callback` recoit le texte saisi.
function Copy.Prompt(title, hint, callback)
    local frame = ensurePopup()
    local titleText = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if titleText then titleText:SetText("SpecAnalyser") end

    frame.header:SetText(title or "")
    frame.hint:SetText(hint or "")
    fitToContent(frame, string.rep(" ", 60))
    frame.edit:SetText("")
    frame.edit:SetFocus()

    if not frame.accept then
        frame.accept = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.accept:SetSize(120, 22)
        frame.accept:SetPoint("BOTTOMRIGHT", -32, 16)
    end

    frame.accept:SetText(OKAY or "OK")
    frame.accept:SetScript("OnClick", function()
        local value = frame.edit:GetText()
        frame:Hide()
        if callback then callback(value) end
    end)
    frame.accept:Show()

    frame:Show()
end

--- Affiche un bloc de texte selectionnable.
function Copy.Show(title, text)
    local frame = ensurePopup()
    local titleText = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if titleText then titleText:SetText("SpecAnalyser") end
    frame.header:SetText(title or "")
    frame.hint:SetText("Ctrl+A / Ctrl+C")
    fitToContent(frame, text)
    frame.edit:SetText(text or "")
    frame.edit:HighlightText()
    frame.edit:SetFocus()
    if frame.accept then frame.accept:Hide() end
    frame:Show()
end
