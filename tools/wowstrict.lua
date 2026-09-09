-- Stub STRICT de l'API de widgets de WoW.
--
-- Le stub de `luaenv.py` rend une fonction pour n'importe quelle cle : il charge tout,
-- donc il ne peut rien attraper. Celui-ci connait les methodes de CHAQUE type de widget
-- et leve sur tout le reste, exactement comme le client.
--
-- Les trois pieges qu'il attrape et que le stub permissif laisse passer :
--
--   1. `SetText` sur un Frame. Un Frame n'en a pas — un FontString et un Button, si.
--      C'est l'erreur qu'on fait en transformant un FontString en conteneur.
--   2. `SetBackdrop` sur un cadre cree SANS le modele "BackdropTemplate". Depuis
--      Shadowlands ce n'est plus une methode de Frame mais un mixin apporte par le
--      modele : l'oublier donne « attempt to call method 'SetBackdrop' (a nil value) ».
--   3. Une methode de Texture appelee sur un FontString, et reciproquement.
--
-- Ce n'est pas une simulation de WoW : rien n'est dessine, aucune ancre n'est resolue.
-- C'est un controleur de SURFACE d'API, et c'est la moitie des erreurs de chargement.

local function class(name, methods, parent)
    local set = {}
    if parent then
        for key in pairs(parent.methods) do set[key] = true end
    end
    for _, key in ipairs(methods) do set[key] = true end
    return { name = name, methods = set }
end

-- Region : la base de tout ce qui a une position.
local Region = class("Region", {
    "SetPoint", "ClearAllPoints", "SetAllPoints", "GetPoint", "GetNumPoints",
    "SetWidth", "SetHeight", "SetSize", "GetWidth", "GetHeight", "GetSize",
    "Show", "Hide", "IsShown", "IsVisible", "SetShown",
    "GetParent", "SetParent", "SetAlpha", "GetAlpha", "GetObjectType", "IsObjectType",
    "SetScale", "GetScale", "GetRect", "GetLeft", "GetRight", "GetTop", "GetBottom",
    "SetDrawLayer", "GetDrawLayer", "SetIgnoreParentAlpha", "SetIgnoreParentScale",
})

local FontString = class("FontString", {
    "SetText", "GetText", "SetFormattedText", "SetTextColor", "GetTextColor",
    "SetJustifyH", "SetJustifyV", "GetJustifyH", "GetJustifyV",
    "SetFont", "GetFont", "SetFontObject", "GetFontObject",
    "GetStringHeight", "GetStringWidth", "SetSpacing", "GetSpacing",
    "SetWordWrap", "SetNonSpaceWrap", "SetMaxLines", "SetVertexColor",
    "SetShadowColor", "SetShadowOffset", "CanWordWrap",
}, Region)

local Texture = class("Texture", {
    "SetTexture", "GetTexture", "SetColorTexture", "SetTexCoord", "GetTexCoord",
    "SetVertexColor", "GetVertexColor", "SetDesaturated", "SetDesaturation",
    "SetBlendMode", "SetAtlas", "GetAtlas", "SetRotation", "SetGradient",
}, Region)

local Frame = class("Frame", {
    "CreateFontString", "CreateTexture", "CreateAnimationGroup",
    "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents", "IsEventRegistered",
    "RegisterUnitEvent", "SetScript", "GetScript", "HookScript",
    "SetMovable", "SetResizable", "EnableMouse", "EnableMouseWheel", "EnableKeyboard",
    "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "StartSizing",
    "SetClampedToScreen", "SetClampRectInsets", "SetFrameStrata", "GetFrameStrata",
    "SetFrameLevel", "GetFrameLevel", "SetToplevel", "SetUserPlaced", "IsUserPlaced",
    "GetRegions", "GetChildren", "GetNumRegions", "GetNumChildren", "GetName",
    "SetID", "GetID", "SetHitRectInsets", "SetPropagateKeyboardInput",
    "SetResizeBounds", "SetMinResize", "SetMaxResize", "Raise", "Lower",
    "SetAttribute", "GetAttribute", "RegisterForClicks",
}, Region)

-- Un Button EST un Frame, plus ses propres methodes. `SetText` en fait partie : c'est
-- pour ca qu'un bouton UIPanelButtonTemplate accepte `ns.Localize`.
local Button = class("Button", {
    "SetText", "GetText", "SetNormalTexture", "GetNormalTexture",
    "SetHighlightTexture", "GetHighlightTexture", "SetPushedTexture",
    "SetDisabledTexture", "SetNormalFontObject", "SetHighlightFontObject",
    "SetDisabledFontObject", "SetFontString", "GetFontString",
    "Enable", "Disable", "IsEnabled", "SetEnabled", "Click", "SetButtonState",
}, Frame)

local EditBox = class("EditBox", {
    "SetText", "GetText", "SetMultiLine", "SetAutoFocus", "SetFontObject",
    "HighlightText", "SetFocus", "ClearFocus", "SetCursorPosition", "SetMaxLetters",
    "SetTextInsets", "Insert", "SetJustifyH",
}, Frame)

-- Une LIGNE est une region a part : elle se pose par deux ancres au lieu d'un cadre, et
-- c'est ce que le client utilise pour les liaisons d'un arbre de talents. Sans elle dans
-- le stub, `content:CreateLine()` rendait nil et la boucle des liaisons n'etait jamais
-- atteinte — l'arbre passait au vert sans qu'un seul trait ait ete dessine.
local Line = class("Line", {
    "SetThickness", "GetThickness", "SetStartPoint", "SetEndPoint",
    "SetColorTexture", "SetVertexColor", "SetTexture", "SetDrawLayer",
    "SetAtlas",
}, Region)

local ScrollFrame = class("ScrollFrame", {
    "SetScrollChild", "GetScrollChild", "SetVerticalScroll", "GetVerticalScroll",
    "GetVerticalScrollRange", "UpdateScrollChildRect", "SetHorizontalScroll",
}, Frame)

local PlayerModel = class("PlayerModel", {
    "SetUnit", "SetModel", "SetPosition", "SetFacing", "SetRotation", "SetCamDistanceScale",
    "RefreshUnit", "SetPortraitZoom", "ClearModel", "SetAnimation", "SetKeepModelOnHide",
}, Frame)

local StatusBar = class("StatusBar", {
    "SetMinMaxValues", "SetValue", "GetValue", "SetStatusBarTexture",
    "GetStatusBarTexture", "SetStatusBarColor", "SetOrientation", "SetFillStyle",
}, Frame)

local Tooltip = class("GameTooltip", {
    "SetOwner", "ClearLines", "AddLine", "AddDoubleLine", "SetHyperlink", "SetItemByID",
    "SetInventoryItem", "SetBagItem", "GetOwner", "NumLines", "SetPadding",
    "GetName", "SetMinimumWidth", "AddTexture",
}, Frame)

local CLASSES = {
    Frame = Frame, Button = Button, EditBox = EditBox, ScrollFrame = ScrollFrame,
    PlayerModel = PlayerModel, StatusBar = StatusBar, GameTooltip = Tooltip,
    Slider = Frame, Cooldown = Frame, SimpleHTML = Frame,
    ModelScene = Frame, Minimap = Frame,
}

CLASSES.CheckButton = class("CheckButton", {
    "SetChecked", "GetChecked", "SetCheckedTexture", "GetCheckedTexture",
    "SetDisabledCheckedTexture",
}, Button)

-- CADRES ENFANTS apportes par un modele. On y accede comme a des CHAMPS, pas comme a des
-- methodes — et Lua ne fait pas la difference a l'indexation. Sans cette table, lire
-- `scroll.ScrollBar` leverait comme une methode inconnue.
local TEMPLATE_FIELDS = {
    UIPanelScrollFrameTemplate = {
        ScrollBar = "Slider", ScrollBarTop = "Texture", ScrollBarBottom = "Texture",
        ScrollBarMiddle = "Texture", ScrollUpButton = "Button",
        ScrollDownButton = "Button", scrollBarHideable = false,
    },
    UIPanelButtonTemplate = { Text = "FontStringRegion", Left = "Texture",
                              Right = "Texture", Middle = "Texture" },
    BackdropTemplate = { Inset = "Frame" },
    GameTooltipTemplate = { TextLeft1 = "FontStringRegion", TextRight1 = "FontStringRegion" },
}

-- LA regle de ce stub.
--
-- A l'indexation, Lua ne distingue pas `frame.SetText` (methode) de `frame.modelReady`
-- (champ personnalise jamais ecrit). Lever sur toute cle inconnue rendrait le stub
-- inutilisable : les vues du depot posent leur propre etat sur les widgets et le lisent
-- parfois avant de l'ecrire.
--
-- On ne leve donc QUE sur une cle qui est une methode connue d'un AUTRE type de widget.
-- C'est exactement l'erreur qu'on cherche — `SetText` sur un Frame, `SetTexture` sur un
-- FontString — et jamais un faux positif sur un champ maison, qui ne porte le nom d'aucune
-- methode de l'API.
local ALL_METHODS = {}

-- Methodes apportees par un MODELE, pas par le type. Les oublier est l'erreur numero un
-- des addons post-Shadowlands.
local TEMPLATE_METHODS = {
    BackdropTemplate = {
        "SetBackdrop", "GetBackdrop", "SetBackdropColor", "GetBackdropColor",
        "SetBackdropBorderColor", "GetBackdropBorderColor", "ApplyBackdrop",
        "OnBackdropLoaded", "OnBackdropSizeChanged", "ClearBackdrop",
    },
    -- Modeles Blizzard courants : ils apportent des sous-cadres nommes et quelques
    -- methodes. On accepte largement, l'important est de ne pas inventer SetBackdrop.
    UIPanelButtonTemplate = {},
    UIPanelCloseButton = {},
    UIPanelScrollFrameTemplate = {},
    GameTooltipTemplate = {},
    TooltipBorderedFrameTemplate = {},
    InsecureActionButtonTemplate = {},
}

-- Index inverse : methode -> type qui la porte. Rempli une fois, apres la declaration de
-- toutes les classes. Une methode presente sur plusieurs types garde la premiere trouvee ;
-- le message ne sert qu'a nommer l'erreur, pas a etre exhaustif.
for _, definition in pairs({ Region, FontString, Texture, Frame, Button, EditBox,
                             ScrollFrame, PlayerModel, StatusBar, Tooltip }) do
    for key in pairs(definition.methods) do
        ALL_METHODS[key] = ALL_METHODS[key] or definition.name
    end
end

local GEARPROOF_CALLS = {}

local function widget(kind, template, label)
    local definition = CLASSES[kind] or Frame
    local allowed = {}
    for key in pairs(definition.methods) do allowed[key] = true end

    local fields = {}
    if template then
        for piece in tostring(template):gmatch("[^,%s]+") do
            local extra = TEMPLATE_METHODS[piece]
            if extra then
                for _, key in ipairs(extra) do allowed[key] = true end
                for key, childKind in pairs(TEMPLATE_FIELDS[piece] or {}) do
                    fields[key] = childKind
                end
            else
                -- Modele inconnu : on ne bloque pas, mais on le note. Un modele qui
                -- n'existe pas cote client leverait, lui, une vraie erreur.
                table.insert(GEARPROOF_CALLS, "modele inconnu: " .. piece)
            end
        end
    end

    local object = {}
    local children = {}

    -- Les scripts sont REELLEMENT stockes. Sans ca, `GetScript("OnEvent")` tombait sur le
    -- repli numerique des accesseurs `Get*` et il devenait impossible de rejouer un
    -- evenement du client — donc de tester le vrai chemin de demarrage.
    local scripts = {}

    local handlers = {
        CreateFontString = function() return widget("FontStringRegion", nil, label) end,
        CreateLine = function() return widget("LineRegion", nil, label) end,
        CreateTexture = function() return widget("TextureRegion", nil, label) end,
        GetRegions = function() return unpack(children) end,
        GetChildren = function() return unpack(children) end,
        GetObjectType = function() return definition.name end,
        IsObjectType = function(_, want) return want == definition.name end,
        SetScript = function(_, name, fn) scripts[name] = fn end,
        GetScript = function(_, name) return scripts[name] end,
        HookScript = function(_, name, fn)
            local previous = scripts[name]
            scripts[name] = function(...)
                if previous then previous(...) end
                return fn(...)
            end
        end,
        -- Le declencheur : `frame:Fire("OnEvent", "ADDON_LOADED", "GearProof")`.
        Fire = function(self, name, ...)
            local fn = scripts[name]
            if fn then return fn(self, ...) end
        end,
    }

    -- TEXTE STOCKE. `SetText` posait dans le vide et `GetText` rendait le repli
    -- numerique des accesseurs : impossible de verifier ce qu'un ecran DIT, seulement
    -- qu'il ne leve pas. Or « ne leve pas » n'est pas « se lit ».
    local shown = ""

    -- UNE LIGNE OU PLUSIEURS : un `EditBox` qui n'a pas recu `SetMultiLine(true)` ne
    -- porte QU'UNE ligne cote client. Un texte a retours a la ligne pose dedans y perd
    -- ses retours — c'est exactement la panne qui a fait repondre « nothing readable in
    -- that paste » sur un CSV parfaitement valide : neuf kilo-octets arrivaient en un
    -- seul bloc, sans ligne de reference.
    --
    -- Le stub LEVE plutot que d'imiter la troncature. La question n'est pas de savoir ce
    -- que le client fait exactement d'un `\n` de trop, c'est qu'un texte multi-ligne dans
    -- un champ d'une ligne est une erreur de conception dans les deux cas.
    local multiLine = false
    handlers.SetMultiLine = function(_, value) multiLine = value ~= false end
    handlers.IsMultiLine = function() return multiLine end

    handlers.SetText = function(_, value)
        local text = tostring(value or "")
        if definition.name == "EditBox" and not multiLine and text:find("\n", 1, true) then
            error(string.format(
                "%s: SetText d'un texte multi-ligne (%d lignes) dans un EditBox d'une "
                .. "seule ligne — appeler SetMultiLine(true), sinon le client perd les "
                .. "retours a la ligne", label or "?", select(2, text:gsub("\n", "")) + 1), 3)
        end
        shown = text
    end
    handlers.GetText = function() return shown end
    handlers.SetFormattedText = function(_, fmt, ...)
        local ok, out = pcall(string.format, fmt, ...)
        shown = ok and out or tostring(fmt)
    end

    -- ARGUMENTS VERIFIES sur les poseurs de geometrie.
    --
    -- Cote C, `SetSize(width, height)` exige deux nombres et leve « Usage: ... ». Un stub
    -- qui accepte tout laisse passer exactement le bug qui a casse l'addon :
    -- `view.content:SetSize(ROSTER_WIDTH, 1)` ou la constante avait ete supprimee. Lire
    -- une globale absente ne leve rien en Lua — elle vaut nil, et c'est l'API qui refuse.
    local function number(value, position, method)
        if type(value) ~= "number" then
            error(string.format("%s: %s argument #%d attendu nombre, recu %s",
                label or "?", method, position, type(value)), 3)
        end
    end

    handlers.SetSize = function(_, w, h)
        number(w, 1, "SetSize"); number(h, 2, "SetSize")
    end
    handlers.SetWidth = function(_, w) number(w, 1, "SetWidth") end
    handlers.SetHeight = function(_, h) number(h, 1, "SetHeight") end
    handlers.SetPoint = function(_, point, a, b, c, d)
        if type(point) ~= "string" then
            error(string.format("%s: SetPoint argument #1 attendu chaine, recu %s",
                label or "?", type(point)), 3)
        end
        -- Deux formes : (point, x, y) et (point, relativeTo, relativePoint, x, y).
        if type(a) == "number" then
            number(a, 2, "SetPoint"); number(b, 3, "SetPoint")
        elseif a ~= nil then
            if type(b) ~= "string" then
                error(string.format("%s: SetPoint argument #3 attendu chaine, recu %s",
                    label or "?", type(b)), 3)
            end
            if c ~= nil or d ~= nil then
                number(c, 4, "SetPoint"); number(d, 5, "SetPoint")
            end
        end
    end

    return setmetatable(object, {
        __index = function(_, key)
            if handlers[key] then return handlers[key] end
            if fields[key] ~= nil then
                if fields[key] == false then return false end
                local child = widget(fields[key], nil, (label or "?") .. "." .. key)
                rawset(object, key, child)
                return child
            end
            if not allowed[key] then
                -- Methode connue AILLEURS : vrai defaut de type.
                if ALL_METHODS[key] then
                    error(string.format(
                        "%s: '%s' est une methode de %s, pas de %s%s",
                        label or "?", tostring(key), ALL_METHODS[key], definition.name,
                        template and (" (modele " .. tostring(template) .. ")") or ""), 2)
                end
                -- Sinon : champ maison jamais ecrit. WoW rendrait nil, nous aussi.
                return nil
            end
            -- Les accesseurs de dimension rendent un nombre : du code qui fait de
            -- l'arithmetique dessus ne doit pas exploser sur un nil.
            if key:find("^Get") then
                return function() return 100 end
            end
            -- Un COMPTEUR rend un nombre, comme cote client. `NumLines` rendait nil, et
            -- `for i = 1, tooltip:NumLines()` levait « 'for' limit must be a number » —
            -- une panne du stub, pas de l'addon. Zero est un etat legitime : c'est ce que
            -- le client rend pour une infobulle qu'il n'a pas encore remplie. Le balayage
            -- d'infobulle ne trouve donc rien, ce qui est le cas a couvrir : l'addon doit
            -- survivre a une infobulle vide, il l'a deja fait planter une fois.
            if key:find("^Num") then
                return function() return 0 end
            end
            return function() return nil end
        end,
        __newindex = rawset,
    })
end

-- FontString et Texture sont des Regions, pas des Frames : elles ont leur propre table.
CLASSES.FontStringRegion = FontString
CLASSES.TextureRegion = Texture
CLASSES.LineRegion = Line

-- Un cadre NOMME devient une globale, comme dans le client. L'addon en depend : il pose
-- "GearProofDroptimizer" dans `UISpecialFrames`, une table de NOMS que le client resout
-- par _G. Sans ca, le stub s'ecartait du client sur un point que le test ne pouvait pas
-- voir — et aucun test ne pouvait atteindre la zone de saisie d'une fenetre dont le cadre
-- est un local de portee fichier.
function CreateFrame(kind, name, parent, template)
    local w = widget(kind, template, name or ("<" .. tostring(kind) .. " anonyme>"))
    if name then _G[name] = w end
    return w
end

GEARPROOF_STRICT_NOTES = GEARPROOF_CALLS
GameTooltip = widget("GameTooltip", nil, "GameTooltip")
UIParent = widget("Frame", nil, "UIParent")
Minimap = widget("Frame", nil, "Minimap")
