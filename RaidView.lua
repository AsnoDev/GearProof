local _, ns = ...

local RaidView = {}
ns.RaidView = RaidView

local L = ns.L

-- Vue par raid et par boss, sur le modele du journal des aventures : liste de rencontres a
-- gauche avec le portrait du boss, table de butin a droite.
--
-- La table de butin n'est PAS fabriquee. L'ensemble des objets qu'un droptimizer a simules
-- pour une rencontre est sa table de butin, telle que Raidbots l'a vue. Un boss absent de tes
-- rapports n'apparait pas : il n'y a rien a en dire.
--
-- Les identifiants viennent des noms de profileset de Raidbots et sont ceux du journal : le
-- client rend les noms traduits et les portraits, donc rien n'est embarque et rien ne perime.

local LIST_WIDTH = 268
local BOSS_HEIGHT = 46
local PORTRAIT = 38
local LOOT_HEIGHT = 34

local view, pools, selected

-- Difficultes de raid, dans l'ordre du selecteur. Le butin du journal N'EST PAS le meme
-- selon la difficulte : sans ce reglage on lirait la table LFR et les niveaux d'objet
-- annonces seraient faux d'une trentaine de points.
local DIFFICULTIES = {
    { id = 14, label = "Normal" },
    { id = 15, label = "Heroic" },
    { id = 16, label = "Mythic" },
}
local difficultyIndex = 3

local function hex(key)
    return ns.Theme.C(key)
end

-- Pooling partage : voir Pool.lua. Cette vue en avait sa propre copie, identique au
-- caractere pres a celle de GearView.

local function resetPools()
    ns.Pool.ResetAll(pools)
end

local function acquire(kind)
    return pools[kind]:Acquire()
end

--- Seuils d'AFFICHAGE. Ils ne pretendent pas qu'un gain de 2 % « compte » et qu'un gain de
--- 1,9 % « ne compte pas » : ils donnent une couleur, pas un verdict.
local function tint(percent)
    if percent >= 2 then return "good" end
    if percent >= 0.5 then return "bis" end
    return "muted"
end

--- Portrait d'un boss, comme le journal l'affiche.
---
--- Mis en cache par rencontre. La version precedente reglait le journal a CHAQUE boss et
--- a CHAQUE rafraichissement — donc une dizaine de changements d'etat par ouverture de
--- l'onglet, sur une interface partagee avec le joueur. Un portrait ne change pas.
local portraitCache = {}

local function bossPortrait(instanceID, encounterID)
    if not encounterID then return nil end

    local cached = portraitCache[encounterID]
    if cached then return cached end

    if type(EJ_GetCreatureInfo) ~= "function" then return nil end

    local portrait = ns.Journal.Read(instanceID, nil, nil, function()
        -- EJ_GetCreatureInfo : id, nom, description, displayInfo, iconImage.
        local results = { pcall(EJ_GetCreatureInfo, 1, encounterID) }
        return results[1] and results[1 + 5] or nil
    end)

    -- SEUL un succes est mis en cache.
    --
    -- La version precedente memorisait l'echec sous forme de `false` pour ne pas relire
    -- a chaque rendu. Mais `Journal.Read` rend nil dans deux cas parfaitement
    -- temporaires : le journal des aventures pas encore initialise, et le joueur qui l'a
    -- ouvert — on s'abstient alors de toucher a sa selection. Un seul echec au premier
    -- affichage condamnait donc le portrait pour toute la session. C'est la cause des
    -- points d'interrogation a la place des boss.
    if portrait then portraitCache[encounterID] = portrait end
    return portrait
end

-- La lecture d'objet passe par ItemInfo.lua : nom, qualite et code couleur.

-- --------------------------------------------------------------------- widgets

local function newBoss()
    local button = CreateFrame("Button", nil, view.list, "BackdropTemplate")
    button:SetSize(LIST_WIDTH - 8, BOSS_HEIGHT)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    button.portrait = button:CreateTexture(nil, "ARTWORK")
    button.portrait:SetSize(PORTRAIT, PORTRAIT)
    button.portrait:SetPoint("LEFT", 4, 0)
    button.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.name:SetPoint("TOPLEFT", button.portrait, "TOPRIGHT", 8, -3)
    button.name:SetWidth(LIST_WIDTH - PORTRAIT - 78)
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)

    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.count:SetPoint("BOTTOMLEFT", button.portrait, "BOTTOMRIGHT", 8, 4)
    button.count:SetJustifyH("LEFT")

    button.best = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.best:SetPoint("RIGHT", -8, 0)
    button.best:SetWidth(58)
    button.best:SetJustifyH("RIGHT")

    return button
end

local function newLoot()
    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(LOOT_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.slot:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.slot:SetJustifyH("LEFT")

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.value:SetPoint("RIGHT", -8, 0)
    row.value:SetWidth(76)
    row.value:SetJustifyH("RIGHT")

    return row
end

local function newHeader()
    local text = view.list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    return text
end

-- ------------------------------------------------------------------- public

function RaidView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- Les lignes de butin et les boutons de boss portent des scripts de survol qui ne
    -- sont pas tous reecrits d'un rendu a l'autre : le pool les vide.
    local function resetRow(row)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:SetScript("OnClick", nil)
    end

    pools = {
        boss = ns.Pool.New(newBoss, resetRow),
        loot = ns.Pool.New(newLoot, resetRow),
        header = ns.Pool.New(newHeader),
    }

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 2, -2)
    view.intro:SetJustifyH("LEFT")

    -- Colonne des rencontres, comme le volet gauche du journal.
    view.listScroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.listScroll:SetPoint("TOPLEFT", 0, -26)
    view.listScroll:SetPoint("BOTTOMLEFT", 0, 0)
    view.listScroll:SetWidth(LIST_WIDTH)

    view.list = CreateFrame("Frame", nil, view.listScroll)
    view.list:SetSize(LIST_WIDTH - 8, 1)
    view.listScroll:SetScrollChild(view.list)
    ns.Theme.CleanScrollBar(view.listScroll)

    -- Table de butin de la rencontre choisie.
    view.lootTitle = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    view.lootTitle:SetPoint("TOPLEFT", LIST_WIDTH + 24, -26)
    view.lootTitle:SetJustifyH("LEFT")

    view.lootNote = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.lootNote:SetPoint("TOPLEFT", view.lootTitle, "BOTTOMLEFT", 0, -2)
    view.lootNote:SetJustifyH("LEFT")

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", LIST_WIDTH + 24, -68)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(400, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    -- Etat vide, centre. Il couvre les deux colonnes : quand il n'y a rien a montrer,
    -- une liste vide a gauche et une table vide a droite ne racontent rien.
    view.empty = CreateFrame("Frame", nil, view)
    view.empty:SetPoint("TOPLEFT", 0, -70)
    view.empty:SetPoint("BOTTOMRIGHT", -28, 0)
    view.empty:Hide()

    view.emptyTitle = view.empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    view.emptyTitle:SetPoint("TOP", view.empty, "TOP", 0, -40)

    view.emptyBody = view.empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.emptyBody:SetPoint("TOP", view.emptyTitle, "BOTTOM", 0, -10)
    view.emptyBody:SetWidth(420)
    view.emptyBody:SetJustifyH("CENTER")
    view.emptyBody:SetSpacing(3)

    -- La marche a suivre, en clair, avec la commande copiable. Pas de bouton « coller
    -- un lien » ici : il ne remplirait pas cet onglet, et un bouton qui ne fait pas ce
    -- qu'il annonce est pire que pas de bouton.
    view.emptyHow = view.empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.emptyHow:SetPoint("TOP", view.emptyBody, "BOTTOM", 0, -18)
    view.emptyHow:SetWidth(460)
    view.emptyHow:SetJustifyH("CENTER")
    view.emptyHow:SetSpacing(4)

    -- Selecteur de difficulte. Il n'apparait que sur la table venue du journal : un
    -- droptimizer a simule UNE difficulte, la changer n'aurait aucun sens.
    view.difficulty = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.difficulty:SetSize(90, 20)
    view.difficulty:SetPoint("TOPRIGHT", -28, -2)
    view.difficulty:SetScript("OnClick", function()
        difficultyIndex = (difficultyIndex % #DIFFICULTIES) + 1
        RaidView.Refresh()
    end)
    view.difficulty:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["Raid difficulty"])
        GameTooltip:AddLine(L["The journal lists different item levels per difficulty."],
            0.8, 0.8, 0.9, true)
        GameTooltip:Show()
    end)
    view.difficulty:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return view
end

--- Liste des raids et de leurs boss, SANS le butin.
---
--- Le butin se lit rencontre par rencontre, a la demande — voir `journalLoot`. Le
--- construire ici pour tous les boss d'un coup demanderait une vingtaine de lectures du
--- journal a la premiere ouverture de l'onglet, avec autant de changements d'etat sur
--- une interface partagee avec le joueur. On paie ce qu'on affiche.
local function journalGroups()
    local order = {}
    for _, raid in ipairs(ns.Journal.Raids()) do
        for _, encounter in ipairs(ns.Journal.Encounters(raid.id)) do
            table.insert(order, {
                encounter = encounter.id,
                instance = raid.id,
                name = encounter.name,
                items = nil,
                best = 0,
                fromJournal = true,
            })
        end
    end
    return #order > 0 and order or nil
end

--- Butin d'une rencontre, chiffre avec ce qu'on sait.
---
--- Les chiffres portent leur unite, comme partout ailleurs dans cet addon : un ecart de
--- niveau d'objet est un ecart de niveau d'objet, un gain estime est une somme de points
--- ponderes, et aucun des deux n'est un pourcentage de DPS. Quand un droptimizer couvre
--- l'objet, sa valeur MESUREE remplace l'estimation.
local function journalLoot(group)
    if group.items then return group.items end

    local difficulty = DIFFICULTIES[difficultyIndex]
    local classID = ns.Spec.ClassID()
    local specID = ns.Spec.Selected()

    local _, summary = ns.Gear.Scan()
    local bySlot = summary.bySlot or {}
    local weights = ns.Weights.Current()

    local items = {}
    for _, loot in ipairs(ns.Journal.Loot(group.instance, group.encounter,
        difficulty.id, classID, specID)) do

        local level = loot.link and ns.ItemInfo.Level(loot.link) or nil
        local facts = loot.link and ns.ItemInfo.Get(loot.link) or nil
        local targets = facts and ns.Bags.SLOTS_FOR(facts.equipLoc)

        -- Compare a la PIRE des pieces portees pour ce type d'emplacement : c'est celle
        -- que l'objet remplacerait. Un objet dont on ne sait pas ou il se porte garde son
        -- nom et perd son chiffre — on n'invente pas de comparaison.
        local best, worn
        for _, slotName in ipairs(targets or {}) do
            local entry = bySlot[slotName]
            local current = entry and entry.itemLevel or nil
            if current and (not best or current < best) then best, worn = current, entry end
        end

        local item = {
            id = loot.id,
            link = loot.link,
            slot = loot.slot,
            ilvl = level,
            encounter = group.encounter,
            instance = group.instance,
            difficulty = difficulty.id,
        }

        item.percent = ns.Sim.Percent(loot.id, level)
        if not item.percent then
            if level and best then item.levelDelta = level - best end
            if weights and worn and worn.link and loot.link then
                local gain = ns.Weights.Score(loot.link, weights)
                    - ns.Weights.Score(worn.link, weights)
                if gain ~= 0 then item.gain = math.floor(gain + 0.5) end
            end
        end

        table.insert(items, item)
    end

    -- Tri dans l'ordre de ce qu'on SAIT : mesure d'abord, puis estime, puis l'ecart de
    -- niveau. Deux unites ne se comparent jamais entre elles.
    local function rank(item)
        if item.percent then return 1 end
        if item.gain then return 2 end
        if item.levelDelta then return 3 end
        return 4
    end
    table.sort(items, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return (a.percent or a.gain or a.levelDelta or 0)
            > (b.percent or b.gain or b.levelDelta or 0)
    end)

    group.items = items
    return items
end

function RaidView.Refresh()
    if not view then return end
    resetPools()

    view.intro:SetWidth(math.max(200, (view:GetWidth() or 600) - 8))

    -- Le droptimizer d'abord quand il existe : il MESURE. A defaut, le journal, qui dit
    -- au moins ce qui tombe et a quel niveau.
    local groups = ns.Sim.ByEncounter() or journalGroups()
    view.difficulty:SetShown(groups ~= nil and groups[1] ~= nil and groups[1].fromJournal or false)
    view.difficulty:SetText(ns.L[DIFFICULTIES[difficultyIndex].label])

    if not groups then
        -- Etat vide, pas page noire.
        --
        -- Il n'y avait qu'une phrase en gris en haut d'un onglet entierement vide, ce qui
        -- se lit comme un addon casse plutot que comme « il te manque une etape ». On dit
        -- ce que l'onglet FERA, et comment y arriver, la ou le regard tombe.
        view.intro:SetText("")
        view.lootTitle:SetText("")
        view.lootNote:SetText("")
        view.list:SetHeight(1)
        view.content:SetHeight(1)

        view.empty:Show()
        view.emptyTitle:SetText(hex("text")
            .. L["No droptimizer imported yet."] .. "|r")
        -- On dit la VERITE : coller un lien dans l'addon n'importe rien. WoW interdit
        -- toute requete reseau a un addon, donc les gains par objet ne peuvent venir que
        -- d'un fichier ecrit hors du jeu. L'ancien texte promettait un remplissage
        -- automatique — c'etait faux, et c'est ce qui a fait chercher un bug inexistant.
        view.emptyBody:SetText(hex("muted") .. L["This tab lists the loot each boss can drop for you, ranked by the gain your own simulation measured."] .. "|r")
        view.emptyHow:SetText(string.format("%s%s|r
|cff8b6bff%s|r
%s%s|r",
            hex("text"), L["An addon cannot download anything. Import the report on your PC:"],
            "specanalyser raidbots <lien du rapport> --to-addon",
            hex("muted"), L["then /reload in game."]))
        return
    end
    view.empty:Hide()

    view.intro:SetText(hex("muted") .. (groups[1].fromJournal
        and L["Loot tables read from the adventure guide, filtered to your spec. Import a droptimizer to replace the estimates with measured gains."]
        or L["Each boss shows the items your droptimizer actually simulated, best gain first."]) .. "|r")

    -- Selection persistante d'un affichage a l'autre, et repli sur la rencontre la plus
    -- payante quand la precedente a disparu du releve.
    local chosen
    for _, group in ipairs(groups) do
        if group.encounter == selected then chosen = group end
    end
    chosen = chosen or groups[1]
    selected = chosen.encounter

    -- ------------------------------------------------------ volet des rencontres
    local top = 0
    local instanceShown = {}

    for _, group in ipairs(groups) do
        local instanceName = ns.Sim.InstanceName(group.instance)
        if instanceName and not instanceShown[group.instance] then
            instanceShown[group.instance] = true
            local title = acquire("header")
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", 4, top - 4)
            title:SetText(hex("link") .. instanceName:upper() .. "|r")
            top = top - 22
        end

        local button = acquire("boss")
        button:SetParent(view.list)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, top)

        local active = group.encounter == selected
        -- Selection par teinte d'accent, pas par un blanc code en dur : invisible sur
        -- le cadre clair du client.
        if active then
            ns.Theme.ApplyCard(button, ns.Theme.RGB.link)
        else
            ns.Theme.ApplyCard(button)
        end

        button.portrait:SetTexture(bossPortrait(group.instance, group.encounter)
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.name:SetText((active and hex("link") or hex("text"))
            .. (group.name or string.format(L["encounter %d"], group.encounter)) .. "|r")
        button.count:SetText(hex("muted") .. (group.fromJournal and ""
            or string.format(L["%d items simulated"], #group.items)) .. "|r")
        button.best:SetText(group.fromJournal and ""
            or string.format("%s%+.2f%%|r", hex(tint(group.best)), group.best))

        button:SetScript("OnClick", function()
            selected = group.encounter
            RaidView.Refresh()
        end)

        top = top - BOSS_HEIGHT - 4
    end

    view.list:SetHeight(math.max(1, -top + 8))

    -- ------------------------------------------------------------ table de butin
    view.lootTitle:SetText(hex("text")
        .. (chosen.name or string.format(L["encounter %d"], chosen.encounter)) .. "|r")
    -- Le butin de la rencontre choisie, et d'elle seule.
    if chosen.fromJournal then journalLoot(chosen) end
    chosen.items = chosen.items or {}

    view.lootNote:SetText(hex("muted") .. string.format(
        chosen.fromJournal and L["%d items this boss can drop for you"]
            or L["%d items simulated by your droptimizer"],
        #chosen.items) .. "|r")

    local width = math.max(320, (view.scroll:GetWidth() or 480) - 8)
    view.content:SetWidth(width)

    local lootTop = 0
    for _, item in ipairs(chosen.items) do
        local row = acquire("loot")
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, lootTop)
        row:SetWidth(width)
        row.name:SetWidth(width - 130)
        row.slot:SetWidth(width - 130)

        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        local icon
        if getIcon then
            local ok, value = pcall(getIcon, item.id)
            if ok then icon = value end
        end
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Le lien du journal porte deja le nom colore a la qualite : quand il est la, on
        -- l'affiche tel quel plutot que de reconstruire.
        local link = ns.Sim.LootLink(item.encounter, item.id, item.difficulty, item.instance)
        if link then
            row.name:SetText(link)
        else
            row.name:SetText(ns.ItemInfo.ColoredName(item.id)
                or (hex("muted") .. "item:" .. item.id .. "|r"))
        end

        local detail = {}
        if item.slot and item.slot ~= "" then table.insert(detail, item.slot) end
        if item.ilvl and item.ilvl > 0 then table.insert(detail, "ilvl " .. item.ilvl) end
        row.slot:SetText(hex("muted") .. table.concat(detail, "  ·  ") .. "|r")

        -- Une colonne, TROIS unites possibles, jamais melangees et toujours ecrites.
        -- Un « +1,24 % » mesure par une simulation et un « +14 ilvl » lu sur le journal
        -- ne se comparent pas ; les afficher sans suffixe laisserait croire que si.
        if item.percent then
            row.value:SetText(string.format("%s%+.2f%%|r", hex(tint(item.percent)), item.percent))
        elseif item.gain then
            row.value:SetText(string.format("%s%+d|r|cff5A5A5A pts|r",
                hex(item.gain > 0 and "good" or "muted"), item.gain))
        elseif item.levelDelta then
            row.value:SetText(string.format("%s%+d|r|cff5A5A5A ilvl|r",
                hex(item.levelDelta > 0 and "bis" or "muted"), item.levelDelta))
        else
            row.value:SetText("")
        end

        -- Au survol : l'infobulle reelle du jeu, puis ce que l'objet t'apporte. « Le besoin »
        -- est ton gain simule ; aucune donnee d'un autre joueur ne circule.
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()

            -- Le lien du journal d'abord : il porte les identifiants de bonus, donc le VRAI
            -- niveau. `SetItemByID` ne connait que le modele et affichait 44 sur une piece de
            -- raid — c'est pour ca que l'Adventure Guide, lui, avait juste.
            local link = ns.Sim.LootLink(item.encounter, item.id, item.difficulty, item.instance)
            local shown = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
            if not shown and not pcall(GameTooltip.SetItemByID, GameTooltip, item.id) then
                GameTooltip:AddLine("item:" .. item.id)
            end

            GameTooltip:AddLine(" ")
            if item.percent then
                GameTooltip:AddDoubleLine(L["simulated (% DPS)"],
                    string.format("%+.2f%%", item.percent), 0.54, 0.54, 0.54, 0, 0.9, 0.46)
            elseif item.gain then
                GameTooltip:AddDoubleLine(L["estimated (stat points)"],
                    string.format("%+d", item.gain), 0.54, 0.54, 0.54, 0, 0.9, 0.46)
            elseif item.levelDelta then
                GameTooltip:AddDoubleLine(L["ilvl vs equipped"],
                    string.format("%+d", item.levelDelta), 0.54, 0.54, 0.54, 1, 0.76, 0.03)
            end
            if item.ilvl and item.ilvl > 0 then
                GameTooltip:AddDoubleLine(L["simulated at ilvl"], tostring(item.ilvl),
                    0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
                -- L'avertissement ne sert que si l'on a du retomber sur le modele.
                if not shown then
                    GameTooltip:AddLine(L["the item level above is the base template, not the drop"],
                        0.54, 0.54, 0.54, true)
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        lootTop = lootTop - LOOT_HEIGHT - 2
    end

    view.content:SetHeight(math.max(1, -lootTop + 8))
end
