local _, ns = ...

local TalentView = {}
ns.TalentView = TalentView

local L = ns.L

-- Onglet Talents : l'ARBRE, comme en jeu, avec le choix du contenu.
--
-- La premiere version affichait deux listes — les builds, puis les talents par taux
-- d'adoption. « C'est peu clair » : une liste de noms ne dit pas ou un talent se trouve
-- dans l'arbre, ni ce qu'il coupe, ni ce qu'il ouvre. Un arbre se lit d'un coup d'oeil
-- parce que c'est la forme dans laquelle le joueur l'a appris.
--
-- CE QUI A ETE CORRIGE EN CHEMIN, ET QUI ETAIT GRAVE. Les noms de talents etaient resolus
-- par `C_Spell.GetSpellInfo`, en supposant que le `talentID` de Warcraft Logs etait un
-- identifiant de SORT. Il ne l'est pas — voir `Traits.lua`. Or `GetSpellInfo` rendait
-- quand meme un nom, celui d'un sort sans rapport : la liste affichait des noms FAUX mais
-- plausibles. Tout passe maintenant par `C_Traits`, qui est la source du client lui-meme.
--
-- L'ARBRE DESSINE EST CELUI DE LA SPE ACTIVE. Aucune API ne rend l'arbre d'une autre spe
-- sans y basculer. Quand la spe regardee n'est pas la spe jouee, on le dit et on retombe
-- sur la liste, qui reste vraie.
--
-- L'EXPORT ne s'affiche que si `Traits.SelfCheck` a confirme le format sur ce client :
-- une chaine fausse ferait coller au joueur un arbre qui n'est pas celui qu'il regarde.

local NODE = 30
local NODE_GAP = 6
local BUILD_ROW = 38
local TALENT_ROW = 22
local SECTION_GAP = 18

local view, pools
local content = "raid"

local function hex(key)
    return ns.Theme.C(key)
end

-- ------------------------------------------------------------------- widgets

local function newNode()
    local button = CreateFrame("Button", nil, view.content, "BackdropTemplate")
    button:SetSize(NODE, NODE)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.rank = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.rank:SetPoint("BOTTOMRIGHT", 1, 0)

    return button
end

local function newBuildRow()
    local row = CreateFrame("Frame", nil, view.content, "BackdropTemplate")
    row:SetHeight(BUILD_ROW)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.rank:SetPoint("LEFT", 10, 0)
    row.rank:SetWidth(28)
    row.rank:SetJustifyH("LEFT")

    row.share = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.share:SetPoint("LEFT", 40, 0)
    row.share:SetWidth(64)
    row.share:SetJustifyH("LEFT")

    row.stats = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.stats:SetPoint("LEFT", 110, 0)
    row.stats:SetJustifyH("LEFT")
    row.stats:SetWordWrap(false)

    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tag:SetPoint("RIGHT", -10, 0)
    row.tag:SetJustifyH("RIGHT")
    row.tag:SetWordWrap(false)

    return row
end

--- Ligne de talent : nom, barre d'adoption, part. Le REPLI quand l'arbre n'est pas lisible.
local function newTalentRow()
    local row = CreateFrame("Frame", nil, view.content)
    row:SetHeight(TALENT_ROW)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetHeight(4)
    row.track:SetColorTexture(0.16, 0.16, 0.17, 1)

    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetHeight(4)

    row.share = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.share:SetPoint("RIGHT", -8, 0)
    row.share:SetWidth(46)
    row.share:SetJustifyH("RIGHT")

    return row
end

local function newText()
    local label = view.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    return label
end

local function resetNode(button)
    button.node, button.share = nil, nil
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
end

local function hideTooltip()
    GameTooltip:Hide()
end

local function nodeOnEnter(self)
    local node = self.node
    if not node then return end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(node.name or ("#" .. tostring(node.id)))
    if self.pickedRank then
        GameTooltip:AddDoubleLine(L["taken by the top build"],
            string.format("%d/%d", self.pickedRank, node.maxRanks or 1),
            0.54, 0.54, 0.54, 0, 0.9, 0.46)
    else
        GameTooltip:AddLine(L["not taken by the top build"], 0.54, 0.54, 0.54)
    end
    -- L'ADOPTION est une mesure differente du build : elle compte tous les joueurs
    -- releves, pas seulement ceux du groupe dominant. Un talent que le build de tete
    -- ignore peut etre pris par la moitie du haut de tableau.
    if self.share then
        GameTooltip:AddDoubleLine(L["taken by"],
            string.format("%d%%", self.share * 100 + 0.5),
            0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
    end
    GameTooltip:Show()
end

-- --------------------------------------------------------------------- rendu

local function text(top, width, value)
    local label = pools.text:Acquire()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", 2, top)
    label:SetWidth(width - 4)
    label:SetText(value)
    return top - math.ceil(label:GetStringHeight() or 14) - 4
end

local function heading(top, width, label)
    top = top - (top < 0 and SECTION_GAP or 0)
    return text(top, width, hex("link") .. label:upper() .. "|r") - 6
end

--- Adoption par identifiant du relevé, pour le contenu choisi.
local function shareByID()
    local out = {}
    for _, entry in ipairs(ns.Meta.Talents(content) or {}) do
        out[entry.id] = entry.share
    end
    return out
end

--- L'ARBRE. Rend le nouveau haut, ou nil quand il n'est pas dessinable.
---
--- Trois raisons de ne pas etre dessinable, toutes dites au joueur plutot que masquees :
--- le client ne rend pas d'arbre, la spe regardee n'est pas la spe jouee, ou le relevé
--- parle un espace d'identifiants que l'arbre ne reconnait pas.
--- @return number|nil top, string|nil raison
local function layoutTree(top, width)
    local builds = ns.Meta.Builds(content)
    local build = builds and builds[1]
    if not build or not build.nodes then return nil, L["The reference does not carry a full tree for this content."] end

    if ns.Spec.Selected() ~= ns.Spec.Active() then
        return nil, L["The tree can only be drawn for the spec you are playing."]
    end

    local shot = ns.Traits.Snapshot()
    if not shot then return nil, L["The client did not return a talent tree."] end

    local match = ns.Traits.Match(build.nodes)
    -- Une correspondance partielle est un signe de desynchronisation, pas un detail : la
    -- moitie de l'arbre serait fausse. On exige large plutot que d'afficher a moitie.
    if not match or match.matched < math.floor(match.total * 0.8) then
        return nil, L["The reference talent ids do not match this client's tree."]
    end

    local shares = shareByID()

    -- MISE A L'ECHELLE. Les positions de `C_Traits` sont dans un repere propre a Blizzard,
    -- de plusieurs milliers d'unites. On ramene l'ensemble dans la largeur disponible en
    -- gardant les proportions : un arbre etire ne se reconnait plus.
    local minX, maxX, minY, maxY
    for _, node in pairs(shot.nodes) do
        minX = math.min(minX or node.x, node.x)
        maxX = math.max(maxX or node.x, node.x)
        minY = math.min(minY or node.y, node.y)
        maxY = math.max(maxY or node.y, node.y)
    end
    if not minX or maxX == minX then return nil, L["The client did not return a talent tree."] end

    local usable = width - NODE - 8
    local scale = usable / (maxX - minX)
    local height = (maxY - minY) * scale

    top = heading(top, width, L["Talent tree"])
    top = text(top, width, hex("muted") .. string.format(
        L["Top build: %d%% of the top players. Hover a node for its adoption."],
        (build.share or 0) * 100 + 0.5) .. "|r")

    local origin = top - 4
    for _, nodeID in ipairs(shot.order) do
        local node = shot.nodes[nodeID]
        if node then
            local picked = match.selection[nodeID]
            local button = pools.node:Acquire()
            button:SetParent(view.content)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT",
                4 + (node.x - minX) * scale,
                origin - (node.y - minY) * scale)

            button.icon:SetTexture(node.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            -- PRIS ou PAS PRIS, et rien entre les deux : la couleur seule ne porte jamais
            -- l'information ici non plus, le rang l'ecrit en chiffres.
            button.icon:SetDesaturated(not picked)
            button.icon:SetAlpha(picked and 1 or 0.35)
            ns.Theme.ApplyCard(button, picked and ns.Theme.RGB.link or nil)

            local maxRanks = node.maxRanks or 1
            button.rank:SetText((picked and maxRanks > 1)
                and (hex("text") .. picked.rank .. "|r") or "")

            button.node = node
            button.pickedRank = picked and picked.rank or nil
            button.share = picked and shares[picked.sourceID] or nil
            button:SetScript("OnEnter", nodeOnEnter)
            button:SetScript("OnLeave", hideTooltip)
            button:Show()
        end
    end

    return origin - height - NODE - NODE_GAP
end

local function layoutTalentList(top, width)
    local list = ns.Meta.Talents(content)
    if not list then return top end

    -- LES NOMS PASSENT PAR `C_Traits`, jamais par `GetSpellInfo`. Un identifiant de noeud
    -- passe a `GetSpellInfo` rend le nom d'un sort SANS RAPPORT — un nom faux mais
    -- plausible, ce qui est pire que pas de nom du tout.
    local shot = ns.Traits.Snapshot()
    local named = {}
    for _, entry in ipairs(list) do
        local name
        if shot then
            local nodeID = shot.byEntry[entry.id] or (shot.nodes[entry.id] and entry.id)
            local node = nodeID and shot.nodes[nodeID]
            name = node and node.name
        end
        if name then table.insert(named, { name = name, share = entry.share }) end
        if #named >= 16 then break end
    end
    if #named == 0 then return top end

    top = heading(top, width, L["Talents"])

    local barLeft, barWidth = math.min(300, width - 220), 140
    for _, entry in ipairs(named) do
        local row = pools.talent:Acquire()
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, top)
        row:SetWidth(width)

        row.name:SetWidth(barLeft - 16)
        row.name:SetText(hex("text") .. entry.name .. "|r")

        row.track:ClearAllPoints()
        row.track:SetPoint("LEFT", row, "LEFT", barLeft, 0)
        row.track:SetWidth(barWidth)

        row.fill:ClearAllPoints()
        row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
        row.fill:SetWidth(math.max(1, barWidth * math.min(1, entry.share or 0)))
        local r, g, b = unpack(ns.Theme.RGB.link)
        row.fill:SetColorTexture(r, g, b, 1)

        row.share:SetText(string.format("%s%d%%|r", hex("muted"), (entry.share or 0) * 100 + 0.5))

        row:Show()
        top = top - TALENT_ROW
    end

    return top
end

--- Quel build ressemble le plus a la repartition du joueur ?
---
--- On compare des REPARTITIONS, pas des talents : rien ne garantit que le `talentID` de
--- Warcraft Logs vive dans le meme espace que celui du client, alors que la repartition
--- secondaire est mesuree des deux cotes avec la meme definition. D'ou « le plus proche »,
--- et jamais « c'est ton build ».
local function closestBuild(builds)
    local mine = ns.Stats.Current()
    if not mine then return nil end

    local total = 0
    for _, definition in ipairs(ns.Stats.LIST) do
        total = total + ((mine[definition.key] or {}).rating or 0)
    end
    if total <= 0 then return nil end

    local best, bestGap
    for index, build in ipairs(builds) do
        if type(build.stats) == "table" then
            local gap = 0
            for _, definition in ipairs(ns.Stats.LIST) do
                local share = ((mine[definition.key] or {}).rating or 0) / total
                gap = gap + math.abs(share - (build.stats[definition.key] or 0))
            end
            if not bestGap or gap < bestGap then best, bestGap = index, gap end
        end
    end
    return best
end

local function layoutBuilds(top, width)
    local builds = ns.Meta.Builds(content)
    if not builds then
        return text(top, width, hex("muted") .. L["No build recorded for this content."] .. "|r")
    end

    top = heading(top, width, L["Builds"])
    local closest = closestBuild(builds)

    for index, build in ipairs(builds) do
        local row = pools.build:Acquire()
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, top)
        row:SetWidth(width)
        ns.Theme.ApplyCard(row, index == closest and ns.Theme.RGB.link or nil)

        row.rank:SetText(hex("muted") .. index .. "|r")
        row.share:SetText(string.format("%s%d%%|r", hex("text"), (build.share or 0) * 100 + 0.5))

        local parts = {}
        for _, definition in ipairs(ns.Stats.LIST) do
            local value = build.stats and build.stats[definition.key]
            if value then
                table.insert(parts, string.format("%s %d%%", L[definition.label], value * 100 + 0.5))
            end
        end
        row.stats:SetWidth(math.max(80, width - 230))
        row.stats:SetText(#parts > 0
            and (hex("text") .. table.concat(parts, "   ") .. "|r")
            -- Les builds de donjon n'emportent PAS de repartition : elle couterait une
            -- requete par joueur, soit un doublement du relevé, pour une colonne de plus.
            or (hex("muted") .. L["stats not measured for this group"] .. "|r"))

        row.tag:SetText(index == closest
            and (hex("link") .. L["closest to yours"] .. "|r") or "")

        row:Show()
        top = top - BUILD_ROW - 4
    end

    return text(top - 2, width, hex("muted") .. string.format(
        L["%d players grouped by identical talent tree"], ns.Meta.Sample()) .. "|r")
end

-- ------------------------------------------------------------------- public

--- Ouvre la fenetre de copie avec la chaine d'import du build de tete.
local function exportBuild()
    local builds = ns.Meta.Builds(content)
    local build = builds and builds[1]
    local match = build and build.nodes and ns.Traits.Match(build.nodes)
    if not match then
        ns.Print(ns.L["nothing readable in that paste"])
        return
    end

    local text, reason = ns.Traits.Export(match)
    if not text then
        ns.Print("%s%s|r", hex("critical"),
            string.format(L["import string refused: %s"], tostring(reason)))
        return
    end
    ns.Copy.Show(L["Talent import string"], text)
end

function TalentView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- LE CHOIX DU CONTENU, en tete, parce qu'il change tout le reste de la page. Deux
    -- boutons plutot qu'un menu : il n'y a que deux reponses.
    view.modes = {}
    for index, mode in ipairs({
        { key = "raid",   label = "Raid" },
        { key = "mythic", label = "Mythic+" },
    }) do
        local button = CreateFrame("Button", nil, view, "BackdropTemplate")
        button:SetSize(96, 22)
        button:SetPoint("TOPLEFT", (index - 1) * 100, -2)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetPoint("CENTER")
        button.key = mode.key
        button.label = mode.label
        button:SetScript("OnClick", function(self)
            content = self.key
            TalentView.Refresh()
        end)
        view.modes[index] = button
    end

    view.export = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.export:SetSize(180, 22)
    view.export:SetPoint("TOPLEFT", 210, -2)
    ns.Localize(view.export, "Copy import string")
    view.export:SetScript("OnClick", exportBuild)

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 400, -8)
    view.intro:SetJustifyH("LEFT")

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", 0, -30)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(600, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    pools = {
        node = ns.Pool.New(newNode, resetNode),
        build = ns.Pool.New(newBuildRow),
        talent = ns.Pool.New(newTalentRow),
        text = ns.Pool.New(newText),
    }

    return view
end

function TalentView.Refresh()
    if not view then return end
    ns.Pool.ResetAll(pools)

    for _, button in ipairs(view.modes) do
        local active = button.key == content
        ns.Theme.ApplyCard(button, active and ns.Theme.RGB.link or nil)
        button.text:SetText((active and hex("link") or hex("muted")) .. L[button.label] .. "|r")
    end

    -- L'EXPORT NE S'AFFICHE QUE S'IL EST SUR. `SelfCheck` compare notre serialiseur a celui
    -- du client sur la configuration du joueur : tant qu'ils ne coincident pas au caractere
    -- pres, un bouton d'export ne ferait que produire une chaine que le jeu refusera — ou,
    -- pire, acceptera de travers.
    view.export:SetShown(ns.Traits.SelfCheck() and true or false)

    view.intro:SetWidth(math.max(120, (view:GetWidth() or 600) - 410))
    view.intro:SetText(hex("muted") .. (content == "mythic"
        and L["Talent trees played in Mythic+ dungeons."]
        or L["Talent trees played on raid bosses."]) .. "|r")

    local available = math.max(360, (view.scroll:GetWidth() or 700) - 8)
    local width = math.min(760, available)
    view.content:SetWidth(available)

    local top = 0
    if not ns.Meta.Available() then
        top = text(top, width, hex("muted")
            .. L["no top-build reference for this spec yet"] .. "|r")
    else
        local drawn, reason = layoutTree(top, width)
        if drawn then
            top = drawn
        else
            -- On DIT pourquoi l'arbre n'est pas la, puis on montre ce qui reste vrai.
            top = text(top, width, hex("bis") .. reason .. "|r")
            top = layoutTalentList(top, width)
        end
        top = layoutBuilds(top, width)
    end

    view.content:SetHeight(math.max(1, -top + 12))
end
