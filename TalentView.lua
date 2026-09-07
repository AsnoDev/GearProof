local _, ns = ...

local TalentView = {}
ns.TalentView = TalentView

local L = ns.L

-- Onglet Talents : ce que le haut de tableau JOUE, avec le choix du contenu.
--
-- Les builds et les talents vivaient dans l'onglet Recommandations, entre les
-- statistiques et les enchantements. Ils y repondaient a une autre question que le reste
-- de la page — ce qu'on JOUE contre ce qu'on POSE — et ils la noyaient : six sections
-- dans un seul defilement.
--
-- CE QUE CETTE PAGE APPORTE DE NEUF : le meme relevé, pris en RAID et en MYTHIQUE+.
-- Ce ne sont pas les memes arbres. Sur un echantillon reel, sept talents n'apparaissent
-- qu'en raid, sept autres qu'en donjon, trente-huit sont communs — cible unique contre
-- paquets, duree de combat, couloirs. Personne ne publie cette comparaison, et c'est
-- pourtant la premiere chose qu'un joueur veut savoir en passant d'un contenu a l'autre.
--
-- Deux vues du meme relevé, parce qu'aucune ne suffit seule :
--   `builds`  groupes d'arbres IDENTIQUES, chacun avec sa repartition de statistiques.
--             Le haut de tableau ne partage presque jamais un arbre au point pres : le
--             groupe dominant plafonne vers 25 %.
--   `talents` taux d'adoption PAR TALENT. Ne dit pas quels ensembles coherents existent,
--             mais dit quels choix font consensus.

local BUILD_ROW = 38
local TALENT_ROW = 22
local SECTION_GAP = 18

local view, pools
local content = "raid"

local function hex(key)
    return ns.Theme.C(key)
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

--- Ligne de talent : nom, barre d'adoption, part.
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

--- Nom d'un talent, si le client sait le resoudre.
---
--- Warcraft Logs rend un `talentID` dont RIEN ne garantit qu'il vive dans le meme espace
--- d'identifiants que celui du client. On tente donc la resolution, et on n'affiche que ce
--- qui porte un nom : montrer « talent 112823 » n'apprend rien et fait passer une donnee
--- vraie pour une donnee cassee. Si la resolution echoue pour toute la liste, la section
--- disparait — c'est le comportement voulu tant que la correspondance n'est pas verifiee
--- en jeu.
local function talentName(id)
    local getInfo = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
    if type(getInfo) ~= "function" then return nil end

    local ok, info = pcall(getInfo, id)
    if not ok or not info then return nil end
    -- `C_Spell.GetSpellInfo` rend une table, l'ancienne globale rendait le nom en premier.
    if type(info) == "table" then return info.name end
    return type(info) == "string" and info or nil
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

local function layoutTalents(top, width)
    local list = ns.Meta.Talents(content)
    if not list then return top end

    local named = {}
    for _, entry in ipairs(list) do
        local name = talentName(entry.id)
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

-- ------------------------------------------------------------------- public

function TalentView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- LE CHOIX DU CONTENU, en tete, parce que c'est ce qui change tout le reste de la
    -- page. Deux boutons plutot qu'un menu : il n'y a que deux reponses.
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

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 210, -8)
    view.intro:SetJustifyH("LEFT")

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", 0, -30)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(600, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    pools = {
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

    view.intro:SetWidth(math.max(120, (view:GetWidth() or 600) - 220))
    view.intro:SetText(hex("muted") .. (content == "mythic"
        and L["Talent trees played in Mythic+ dungeons."]
        or L["Talent trees played on raid bosses."]) .. "|r")

    local available = math.max(360, (view.scroll:GetWidth() or 700) - 8)
    local width = math.min(620, available)
    view.content:SetWidth(available)

    local top = 0
    if not ns.Meta.Available() then
        top = text(top, width, hex("muted")
            .. L["no top-build reference for this spec yet"] .. "|r")
    else
        top = layoutBuilds(top, width)
        top = layoutTalents(top, width)
    end

    view.content:SetHeight(math.max(1, -top + 12))
end
