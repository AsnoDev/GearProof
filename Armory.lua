local _, ns = ...

local Armory = {}
ns.Armory = Armory

local L = ns.L

-- Grille compacte : 16 cases en 4x4, l'ilvl dans la case, l'etat dans la bordure.
--
-- L'ancienne disposition reprenait la feuille de personnage de Blizzard — deux colonnes
-- verticales autour d'un modele 3D. Elle coutait 332x500 pixels pour afficher 16 icones.
-- La grille tient dans 191x191 et libere la place pour la liste d'actions.

local TILE = 44
local GAP = 5
local COLUMNS = 4
local WIDTH = COLUMNS * TILE + (COLUMNS - 1) * GAP

-- Ordre de lecture : armure de haut en bas, puis bijouterie, puis armes.
local LAYOUT = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot",
    "ChestSlot", "WristSlot", "HandsSlot", "WaistSlot",
    "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
    "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
}

local function statusColor(status)
    local palette = ns.Theme.RGB
    if status == "ok" then return palette.good end
    if status == "problem" then return palette.bis end
    if status == "critical" then return palette.critical end
    if status == "ignored" then return { 0.24, 0.24, 0.24 } end
    return { 0.30, 0.30, 0.30 }
end

local panel, tiles, model, recoverable, modelToggle

Armory.WIDTH = WIDTH

local function statusOf(entry)
    if not entry then return "empty" end
    if entry.ignored and #entry.problems > 0 then return "ignored" end
    if entry.empty or entry.damaged then return "critical" end
    if #entry.problems > 0 then return "problem" end
    return "ok"
end

local function qualityColor(quality)
    local colors = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if colors then return colors.r, colors.g, colors.b end
    return 0.82, 0.82, 0.88
end

--- Alternatives portables pour cet emplacement, lues dans les sacs.
local function bagLines(slotName)
    local ok, simmed, unrated, _, estimated = pcall(ns.Bags.Compare)
    if not ok then return nil end

    local lines = {}
    -- L'unite est ecrite sur chaque ligne : « % DPS » vient d'un droptimizer, « pts » d'une
    -- estimation lineaire. Sans le suffixe, les deux se lisaient comme la meme grandeur.
    for _, entry in ipairs(simmed or {}) do
        if entry.slot == slotName then
            table.insert(lines, { string.format("%s  i%d  %+.2f%% DPS",
                entry.link or "?", entry.itemLevel or 0, entry.dps), true })
        end
    end
    for _, entry in ipairs(estimated or {}) do
        if entry.slot == slotName then
            table.insert(lines, { string.format("%s  i%d  %+d pts",
                entry.link or "?", entry.itemLevel or 0, entry.gain), true })
        end
    end
    for _, entry in ipairs(unrated or {}) do
        if entry.slot == slotName then
            table.insert(lines, { string.format("%s  i%d  ?",
                entry.link or "?", entry.itemLevel or 0), false })
        end
    end
    return lines
end

local function showTooltip(tile)
    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")

    local entry = tile.entry
    if entry and entry.link then
        GameTooltip:SetInventoryItem("player", tile.slotID)
    else
        GameTooltip:AddLine(L[tile.label or "?"])
        GameTooltip:AddLine(L["empty slot"], 0.62, 0.58, 0.71)
    end

    if entry and #entry.problems > 0 then
        GameTooltip:AddLine(" ")
        for _, problem in ipairs(entry.problems) do
            GameTooltip:AddLine(problem, 0.89, 0.64, 0.36)
        end
        if entry.ignored then
            GameTooltip:AddLine(L["Alert ignored for this piece"], 0.55, 0.42, 1)
        end
    elseif entry and entry.link then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Enchant and gems: ok"], 0.29, 0.72, 0.51)
    end

    -- Ce qui dort dans les sacs pour cet emplacement. C'est la comparaison utile ;
    -- l'infobulle de comparaison du client, elle, repete la piece deja portee.
    local alternatives = bagLines(tile.slotName)
    if alternatives and #alternatives > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["In your bags"], 1, 1, 1)
        for _, line in ipairs(alternatives) do
            if line[2] then
                GameTooltip:AddLine(line[1], 0, 0.90, 0.46)
            else
                GameTooltip:AddLine(line[1], 0.54, 0.54, 0.54)
            end
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Right click: ignore or re-enable the alert"], 0, 0.69, 1)
    GameTooltip:Show()

    -- L'infobulle de comparaison du client double l'affichage sur un objet equipe :
    -- elle compare la piece a elle-meme. On la masque.
    if GameTooltip.shoppingTooltips then
        for _, shopping in ipairs(GameTooltip.shoppingTooltips) do
            shopping:Hide()
        end
    end
end

local function createTile(parent, slotName, index)
    local slotID, defaultTexture = GetInventorySlotInfo(slotName)
    local column = (index - 1) % COLUMNS
    local row = math.floor((index - 1) / COLUMNS)

    local tile = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tile:SetSize(TILE, TILE)
    tile:SetPoint("TOPLEFT", column * (TILE + GAP), -row * (TILE + GAP))
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile.slotName = slotName
    tile.slotID = slotID
    tile.defaultTexture = defaultTexture

    tile:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    tile:SetBackdropColor(0, 0, 0, 0.45)

    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 3, -3)
    tile.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    tile.icon:SetTexCoord(0.09, 0.91, 0.09, 0.91)

    -- Voile sombre en bas de l'icone : l'ilvl doit rester lisible sur toute texture.
    tile.shade = tile:CreateTexture(nil, "OVERLAY")
    tile.shade:SetPoint("BOTTOMLEFT", 3, 3)
    tile.shade:SetPoint("BOTTOMRIGHT", -3, 3)
    tile.shade:SetHeight(13)
    tile.shade:SetColorTexture(0, 0, 0, 0.6)

    tile.ilvl = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.ilvl:SetPoint("BOTTOM", 0, 4)
    pcall(function()
        local font = tile.ilvl:GetFont()
        tile.ilvl:SetFont(font, 11, "OUTLINE")
    end)

    -- Pastille 12x12 en haut a droite : rouge "!" si un enchantement ou une gemme
    -- manque, or "*" si une meilleure piece dort dans les sacs.
    tile.pill = CreateFrame("Frame", nil, tile, "BackdropTemplate")
    tile.pill:SetSize(13, 13)
    tile.pill:SetPoint("TOPRIGHT", 2, 2)
    tile.pill:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    tile.pill:SetBackdropBorderColor(0.07, 0.07, 0.07, 1)

    tile.pill.glyph = tile.pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.pill.glyph:SetPoint("CENTER", 0, 0)
    pcall(function()
        local font = tile.pill.glyph:GetFont()
        tile.pill.glyph:SetFont(font, 10, "OUTLINE")
    end)
    tile.pill:Hide()

    tile.glow = tile:CreateTexture(nil, "OVERLAY")
    tile.glow:SetPoint("TOPLEFT", -2, 2)
    tile.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    tile.glow:SetColorTexture(1, 1, 1, 0.25)
    tile.glow:Hide()

    tile:SetScript("OnEnter", showTooltip)
    tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tile:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Gear.SetIgnored(slotName, not ns.Gear.IsIgnored(slotName))
            ns.UI.Refresh()
            return
        end

        -- Clic gauche : la piece s'ouvre dans le panneau de detail, qui reste affiche.
        -- C'est ce qui remplace l'infobulle au survol : elle disparaissait des qu'on
        -- bougeait la souris, donc impossible de la lire en cherchant autre chose.
        ns.GearView.Select(slotName)
    end)

    return tile
end

--- Cree la grille dans `parent`. Largeur fixe, hauteur suivant le contenu.
function Armory.Create(parent)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(WIDTH)

    -- Le mannequin en haut, les cases en dessous : on garde la lecture "feuille de
    -- personnage" sans lui sacrifier la moitie de la largeur de la fenetre.
    model = CreateFrame("PlayerModel", nil, panel)
    model:SetPoint("TOPLEFT", 0, 0)
    model:SetSize(WIDTH, 236)

    panel.header = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.header:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 0, -8)

    local grid = CreateFrame("Frame", nil, panel)
    grid:SetPoint("TOPLEFT", model, "BOTTOMLEFT", 0, -22)
    grid:SetSize(WIDTH, COLUMNS * TILE + (COLUMNS - 1) * GAP)
    panel.grid = grid

    tiles = {}
    for index, slotName in ipairs(LAYOUT) do
        tiles[slotName] = createTile(grid, slotName, index)
    end

    -- Total recuperable : le chiffre qui decide si on passe chez l'enchanteur maintenant.
    recoverable = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    recoverable:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -10)
    recoverable:SetSize(WIDTH, 42)
    recoverable:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    recoverable.label = recoverable:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    recoverable.label:SetPoint("TOPLEFT", 8, -7)

    recoverable.value = recoverable:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    recoverable.value:SetPoint("BOTTOMLEFT", 8, 6)

    -- Rotation a la souris : le modele reste vivant sans bouton supplementaire.
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self)
        self.dragging = true
        self.lastX = select(1, GetCursorPosition())
    end)
    model:SetScript("OnMouseUp", function(self) self.dragging = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local x = select(1, GetCursorPosition())
        self.rotation = (self.rotation or 0.35) + (x - (self.lastX or x)) * 0.01
        self.lastX = x
        pcall(self.SetRotation, self, self.rotation)
    end)

    Armory.Refresh()
    return panel
end

function Armory.Refresh()
    if not panel then return end

    local _, summary = ns.Gear.Scan()
    local bySlot = summary.bySlot or {}

    -- Une meilleure piece dans les sacs vaut une pastille or sur la case concernee.
    local upgradesBySlot = {}
    local ok, simmed, _, _, estimated = pcall(ns.Bags.Compare)
    if ok then
        for _, upgrade in ipairs(simmed or {}) do
            upgradesBySlot[upgrade.slot] = true
        end
        for _, upgrade in ipairs(estimated or {}) do
            upgradesBySlot[upgrade.slot] = true
        end
    end

    panel.header:SetText(L["gear grid"])

    for slotName, tile in pairs(tiles) do
        local entry = bySlot[slotName]
        tile.entry = entry
        tile.label = entry and entry.label or slotName

        local texture = GetInventoryItemTexture("player", tile.slotID)
        tile.icon:SetTexture(texture or tile.defaultTexture)
        tile.icon:SetDesaturated(texture == nil or (entry and entry.ignored) or false)

        local status = statusOf(entry)
        local color = statusColor(status)
        tile:SetBackdropBorderColor(color[1], color[2], color[3], status == "ok" and 0.7 or 1)

        if entry and entry.itemLevel then
            tile.ilvl:SetText(tostring(entry.itemLevel))
            tile.ilvl:SetTextColor(qualityColor(entry.quality))
            tile.ilvl:Show()
            tile.shade:Show()
        else
            tile.ilvl:Hide()
            tile.shade:Hide()
        end

        -- Pastille : l'alerte prime sur la suggestion d'amelioration.
        local critical = entry and not entry.ignored
            and (entry.missingEnchant or (entry.emptySockets or 0) > 0 or entry.empty)
        local better = upgradesBySlot[slotName]

        if critical then
            local color = ns.Theme.RGB.critical
            tile.pill:SetBackdropColor(color[1], color[2], color[3], 1)
            tile.pill.glyph:SetText("|cff121212!|r")
            tile.pill:Show()
        elseif better then
            local color = ns.Theme.RGB.bis
            tile.pill:SetBackdropColor(color[1], color[2], color[3], 1)
            tile.pill.glyph:SetText("|cff121212*|r")
            tile.pill:Show()
        else
            tile.pill:Hide()
        end
    end

    local stat, measured, fixes = ns.Gear.Recoverable()
    if fixes == 0 then
        recoverable.label:SetText("|cff615c73" .. L["nothing to recover"] .. "|r")
        recoverable.value:SetText("|cff4ab882" .. L["Gear complete"] .. "|r")
        recoverable:SetBackdropColor(0.29, 0.72, 0.51, 0.10)
        recoverable:SetBackdropBorderColor(0.29, 0.72, 0.51, 0.35)
    else
        recoverable.label:SetText(string.format("|cff615c73" .. L["%d fix(es) pending"] .. "|r", fixes))
        if stat > 0 then
            local prefix = measured < fixes and "≥ " or ""
            local shown = BreakUpLargeNumbers and BreakUpLargeNumbers(stat) or tostring(stat)
            recoverable.value:SetText(string.format("|cffe3a45c%s%s %s|r", prefix, shown, L["stat"]))
        else
            recoverable.value:SetText(string.format("|cffe3a45c%d %s|r", fixes, L["to fix"]))
        end
        recoverable:SetBackdropColor(0.89, 0.64, 0.36, 0.10)
        recoverable:SetBackdropBorderColor(0.89, 0.64, 0.36, 0.35)
    end

    if not panel.modelReady then
        panel.modelReady = pcall(function()
            model:SetUnit("player")
            model:SetPortraitZoom(0)
            model:SetRotation(0.35)
        end)
        if not panel.modelReady then model:Hide() end
    end

    panel:SetHeight(236 + 22 + panel.grid:GetHeight() + 10 + 42)
end

--- Fait ressortir une case depuis la liste d'actions.
function Armory.Highlight(slotName, on)
    if not tiles then return end
    local tile = tiles[slotName]
    if tile then tile.glow:SetShown(on and true or false) end
end
