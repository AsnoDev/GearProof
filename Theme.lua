local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- Trois habillages : le cadre du client, un fond sombre a bordure violette (defaut), ou
-- un plat minimaliste sans aucune texture du client. Voir STYLES plus bas.

-- Palette de reference, partagee par tous les modules. Une seule source pour les
-- couleurs d'etat : si un module code sa propre teinte, l'interface derive.
local function rgb(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end

Theme.HEX = {
    frame    = "121212",
    card     = "1E1E1E",
    border   = "2A2A2A",
    critical = "FF4D4D",
    bis      = "FFC107",
    good     = "00E676",
    link     = "00B0FF",
    text     = "E8E8E8",
    muted    = "8A8A8A",
}

Theme.RGB = {}
for key, hex in pairs(Theme.HEX) do
    local r, g, b = rgb(hex)
    Theme.RGB[key] = { r, g, b }
end

--- Code couleur pret a coller dans une chaine : Theme.C("critical") .. "texte|r"
function Theme.C(key)
    return "|cff" .. (Theme.HEX[key] or "FFFFFF")
end

-- Trois habillages :
--   blizzard : le cadre du client, pour rester coherent avec l'interface par defaut
--   dark     : fond sombre, bordure fine, mais on garde les marges Blizzard
--   elvui    : plat, bordure 1px, marges resserrees, aucune texture du client
local STYLES = {
    blizzard = {
        card = { 1, 1, 1, 0.035 },
        border = { 1, 1, 1, 0.09 },
        frame = nil,
    },
    dark = {
        card = { 0.04, 0.04, 0.06, 0.85 },
        border = { 1, 1, 1, 0.12 },
        frame = { bg = { 0.035, 0.03, 0.05, 0.96 }, border = { 0.55, 0.42, 1, 0.35 } },
    },
    -- Dark minimaliste : #121212 pour le cadre, #1E1E1E pour les cartes,
    -- #2A2A2A pour les bordures. Aucune texture du client.
    minimal = {
        card = { rgb(Theme.HEX.card) },
        border = { rgb(Theme.HEX.border) },
        frame = { bg = { rgb(Theme.HEX.frame) }, border = { rgb(Theme.HEX.border) } },
        cardAlpha = 1,
        frameAlpha = 0.88,
    },
}

STYLES.minimal.card[4] = 1
STYLES.minimal.border[4] = 1
STYLES.minimal.frame.bg[4] = 0.88
STYLES.minimal.frame.border[4] = 1

local ORDER = { "dark", "minimal", "blizzard" }

local hidden = {}

-- Cadres deja habilles. Sans ce registre, changer d'habillage en cours de jeu ne reprenait
-- que la fenetre principale : les fenetres secondaires gardaient le cadre du client, et
-- une pop-up ouverte par-dessus l'interface sombre jurait.
local registered = {}

function Theme.Current()
    local current = ns.db and ns.db.theme
    return STYLES[current] and current or "dark"
end

function Theme.IsFlat()
    return Theme.Current() ~= "blizzard"
end

function Theme.Style()
    return STYLES[Theme.Current()]
end

--- Applique le style de carte, avec une teinte d'accent optionnelle.
function Theme.ApplyCard(card, accent)
    if not card or not card.SetBackdropColor then return end
    local style = Theme.Style()

    if accent then
        card:SetBackdropColor(accent[1] * 0.16, accent[2] * 0.12, accent[3] * 0.12,
            Theme.Current() == "dark" and 0.5 or 0.35)
        card:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.5)
    else
        card:SetBackdropColor(unpack(style.card))
        card:SetBackdropBorderColor(unpack(style.border))
    end
end

-- Cartes suivies individuellement, hors de tout cadre enregistre.
--
-- `Theme.Apply` ne reprend que les cadres qu'on lui a donnes et leur `themeCards`. Les
-- tuiles de la grille, les lignes de butin et les boutons de sous-vue vivent dans des
-- hotes d'onglet qui ne sont pas enregistres : ils codaient donc leurs couleurs en dur et
-- restaient sombres en habillage `blizzard`, au milieu d'un cadre clair.
local tracked = setmetatable({}, { __mode = "k" })

--- Suit une carte pour qu'elle reprenne l'habillage a chaque changement.
---
--- @param shade number|nil multiplicateur d'opacite. Quand il est fourni, SEUL le fond
---   est pose : la bordure appartient a l'appelant. C'est le cas des tuiles de la grille,
---   dont la bordure porte l'etat de la piece — l'ecraser ferait disparaitre le vert,
---   l'orange et le rouge a chaque changement d'habillage.
function Theme.Track(card, shade)
    if not card or not card.SetBackdropColor then return card end
    tracked[card] = shade or false

    if shade then
        local style = Theme.Style()
        card:SetBackdropColor(style.card[1], style.card[2], style.card[3],
            math.min(1, (style.card[4] or 1) * shade))
    else
        Theme.ApplyCard(card)
    end
    return card
end

--- Retire une carte du suivi. Rarement utile : la table est a cles faibles.
function Theme.Untrack(card)
    tracked[card] = nil
end

local function collectRegions(frame, list)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            table.insert(list, region)
        end
    end
end

--- Habille un cadre, principal ou secondaire, et le retient pour les changements a venir.
function Theme.Apply(frame)
    if not frame then return end

    registered[frame] = true
    local style = Theme.Style()

    if Theme.IsFlat() then
        if not hidden[frame] then
            local regions = {}
            collectRegions(frame, regions)
            collectRegions(frame.Inset, regions)
            hidden[frame] = regions
        end
        for _, region in ipairs(hidden[frame]) do
            region:Hide()
        end

        if not frame.themeBackdrop then
            frame.themeBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            frame.themeBackdrop:SetPoint("TOPLEFT", 0, -1)
            frame.themeBackdrop:SetPoint("BOTTOMRIGHT", 0, 0)
            frame.themeBackdrop:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
            frame.themeBackdrop:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
        end
        local frameStyle = style.frame or STYLES.dark.frame
        frame.themeBackdrop:SetBackdropColor(unpack(frameStyle.bg))
        frame.themeBackdrop:SetBackdropBorderColor(unpack(frameStyle.border))
        frame.themeBackdrop:Show()
    else
        for _, region in ipairs(hidden[frame] or {}) do
            region:Show()
        end
        if frame.themeBackdrop then frame.themeBackdrop:Hide() end
    end

    -- Cartes rattachees a ce cadre : elles suivent le meme habillage, y compris quand il
    -- change en cours de jeu.
    for _, card in ipairs(frame.themeCards or {}) do
        Theme.ApplyCard(card)
    end
end

--- Reapplique l'habillage courant a tous les cadres et cartes deja crees.
function Theme.Refresh()
    for frame in pairs(registered) do
        Theme.Apply(frame)
    end
    for card, shade in pairs(tracked) do
        Theme.Track(card, shade or nil)
    end
end

--- Passe a l'habillage suivant : sombre -> minimaliste -> Blizzard -> sombre.
function Theme.Toggle()
    local current = Theme.Current()
    local index = 1
    for position, name in ipairs(ORDER) do
        if name == current then index = position end
    end

    ns.db.theme = ORDER[(index % #ORDER) + 1]
    Theme.Refresh()
    ns.Print(ns.L["skin: %s"], ns.db.theme)
    return ns.db.theme
end

function Theme.Set(name)
    if not STYLES[name] then return false end
    ns.db.theme = name
    Theme.Refresh()
    return true
end
