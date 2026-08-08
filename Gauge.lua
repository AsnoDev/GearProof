local _, ns = ...

local Gauge = {}
ns.Gauge = Gauge

-- Jauge circulaire construite en segments : 48 petits traits disposes en cercle.
-- Pas de texture d'anneau a embarquer, et le rendu reste previsible.

local TICKS = 48
local TICK_WIDTH = 4
local TICK_LENGTH = 9

-- La jauge affichait un score sur 100 issu de quatre penalites arbitraires (12, 8, 25, 10).
-- C'etait le SEUL nombre invente de l'interface, et c'etait le plus gros a l'ecran, surmonte
-- d'un superlatif. Il se contredisait avec la liste a cote : un enchantement d'arme manquant
-- donnait 88, donc un « EXCELLENT » vert, pendant que la carte de la meme piece etait peinte
-- en rouge critique. Les libelles etaient en plus codes en francais, sans passer par ns.L,
-- dans un addon annonce en anglais.
--
-- Elle compte desormais ce qui est mesure : le nombre de correctifs en attente. La couleur
-- suit ce compte, et ces seuils-la sont assumes comme de l'AFFICHAGE, pas comme une note.
local COLOR_CLEAN = { 0.29, 0.78, 0.47 }
local COLOR_FEW = { 0.95, 0.72, 0.25 }
local COLOR_MANY = { 1.00, 0.42, 0.42 }

local function colorFor(fixes)
    if fixes == 0 then return COLOR_CLEAN end
    if fixes <= 2 then return COLOR_FEW end
    return COLOR_MANY
end

--- Cree une jauge de `size` pixels de diametre.
function Gauge.Create(parent, size)
    local widget = CreateFrame("Frame", nil, parent)
    widget:SetSize(size, size)
    widget.size = size
    widget.ticks = {}

    local radius = size / 2 - TICK_LENGTH / 2 - 2

    for index = 1, TICKS do
        -- On part du haut et on tourne dans le sens horaire.
        local angle = (index - 1) / TICKS * math.pi * 2 - math.pi / 2
        local tick = widget:CreateTexture(nil, "ARTWORK")
        tick:SetSize(TICK_LENGTH, TICK_WIDTH)
        tick:SetPoint("CENTER", widget, "CENTER",
            math.cos(angle) * radius, -math.sin(angle) * radius)
        tick:SetRotation(-angle)
        widget.ticks[index] = tick
    end

    widget.value = widget:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    widget.value:SetPoint("CENTER", 0, size * 0.08)

    widget.max = widget:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.max:SetPoint("TOP", widget.value, "BOTTOM", 0, -2)

    widget.caption = widget:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.caption:SetPoint("TOP", widget.max, "BOTTOM", 0, -1)

    widget.tier = widget:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    widget.tier:SetPoint("TOP", widget, "BOTTOM", 0, -4)

    return widget
end

--- Met la jauge a jour avec des quantites MESUREES.
--- @param fixes number correctifs en attente
--- @param clean number emplacements sans probleme
--- @param checked number emplacements verifies
--- @param caption string ligne sous le total
function Gauge.SetValue(widget, fixes, clean, checked, caption)
    fixes = math.max(0, fixes or 0)
    checked = math.max(1, checked or 1)
    clean = math.max(0, math.min(checked, clean or 0))

    local color = colorFor(fixes)
    -- L'anneau se remplit de la part d'emplacements propres : un rapport de deux nombres
    -- comptes, pas une note.
    local filled = math.floor(TICKS * clean / checked + 0.5)

    for index, tick in ipairs(widget.ticks) do
        if index <= filled then
            tick:SetColorTexture(color[1], color[2], color[3], 1)
        else
            tick:SetColorTexture(1, 1, 1, 0.08)
        end
    end

    local code = string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
    widget.value:SetText(code .. fixes .. "|r")
    widget.max:SetText(fixes == 1 and ns.L["fix pending"] or ns.L["fixes pending"])
    widget.caption:SetText(caption or "")
    widget.tier:SetText(string.format("%s%d / %d %s|r",
        code, clean, checked, ns.L["slots clean"]))
end
