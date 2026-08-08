local _, ns = ...

local RecoView = {}
ns.RecoView = RecoView

-- Onglet Recommandations : ce qu'il faut POSER, par catégorie.
--
-- L'onglet Équipement dit ce qui MANQUE — il le lit sur l'objet. Celui-ci dit ce que le
-- haut de tableau a posé à la place, avec la part qui le justifie. Les deux questions
-- sont différentes et ne tiennent pas dans la même colonne.
--
-- Cet onglet a existé, a été supprimé, et ses fonctionnalités n'ont pas été migrées :
-- les auras au pull, les tertiaires, les gemmes par rang de châsse et la détection de
-- builds bimodaux étaient toujours générées et livrées pour les 40 spés, et lues par
-- personne. Il est reconstruit ici.
--
-- Règle tenue partout, comme dans le reste de l'addon : chaque ligne dit d'où vient son
-- conseil. Un « recommandé » sans taux d'adoption serait un avis.

local SIDEBAR_WIDTH = 150
local ROW_HEIGHT = 24
local HEADER_HEIGHT = 26

local CATEGORIES = {
    { key = "enchants", label = "Enchants" },
    { key = "gems",     label = "Gems" },
    { key = "trinkets", label = "Trinkets" },
    { key = "fixes",    label = "Fixes" },
    { key = "buffs",    label = "Buffs at pull" },
    { key = "general",  label = "General" },
}

local view, pools, category

local function hex(key)
    return ns.Theme.C(key)
end

-- ------------------------------------------------------------------- widgets

--- Ligne à trois colonnes à décalage FIXE.
---
--- Les colonnes ne se recalent pas sur la longueur du texte : un verdict qui danse d'une
--- ligne à l'autre force à relire chaque ligne au lieu de balayer la colonne.
local function newRow()
    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetJustifyH("LEFT")
    row.value:SetWordWrap(false)

    -- La provenance, systématiquement à droite : c'est ce qui transforme un avis en
    -- mesure, et elle doit être lisible sans traverser la ligne.
    row.source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.source:SetJustifyH("RIGHT")

    return row
end

local function newHeading()
    local text = view.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    return text
end

local function resetRow(row)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    row.label:SetText("")
    row.value:SetText("")
    row.source:SetText("")
end

-- ------------------------------------------------------------------- rendu

local layout

--- Pose une ligne. `source` peut être nil : la colonne reste vide plutôt que meublée.
local function line(top, width, label, value, source, tooltip)
    local row = pools.row:Acquire()
    row:SetParent(view.content)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, top)
    row:SetWidth(width)

    local labelWidth = math.floor(width * 0.28)
    local sourceWidth = math.floor(width * 0.24)

    row.label:SetWidth(labelWidth)
    row.value:ClearAllPoints()
    row.value:SetPoint("LEFT", labelWidth + 12, 0)
    row.value:SetWidth(width - labelWidth - sourceWidth - 24)
    row.source:ClearAllPoints()
    row.source:SetPoint("RIGHT", -8, 0)
    row.source:SetWidth(sourceWidth)

    row.label:SetText(hex("text") .. label .. "|r")
    row.value:SetText(value or "")
    row.source:SetText(source and (hex("muted") .. source .. "|r") or "")

    if tooltip then
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            tooltip(GameTooltip)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return top - ROW_HEIGHT
end

local function heading(top, width, text)
    local label = pools.heading:Acquire()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", 8, top - 8)
    label:SetWidth(width - 16)
    label:SetText(hex("link") .. text:upper() .. "|r")
    return top - HEADER_HEIGHT
end

local function note(top, width, text)
    local label = pools.heading:Acquire()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", 8, top - 4)
    label:SetWidth(width - 16)
    label:SetText(hex("muted") .. text .. "|r")
    return top - 22
end

local function adoption(share)
    return string.format(ns.L["%d%% adoption"], (share or 0) * 100 + 0.5)
end

-- --------------------------------------------------------------- catégories

--- Enchantements : un par emplacement que le relevé réclame, puis la PAIRE d'armes.
local function layoutEnchants(top, width)
    local _, summary = ns.Gear.Scan()
    local bySlot = summary.bySlot or {}
    local shown = 0

    for _, definition in ipairs(ns.Gear.SLOTS) do
        local expected, known = ns.Meta.ExpectsEnchant(definition.slot)
        if known and expected then
            local entry = bySlot[definition.slot]
            local enchantID, share = ns.Meta.Enchant(definition.slot)
            local name = enchantID and entry
                and ns.Meta.EnchantName(entry.link, enchantID)

            local worn = entry and (entry.enchantID or 0) > 0
            local value = string.format("%s%s|r", worn and hex("good") or hex("critical"),
                name or (enchantID and ("enchant #" .. enchantID)) or ns.L["no measure"])

            top = line(top, width, ns.L[definition.label], value, adoption(share),
                enchantID and entry and function(tooltip)
                    tooltip:AddLine(name or ("enchant #" .. enchantID), 0, 0.9, 0.46)
                    local points, lines = ns.Gear.EnchantPoints(entry.link, definition.slot, enchantID)
                    for _, item in ipairs(lines or {}) do
                        tooltip:AddLine(item.text, item.r, item.g, item.b, true)
                    end
                    if points > 0 then
                        tooltip:AddLine(string.format(ns.L["%d stat points"], points), 0.54, 0.54, 0.54)
                    end
                    tooltip:AddLine(worn and ns.L["as measured"] or ns.L["Missing"],
                        0.54, 0.54, 0.54)
                end or nil)
            shown = shown + 1
        end
    end

    -- Les armes se lisent en PAIRE, jamais main par main : compter chaque main
    -- séparément cache l'appariement, et la majorité du haut de tableau porte deux
    -- enchantements différents.
    local pairs_ = ns.Meta.WeaponPairs()
    if pairs_ and pairs_[1] then
        local best = pairs_[1]
        local main, off = bySlot.MainHandSlot, bySlot.SecondaryHandSlot
        local ok = ns.Meta.WeaponPairAdvice(main and main.enchantID, off and off.enchantID)

        local names = {}
        for _, id in ipairs(best.ids or {}) do
            table.insert(names, (main and ns.Meta.EnchantName(main.link, id)) or ("#" .. id))
        end

        top = heading(top, width, ns.L["Weapons (pair)"])
        top = line(top, width, ns.L["Weapon"],
            string.format("%s%s|r", ok and hex("good") or hex("bis"),
                table.concat(names, "  +  ")),
            adoption(best.share))

        local mixed = 0
        for _, entry in ipairs(pairs_) do
            local ids = entry.ids or {}
            if #ids > 1 and ids[1] ~= ids[2] then mixed = mixed + (entry.share or 0) end
        end
        if mixed > 0 then
            top = note(top, width, string.format(
                ns.L["%d%% of the top players run two DIFFERENT weapon enchants"], mixed * 100 + 0.5))
        end
        shown = shown + 1
    end

    if shown == 0 then
        top = note(top, width, ns.L["no top-build reference for this spec yet"])
    end
    return top
end

--- Gemmes, par emplacement ET par RANG de châsse.
--- Le rang, pas la couleur : la couleur de la châsse n'est pas dans les données relevées.
local function layoutGems(top, width)
    local _, summary = ns.Gear.Scan()
    local bySlot = summary.bySlot or {}
    local shown = 0

    for _, definition in ipairs(ns.Gear.SLOTS) do
        local sockets = ns.Meta.SocketGems(definition.slot)
        local entry = bySlot[definition.slot]
        if sockets and entry then
            for rank = 1, 4 do
                local list = sockets[rank]
                local best = list and list[1]
                if best then
                    local worn = entry.gemIDs and entry.gemIDs[rank]
                    local name = ns.Meta.GemName(best.id) or ("#" .. best.id)
                    local matches = worn == best.id

                    local state
                    if not worn then
                        state = hex("critical") .. "! " .. name .. "|r"
                    elseif matches then
                        state = hex("good") .. "+ " .. name .. "|r"
                    else
                        state = hex("muted") .. "~ "
                            .. (ns.Meta.GemName(worn) or ("#" .. worn)) .. "|r"
                    end

                    top = line(top,  width,
                        string.format("%s  %s %d", ns.L[definition.label], ns.L["socket"], rank),
                        state, adoption(best.share))
                    shown = shown + 1
                end
            end
        end
    end

    if shown == 0 then
        top = note(top, width, ns.L["No socket was measured for this spec."])
    else
        top = note(top, width, string.format("%s+|r %s   %s~|r %s   %s!|r %s",
            hex("good"), ns.L["as measured"],
            hex("muted"), ns.L["different"],
            hex("critical"), ns.L["empty"]))
    end
    return top
end

--- Bijoux : le gain simulé, ou « non chiffré » avec la raison. Aucune tier list.
local function layoutTrinkets(top, width)
    local _, summary = ns.Gear.Scan()
    local bySlot = summary.bySlot or {}
    local shown = 0

    for _, slot in ipairs({ "Trinket0Slot", "Trinket1Slot" }) do
        local entry = bySlot[slot]
        if entry and entry.link then
            local simulated = ns.Sim.Percent(entry.itemID, entry.itemLevel)
            local value, source
            if simulated then
                value = string.format("%s%+.2f%% DPS|r", hex("good"), simulated)
                source = ns.L["measured by your droptimizer"]
            else
                -- Un bijou vaut son proc, pas ses points de statistique. Le classer
                -- serait inventer : on dit qu'on ne sait pas, et pourquoi.
                value = hex("bis") .. ns.L["unrated"] .. "|r"
                source = ns.L["import a droptimizer that covers it"]
            end
            top = line(top, width, entry.link, value, source)
            shown = shown + 1
        end
    end

    if shown == 0 then
        top = note(top, width, ns.L["empty slot"])
    end
    return top
end

--- Correctifs : le compte par type, et les points récupérables quand ils sont mesurables.
local function layoutFixes(top, width)
    local _, summary = ns.Gear.Scan()

    local rows = {
        { ns.L["missing enchant"], summary.missingEnchants },
        { ns.L["empty socket"], summary.emptySockets },
        { ns.L["empty slot"], summary.emptySlots },
        { ns.L["durability"], summary.damaged },
        { ns.L["weapon enchant combination"], summary.weaponPair },
    }

    for _, item in ipairs(rows) do
        local count = item[2] or 0
        top = line(top, width, item[1],
            string.format("%s%d|r", count > 0 and hex("bis") or hex("muted"), count))
    end

    local stat, measured, fixes = ns.Gear.Recoverable()
    top = heading(top, width, ns.L["Recoverable"])
    if fixes == 0 then
        top = line(top, width, ns.L["Nothing to fix"], hex("good") .. ns.L["Gear complete"] .. "|r")
    elseif stat > 0 then
        -- `≥` quand tous les correctifs ne sont pas chiffrables : le total est un
        -- plancher mesure, pas une estimation.
        local prefix = measured < fixes and "≥ " or ""
        top = line(top, width, ns.L["stat"],
            string.format("%s%s%s|r", hex("bis"), prefix,
                BreakUpLargeNumbers and BreakUpLargeNumbers(stat) or tostring(stat)),
            string.format(ns.L["measured on %d of %d fixes"], measured, fixes))
    else
        top = line(top, width, ns.L["to fix"], string.format("%s%d|r", hex("bis"), fixes))
    end

    return top
end

--- Auras portées au pull.
---
--- Ce sont des BUFFS, pas des consommables : rien dans la source ne distingue un flacon
--- d'une Intelligence arcanique. On liste ce qui est mesuré et le titre le dit.
local function layoutBuffs(top, width)
    local list, sample = ns.Meta.Auras()
    if not list then
        top = note(top, width, ns.L["no top-build reference for this spec yet"])
        return top
    end

    for index = 1, math.min(14, #list) do
        local aura = list[index]
        local name
        if C_Spell and C_Spell.GetSpellName then
            local ok, value = pcall(C_Spell.GetSpellName, aura.id)
            if ok then name = value end
        end

        top = line(top, width, name or ("spell #" .. aura.id),
            string.format("%s%d / %d|r",
                (aura.share or 0) >= 0.9 and hex("good") or hex("text"),
                aura.count or 0, sample),
            adoption(aura.share),
            function(tooltip)
                if not pcall(tooltip.SetSpellByID, tooltip, aura.id) then
                    tooltip:AddLine(name or ("spell #" .. aura.id))
                end
            end)
    end

    top = note(top, width, string.format(ns.L["measured on %d top players"], sample))
    return top
end

--- Général : provenance complète, et les deux écoles quand le relevé en détecte.
local function layoutGeneral(top, width)
    top = heading(top, width, ns.L["Specialisation"])
    top = line(top, width, ns.L["Specialisation"],
        hex("text") .. (ns.Spec.Name(ns.Spec.Selected()) or "?") .. "|r",
        ns.Spec.IsPreview() and ns.L["preview, not your active spec"] or nil)
    top = line(top, width, ns.L["Sample"],
        string.format("%s%d|r", hex("text"), ns.Meta.Sample()),
        ns.L["top players measured"])

    local fights = ns.Meta.Fights()
    if #fights > 0 then
        top = line(top, width, ns.L["Raid"], hex("text") .. table.concat(fights, ", ") .. "|r")
    end

    local age = ns.Meta.AgeInDays()
    if age then
        top = line(top, width, ns.L["Reference"],
            string.format("%s%s|r", age >= 14 and hex("bis") or hex("muted"),
                string.format(ns.L["reference measured %d day(s) ago"], age)))
    end

    -- Deux écoles, quand le relevé en détecte.
    --
    -- C'est le seul endroit de l'addon où l'on peut dire « la moyenne ne décrit
    -- personne ». Une spé dont la maîtrise se joue soit à 21 % soit à 38 % n'a pas de
    -- cible à 27 % : viser la moyenne, c'est ne jouer aucun des deux builds.
    local modes = ns.Meta.Modes()
    if modes then
        top = heading(top, width, ns.L["Two builds measured"])
        top = note(top, width, ns.L["The top players split into two groups on these stats. The average describes neither."])
        for _, mode in ipairs(modes) do
            local function tag(side, share, count)
                return string.format("%s%d%% (%d)|r",
                    mode.side == side and hex("good") or hex("muted"),
                    share * 100 + 0.5, count)
            end
            top = line(top, width, ns.L[mode.label],
                string.format("%s   %s%s|r   %s",
                    tag("low", mode.low, mode.lowN), hex("muted"), "·",
                    tag("high", mode.high, mode.highN)),
                mode.side and ns.L["you are here"] or nil)
        end
    end

    local tertiary = ns.Meta.Tertiary()
    if tertiary then
        top = heading(top, width, ns.L["Tertiary (top average)"])
        for _, key in ipairs({ "avoidance", "leech", "speed" }) do
            if tertiary[key] then
                top = line(top, width, key,
                    string.format("%s%d|r", hex("text"), tertiary[key]))
            end
        end
    end

    top = heading(top, width, ns.L["Stat weights"])
    local description = ns.Weights.Describe()
    top = line(top, width, ns.L["Stat weights"], hex("text") .. description .. "|r")

    local reportAge = ns.SimC.DroptimizerAge()
    top = line(top, width, ns.L["Droptimizer"],
        reportAge and string.format("%s%s|r", reportAge >= 7 and hex("bis") or hex("good"),
            string.format(ns.L["%d day(s) old"], reportAge))
        or (hex("muted") .. ns.L["none"] .. "|r"))

    top = note(top, width, ns.L["Every line says where its advice comes from. A verdict without an adoption rate would be an opinion; with one it is a measurement."])
    return top
end

layout = {
    enchants = layoutEnchants,
    gems = layoutGems,
    trinkets = layoutTrinkets,
    fixes = layoutFixes,
    buffs = layoutBuffs,
    general = layoutGeneral,
}

-- ------------------------------------------------------------------- public

function RecoView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)
    category = category or "enchants"

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 2, -2)
    view.intro:SetJustifyH("LEFT")
    ns.Localize(view.intro,
        "What the top players of your spec actually put on. Each line says where its advice comes from.")

    -- Barre latérale de catégories. Boutons plats maison : la fenêtre a déjà une rangée
    -- d'onglets, en empiler une seconde brouillerait la hiérarchie.
    view.buttons = {}
    for index, definition in ipairs(CATEGORIES) do
        local button = CreateFrame("Button", nil, view, "BackdropTemplate")
        button:SetSize(SIDEBAR_WIDTH - 8, 26)
        button:SetPoint("TOPLEFT", 0, -30 - (index - 1) * 30)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetPoint("LEFT", 10, 0)
        button.text:SetJustifyH("LEFT")
        button.key = definition.key
        button.label = definition.label
        button:SetScript("OnClick", function(self)
            category = self.key
            RecoView.Refresh()
        end)
        view.buttons[index] = button
    end

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", SIDEBAR_WIDTH + 8, -30)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(600, 1)
    view.scroll:SetScrollChild(view.content)

    pools = {
        row = ns.Pool.New(newRow, resetRow),
        heading = ns.Pool.New(newHeading),
    }

    return view
end

function RecoView.Refresh()
    if not view then return end
    ns.Pool.ResetAll(pools)

    view.intro:SetWidth(math.max(200, (view:GetWidth() or 600) - 8))

    for _, button in ipairs(view.buttons) do
        local active = button.key == category
        if active then
            ns.Theme.ApplyCard(button, ns.Theme.RGB.link)
        else
            ns.Theme.ApplyCard(button)
        end
        button.text:SetText((active and hex("link") or hex("text")) .. ns.L[button.label] .. "|r")
    end

    local width = math.max(420, (view.scroll:GetWidth() or 700) - 8)
    view.content:SetWidth(width)

    local top = 0
    if not ns.Meta.Available() and category ~= "fixes" and category ~= "trinkets" then
        top = note(top, width, ns.L["no top-build reference for this spec yet"])
    else
        top = (layout[category] or layoutGeneral)(top, width)
    end

    view.content:SetHeight(math.max(1, -top + 12))
end
