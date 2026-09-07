local _, ns = ...

local RecoView = {}
ns.RecoView = RecoView

-- Onglet Recommandations : ce qu'il faut POSER.
--
-- L'onglet Équipement dit ce qui MANQUE — il le lit sur l'objet. Celui-ci dit ce que le
-- haut de tableau a posé à la place, avec la part qui le justifie.
--
-- Ce qui se POSE sur une pièce, et rien d'autre : statistiques visées, enchantements,
-- gemmes. Les builds et les talents sont partis dans l'onglet Talents, les bijoux et
-- l'artisanat dans l'onglet Objets — six sections dans un seul défilement répondaient à
-- six questions différentes et n'en servaient bien aucune. Il ne reste ici qu'un
-- raccourci de quatre bijoux, parce que c'est la décision d'équipement la plus discutée.
--
-- Il y avait déjà eu six sections dans une barre latérale : quatre
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
local ITEM_ROW_HEIGHT = 34

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

--- Ligne de build : rang, part, et la repartition de stats de CE groupe.
--- Ligne de statistique : nom, fourchette du haut de tableau, et TA position dedans.
local function newStatRow()
    local row = CreateFrame("Frame", nil, view.content)
    row:SetHeight(ROW_HEIGHT)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetWidth(96)
    row.label:SetJustifyH("LEFT")

    -- Piste = l'etendue affichee. Bande = la fourchette interquartile du haut de tableau.
    -- Curseur = toi. Trois objets, trois sens, aucun ne code deux choses a la fois.
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetHeight(8)

    row.band = row:CreateTexture(nil, "ARTWORK")
    row.band:SetHeight(8)

    row.marker = row:CreateTexture(nil, "OVERLAY")
    row.marker:SetSize(2, 14)

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", -8, 0)
    row.value:SetWidth(112)
    row.value:SetJustifyH("RIGHT")

    return row
end

--- Ligne d'objet : icone, nom, une ligne de detail dessous, part a droite.
---
--- Distincte de la ligne de gemme, qui n'a pas de place pour un detail : un objet doit
--- dire OU il se porte et a quel niveau, sans quoi « Spellbreaker's Bracers » ne se
--- rattache a rien de ce que le joueur a sur lui.
local function newItemRow()
    local row = CreateFrame("Button", nil, view.content, "BackdropTemplate")
    row:SetHeight(ITEM_ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- `sub` et non `detail` : `resetRow` met `row.detail` a nil pour les lignes de build,
    -- ou c'est une DONNEE. Un widget portant le meme nom disparaitrait au recyclage.
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row.share = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.share:SetPoint("RIGHT", -10, 0)
    row.share:SetWidth(56)
    row.share:SetJustifyH("RIGHT")

    return row
end

local function newText()
    local text = view.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("LEFT")
    return text
end

local function resetRow(row)
    row.detail, row.gemID = nil, nil
    row.itemID, row.itemLevel = nil, nil
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
end

-- Gestionnaires poses UNE fois.
--
-- Chaque ligne d'enchantement recevait deux fermetures neuves par rendu, plus une
-- troisieme construite par l'appelant et passee en parametre pour peindre l'infobulle.
-- L'appelant passe maintenant les DONNEES (`detail`) et non plus une fonction.

local function hideTooltip()
    GameTooltip:Hide()
end

local function enchantOnEnter(self)
    local detail = self.detail
    if not detail then return end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(detail.name or ("enchant #" .. detail.enchantID), 0, 0.9, 0.46)

    local points, lines = ns.Gear.EnchantPoints(detail.link, detail.slot, detail.enchantID)
    for _, item in ipairs(lines or {}) do
        GameTooltip:AddLine(item.text, item.r, item.g, item.b, true)
    end
    if points > 0 then
        GameTooltip:AddLine(string.format(ns.L["%d stat points"], points), 0.54, 0.54, 0.54)
    end
    GameTooltip:Show()
end

local function itemOnEnter(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then
        GameTooltip:AddLine("item:" .. self.itemID)
    end
    -- Le niveau du releve, pas celui du modele : le second vaut 44 sur une piece de raid,
    -- et pour un craft il ne dit pas a quelle qualite il faut le monter.
    if self.itemLevel and self.itemLevel > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(ns.L["worn at ilvl"], tostring(self.itemLevel),
            0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
    end
    GameTooltip:Show()
end

local function gemOnEnter(self)
    if not self.gemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.gemID) then
        GameTooltip:AddLine("item:" .. self.gemID)
    end
    GameTooltip:Show()
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


-- ------------------------------------------------------------------- stats

--- Priorite des statistiques, avec la FOURCHETTE et non un seul chiffre.
---
--- `p25`, `p75` et `spread` etaient generes depuis toujours et jamais lus. C'est pourtant
--- ce qui distingue une cible d'un intervalle : « critique 55 %, ecart 8 points » veut
--- dire serre, donc vise ; « ecart 30 » veut dire que le haut de tableau ne s'accorde pas,
--- donc ne t'en fais pas. Une priorite sans dispersion se lit comme un ordre alors que
--- c'est parfois une fourchette.
local function layoutStats(top, width)
    local priority = ns.Meta.StatPriority()
    if not priority then return top end

    top = heading(top, width, ns.L["Secondary stats"])

    local mine = ns.Stats.Current() or {}
    local total = 0
    for _, definition in ipairs(ns.Stats.LIST) do
        total = total + ((mine[definition.key] or {}).rating or 0)
    end

    -- Echelle COMMUNE aux quatre lignes. Une echelle par ligne rendrait les barres
    -- incomparables entre elles, ce qui est precisement ce qu'on vient lire.
    local scale = 0.05
    for _, entry in ipairs(priority) do
        local _, p75 = ns.Meta.StatRange(entry.key)
        scale = math.max(scale, entry.share or 0, p75 or 0,
            total > 0 and (((mine[entry.key] or {}).rating or 0) / total) or 0)
    end
    scale = math.min(1, scale * 1.15)

    local LABEL, VALUE = 96, 112
    local trackWidth = math.max(80, width - LABEL - VALUE - 30)

    for _, entry in ipairs(priority) do
        local row = pools.stat:Acquire()
        row:SetParent(view.content)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, top)
        row:SetWidth(width)

        row.label:SetText(hex("text") .. ns.L[entry.label] .. "|r")

        row.track:ClearAllPoints()
        row.track:SetPoint("LEFT", LABEL + 12, 0)
        row.track:SetWidth(trackWidth)
        row.track:SetColorTexture(0.14, 0.14, 0.16, 1)

        local p25, p75, spread = ns.Meta.StatRange(entry.key)
        local low = (p25 or entry.share or 0) / scale
        local high = (p75 or entry.share or 0) / scale
        row.band:ClearAllPoints()
        row.band:SetPoint("LEFT", row.track, "LEFT", trackWidth * low, 0)
        row.band:SetWidth(math.max(2, trackWidth * math.max(0, high - low)))
        row.band:SetColorTexture(unpack(ns.Theme.RGB.link))

        local share = total > 0 and (((mine[entry.key] or {}).rating or 0) / total) or nil
        if share then
            row.marker:ClearAllPoints()
            row.marker:SetPoint("LEFT", row.track, "LEFT",
                math.min(trackWidth, trackWidth * (share / scale)), 0)
            row.marker:SetColorTexture(1, 1, 1, 0.95)
            row.marker:Show()
        else
            row.marker:Hide()
        end

        -- La colonne de droite dit la MEME chose en chiffres : la fourchette relevee, et
        -- toi. Un lecteur qui ne decode pas la barre lit la ligne.
        if p25 and p75 then
            row.value:SetText(string.format("%s%d–%d%%|r%s",
                hex("muted"), p25 * 100 + 0.5, p75 * 100 + 0.5,
                share and string.format("   %s%d%%|r", hex("text"), share * 100 + 0.5) or ""))
        else
            row.value:SetText(string.format("%s%d%%|r", hex("muted"),
                (entry.share or 0) * 100 + 0.5))
        end

        row:Show()
        top = top - ROW_HEIGHT
    end

    -- Une seule phrase de lecture, sous les quatre lignes, jamais repetee par ligne.
    top = text(top - 4, width, hex("muted")
        .. ns.L["The band is where the top players sit, the mark is you. A wide band means the choice is open."] .. "|r")
    return top
end

-- ------------------------------------------------------------ enchantements

--- Un enchantement par emplacement que le relevé réclame, puis la PAIRE d'armes.
---
--- Les deux emplacements d'arme sont EXCLUS de la boucle par emplacement : ils étaient
--- listés une fois là, puis une seconde fois sous « Armes (paire) ». Une arme ne se juge
--- pas main par main — compter chaque main séparément cache l'appariement, et la
--- majorité du haut de tableau porte deux enchantements différents.
local WEAPON_SLOTS = { MainHandSlot = true, SecondaryHandSlot = true }

--- @param detail table|nil  { link, slot, enchantID, name } — de quoi rendre l'infobulle
local function enchantRow(top, width, slotLabel, name, share, worn, detail)
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

    row.detail = detail
    if detail then
        row:SetScript("OnEnter", enchantOnEnter)
        row:SetScript("OnLeave", hideTooltip)
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
                    (enchantID and entry) and {
                        link = entry.link,
                        slot = definition.slot,
                        enchantID = enchantID,
                        name = name,
                    } or nil)
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
        -- Le chiffre nu, comme sur les lignes d'enchantement juste au-dessus. Le mot
        -- « adoption » etait repete a chaque ligne pour dire ce que l'entete dit deja.
        row.share:SetText(string.format("%s%d%%|r", hex(index == 1 and "link" or "muted"),
            (gem.share or 0) * 100 + 0.5))

        row.gemID = gem.id
        row:SetScript("OnEnter", gemOnEnter)
        row:SetScript("OnLeave", hideTooltip)

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

-- ------------------------------------------------------------- bijoux, en bref

--- QUATRE bijoux, pas un de plus : deux du raid, deux des donjons.
---
--- La page Objets porte les listes completes. Ici on ne garde qu'un raccourci, et il est
--- volontairement court — cet onglet dit ce qui se POSE sur une piece, et une liste de
--- douze bijoux au milieu des enchantements ramenait exactement le fouillis qu'on vient
--- de defaire. Deux et deux, parce qu'un joueur a deux emplacements et deux contenus.
local SHORTLIST = 2

local function layoutTrinkets(top, width)
    local raid, dungeon = ns.Meta.TrinketsBySource(SHORTLIST)
    if #raid == 0 and #dungeon == 0 then return top end

    top = heading(top, width, ns.L["Trinkets"])

    local function line(label, rows)
        if #rows == 0 then return end
        for index, item in ipairs(rows) do
            local row = pools.item:Acquire()
            row:SetParent(view.content)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, top)
            row:SetWidth(width)
            ns.Theme.ApplyCard(row, index == 1 and ns.Theme.RGB.link or nil)

            local icon
            local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
            if getIcon then
                local ok, value = pcall(getIcon, item.id)
                if ok then icon = value end
            end
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            local name = ns.Meta.GemName(item.id) or item.name
            row.name:SetWidth(math.max(80, width - 150))
            row.name:SetText(hex("text") .. (name or ("#" .. tostring(item.id))) .. "|r")

            -- La PROVENANCE plutot que l'emplacement : un bijou se porte toujours au meme
            -- endroit, et c'est justement d'ou il tombe qui decide si le joueur peut
            -- l'avoir.
            row.sub:SetWidth(math.max(60, width - 150))
            row.sub:SetText(hex("muted") .. label .. "|r")

            row.share:SetText(string.format("%s%d%%|r",
                hex(index == 1 and "link" or "muted"), (item.share or 0) * 100 + 0.5))

            row.itemID, row.itemLevel = item.id, item.ilvl
            row:SetScript("OnEnter", itemOnEnter)
            row:SetScript("OnLeave", hideTooltip)

            top = top - ITEM_ROW_HEIGHT - 4
        end
    end

    line(ns.L["Drops in the raid"], raid)
    line(ns.L["Drops in Mythic+ dungeons"], dungeon)

    return text(top - 2, width, hex("muted")
        .. ns.L["Full lists, and the crafted gear, are on the Items tab."] .. "|r")
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
        build = ns.Pool.New(newBuildRow, resetRow),
        stat = ns.Pool.New(newStatRow),
        item = ns.Pool.New(newItemRow, resetRow),
        text = ns.Pool.New(newText),
    }

    return view
end

function RecoView.Refresh()
    if not view then return end
    ns.Pool.ResetAll(pools)

    view.intro:SetWidth(math.max(200, (view:GetWidth() or 600) - 8))

    -- SUR QUOI le releve est classe, dit en toutes lettres.
    --
    -- Le classement etait pris en degats pour TOUT LE MONDE, y compris les sept
    -- specialisations de soin : leur « top 20 » etait le top 20 par degats, une population
    -- qui ne decrit personne, et rien ne le signalait. La metrique suit maintenant le role,
    -- et la ligne le dit — un releve qui ne dit pas sur quoi il classe est un avis.
    local role = ns.Meta.Role()
    if role then
        local measured = (role == "healer") and ns.L["ranked on healing"]
            or ns.L["ranked on damage"]
        view.intro:SetText(string.format("%s%s  ·  %s|r", hex("muted"),
            string.format(ns.L["top %d of your spec"], ns.Meta.Sample()), measured))
    end

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
        -- L'ordre est celui dans lequel on decide : le build d'abord, les
        -- statistiques qu'il implique ensuite, les consommables en dernier. L'onglet
        -- s'appelait « Recommandations » et ne recommandait que des consommables.
        -- L'ordre est celui dans lequel on decide : la cible de statistiques d'abord,
        -- puis ce qu'on pose dessus. Les bijoux en dernier, en raccourci : ils
        -- s'OBTIENNENT, ils ne se posent pas, et leur place est l'onglet Objets.
        top = layoutStats(top, width)
        top = layoutEnchants(top, width)
        top = layoutGems(top, width)
        top = layoutTrinkets(top, width)
    end

    view.content:SetHeight(math.max(1, -top + 12))
end
