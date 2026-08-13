local _, ns = ...

local GuildView = {}
ns.GuildView = GuildView

local L = ns.L

-- Onglet Guilde : DEUX ecrans, une question chacun.
--
--   Roster — « est-ce que tout le monde est pret ? »
--   Butin  — « quel boss ce soir, et qui a besoin de cet objet ? »
--
-- L'ancienne version les faisait cohabiter dans une seule grille de cinq FontStrings
-- reutilisees pour des sens sans rapport : en mode Butin, `name` portait un nom d'objet,
-- `spec` un nom de joueur, `fixes` un compte de convoiteurs — et l'entete de colonnes
-- etait remplacee par une phrase, donc cinq colonnes de chiffres sans le moindre libelle.
--
-- TROIS REGLES, qui expliquent la quasi-totalite des choix ci-dessous.
--
-- 1. Le mot « pret » n'apparait plus. Il designait deux choses a la fois — une simulation
--    fraiche et « rien a corriger » — et l'ecran affichait les deux sous le meme nom.
--    Desormais : « frais » pour une simulation, « rien a signaler » pour une ligne propre.
--
-- 2. Un compte ne s'ecrit que s'il est exact sur TOUT le roster. Le bandeau porte deux
--    partitions qui somment chacune au total, et la liste deux sections qui somment au
--    total. Aucune paire de nombres de cet ecran ne peut se contredire. Les sous-etats
--    sont portes par le TRI et le GLYPHE, jamais par un sous-compte qui ne tombe pas juste.
--
-- 3. La gouttiere de gauche ne porte pas d'alphabet a elle : elle RECOPIE le glyphe de la
--    colonne qui a decide du rang de la ligne. `!` ne veut donc jamais dire autre chose
--    que « correctif », ou qu'on le lise.
--
-- Alphabet, repris de `GearView.layoutGems` — un seul jeu de signes dans tout l'addon :
--   `!` correctif en attente   `x` rien de partage   `~` perime   `+` conforme

local ROW_HEIGHT = 22
local SECTION_HEIGHT = 24
local BOSS_HEIGHT = 46
local LOOT_HEIGHT = 34
local GUTTER = 18
local CHEVRON = 14
local PADDING = 8
local BOSS_WIDTH = 246

-- Colonnes de droite du roster : largeur FIXE, elles portent des nombres dont la place ne
-- depend pas de la fenetre. Le nom prend ce qui reste — c'est la seule colonne dont
-- l'allongement serve a quelque chose.
local COLUMNS = {
    { key = "spec",  width = 128, justify = "LEFT" },
    { key = "ilvl",  width = 54,  justify = "RIGHT" },
    { key = "fixes", width = 66,  justify = "RIGHT" },
    { key = "sim",   width = 84,  justify = "RIGHT" },
}
local NAME_MIN = 90

local view, pools
local screen = "roster"
local expanded = false
local selectedEncounter

local function hex(key)
    return ns.Theme.C(key)
end

--- Teinte d'un glyphe. La couleur DOUBLE le signe, elle ne le remplace jamais.
local function glyphColor(glyph)
    if glyph == "!" then return hex("critical") end
    if glyph == "x" then return hex("critical") end
    if glyph == "~" then return hex("bis") end
    return hex("good")
end

local function tint(percent)
    if percent >= 2 then return "good" end
    if percent >= 0.5 then return "bis" end
    return "muted"
end

-- ------------------------------------------------------------------ fabriques

--- Une ligne de membre : gouttiere, nom, puis les colonnes de nombres.
local function newMemberRow()
    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.glyph = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.glyph:SetPoint("LEFT", PADDING, 0)
    row.glyph:SetWidth(GUTTER)
    row.glyph:SetJustifyH("CENTER")

    -- Le NOM est le texte le plus gros de la ligne, et les nombres viennent juste apres.
    -- L'ancienne version mettait le nom en GameFontHighlight et TOUS les chiffres en
    -- GameFontNormalSmall : le contenu utile etait le plus petit texte de la ligne.
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    for _, column in ipairs(COLUMNS) do
        local font = column.key == "spec" and "GameFontDisableSmall" or "GameFontHighlight"
        row[column.key] = row:CreateFontString(nil, "OVERLAY", font)
        row[column.key]:SetWordWrap(false)
    end

    row.chevron = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.chevron:SetPoint("RIGHT", -PADDING, 0)
    row.chevron:SetWidth(CHEVRON)
    row.chevron:SetJustifyH("RIGHT")

    return row
end

--- Titre de section : « A CORRIGER — 10 ». Ce n'est PAS une ligne de donnees deguisee.
local function newSection()
    local frame = CreateFrame("Button", nil, view.content)
    frame:SetHeight(SECTION_HEIGHT)

    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetPoint("LEFT", PADDING, -2)
    frame.label:SetJustifyH("LEFT")

    frame.action = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.action:SetPoint("RIGHT", -PADDING, -2)
    frame.action:SetJustifyH("RIGHT")

    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetHeight(1)
    frame.rule:SetPoint("BOTTOMLEFT", PADDING, 0)
    frame.rule:SetPoint("BOTTOMRIGHT", -PADDING, 0)

    return frame
end

--- Carte de boss, colonne de gauche de l'ecran Butin.
local function newBossCard()
    local card = CreateFrame("Button", nil, view.bossList, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetHeight(BOSS_HEIGHT)

    card.portrait = card:CreateTexture(nil, "ARTWORK")
    card.portrait:SetSize(34, 34)
    card.portrait:SetPoint("LEFT", 6, 0)
    card.portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.name:SetPoint("TOPLEFT", card.portrait, "TOPRIGHT", 8, -2)
    card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.name:SetJustifyH("LEFT")
    card.name:SetWordWrap(false)

    card.detail = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.detail:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.detail:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.detail:SetJustifyH("LEFT")
    card.detail:SetWordWrap(false)

    return card
end

--- Ligne d'objet convoite, colonne de droite de l'ecran Butin.
local function newLootRow()
    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(LOOT_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", PADDING, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Sous-ligne grise : niveau simule, premier pretendant, nombre de membres. Le
    -- CLASSEMENT complet reste dans l'infobulle, ou `AddDoubleLine` l'aligne deja en deux
    -- colonnes — l'aplatir ici ferait une file de nombres a abscisses variables.
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.value:SetPoint("RIGHT", -PADDING, 0)
    row.value:SetWidth(86)
    row.value:SetJustifyH("RIGHT")

    return row
end

-- Remise a neuf. AUCUN champ ne survit d'un rendu a l'autre.
--
-- L'ancienne version ne vidait ni texte ni script : elle ne tenait que parce que les deux
-- sous-vues ecrivaient les cinq memes `SetText`. Survoler la liste des membres apres avoir
-- consulte la sous-vue Butin sortait donc l'infobulle d'un objet. C'est la famille de bug
-- deja payee deux fois dans ce depot.
local function resetMemberRow(row)
    row.card = nil
    row.glyph:SetText("")
    row.name:SetText("")
    row.chevron:SetText("")
    for _, column in ipairs(COLUMNS) do row[column.key]:SetText("") end
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
end

local function resetSection(frame)
    frame.label:SetText("")
    frame.action:SetText("")
    frame:SetScript("OnClick", nil)
end

local function resetBossCard(card)
    card.group = nil
    card.name:SetText("")
    card.detail:SetText("")
    card.portrait:SetTexture(nil)
    card:SetScript("OnClick", nil)
end

local function resetLootRow(row)
    row.item, row.encounter = nil, nil
    row.name:SetText("")
    row.detail:SetText("")
    row.value:SetText("")
    row.icon:SetTexture(nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
end

-- ---------------------------------------------------------------- gestionnaires

local function hideTooltip()
    GameTooltip:Hide()
end

local function memberOnClick(self)
    local card = self.card
    if card and card.sim ~= "" then
        ns.Copy.Show(card.name, "https://www.raidbots.com/simbot/report/" .. card.sim)
    end
end

local function memberOnEnter(self)
    local card = self.card
    if not card then return end

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(card.name, 0.91, 0.91, 0.91)
    if card.spec ~= "" then GameTooltip:AddLine(card.spec, 0.54, 0.54, 0.54) end

    GameTooltip:AddLine(" ")
    if (card.fixes or 0) > 0 then
        GameTooltip:AddDoubleLine(L["Fixes pending"], tostring(card.fixes),
            0.54, 0.54, 0.54, 1, 0.42, 0.42)
    else
        GameTooltip:AddDoubleLine(L["Fixes pending"], L["none"],
            0.54, 0.54, 0.54, 0.45, 0.78, 0.62)
    end

    if card.simState == "missing" then
        GameTooltip:AddDoubleLine(L["Droptimizer"], L["not shared"],
            0.54, 0.54, 0.54, 1, 0.42, 0.42)
    else
        GameTooltip:AddDoubleLine(L["Droptimizer"],
            string.format(L["%d day(s) old"], math.max(0, card.simAge)),
            0.54, 0.54, 0.54, card.simState == "stale" and 0.89 or 0.45,
            card.simState == "stale" and 0.64 or 0.78, card.simState == "stale" and 0.36 or 0.62)
        GameTooltip:AddLine(L["click to copy the report link"], 0, 0.69, 1)
    end
    GameTooltip:Show()
end

local function sectionOnClick()
    expanded = not expanded
    GuildView.Refresh()
end

local function bossOnClick(self)
    selectedEncounter = self.group and self.group.encounter
    GuildView.Refresh()
end

local function lootOnEnter(self)
    local item = self.item
    if not item then return end

    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    -- Le lien du journal porte les identifiants de bonus, donc le VRAI niveau.
    -- `SetItemByID` ne connait que le modele et rend 44 sur une piece de raid.
    local link = ns.Sim.LootLink(self.encounter, item.id, item.difficulty, item.instance)
    local shown = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not shown and not pcall(GameTooltip.SetItemByID, GameTooltip, item.id) then
        GameTooltip:AddLine("item:" .. item.id)
    end

    if item.ilvl and item.ilvl > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["simulated at ilvl"], tostring(item.ilvl),
            0, 0.69, 1, 0.91, 0.91, 0.91)
        if not shown then
            GameTooltip:AddLine(L["the item level above is the base template, not the drop"],
                0.54, 0.54, 0.54, true)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Guild ranking"], 0, 0.69, 1)
    for rank, member in ipairs(item.members) do
        if rank > 12 then
            GameTooltip:AddLine(string.format("+%d…", #item.members - 12), 0.54, 0.54, 0.54)
            break
        end
        GameTooltip:AddDoubleLine(
            string.format("%d. %s", rank, member.name),
            string.format("%+.2f%%", member.percent),
            0.91, 0.91, 0.91, 0, 0.9, 0.46)
    end
    GameTooltip:Show()
end

-- ------------------------------------------------------------------ mise en page

--- Pose les colonnes d'une ligne de membre. Le nom prend ce que les nombres laissent.
local function layoutMemberRow(row, width)
    row:SetWidth(width)

    local fixed = CHEVRON + PADDING
    for _, column in ipairs(COLUMNS) do fixed = fixed + column.width end

    local nameWidth = math.max(NAME_MIN, width - fixed - GUTTER - PADDING * 2)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", PADDING + GUTTER + 4, 0)
    row.name:SetWidth(nameWidth)

    local offset = PADDING + GUTTER + 4 + nameWidth
    for _, column in ipairs(COLUMNS) do
        local field = row[column.key]
        field:ClearAllPoints()
        field:SetPoint("LEFT", offset, 0)
        field:SetWidth(column.width)
        field:SetJustifyH(column.justify)
        offset = offset + column.width
    end
end

--- Entete de colonnes : la MEME fonction de mise en page que les lignes.
---
--- C'etait une chaine unique bourree d'espaces censee tomber en face de colonnes qu'elle
--- ne pouvait pas connaitre — la police n'est pas a chasse fixe. Elle ne peut plus
--- deriver : elle EST le modele.
local function layoutHeader(width)
    layoutMemberRow(view.header, width)
    view.header.glyph:SetText("")
    view.header.chevron:SetText("")
    view.header.name:SetText(hex("muted") .. L["MEMBER"] .. "|r")
    view.header.spec:SetText(hex("muted") .. L["SPEC"] .. "|r")
    view.header.ilvl:SetText(hex("muted") .. L["ILVL"] .. "|r")
    view.header.fixes:SetText(hex("muted") .. L["FIXES"] .. "|r")
    view.header.sim:SetText(hex("muted") .. L["DROPTIMIZER"] .. "|r")
end

--- Une carte du bandeau : un titre, puis une partition qui somme au total.
local function fillCard(card, title, total, parts)
    card.title:SetText(string.format("%s%s|r   %s%s|r",
        hex("link"), title, hex("muted"), string.format(L["of %d"], total)))

    local text = {}
    for _, part in ipairs(parts) do
        table.insert(text, string.format("%s%s|r %s%d|r %s%s|r",
            glyphColor(part.glyph), part.glyph,
            part.count > 0 and hex("text") or hex("muted"), part.count,
            hex("muted"), part.label))
    end
    card.body:SetText(table.concat(text, "    "))
end

-- ------------------------------------------------------------------ ecran Roster

local function refreshRoster(width)
    local state = ns.Guild.RosterState()

    fillCard(view.gearCard, L["EQUIPMENT"], state.total, {
        { glyph = "!", count = state.gear.withFixes, label = L["to fix"] },
        { glyph = "+", count = state.gear.clean,     label = L["no fix"] },
    })
    fillCard(view.simCard, L["DROPTIMIZER"], state.total, {
        { glyph = "x", count = state.sim.missing, label = L["none"] },
        { glyph = "~", count = state.sim.stale,   label = L["stale"] },
        { glyph = "+", count = state.sim.fresh,   label = L["fresh"] },
    })

    layoutHeader(width)

    local todo, done = {}, {}
    for _, card in ipairs(state.list) do
        table.insert(card.needsWork and todo or done, card)
    end

    local top = 0

    local function memberRow(card)
        local row = pools.member:Acquire()
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, top)
        layoutMemberRow(row, width)

        row.glyph:SetText(glyphColor(card.glyph) .. card.glyph .. "|r")
        row.name:SetText(card.name)
        row.spec:SetText(card.spec ~= "" and card.spec or "")
        row.ilvl:SetText(card.ilvl > 0 and tostring(card.ilvl) or "—")

        -- Zero ne s'ecrit pas « 0 » ni « ok » : un tiret cadratin n'a pas de forme de
        -- chiffre, donc une colonne sans probleme se balaie sans etre lue.
        row.fixes:SetText((card.fixes or 0) > 0
            and string.format("%s!|r %s%d|r", hex("critical"), hex("text"), card.fixes)
            or (hex("muted") .. "—|r"))

        if card.simState == "missing" then
            row.sim:SetText(string.format("%sx|r %s—|r", hex("critical"), hex("muted")))
        else
            local color = card.simState == "stale" and hex("bis") or hex("good")
            local mark = card.simState == "stale" and "~" or "+"
            row.sim:SetText(string.format("%s%s|r %s%s|r", color, mark, hex("text"),
                string.format(L["%d d"], math.max(0, card.simAge))))
        end

        -- Le chevron n'apparait QUE si le clic fait quelque chose. Un geste annonce sous
        -- un clic mort est le bug deja corrige sur la carte « Rien a corriger ».
        row.chevron:SetText(card.sim ~= "" and (hex("muted") .. ">|r") or "")

        row.card = card
        row:SetScript("OnClick", memberOnClick)
        row:SetScript("OnEnter", memberOnEnter)
        row:SetScript("OnLeave", hideTooltip)
        row:Show()
        top = top - ROW_HEIGHT
    end

    local function section(label, count, action)
        local frame = pools.section:Acquire()
        frame:SetParent(view.content)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", 0, top)
        frame:SetWidth(width)
        frame.label:SetText(string.format("%s%s|r %s— %d|r",
            hex("text"), label, hex("muted"), count))
        frame.rule:SetColorTexture(unpack(ns.Theme.RGB.border))
        if action then
            frame.action:SetText(hex("link") .. action .. "|r")
            frame:SetScript("OnClick", sectionOnClick)
        end
        frame:Show()
        top = top - SECTION_HEIGHT
    end

    if #todo > 0 then
        section(L["TO FIX"], #todo)
        for _, card in ipairs(todo) do memberRow(card) end
    end

    if #done > 0 then
        top = top - 6
        section(L["NOTHING TO REPORT"], #done, expanded and L["collapse"] or L["expand"])
        if expanded then
            for _, card in ipairs(done) do memberRow(card) end
        end
    end

    view.content:SetHeight(math.max(1, -top + 8))
    return state.total
end

-- ------------------------------------------------------------------- ecran Butin

local function refreshLoot(width)
    local groups = ns.Guild.LootByEncounter()
    if not groups then
        view.bossList:Hide()
        view.content:SetHeight(1)
        return 0, L["No droptimizer shared yet. Run the roll call, and ask members to enable sharing."]
    end

    view.bossList:Show()

    -- Rencontre choisie : celle qu'on a cliquee, sinon la premiere — la plus payante.
    local chosen
    for _, group in ipairs(groups) do
        if group.encounter == selectedEncounter then chosen = group end
    end
    chosen = chosen or groups[1]
    selectedEncounter = chosen.encounter

    local top = 0
    for _, group in ipairs(groups) do
        local card = pools.boss:Acquire()
        card:SetParent(view.bossList)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, top)
        card:SetWidth(BOSS_WIDTH)

        local active = group.encounter == chosen.encounter
        ns.Theme.ApplyCard(card, active and ns.Theme.RGB.link or nil)

        -- Portrait absent : la carte se decale, elle ne montre pas un point
        -- d'interrogation permanent. Une fiche venue d'un client anterieur ne porte pas
        -- d'instance, donc la lecture du journal echoue — c'est un manque, pas une erreur.
        local portrait = ns.Journal.Portrait(group.instance, group.encounter)
        card.portrait:SetTexture(portrait)
        card.portrait:SetShown(portrait ~= nil)
        card.name:ClearAllPoints()
        card.name:SetPoint("TOPLEFT", portrait and 48 or 10, -6)
        card.name:SetPoint("RIGHT", card, "RIGHT", -8, 0)

        local members = 0
        for _, item in ipairs(group.items) do members = members + #item.members end

        card.name:SetText((active and hex("link") or hex("text"))
            .. (group.name or string.format(L["encounter %d"], group.encounter)) .. "|r")
        card.detail:SetText(string.format("%s%s  ·  %s|r   %s%+.2f%%|r",
            hex("muted"),
            string.format(L["%d items"], #group.items),
            string.format(L["%d concerned"], members),
            hex(tint(group.best)), group.best))

        card.group = group
        card:SetScript("OnClick", bossOnClick)
        card:Show()
        top = top - BOSS_HEIGHT - 4
    end
    view.bossList:SetHeight(math.max(1, -top))

    -- Colonne de droite : les objets de la rencontre choisie, et d'elle seule.
    local lootTop = 0
    for _, item in ipairs(chosen.items) do
        local row = pools.loot:Acquire()
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, lootTop)
        row:SetWidth(width)

        local link = ns.Sim.LootLink(chosen.encounter, item.id,
            item.difficulty or chosen.difficulty, item.instance or chosen.instance)

        local icon
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        if getIcon then
            local ok, value = pcall(getIcon, item.id)
            if ok then icon = value end
        end
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        row.name:SetWidth(math.max(80, width - 150))
        row.name:SetText(link or ns.ItemInfo.ColoredName(item.id)
            or (hex("muted") .. "item:" .. item.id .. "|r"))

        local top1 = item.members[1]
        local detail = {}
        if item.ilvl and item.ilvl > 0 then
            table.insert(detail, "ilvl " .. item.ilvl)
        end
        if top1 then table.insert(detail, top1.name) end
        table.insert(detail, string.format(L["%d concerned"], #item.members))
        row.detail:SetWidth(math.max(80, width - 150))
        row.detail:SetText(hex("muted") .. table.concat(detail, "  ·  ") .. "|r")

        row.value:SetText(string.format("%s%+.2f%%|r", hex(tint(item.best)), item.best))

        row.item, row.encounter = item, chosen.encounter
        row:SetScript("OnEnter", lootOnEnter)
        row:SetScript("OnLeave", hideTooltip)
        row:Show()
        lootTop = lootTop - LOOT_HEIGHT - 2
    end

    view.content:SetHeight(math.max(1, -lootTop + 8))
    return #groups
end

-- ---------------------------------------------------------------------- public

function GuildView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- UNE barre d'action. Le titre « Audit de guilde » a disparu : l'onglet porte deja le
    -- nom, et la phrase permanente sur la confidentialite se lit une fois puis n'est plus
    -- que du bruit — elle vit maintenant dans l'infobulle de la case de partage et dans
    -- le panneau de reglages, ou on la cherche.
    view.modes = {}
    for index, mode in ipairs({
        { key = "roster", label = "Roster" },
        { key = "loot",   label = "Loot" },
    }) do
        local button = CreateFrame("Button", nil, view, "BackdropTemplate")
        button:SetSize(84, 22)
        button:SetPoint("TOPLEFT", (index - 1) * 88, -2)
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
            screen = self.key
            GuildView.Refresh()
        end)
        view.modes[index] = button
    end

    view.request = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.request:SetSize(130, 22)
    view.request:SetPoint("TOPLEFT", 190, -2)
    ns.Localize(view.request, "Roll call")
    view.request:SetScript("OnClick", function()
        if ns.Guild.Request() then GuildView.Refresh() end
    end)

    view.export = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.export:SetSize(150, 22)
    view.export:SetPoint("LEFT", view.request, "RIGHT", 6, 0)
    ns.Localize(view.export, "Copy for Discord")
    view.export:SetScript("OnClick", function()
        ns.Copy.Show(L["Guild audit"], ns.Guild.Export())
    end)

    view.share = CreateFrame("CheckButton", "GearProofShareToggle", view, "UICheckButtonTemplate")
    view.share:SetSize(22, 22)
    view.share:SetPoint("LEFT", view.export, "RIGHT", 14, 0)
    view.share.text = view.share:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    view.share.text:SetPoint("LEFT", view.share, "RIGHT", 2, 0)
    ns.Localize(view.share.text, "Share my data")
    view.share:SetScript("OnClick", function(self)
        ns.db.shareWithGuild = self:GetChecked() and true or false
    end)
    view.share:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Share my data"])
        GameTooltip:AddLine(L["Members running GearProof answer the roll call. Nothing is sent unless sharing is on."],
            0.8, 0.8, 0.9, true)
        GameTooltip:Show()
    end)
    view.share:SetScript("OnLeave", hideTooltip)

    -- Bandeau : DEUX cartes, deux partitions du meme total. Elles se partagent la largeur
    -- en fraction — jamais a x fixe : le francais fait une bonne moitie de plus que
    -- l'anglais, et le mode etroit est le cas nominal a l'ouverture, pas un cas limite.
    local function newCard()
        local card = CreateFrame("Frame", nil, view, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        card:SetHeight(44)
        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.title:SetPoint("TOPLEFT", 10, -7)
        card.title:SetJustifyH("LEFT")
        card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        card.body:SetPoint("TOPLEFT", 10, -24)
        card.body:SetJustifyH("LEFT")
        card.body:SetWordWrap(false)
        ns.Theme.Track(card)
        return card
    end

    view.gearCard = newCard()
    view.gearCard:SetPoint("TOPLEFT", 0, -30)
    view.simCard = newCard()
    view.simCard:SetPoint("TOPLEFT", view.gearCard, "TOPRIGHT", 8, 0)

    -- L'entete de colonnes est HORS de la zone de defilement : c'est la legende des
    -- glyphes, elle doit rester quand la liste defile.
    view.header = CreateFrame("Frame", nil, view)
    view.header:SetHeight(ROW_HEIGHT)
    view.header:SetPoint("TOPLEFT", view.gearCard, "BOTTOMLEFT", 0, -6)
    view.header.glyph = view.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.header.glyph:SetPoint("LEFT", PADDING, 0)
    view.header.glyph:SetWidth(GUTTER)
    view.header.name = view.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.header.name:SetJustifyH("LEFT")
    for _, column in ipairs(COLUMNS) do
        view.header[column.key] = view.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    end
    view.header.chevron = view.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.header.chevron:SetPoint("RIGHT", -PADDING, 0)
    view.header.chevron:SetWidth(CHEVRON)

    -- Colonne des boss, ecran Butin. Elle vit a cote de la zone de defilement, pas dedans.
    view.bossList = CreateFrame("Frame", nil, view)
    view.bossList:SetWidth(BOSS_WIDTH)
    view.bossList:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", 0, -4)
    view.bossList:Hide()

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", 0, -4)
    view.scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetHeight(1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    view.note = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.note:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", PADDING, -6)
    view.note:SetPoint("RIGHT", view, "RIGHT", -26, 0)
    view.note:SetJustifyH("LEFT")
    view.note:Hide()

    -- Etat vide, centre. Une ligne grise en haut d'un onglet vide se lit comme un addon
    -- casse, pas comme « il manque une action ».
    view.empty = CreateFrame("Frame", nil, view)
    view.empty:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", 0, -40)
    view.empty:SetPoint("BOTTOMRIGHT", -26, 0)
    view.empty:Hide()

    view.emptyTitle = view.empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.emptyTitle:SetPoint("TOP", view.empty, "TOP", 0, -30)

    view.emptyBody = view.empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.emptyBody:SetPoint("TOP", view.emptyTitle, "BOTTOM", 0, -10)
    view.emptyBody:SetPoint("LEFT", view.empty, "LEFT", 40, 0)
    view.emptyBody:SetPoint("RIGHT", view.empty, "RIGHT", -40, 0)
    view.emptyBody:SetJustifyH("CENTER")
    view.emptyBody:SetSpacing(3)

    pools = {
        member = ns.Pool.New(newMemberRow, resetMemberRow),
        section = ns.Pool.New(newSection, resetSection),
        boss = ns.Pool.New(newBossCard, resetBossCard),
        loot = ns.Pool.New(newLootRow, resetLootRow),
    }

    return view
end

function GuildView.Refresh()
    if not view then return end

    ns.Pool.ResetAll(pools)
    view.share:SetChecked(ns.db.shareWithGuild and true or false)

    for _, button in ipairs(view.modes) do
        local active = button.key == screen
        ns.Theme.ApplyCard(button, active and ns.Theme.RGB.link or nil)
        button.text:SetText((active and hex("link") or hex("muted")) .. L[button.label] .. "|r")
    end

    -- Les deux cartes se partagent la largeur en fraction.
    local total = view:GetWidth()
    if not total or total < 200 then total = 900 end
    local cardWidth = math.floor((total - 26 - 8) / 2)
    view.gearCard:SetWidth(cardWidth)
    view.simCard:SetWidth(cardWidth)

    local loot = screen == "loot"
    view.gearCard:SetShown(not loot)
    view.simCard:SetShown(not loot)
    view.header:SetShown(not loot)
    view.note:SetShown(loot)

    -- La zone de defilement demarre sous le bandeau au Roster, sous la barre d'action au
    -- Butin : ancrage RELATIF, aucune hauteur devinee.
    view.scroll:ClearAllPoints()
    view.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    view.bossList:ClearAllPoints()
    if loot then
        view.bossList:SetPoint("TOPLEFT", view.note, "BOTTOMLEFT", -PADDING, -6)
        view.scroll:SetPoint("TOPLEFT", view.bossList, "TOPRIGHT", 12, 0)
    else
        view.scroll:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", 0, -4)
    end

    local width = math.max(360, (view.scroll:GetWidth() or 640) - 8)
    view.content:SetWidth(width)

    local count, message
    if loot then
        view.note:SetText(hex("muted")
            .. L["Sorted by the best gain in the guild. Hover an item for the full ranking."] .. "|r")
        count, message = refreshLoot(width)
    else
        count = refreshRoster(width)
    end

    -- L'etat vide passe APRES le remplissage : un ecran replie ne doit jamais afficher
    -- « personne n'a repondu » alors que vingt personnes ont repondu.
    if count and count <= 1 then
        view.empty:Show()
        view.emptyTitle:SetText(hex("text") .. L["Nobody has answered yet."] .. "|r")
        view.emptyBody:SetText(hex("muted") .. (message
            or L["Run the roll call: every guild member running GearProof answers with their spec, item level and pending fixes. Nothing is sent from your client unless you tick sharing."]) .. "|r")
    else
        view.empty:Hide()
    end
end
