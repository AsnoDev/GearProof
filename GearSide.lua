local _, ns = ...

local GearSide = {}
ns.GearSide = GearSide

-- Colonne de droite de l'onglet Equipement : la jauge, la repartition des statistiques
-- secondaires, la ligne de priorite relevee, l'etat de l'ensemble de classe et le bloc
-- droptimizer.
--
-- Extraite de GearView.lua, qui atteignait mille lignes en melangeant trois choses sans
-- rapport : la grille des pieces, la liste des correctifs, et cette colonne. Elle est le
-- morceau le plus facile a isoler parce qu'elle ne partage RIEN avec le reste de l'onglet
-- — elle lit le resume de l'audit et ecrit dans ses propres widgets.
--
-- Interface, deux fonctions :
--   GearSide.Create(parent)   -> le cadre, construit une fois
--   GearSide.Refresh(summary) -> la mise en page, a chaque affichage
--
-- Elle a son propre pool de lignes : le partager avec GearView aurait recree le couplage
-- qu'on defait ici.

GearSide.WIDTH = 236

local COLORS = setmetatable({}, {
    __index = function(_, key)
        local map = { critical = "critical", major = "bis", good = "good",
                      accent = "link", minor = "muted" }
        return ns.Theme.RGB[map[key] or key] or { 1, 1, 1 }
    end,
})

local STAT_COLORS = {
    haste       = { 0.45, 0.78, 0.62 },
    crit        = { 0.89, 0.64, 0.36 },
    mastery     = { 0.55, 0.42, 1.00 },
    versatility = { 0.36, 0.62, 0.89 },
}

local L = ns.L
local SIDE_WIDTH = GearSide.WIDTH

local view, pool

local function hex(color)
    return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

-- ------------------------------------------------------- lignes de statistique

-- Une ligne de statistique secondaire.
--
-- L'ancienne version montrait quatre nombres dans trois unites differentes : la hate reelle
-- (« 18.7% »), les points bruts, la part de ton propre budget (« 40% of yours ») et la part
-- du haut de tableau (« top 43% ») — plus un badge signe sans colonne fixe. Deux
-- pourcentages qui se ressemblent et ne veulent pas dire la meme chose, cote a cote.
--
-- Ici la soustraction est faite pour le lecteur : un seul nombre par ligne, toujours signe,
-- toujours en POINTS, toujours dans le meme champ a droite. La barre ne fait que redire ce
-- meme fait — sens, couleur, longueur — pour que la ligne se lise sans lire les chiffres.
--
-- Une ligne de statistique secondaire : nom a gauche, barre au milieu, valeur a droite. Une
-- seule ligne, un seul nombre, une seule unite.
--
-- Trois versions ont precede celle-ci. La premiere empilait quatre nombres dans quatre unites
-- dont aucune n'etait la reponse ; la deuxieme et la troisieme ajoutaient un ecart signe, un
-- repere de cible, une colonne d'unite et un tri qui deplacait les lignes d'une session a
-- l'autre. Trop de machinerie dans une colonne de 228 px. La comparaison au haut de tableau
-- vit maintenant dans la ligne de priorite, en dessous, ecrite une fois.

local ROW_HEIGHT, BAR_HEIGHT = 20, 10
local LABEL_WIDTH, VALUE_WIDTH = 76, 46

local function newStatRow()
    local row = CreateFrame("Frame", nil, view)
    row:SetHeight(ROW_HEIGHT)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetWidth(LABEL_WIDTH)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- Largeur explicite : un FontString justifie a droite se recale sinon sur sa propre
    -- longueur, et la colonne danse d'une ligne a l'autre.
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetPoint("RIGHT", 0, 0)
    row.value:SetWidth(VALUE_WIDTH)
    row.value:SetJustifyH("RIGHT")

    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetHeight(BAR_HEIGHT)
    row.track:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + 4, 0)
    row.track:SetPoint("RIGHT", row, "RIGHT", -(VALUE_WIDTH + 6), 0)
    row.track:SetColorTexture(0.10, 0.10, 0.11, 1)

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetHeight(BAR_HEIGHT)
    row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)

    return row
end

local function hideTooltip()
    GameTooltip:Hide()
end

--- Detail chiffre d'une ligne de statistique. Lit `row.stat`, pose au rendu.
local function statRowOnEnter(self)
    local stat = self.stat
    if not stat then return end

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(L[stat.label], 0.91, 0.91, 0.91)
    GameTooltip:AddDoubleLine(L["yours"],
        string.format("%d pts · %.0f%% " .. L["of yours"], stat.rating, stat.share * 100),
        0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
    if stat.target then
        -- On n'affiche que la PART relevee. Ecrire « top 20 : N pts » en multipliant leur
        -- composition par TON budget donnait un nombre qui ne decrit ni eux ni toi. Leur
        -- moyenne absolue existe dans le fichier de donnees, mais elle n'est comparable
        -- qu'a niveau d'objet egal — donc on ne la melange pas ici.
        GameTooltip:AddDoubleLine(string.format(L["top %d"], ns.Meta.Sample()),
            string.format("%.0f%% " .. L["of their budget"], stat.target * 100),
            0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
    end
    if stat.tier > 0 then
        GameTooltip:AddLine(string.format(L["diminishing tier %d"], stat.tier), 1, 0.76, 0.03)
    end
    GameTooltip:Show()
end

-- --------------------------------------------------------------------- public

function GearSide.Refresh(summary)
    if not view then return end

    -- Les lignes repartent du pool a chaque rendu. C'etait `resetPools()` de GearView qui
    -- s'en chargeait ; en emportant le pool, cette colonne emporte sa remise a zero.
    pool:Reset()

    local stats = ns.Stats.Current()

    -- Emplacements propres : ceux qu'on a verifies moins ceux qui portent un probleme. Deux
    -- nombres comptes, pas une note ponderee par des penalites inventees.
    local flagged = 0
    for _, entry in pairs(summary.bySlot or {}) do
        if not entry.skipped and #entry.problems > 0 then flagged = flagged + 1 end
    end
    local checked = math.max(1, summary.checked or 1)

    local _, equipped = GetAverageItemLevel()
    ns.Gauge.SetValue(view.gauge, summary.problems, checked - flagged, checked,
        equipped and ("ilvl " .. math.floor(equipped + 0.5)) or "")

    -- Repartition : part de chaque statistique dans le budget secondaire total.
    local total = 0
    for _, definition in ipairs(ns.Stats.LIST) do
        total = total + (stats[definition.key] and stats[definition.key].rating or 0)
    end

    local WIDTH = SIDE_WIDTH - 8
    local TRACK_WIDTH = WIDTH - LABEL_WIDTH - VALUE_WIDTH - 10

    view.statsTitle:SetText(hex(COLORS.accent) .. L["SECONDARY STATS"] .. "|r")

    -- La colonne de droite s'empile : jauge (haut, 108 px) → verdict → titre a -152 →
    -- lignes. Demarrer les lignes plus haut les fait passer sous la jauge.
    local top = -172

    -- Ordre fixe, celui de la feuille de personnage. Trier par ecart deplacait les lignes
    -- d'une session a l'autre et coutait la memoire du geste.
    for _, definition in ipairs(ns.Stats.LIST) do
        local data = stats[definition.key] or { rating = 0, percent = 0, tier = 0 }
        local share = total > 0 and ((data.rating or 0) / total) or 0
        local color = STAT_COLORS[definition.key] or COLORS.accent

        local row = pool:Acquire()
        row:SetParent(view)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, top)
        row:SetWidth(WIDTH)
        row:SetHeight(ROW_HEIGHT)

        row.label:SetText(hex(color) .. L[definition.label] .. "|r")
        row.value:SetText(string.format("|cffE8E8E8%.1f%%|r", data.percent or 0))

        -- La barre montre la part de cette statistique dans ton budget secondaire. La
        -- comparaison au haut de tableau n'est pas ici : elle est dans la ligne de priorite,
        -- ecrite une fois, au lieu d'un repere par ligne a decoder.
        row.fill:SetColorTexture(color[1], color[2], color[3], 1)
        row.fill:SetWidth(math.max(1, share * TRACK_WIDTH))

        -- Le detail chiffre reste accessible, sans encombrer la ligne.
        row.stat = {
            label = definition.label,
            rating = data.rating or 0,
            tier = data.tier or 0,
            share = share,
            target = ns.Recommendations.StatTarget(definition.key),
        }
        row:SetScript("OnEnter", statRowOnEnter)
        row:SetScript("OnLeave", hideTooltip)

        top = top - ROW_HEIGHT
    end

    -- Priorite : l'ordre releve chez les joueurs du haut de tableau, part a l'appui. C'est
    -- ici que vivent desormais les parts du haut de tableau, une fois chacune, au lieu d'un
    -- « top 43% » repete sur chaque ligne a cote d'un « 40% of yours » qui lui ressemble.
    local priority = ns.Meta.StatPriority()
    view.priority:ClearAllPoints()
    view.priority:SetPoint("TOPLEFT", view, "TOPLEFT", 0, top - 8)
    if priority then
        local parts = {}
        for _, entry in ipairs(priority) do
            table.insert(parts, string.format("%s (%d%%)", L[entry.label], entry.share * 100 + 0.5))
        end
        -- Une fleche par ligne plutot qu'une seule ligne qui passe a la ligne toute
        -- seule : quatre statistiques et leurs parts ne tiennent pas dans 228 px, et le
        -- retour automatique cassait le compte de hauteur juste en dessous.
        -- Deux ecoles, quand le releve en detecte.
        --
        -- C'est ICI que l'information a un sens, et nulle part ailleurs : elle qualifie
        -- directement la ligne de priorite juste au-dessus. Une spe dont la maitrise se
        -- joue soit a 21 % soit a 38 % n'a pas de cible a 27 % — viser la moyenne, c'est
        -- ne jouer aucun des deux builds. Deux lignes suffisent a le dire.
        local modes = ns.Meta.Modes()
        if modes then
            table.insert(parts, "")
            table.insert(parts, hex(COLORS.major) .. L["Two builds measured"] .. "|r")
            for index = 1, math.min(2, #modes) do
                local mode = modes[index]
                table.insert(parts, string.format("%s  %s%d%%|r %s·|r %s%d%%|r",
                    L[mode.label],
                    mode.side == "low" and hex(COLORS.good) or "|cff8A8A8A",
                    mode.low * 100 + 0.5,
                    "|cff5A5A5A",
                    mode.side == "high" and hex(COLORS.good) or "|cff8A8A8A",
                    mode.high * 100 + 0.5))
            end
        end

        view.priority:SetText(string.format("%s%s|r\n|cffE8E8E8%s|r",
            hex(COLORS.accent), L["PRIORITY"], table.concat(parts, "\n")))
    else
        view.priority:SetText("|cff615c73" .. L["no top-build reference for this spec yet"] .. "|r")
    end

    -- La hauteur est MESUREE, jamais devinee.
    --
    -- Elle etait avancee de 34 px en dur, pour un texte qui passait a deux puis trois
    -- lignes selon la langue et le nombre de statistiques relevees. La ligne « Ensemble »
    -- juste en dessous se dessinait donc PAR-DESSUS. C'est la forme exacte du bug de
    -- mise en page que ce depot traine depuis le debut : un decalage constant pour un
    -- contenu de taille variable.
    top = top - 8 - math.ceil(view.priority:GetStringHeight() or 16) - 10

    -- Ensemble de classe.
    --
    -- `summary.setID` et `summary.setPieces` etaient calcules a CHAQUE scan et affiches
    -- nulle part. L'etat 2p/4p est la premiere question d'un joueur de raid, et la
    -- reponse etait deja en memoire.
    -- Survie, avant l'ensemble de classe et seulement pour un tank. Aucune comparaison
    -- au haut de tableau : le releve ne porte ni endurance ni armure, et les deux suivent
    -- le niveau d'objet bien plus qu'un choix. Un chiffre brut, pas un verdict invente.
    view.survival:ClearAllPoints()
    view.survival:SetPoint("TOPLEFT", view, "TOPLEFT", 0, top - 6)
    local survival = ns.Spec.IsTank() and ns.Stats.Survival() or nil
    if survival then
        local parts = {}
        local function big(value)
            return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
        end
        if survival.stamina then
            table.insert(parts, string.format("%s%s|r %s%s|r", hex(COLORS.accent),
                L["Stamina"], "|cffE8E8E8", big(math.floor(survival.stamina.value))))
        end
        if survival.armor then
            table.insert(parts, string.format("%s%s|r %s%s|r", hex(COLORS.accent),
                L["Armor"], "|cffE8E8E8", big(math.floor(survival.armor.value))))
        end
        view.survival:SetText(table.concat(parts, "\n"))
        top = top - 6 - math.ceil(view.survival:GetStringHeight() or 14) - 8
    else
        view.survival:SetText("")
    end

    view.setLine:ClearAllPoints()
    view.setLine:SetPoint("TOPLEFT", view, "TOPLEFT", 0, top - 6)
    local pieces = summary.setPieces or 0
    if summary.setID and pieces > 0 then
        local function bonus(count)
            return string.format("%s%dp|r", pieces >= count and hex(COLORS.good) or "|cff615c73", count)
        end
        view.setLine:SetText(string.format("%s%s|r  |cffE8E8E8%s|r   %s  %s",
            hex(COLORS.accent), L["Class set"],
            string.format(L["%d pieces"], pieces), bonus(2), bonus(4)))
        top = top - 6 - math.ceil(view.setLine:GetStringHeight() or 14) - 6
    else
        view.setLine:SetText("")
    end

    view.simc:ClearAllPoints()
    view.simc:SetPoint("TOPLEFT", view, "TOPLEFT", 0, top - 12)

    view.simcCopy:ClearAllPoints()
    view.simcCopy:SetPoint("TOPLEFT", view.simc, "BOTTOMLEFT", 0, -4)

    view.paste:ClearAllPoints()
    view.paste:SetPoint("TOPLEFT", view.simcCopy, "BOTTOMLEFT", 0, -4)

    local description, stale = ns.Weights.Describe()
    view.droptimizer:ClearAllPoints()
    view.droptimizer:SetPoint("TOPLEFT", view.paste, "BOTTOMLEFT", 0, -6)
    view.droptimizer:SetText(string.format("%s%s|r\n|cff615c73raidbots.com/simbot/droptimizer|r",
        stale and hex(COLORS.major) or "|cff615c73", description))
end

function GearSide.Create(parent)
    if view then return view end

    pool = ns.Pool.New(newStatRow)

    view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPRIGHT", 0, -4)
    view:SetWidth(SIDE_WIDTH)
    view:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)

    view.gauge = ns.Gauge.Create(view, 108)
    view.gauge:SetPoint("TOP", view, "TOP", 0, -4)

    view.statsTitle = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.statsTitle:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -152)
    view.statsTitle:SetText(hex(COLORS.accent) .. L["SECONDARY STATS"] .. "|r")

    view.priority = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.priority:SetJustifyH("LEFT")
    view.priority:SetWidth(SIDE_WIDTH - 8)
    view.priority:SetSpacing(3)

    -- Survie : affichee UNIQUEMENT pour un tank. La colonne montrait la meme
    -- repartition secondaire a tout le monde sans jamais nommer ce qui maintient un
    -- tank en vie.
    view.survival = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.survival:SetJustifyH("LEFT")
    view.survival:SetWidth(GearSide.WIDTH - 8)

    view.setLine = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.setLine:SetJustifyH("LEFT")
    view.setLine:SetWidth(SIDE_WIDTH - 8)

    view.simc = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.simc:SetSize(SIDE_WIDTH - 8, 24)
    ns.Localize(view.simc, "Droptimizer link")
    view.simc:SetScript("OnClick", function() ns.SimC.ShowDroptimizer() end)

    -- Bloc de simulation : la chaine part vers Raidbots, les poids reviennent a la main.
    view.droptimizer = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.droptimizer:SetJustifyH("LEFT")
    view.droptimizer:SetWidth(SIDE_WIDTH - 8)

    -- Copie de la chaine SimC : c'est ce qu'on colle DANS le droptimizer.
    view.simcCopy = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.simcCopy:SetSize(SIDE_WIDTH - 8, 22)
    ns.Localize(view.simcCopy, "Droptimizer Copy")
    view.simcCopy:SetScript("OnClick", function() ns.SimC.Show() end)

    view.paste = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.paste:SetSize(SIDE_WIDTH - 8, 22)
    ns.Localize(view.paste, "Paste droptimizer link")
    -- Le bouton accepte le lien OU les donnees du rapport, et l'infobulle dit la marche
    -- a suivre : coller le lien rend l'adresse du CSV, coller le CSV importe pour de
    -- bon. Un addon ne peut rien telecharger, mais un joueur peut ouvrir une adresse.
    view.paste:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Paste droptimizer link"])
        GameTooltip:AddLine(L["Paste the report link and GearProof gives you the address of its data. Open it, copy everything, paste it back here — no tool needed."],
            0.8, 0.8, 0.9, true)
        GameTooltip:Show()
    end)
    view.paste:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.paste:SetScript("OnClick", function() ns.SimC.PromptImport() end)
    return view
end
