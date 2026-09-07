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
-- presse-papier. UN aller-retour par le navigateur : ce plancher ne descend pas.
--
-- CE QUI ETAIT ECRIT ICI ET QUI ETAIT FAUX : « l'adresse du fichier de donnees ne se
-- devine pas ». Elle se devine. Raidbots documente que tout fichier d'un rapport s'obtient
-- en ajoutant son nom a l'adresse du rapport, et la page du rapport porte un menu
-- « ... > Raw Files > data.csv » qui y mene en un clic. Le joueur n'a donc pas a revenir
-- chercher une adresse : il repart de Raidbots avec le CSV deja en main.
--
-- Le collage d'un LIEN reste accepte, en repli : GearProof rend alors l'adresse du CSV.
--
-- DEUX ZONES MULTI-LIGNES, ET C'EST LA TOUTE LA DIFFERENCE. La premiere version posait des
-- `EditBox` d'UNE SEULE LIGNE. Or les deux textes qui transitent ici en font des dizaines :
-- la chaine SimulationCraft (un profil complet) et le CSV du rapport (neuf kilo-octets).
-- Un champ d'une ligne perd les retours a la ligne au collage — le CSV arrivait donc en UN
-- bloc, `Sim.ImportCSV` n'y trouvait plus la ligne de reference, et l'addon repondait
-- « nothing readable in that paste » sur une donnee parfaitement valide. C'est le montage
-- de `Copy.lua` — `ScrollFrame` + `EditBox` multi-ligne — qui, lui, a toujours marche.
--
-- Et le mot qui manquait le plus : FACULTATIF. Sans droptimizer, l'onglet Raid fonctionne
-- — il compare les niveaux d'objet lus dans le journal des aventures. Le droptimizer
-- remplace cette estimation par du gain mesure, sur les objets qu'il couvre. Un joueur qui
-- ne fera jamais ces etapes n'a pas un addon amoindri.

local WIDTH, PADDING = 560, 16
local STEPS = 4

-- Largeur mangee par l'ascenseur d'un `UIPanelScrollFrameTemplate`. Mesuree sur
-- `Copy.lua`, qui rend une chaine SimC sans la tronquer.
local SCROLLBAR = 28

local DROPTIMIZER_URL = "https://www.raidbots.com/simbot/droptimizer"

local frame, steps, stage

local function hex(key)
    return ns.Theme.C(key)
end

--- Un EditBox de lecture, d'une seule ligne : pre-selectionne, pour un Ctrl+C immediat.
---
--- WoW n'accede pas au presse-papier : aucune « copie » n'est possible depuis l'addon.
--- Tout ce qu'on peut faire est presenter le texte deja selectionne.
---
--- Reserve aux ADRESSES, qui tiennent sur une ligne. Tout ce qui en fait plusieurs passe
--- par `scrollBox`.
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

--- Une zone multi-ligne avec ascenseur, pour les textes qui font des dizaines de lignes.
--- @return table scroll, table edit, table well
local function scrollBox(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")

    -- L'habillage masque les textures du modele. Sans ce cadre, la zone se poserait a plat
    -- sur le fond, sans aucune delimitation — le joueur ne verrait pas ou coller.
    local well = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    well:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 6)
    well:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 6, -6)
    well:SetFrameLevel(math.max(0, scroll:GetFrameLevel() - 1))
    well:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(ChatFontNormal)
    edit:SetAutoFocus(false)
    -- 0 = sans limite. Le CSV d'un droptimizer fait neuf kilo-octets, et un champ qui
    -- tronque en silence rendrait exactement la meme panne que celle d'avant.
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    scroll:SetScrollChild(edit)

    return scroll, edit, well
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
    frame:SetSize(WIDTH, 420)
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
    for index = 1, STEPS do
        local badge, text = stepLabel(frame, index)
        steps[index] = { badge = badge, text = text }
    end

    -- L'ADRESSE D'ABORD, la chaine ensuite. C'est l'ordre des gestes : on ouvre la page,
    -- puis on colle dedans. L'inverse faisait copier une chaine avant de savoir ou la
    -- mettre, et le presse-papier ne garde qu'une chose a la fois.
    frame.url = readBox(frame)
    -- Boite propre a l'etape de repli : l'adresse du CSV quand un lien a ete colle.
    -- Reutiliser celle du droptimizer l'ecraserait.
    frame.csvUrl = readBox(frame)

    frame.simcScroll, frame.simc, frame.simcWell = scrollBox(frame)
    frame.simc:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- Lecture seule : le joueur la copie, il ne la modifie pas.
    frame.simc:SetScript("OnTextChanged", function(self, byUser)
        if byUser and self.locked then
            self:SetText(self.locked)
            self:HighlightText()
        end
    end)

    frame.inputScroll, frame.input, frame.inputWell = scrollBox(frame)

    frame.submit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.submit:SetSize(120, 22)
    ns.Localize(frame.submit, "Validate")
    frame.submit:SetScript("OnClick", function() Droptimizer.Submit() end)

    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.note:SetJustifyH("LEFT")
    frame.note:SetSpacing(2)

    frame.themeCards = { frame.simcWell, frame.inputWell }
    ns.Theme.Apply(frame)
    tinsert(UISpecialFrames, "GearProofDroptimizer")
    return frame
end

--- Pose la fenetre. `stage` decide de ce que l'etape 3 montre.
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

    local function line(widget, value, locked)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", PADDING + 26, top)
        widget:SetWidth(inner - 30)
        widget:SetText(value or "")
        widget.locked = locked and value or nil
        widget:Show()
        top = top - 30
    end

    local function area(scroll, edit, height, value, locked)
        local width = inner - 30
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", PADDING + 26, top)
        scroll:SetSize(width, height)
        edit:SetWidth(width - SCROLLBAR)
        if value ~= nil then
            edit:SetText(value)
            edit.locked = locked and value or nil
        end
        scroll:Show()
        top = top - height - 10
    end

    -- 1. Ou aller. 2. Quoi y coller.
    place(1, hex("text") .. L["Open this address"] .. "|r")
    line(frame.url, DROPTIMIZER_URL, true)

    place(2, hex("text") .. L["Paste this string there, then run the simulation"] .. "|r")
    area(frame.simcScroll, frame.simc, 56, ns.SimC.FromOfficial() or ns.SimC.Build(), true)

    -- 3. Le fichier de resultats. Deux chemins vers la meme chose.
    if stage == "csv" then
        local url = ns.Sim.ReportCSVURL((ns.db.droptimizer and ns.db.droptimizer.id) or "")
        place(3, hex("text") .. L["Report link received. Open this address:"] .. "|r")
        line(frame.csvUrl, url, true)
    else
        frame.csvUrl:Hide()
        place(3, hex("text") .. L["On the report page: ... menu > Raw Files > data.csv (or add /data.csv to its address)"] .. "|r")
    end

    -- 4. Le retour.
    place(4, hex("text") .. L["Select everything there (Ctrl+A), copy, and paste it below"] .. "|r")
    area(frame.inputScroll, frame.input, 90)

    frame.submit:ClearAllPoints()
    frame.submit:SetPoint("TOPRIGHT", frame.inputScroll, "BOTTOMRIGHT", 0, -8)
    top = top - 34

    frame.note:ClearAllPoints()
    frame.note:SetPoint("TOPLEFT", PADDING, top - 6)
    frame.note:SetWidth(inner)
    frame.note:SetText(hex("muted")
        .. L["A report link pasted here works too: GearProof then gives you the address."] .. "\n"
        .. L["Without a droptimizer the Raid tab still works: it compares item levels. A droptimizer replaces that estimate with measured gain."] .. "|r")

    frame:SetHeight(math.max(240, -top + math.ceil(frame.note:GetStringHeight() or 14) + 24))
end

--- Traite ce que le joueur a colle. Meme detection que l'ancien bouton unique.
function Droptimizer.Submit()
    local text = frame and frame.input:GetText()
    if not text or text == "" then return end

    frame.input:SetText("")
    frame.input:ClearFocus()

    -- La NATURE de ce qui a ete accepte, pas un etat global : `Sim.Available()` est vrai
    -- des qu'un rapport existe, donc un joueur qui en avait deja un et collait un nouveau
    -- lien voyait la fenetre se fermer sans jamais voir l'etape suivante.
    local ok, kind = ns.SimC.HandlePaste(text)
    if ok and kind == "link" then
        stage = "csv"
    elseif ok and kind == "csv" then
        frame:Hide()
        return
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
