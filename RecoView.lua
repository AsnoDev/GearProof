local _, ns = ...

local RecoView = {}
ns.RecoView = RecoView

-- Onglet Recommandations : ce qu'il faut POSER.
--
-- L'onglet Équipement dit ce qui MANQUE — il le lit sur l'objet. Celui-ci dit ce que le
-- haut de tableau a posé à la place, avec la part qui le justifie.
--
-- Deux sections, sur une seule page. Il y en avait six, dans une barre latérale : quatre
-- d'entre elles n'apportaient rien. Correctifs et Bijoux redisaient l'onglet Équipement
-- avec d'autres mots, Général était de la paperasse de provenance, et Buffs au pull
-- listait des auras que personne ne peut poser depuis cette fenêtre. Une barre latérale
-- de six entrées dont quatre vides coûte de la largeur et fait chercher.
--
-- Les gemmes sont classées GLOBALEMENT, pas par emplacement. Où poser quelle gemme est
-- une décision de joueur ; ce que la mesure apporte, c'est le classement réel et le
-- nombre de châsses vides. La version par rang de châsse produisait une quarantaine de
-- lignes pour dire ce que trois disent mieux.
--
-- Règle tenue partout : chaque ligne dit d'où vient son conseil. Un « recommandé » sans
-- taux d'adoption serait un avis.

local ROW_HEIGHT = 26
local SECTION_GAP = 18
local GEM_ROW_HEIGHT = 34

local view, pools

local function hex(key)
    return ns.Theme.C(key)
end

-- ------------------------------------------------------------------- widgets

--- Ligne d'enchantement : état, emplacement, nom, barre d'adoption, part.
---
--- Colonnes à décalage FIXE, calculées depuis la largeur : un verdict qui se recale sur
--- la longueur du texte force à relire chaque ligne au lieu de balayer la colonne. Le
--- nom est tronqué plutôt que de déborder sur son voisin.
local function newEnchantRow()
    local row = CreateFrame("Button", nil, view.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.state:SetPoint("LEFT", 8, 0)
    row.state:SetWidth(16)
    row.state:SetJustifyH("CENTER")

    row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.slot:SetPoint("LEFT", 30, 0)
    row.slot:SetJustifyH("LEFT")
    row.slot:SetWordWrap(false)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

--- Ligne de gemme : icône, nom, part.
local function newGemRow()
    local row = CreateFrame("Button", nil, view.content, "BackdropTemplate")
    row:SetHeight(GEM_ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 38, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.share = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.share:SetPoint("RIGHT", -10, 0)
    row.share:SetWidth(120)
    row.share:SetJustifyH("RIGHT")

    return row
end

local function newText()
    local text = view.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    return text
end

local function resetRow(row)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
end

-- --------------------------------------------------------------------- rendu

--- Pose un bloc de texte et rend le nouveau haut, HAUTEUR MESUREE.
local function text(top, width, content, font)
    local label = pools.text:Acquire()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", 2, top)
    label:SetWidth(width - 4)
    label:SetFontObject(font or "GameFontNormalSmall")
    label:SetText(content)
    return top - math.ceil(label:GetStringHeight() or 14) - 4
end

local function heading(top, width, label)
    top = top - (top < 0 and SECTION_GAP or 0)
    return text(top, width, hex("link") .. label:upper() .. "|r") - 6
end

local function adoption(share)
    return string.format(ns.L["%d%% adoption"], (share or 0) * 100 + 0.5)
end

-- ------------------------------------------------------------ enchantements

--- Un enchantement par emplacement que le relevé réclame, puis la PAIRE d'armes.
---
--- Les deux emplacements d'arme sont EXCLUS de la boucle par emplacement : ils étaient
--- listés une fois là, puis une seconde fois sous « Armes (paire) ». Une arme ne se juge
--- pas main par main — compter chaque main séparément cache l'appariement, et la
--- majorité du haut de tableau porte deux enchantements différents.
local WEAPON_SLOTS = { MainHandSlot = true, SecondaryHandSlot = true }

local function enchantRow(top, width, slotLabel, name, share, worn, tooltip)
    local row = pools.enchant:Acquire()
    row:SetParent(view.content)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, top)
    row:SetWidth(width)

    local slotWidth, barWidth, shareWidth = 96, 88, 46
    row.slot:SetWidth(slotWidth)

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", 30 + slotWidth + 8, 0)
    row.name:SetWidth(math.max(60, width - slotWidth - barWidth - shareWidth - 70))

    row.track:ClearAllPoints()
    row.track:SetPoint("RIGHT", row, "RIGHT", -(shareWidth + 12), 0)
    row.track:SetWidth(barWidth)

    row.fill:ClearAllPoints()
    row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
    row.fill:SetWidth(math.max(1, barWidth * math.min(1, share or 0)))

    -- UN canal visuel, UNE information.
    --
    -- La barre encodait deux choses a la fois : sa longueur disait l'adoption, sa couleur
    -- disait ton etat. On obtenait donc une barre ROUGE a 95 % d'adoption — et l'oeil lit
    -- « 95 %, en rouge, donc mauvais » avant de comprendre que le rouge parlait d'autre
    -- chose. Rouge veut dire « probleme » partout ailleurs dans cet addon.
    --
    -- Desormais : la barre ne dit QUE l'adoption, dans la teinte d'accent, toujours la
    -- meme. Ton etat vit dans la colonne de marqueurs a gauche, qui se balaie
    -- verticalement — ce qu'une couleur de barre ne permet pas.
    row.state:SetText(hex(worn and "good" or "critical") .. (worn and "+" or "!") .. "|r")
    row.slot:SetText(slotLabel)
    row.name:SetText((worn and hex("text") or hex("critical")) .. name .. "|r")
    row.fill:SetColorTexture(unpack(ns.Theme.RGB.link))
    row.share:SetText(string.format("%d%%", (share or 0) * 100 + 0.5))

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

local function layoutEnchants(top, width)
    local _, summary = ns.Gear.Scan()
    local bySlot = summary.bySlot or {}

    top = heading(top, width, ns.L["Enchants"])
    local shown = 0

    for _, definition in ipairs(ns.Gear.SLOTS) do
        if not WEAPON_SLOTS[definition.slot] then
            local expected, known = ns.Meta.ExpectsEnchant(definition.slot)
            if known and expected then
                local entry = bySlot[definition.slot]
                local enchantID, share = ns.Meta.Enchant(definition.slot)
                local name = enchantID and entry
                    and ns.Meta.EnchantName(entry.link, enchantID)
                local worn = entry and (entry.enchantID or 0) > 0

                top = enchantRow(top, width, ns.L[definition.label],
                    name or (enchantID and ("enchant #" .. enchantID)) or ns.L["no measure"],
                    share, worn,
                    (enchantID and entry) and function(tooltip)
                        tooltip:AddLine(name or ("enchant #" .. enchantID), 0, 0.9, 0.46)
                        local points, lines = ns.Gear.EnchantPoints(entry.link, definition.slot, enchantID)
                        for _, item in ipairs(lines or {}) do
                            tooltip:AddLine(item.text, item.r, item.g, item.b, true)
                        end
                        if points > 0 then
                            tooltip:AddLine(string.format(ns.L["%d stat points"], points),
                                0.54, 0.54, 0.54)
                        end
                    end or nil)
                shown = shown + 1
            end
        end
    end

    local pairs_ = ns.Meta.WeaponPairs()
    if pairs_ and pairs_[1] then
        local best = pairs_[1]
        local main, off = bySlot.MainHandSlot, bySlot.SecondaryHandSlot
        local ok = ns.Meta.WeaponPairAdvice(main and main.enchantID, off and off.enchantID)

        local names = {}
        for _, id in ipairs(best.ids or {}) do
            table.insert(names, (main and ns.Meta.EnchantName(main.link, id)) or ("#" .. id))
        end

        top = enchantRow(top, width, ns.L["Weapons (pair)"],
            table.concat(names, "  +  "), best.share, ok and true or false)

        local mixed = 0
        for _, entry in ipairs(pairs_) do
            local ids = entry.ids or {}
            if #ids > 1 and ids[1] ~= ids[2] then mixed = mixed + (entry.share or 0) end
        end
        if mixed > 0 then
            top = text(top - 2, width, hex("muted") .. string.format(
                ns.L["%d%% of the top players run two DIFFERENT weapon enchants"],
                mixed * 100 + 0.5) .. "|r")
        end
        shown = shown + 1
    end

    if shown == 0 then
        top = text(top, width, hex("muted") .. ns.L["no top-build reference for this spec yet"] .. "|r")
    end
    return top
end

-- -------------------------------------------------------------------- gemmes

local function layoutGems(top, width)
    top = heading(top, width, ns.L["Gems"])

    local ranking = ns.Meta.GemRanking()
    if not ranking then
        return text(top, width, hex("muted") .. ns.L["No gem recorded yet."] .. "|r")
    end

    for index = 1, math.min(5, #ranking) do
        local gem = ranking[index]
        local row = pools.gem:Acquire()
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, top)
        row:SetWidth(width)
        ns.Theme.ApplyCard(row, index == 1 and ns.Theme.RGB.link or nil)

        local icon
        local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        if getIcon then
            local ok, value = pcall(getIcon, gem.id)
            if ok then icon = value end
        end
        row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Gem_Variety_01")

        row.name:SetWidth(math.max(80, width - 180))
        row.name:SetText(hex("text") .. (ns.Meta.GemName(gem.id) or ("#" .. gem.id)) .. "|r")
        row.share:SetText(string.format("%s%s|r", hex(index == 1 and "link" or "muted"),
            adoption(gem.share)))

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if not pcall(GameTooltip.SetItemByID, GameTooltip, gem.id) then
                GameTooltip:AddLine("item:" .. gem.id)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        top = top - GEM_ROW_HEIGHT - 4
    end

    top = text(top - 2, width, hex("muted")
        .. string.format(ns.L["measured on %d top players"], ns.Meta.Sample()) .. "|r")

    -- Le seul detail par emplacement qui merite d'etre garde : ou il MANQUE une gemme.
    -- Le reste — quelle gemme dans quelle chasse — appartient au joueur.
    local entries, summary = ns.Gear.Scan()
    if (summary.emptySockets or 0) > 0 then
        local slots = {}
        for _, entry in ipairs(entries) do
            if (entry.emptySockets or 0) > 0 then
                table.insert(slots, ns.L[entry.label])
            end
        end
        top = text(top - 6, width, string.format("%s%s|r  %s",
            hex("bis"),
            string.format(ns.L["%d empty socket(s)"], summary.emptySockets),
            hex("muted") .. table.concat(slots, ", ") .. "|r"))
    end

    return top
end

-- ------------------------------------------------------------------- public

function RecoView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 2, -2)
    view.intro:SetJustifyH("LEFT")
    ns.Localize(view.intro,
        "What the top players of your spec actually put on. Each line says where its advice comes from.")

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", 0, -26)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(600, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    pools = {
        enchant = ns.Pool.New(newEnchantRow, resetRow),
        gem = ns.Pool.New(newGemRow, resetRow),
        text = ns.Pool.New(newText),
    }

    return view
end

function RecoView.Refresh()
    if not view then return end
    ns.Pool.ResetAll(pools)

    view.intro:SetWidth(math.max(200, (view:GetWidth() or 600) - 8))

    -- La colonne se limite a 620 px meme dans une fenetre large : une ligne de texte de
    -- 900 px de long ne se lit pas, elle se balaie.
    local available = math.max(360, (view.scroll:GetWidth() or 700) - 8)
    local width = math.min(620, available)
    view.content:SetWidth(available)

    local top = 0
    if not ns.Meta.Available() then
        top = text(top, width, hex("muted")
            .. ns.L["no top-build reference for this spec yet"] .. "|r")
    else
        top = layoutEnchants(top, width)
        top = layoutGems(top, width)
    end

    view.content:SetHeight(math.max(1, -top + 12))
end
