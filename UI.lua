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
    { key = "reco",  label = "Recommendations" },
    { key = "raid",  label = "Raid" },
    { key = "guild", label = "Guild" },
    { key = "help",  label = "Help" },
}

local WIDTH, HEIGHT = 1040, 660
-- Plancher de redimensionnement : en dessous, la colonne laterale de l'onglet Equipement
-- (236 px) et la grille (191 px) ne laissent plus de place aux cartes.
local MIN_WIDTH, MIN_HEIGHT = 900, 560
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

        -- L'age du releve, quand il est date. La taille de l'echantillon etait annoncee
        -- sans jamais dire de QUAND il vient : un releve de six semaines decrit un patch
        -- qui n'existe plus, et rien ne le signalait.
        local age = ns.Meta.AgeInDays()
        local suffix = ""
        if age and age >= 14 then
            suffix = string.format("  %s%s|r", ns.Theme.C("bis"),
                string.format(L["reference measured %d day(s) ago"], age))
        end

        metaStatus:SetText(string.format("%s%s%s%s",
            COLORS.muted, string.format(L["meta reference: %s (%d players)"],
                where, ns.Meta.Sample()), COLORS.reset, suffix))
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
    elseif activeTab == "reco" then
        ns.RecoView.Refresh()
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

local TAB_WIDTH, TAB_GAP, TAB_HEIGHT = 112, 4, 24

local function createTabButton(parent, index, definition)
    -- Rangee d'onglets ALIGNEE A GAUCHE, sur la marge de contenu.
    --
    -- Elle etait centree dans un espace calcule sur `WIDTH - 210`, une reserve pour une
    -- case a cocher qui n'existe plus depuis longtemps. Resultat : des onglets flottant
    -- au milieu, alignes sur rien, et un decalage qui bougeait avec le nombre d'onglets.
    -- La marge gauche est la meme que celle du contenu en dessous : les deux s'alignent.
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(TAB_WIDTH, TAB_HEIGHT)
    button:SetPoint("TOPLEFT", CONTENT_LEFT + (index - 1) * (TAB_WIDTH + TAB_GAP), -58)
    button.key = definition.key

    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()

    button.border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.border:SetAllPoints()
    button.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("CENTER")
    ns.Localize(button.label, definition.label)

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
    -- Sous la rangee d'onglets (-58, hauteur 24) plus une respiration.
    host:SetPoint("TOPLEFT", CONTENT_LEFT, -92)
    host:SetPoint("BOTTOMRIGHT", -16, 40)
    host:Hide()
    hosts[name] = host
    return host
end

--- Retient ou l'on a laisse la fenetre.
---
--- Elle revenait au centre a chaque /reload, dans une taille fixe de 1040x660 qui
--- deborde d'un ecran 1366x768. Deux gestes a refaire a chaque session.
local function rememberPlacement()
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then return end
    ns.db.frame = {
        point = point, relativePoint = relativePoint,
        x = math.floor(x + 0.5), y = math.floor(y + 0.5),
        width = math.floor(frame:GetWidth() + 0.5),
        height = math.floor(frame:GetHeight() + 0.5),
    }
end

local function restorePlacement()
    local saved = ns.db and ns.db.frame
    if type(saved) ~= "table" or not saved.point then
        frame:SetPoint("CENTER")
        return
    end

    -- Bornes : une taille sauvegardee peut venir d'un ecran qu'on n'a plus.
    local width = math.max(MIN_WIDTH, math.min(saved.width or WIDTH, UIParent:GetWidth()))
    local height = math.max(MIN_HEIGHT, math.min(saved.height or HEIGHT, UIParent:GetHeight()))
    frame:SetSize(width, height)
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point,
        saved.x or 0, saved.y or 0)
end

local function createFrame()
    frame = CreateFrame("Frame", "GearProofFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    -- Sans strata explicite, les barres d'action et les autres addons passent devant.
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 1920, 1200)
    end
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self) self:Raise() end)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        rememberPlacement()
    end)
    frame:SetClampedToScreen(true)
    frame:Hide()

    restorePlacement()

    -- Poignee de redimensionnement, en bas a droite. Les vues lisent deja leur largeur
    -- reelle a chaque rendu : l'essentiel du travail etait deja fait.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        rememberPlacement()
        refresh()
    end)

    local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
    if title then title:SetText("GearProof") end

    -- Entete : DEUX rangees, chacune avec un role.
    --
    -- Il y en avait quatre qui se disputaient la meme bande : un titre « GearProof » qui
    -- repetait celui de la barre de titre juste au-dessus, la ligne de personnage, deux
    -- lignes de provenance a droite, un bouton Refresh, et un gros bouton de spe rouge
    -- pose au milieu a x=300 — juste au-dessus des onglets, sans rapport visuel avec
    -- quoi que ce soit. Le resultat se lisait comme un bandeau, pas comme un entete.
    --
    --   rangee 1 : qui tu es          |  d'ou vient la reference
    --   rangee 2 : les onglets        |  quelle spe tu regardes
    --
    -- Refresh part en pied de fenetre avec les autres actions permanentes : ce n'est pas
    -- une information, c'est un bouton, et il n'a rien a faire dans la zone de lecture.

    characterLine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    characterLine:SetPoint("TOPLEFT", CONTENT_LEFT + 2, -30)
    characterLine:SetJustifyH("LEFT")

    -- Provenance : une seule ligne, a droite, en gris. La fraicheur des poids passait sur
    -- une deuxieme ligne qui doublait la hauteur de l'entete pour une information qui se
    -- lit deja dans l'onglet Equipement.
    metaStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaStatus:SetPoint("TOPRIGHT", -CONTENT_LEFT - 2, -32)
    metaStatus:SetJustifyH("RIGHT")

    weightStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    weightStatus:SetPoint("TOPRIGHT", metaStatus, "BOTTOMRIGHT", 0, -2)
    weightStatus:SetJustifyH("RIGHT")

    -- Selecteur de spe : au bout de la rangee d'onglets, aligne a droite. Il est de la
    -- meme hauteur que les onglets et se lit comme ce qu'il est — un choix de contexte,
    -- pas une action.
    specButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    specButton:SetSize(176, 24)
    specButton:SetPoint("TOPRIGHT", -CONTENT_LEFT, -58)
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
    ns.RecoView.Create(createHost("reco"))
    ns.RaidView.Create(createHost("raid"))
    ns.GuildView.Create(createHost("guild"))
    ns.HelpView.Create(createHost("help"))

    local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", 18, 16)
    ns.Localize(footer, "/sa to open  ·  minimap icon  ·  right click a tile to mute its alert")

    -- La poignee de redimensionnement occupe le coin : les boutons remontent de 6 px.
    local themeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    themeButton:SetSize(90, 20)
    themeButton:SetPoint("BOTTOMRIGHT", -24, 18)
    ns.Localize(themeButton, "Skin")
    themeButton:SetScript("OnClick", function()
        -- Toggle reprend tous les cadres enregistres, pop-ups comprises.
        ns.Theme.Toggle()
        refresh()
    end)

    local reloadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reloadButton:SetSize(90, 20)
    reloadButton:SetPoint("RIGHT", themeButton, "LEFT", -6, 0)
    ns.Localize(reloadButton, "Reload UI")
    reloadButton:SetScript("OnClick", ReloadUI)
    reloadButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Reload UI"])
        GameTooltip:AddLine(L["A freshly generated analysis is only read at load."], 0.8, 0.8, 0.9, true)
        GameTooltip:Show()
    end)
    reloadButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Reglages : le panneau du client, la ou un joueur cherche en premier.
    local optionsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    optionsButton:SetSize(90, 20)
    optionsButton:SetPoint("RIGHT", reloadButton, "LEFT", -6, 0)
    ns.Localize(optionsButton, "Settings")
    optionsButton:SetScript("OnClick", function() ns.Options.Open() end)

    -- Refresh descend en pied de fenetre : ce n'est pas une information, c'est un bouton,
    -- et il occupait une ligne entiere de l'entete au-dessus de la zone de lecture.
    local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshButton:SetSize(90, 20)
    refreshButton:SetPoint("RIGHT", optionsButton, "LEFT", -6, 0)
    ns.Localize(refreshButton, "Refresh")
    refreshButton:SetScript("OnClick", function() refresh() end)

    ns.Theme.Apply(frame)
    tinsert(UISpecialFrames, "GearProofFrame")
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


--- Redessine tout de suite. Pour les gestes du joueur : un clic doit repondre.
function UI.RefreshNow()
    if frame and frame:IsShown() then refresh() end
end

--- Redessine au plus une fois par quart de seconde.
---
--- A reserver aux declencheurs PASSIFS : messages de guilde, changements d'equipement,
--- evenements du client. Une tournee de guilde a trente membres produisait quatre-vingt-
--- dix appels en quelques secondes, chacun redessinant l'onglet actif — donc, sur
--- l'onglet Equipement, cinq scans complets et deux parcours de sacs par appel.
local pendingRefresh
function UI.Refresh()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0.25, function()
        pendingRefresh = nil
        if frame and frame:IsShown() then refresh() end
    end)
end

-- Un changement d'equipement invalide l'onglet Equipement et la pastille de minicarte.
--
-- Un seul rendez-vous differe pour les deux. Changer un set complet emet seize
-- evenements d'affilee, et chacun invalide le cache d'audit : sans ce regroupement, la
-- pastille declenchait seize scans reels, cache ou pas.
local pendingEquipment
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    if pendingEquipment then return end
    pendingEquipment = true
    C_Timer.After(0.25, function()
        pendingEquipment = nil
        if frame and frame:IsShown() then
            refresh()          -- rafraichit aussi la grille et la pastille
        else
            ns.MinimapButton.Refresh()
        end
    end)
end)
