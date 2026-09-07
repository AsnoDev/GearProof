local _, ns = ...

local ItemsView = {}
ns.ItemsView = ItemsView

local L = ns.L

-- Onglet Objets : les BIJOUX, par provenance, et l'ARTISANAT.
--
-- Ces deux blocs vivaient dans l'onglet Recommandations, qui portait alors six sections
-- empilees dans un seul defilement. « Il faut que ce soit plus sobre » : un onglet qui
-- repond a six questions n'en repond bien a aucune. Recommandations garde ce qui se POSE
-- sur une piece — statistiques, enchantements, gemmes — plus quatre bijoux en raccourci.
-- Tout ce qui s'OBTIENT vit ici.
--
-- LA PROVENANCE, ET POURQUOI ELLE A DEMANDE UNE CORRECTION.
--
-- Le relevé publiait deux listes de bijoux : « raid + mythique+ » et « mythique+ seul ».
-- Deux POPULATIONS observees — ce que portent les joueurs vus en raid, ce que portent
-- ceux vus en donjon. Ce n'est pas la question que se pose un joueur. Un raideur porte son
-- bijou de raid en cle mythique+ : il apparaissait donc dans la liste « mythique+ » sans y
-- etre obtenable une seule seconde. Pour qui ne raide pas, c'etait le contraire d'une
-- reponse.
--
-- Ce qui compte est d'ou l'objet TOMBE. Warcraft Logs ne le dit pas ; le journal des
-- aventures du client, si. Le relevé mesure donc l'adoption, et `Meta.TrinketsBySource`
-- separe — voir `Journal.ItemSource`.

local ITEM_ROW = 34
local SECTION_GAP = 18

local view, pools

local function hex(key)
    return ns.Theme.C(key)
end

local function newItemRow()
    local row = CreateFrame("Button", nil, view.content, "BackdropTemplate")
    row:SetHeight(ITEM_ROW)
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
    local label = view.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    return label
end

local function resetRow(row)
    row.itemID, row.itemLevel = nil, nil
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
end

local function hideTooltip()
    GameTooltip:Hide()
end

local function itemOnEnter(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then
        GameTooltip:AddLine("item:" .. self.itemID)
    end
    -- Le niveau du relevé, pas celui du modele : le second vaut 44 sur une piece de raid,
    -- et pour un craft il ne dit pas a quelle qualite il faut le monter.
    if self.itemLevel and self.itemLevel > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["worn at ilvl"], tostring(self.itemLevel),
            0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
    end
    GameTooltip:Show()
end

-- --------------------------------------------------------------------- rendu

local function text(top, width, content)
    local label = pools.text:Acquire()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", 2, top)
    label:SetWidth(width - 4)
    label:SetText(content)
    return top - math.ceil(label:GetStringHeight() or 14) - 4
end

local function heading(top, width, label)
    top = top - (top < 0 and SECTION_GAP or 0)
    return text(top, width, hex("link") .. label:upper() .. "|r") - 6
end

-- Noms d'emplacement du client. Le relevé porte le nom technique de Warcraft Logs.
local SLOT_GLOBALS = {
    HeadSlot = "HEADSLOT", NeckSlot = "NECKSLOT", ShoulderSlot = "SHOULDERSLOT",
    ChestSlot = "CHESTSLOT", WaistSlot = "WAISTSLOT", LegsSlot = "LEGSSLOT",
    FeetSlot = "FEETSLOT", WristSlot = "WRISTSLOT", HandsSlot = "HANDSSLOT",
    Finger0Slot = "FINGER0SLOT", Finger1Slot = "FINGER0SLOT",
    Trinket0Slot = "TRINKET0SLOT", Trinket1Slot = "TRINKET0SLOT",
    BackSlot = "BACKSLOT", MainHandSlot = "MAINHANDSLOT",
    SecondaryHandSlot = "SECONDARYHANDSLOT",
}

--- Pose une liste d'objets relevés. Rend le nouveau haut.
--- @param showSlot boolean|nil ecrire l'emplacement — utile pour l'artisanat, qui touche
---        toute la panoplie ; inutile pour les bijoux, qui n'en occupent qu'un.
local function layoutItems(top, width, rows, showSlot)
    for index = 1, #rows do
        local item = rows[index]
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

        -- Le nom du CLIENT quand il le connait : traduit, et a jour. Celui du relevé est
        -- de l'anglais fige au moment de la generation — il ne sert que de repli.
        local name = ns.Meta.GemName(item.id) or item.name
        row.name:SetWidth(math.max(80, width - 150))
        row.name:SetText(hex("text") .. (name or ("#" .. tostring(item.id))) .. "|r")

        local parts = {}
        if showSlot then
            local key = SLOT_GLOBALS[item.slot or ""]
            local label = key and _G[key]
            if type(label) == "string" and label ~= "" then table.insert(parts, label) end
        end
        if item.ilvl and item.ilvl > 0 then
            table.insert(parts, string.format(L["ilvl %d"], item.ilvl))
        end
        row.sub:SetWidth(math.max(60, width - 150))
        row.sub:SetText(hex("muted") .. table.concat(parts, "  ·  ") .. "|r")

        row.share:SetText(string.format("%s%d%%|r", hex(index == 1 and "link" or "muted"),
            (item.share or 0) * 100 + 0.5))

        row.itemID, row.itemLevel = item.id, item.ilvl
        row:SetScript("OnEnter", itemOnEnter)
        row:SetScript("OnLeave", hideTooltip)

        top = top - ITEM_ROW - 4
    end
    return top
end

--- BIJOUX, separes par provenance.
local function layoutTrinkets(top, width)
    local all = ns.Meta.Trinkets()
    if not all then return top end

    top = heading(top, width, L["Trinkets"])
    top = text(top, width, hex("muted")
        .. L["No number ranks a trinket for a tank or a healer: a droptimizer measures damage, and Warcraft Logs has no survival ranking. This is what the top players wear."] .. "|r")

    local raid, dungeon = ns.Meta.TrinketsBySource()

    if #raid == 0 and #dungeon == 0 then
        -- Le journal des aventures charge son butin de facon asynchrone. On le DIT plutot
        -- que d'afficher une page vide qui se lit comme un addon casse — et on montre la
        -- liste non separee, qui reste vraie.
        top = text(top - 4, width, hex("bis")
            .. L["Source unknown for now: the adventure guide has not answered yet. Reopen this tab."] .. "|r")
        return layoutItems(top - 2, width, all, false)
    end

    if #raid > 0 then
        top = text(top - 4, width, hex("text") .. L["Drops in the raid"] .. "|r")
        top = layoutItems(top - 2, width, raid, false)
    end
    if #dungeon > 0 then
        top = text(top - 4, width, hex("text") .. L["Drops in Mythic+ dungeons"] .. "|r")
        top = text(top, width, hex("muted")
            .. L["Obtainable without setting foot in the raid."] .. "|r")
        top = layoutItems(top - 2, width, dungeon, false)
    end

    return text(top - 2, width, hex("muted")
        .. string.format(L["measured on %d top players"], ns.Meta.Sample()) .. "|r")
end

--- ARTISANAT : les recettes que le haut de tableau a fait faire.
local function layoutCrafts(top, width)
    local crafts = ns.Meta.Crafts()
    if not crafts then return top end

    top = heading(top, width, L["Crafted"])
    top = text(top, width, hex("muted")
        .. L["Made, not dropped. These are the recipes worth ordering."] .. "|r")
    top = layoutItems(top - 2, width, crafts, true)
    return text(top - 2, width, hex("muted")
        .. string.format(L["measured on %d top players"], ns.Meta.Sample()) .. "|r")
end

-- ------------------------------------------------------------------- public

function ItemsView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 2, -2)
    view.intro:SetJustifyH("LEFT")
    ns.Localize(view.intro,
        "What the top players of your spec obtain: which trinkets, and where they drop.")

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", 0, -26)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(600, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    pools = {
        item = ns.Pool.New(newItemRow, resetRow),
        text = ns.Pool.New(newText),
    }

    return view
end

function ItemsView.Refresh()
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
            .. L["no top-build reference for this spec yet"] .. "|r")
    else
        top = layoutTrinkets(top, width)
        top = layoutCrafts(top, width)
    end

    view.content:SetHeight(math.max(1, -top + 12))
end
