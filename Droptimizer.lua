local _, ns = ...

local Droptimizer = {}
ns.Droptimizer = Droptimizer

local L = ns.L

-- Le parcours droptimizer, en UNE fenetre.
--
-- Il y avait TROIS boutons dans la colonne de droite — « Lien droptimizer », « Copier pour
-- droptimizer », « Coller le lien droptimizer » — dont les libelles ne disaient pas
-- l'ordre, et chacun ouvrait sa propre fenetre. Le joueur devait deviner la sequence, et
-- decouvrait l'etape du fichier de donnees seulement apres avoir colle son lien. D'ou
-- « la chaine d'import est tres complexe ».
--
-- CE QUI EST IRREDUCTIBLE, et qu'il vaut mieux dire que masquer : un addon WoW ne peut
-- faire aucune requete reseau. Les gains simules ne peuvent donc arriver que par le
-- presse-papier, et l'adresse du fichier de donnees ne se devine pas — le chemin passe de
-- /simbot/report/<id> a /reports/<id>/data.csv. Deux allers-retours par le navigateur : ce
-- plancher ne descend pas.
--
-- CE QUI NE L'ETAIT PAS : la sequence est ecrite d'avance, numerotee, et tient dans une
-- seule fenetre qui suit l'avancement. Le joueur voit les trois etapes AVANT de partir,
-- au lieu d'en decouvrir une a chaque retour.
--
-- Et le mot qui manquait le plus : FACULTATIF. Sans droptimizer, l'onglet Raid fonctionne
-- — il compare les niveaux d'objet lus dans le journal des aventures. Le droptimizer
-- remplace cette estimation par du gain mesure, sur les objets qu'il couvre. Un joueur qui
-- ne fera jamais ces etapes n'a pas un addon amoindri.

local WIDTH, PADDING = 560, 16

local frame, steps, stage

local function hex(key)
    return ns.Theme.C(key)
end

--- Un EditBox de lecture : pre-selectionne, pour un Ctrl+C immediat.
---
--- WoW n'accede pas au presse-papier : aucune « copie » n'est possible depuis l'addon.
--- Tout ce qu'on peut faire est presenter le texte deja selectionne.
local function readBox(parent)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- Lecture seule en pratique : toute frappe restaure le texte d'origine.
    box:SetScript("OnTextChanged", function(self, byUser)
        if byUser and self.locked then
            self:SetText(self.locked)
            self:HighlightText()
        end
    end)
    return box
end

local function stepLabel(parent, number)
    local badge = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    badge:SetWidth(20)
    badge:SetJustifyH("LEFT")
    badge:SetText(hex("link") .. number .. "|r")

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return badge, text
end

function Droptimizer.Create()
    if frame then return frame end

    frame = CreateFrame("Frame", "GearProofDroptimizer", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 300)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -2, -2)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", PADDING, -14)
    ns.Localize(frame.title, "Droptimizer")

    -- Le mot le plus important de cette fenetre, a cote du titre.
    frame.optional = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.optional:SetPoint("LEFT", frame.title, "RIGHT", 8, -1)
    ns.Localize(frame.optional, "optional")

    steps = {}
    for index = 1, 3 do
        local badge, text = stepLabel(frame, index)
        steps[index] = { badge = badge, text = text }
    end

    -- Etape 1 : la chaine a simuler, et l'adresse ou la coller.
    frame.simc = readBox(frame)
    frame.url = readBox(frame)
    -- Troisieme boite, propre a l'etape 3 : reutiliser celle de la chaine SimC
    -- l'ecraserait, et le joueur perdrait ce qu'il doit encore pouvoir recopier.
    frame.csvUrl = readBox(frame)

    -- Etapes 2 et 3 : une seule zone de saisie, dont le sens change avec l'avancement.
    frame.input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.input:SetHeight(22)
    frame.input:SetAutoFocus(false)
    frame.input:SetFontObject("GameFontHighlightSmall")
    frame.input:SetScript("OnEscapePressed", frame.input.ClearFocus)
    frame.input:SetScript("OnEnterPressed", function() Droptimizer.Submit() end)

    frame.submit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.submit:SetSize(96, 22)
    ns.Localize(frame.submit, "Validate")
    frame.submit:SetScript("OnClick", function() Droptimizer.Submit() end)

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.note:SetJustifyH("LEFT")
    frame.note:SetSpacing(2)

    ns.Theme.Apply(frame)
    tinsert(UISpecialFrames, "GearProofDroptimizer")
    return frame
end

--- Pose la fenetre. `stage` decide de ce que l'etape 2 demande.
function Droptimizer.Refresh()
    if not frame then return end

    local inner = WIDTH - PADDING * 2
    local top = -52

    local function place(index, text)
        local step = steps[index]
        step.badge:ClearAllPoints()
        step.badge:SetPoint("TOPLEFT", PADDING, top)
        step.text:ClearAllPoints()
        step.text:SetPoint("TOPLEFT", PADDING + 20, top)
        step.text:SetWidth(inner - 20)
        step.text:SetText(text)
        top = top - 20
    end

    local function box(widget, value, locked)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", PADDING + 26, top)
        widget:SetWidth(inner - 30)
        widget:SetText(value or "")
        widget.locked = locked and value or nil
        widget:Show()
        top = top - 30
    end

    -- 1. La chaine, et l'adresse. Les deux ensemble : le joueur copie, ouvre, colle.
    place(1, hex("text") .. L["Copy this, then open Raidbots and paste it"] .. "|r")
    local simc = ns.SimC.FromOfficial() or ns.SimC.Build()
    box(frame.simc, simc, true)
    box(frame.url, "https://www.raidbots.com/simbot/droptimizer", true)

    top = top - 6

    -- 2 et 3. La meme zone, deux sens.
    if stage == "csv" then
        local url = ns.Sim.ReportCSVURL((ns.db.droptimizer and ns.db.droptimizer.id) or "")
        place(2, hex("muted") .. L["Report link received."] .. "|r")
        place(3, hex("text") .. L["Open this address, select everything, copy — then paste below"] .. "|r")
        box(frame.csvUrl, url, true)
    else
        frame.csvUrl:Hide()
        place(2, hex("text") .. L["When the simulation is done, paste the report link below"] .. "|r")
        place(3, hex("muted") .. L["GearProof then gives you one address to open, and you paste its content back"] .. "|r")
    end

    frame.input:ClearAllPoints()
    frame.input:SetPoint("TOPLEFT", PADDING + 26, top - 4)
    frame.input:SetWidth(inner - 140)
    frame.submit:ClearAllPoints()
    frame.submit:SetPoint("LEFT", frame.input, "RIGHT", 12, 0)
    top = top - 34

    frame.note:ClearAllPoints()
    frame.note:SetPoint("TOPLEFT", PADDING, top - 6)
    frame.note:SetWidth(inner)
    frame.note:SetText(hex("muted")
        .. L["Without a droptimizer the Raid tab still works: it compares item levels. A droptimizer replaces that estimate with measured gain."] .. "|r")

    frame:SetHeight(math.max(200, -top + math.ceil(frame.note:GetStringHeight() or 14) + 24))
end

--- Traite ce que le joueur a colle. Meme detection que l'ancien bouton unique.
function Droptimizer.Submit()
    local text = frame and frame.input:GetText()
    if not text or text == "" then return end

    frame.input:SetText("")
    frame.input:ClearFocus()

    if ns.SimC.HandlePaste(text) then
        -- Le CSV a-t-il ete importe, ou seulement le lien enregistre ? `Sim.Available`
        -- ne devient vrai qu'apres un import reel.
        stage = ns.Sim.Available() and "link" or "csv"
        if stage == "link" then
            frame:Hide()
            return
        end
    end
    Droptimizer.Refresh()
end

function Droptimizer.Open()
    Droptimizer.Create()
    stage = "link"
    Droptimizer.Refresh()
    frame:Show()
    frame:Raise()
end
