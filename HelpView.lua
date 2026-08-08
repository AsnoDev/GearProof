local _, ns = ...

local HelpView = {}
ns.HelpView = HelpView

-- Onglet Aide : trois colonnes de cartes.
--
-- Regle de mise en page : le texte n'est pose et les hauteurs ne sont calculees que dans
-- Refresh(), jamais a la creation. A la creation, la largeur des cadres n'est pas encore
-- resolue et GetStringHeight() renvoie une valeur fausse — c'est ce qui faisait deborder
-- le texte hors des cartes.

local COLUMN_GAP = 12
local CARD_GAP = 10
local PADDING = 12

local COLORS = {
    accent = { 0.55, 0.42, 1.00 },
    good   = { 0.45, 0.78, 0.62 },
    gold   = { 0.95, 0.72, 0.25 },
    warn   = { 0.89, 0.64, 0.36 },
    bad    = { 1.00, 0.42, 0.42 },
}

local L = ns.L

local view, cards

local function hex(color)
    return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

local function newCard(title)
    local card = CreateFrame("Frame", nil, view, "BackdropTemplate")
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", PADDING, -10)
    card.title:SetJustifyH("LEFT")
    card.title:SetText(title)

    card.body = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.body:SetPoint("TOPLEFT", PADDING, -30)
    card.body:SetJustifyH("LEFT")
    card.body:SetJustifyV("TOP")
    card.body:SetSpacing(3)
    card.body:SetWordWrap(true)

    return card
end

--- Pose le texte a la bonne largeur puis ajuste la hauteur de la carte.
--- `extra` reserve de la place sous le texte (boutons).
local function fill(card, columnWidth, text, extra)
    card:SetWidth(columnWidth)
    card.title:SetWidth(columnWidth - PADDING * 2)
    card.body:SetWidth(columnWidth - PADDING * 2)
    card.body:SetText(text)
    card:SetHeight(30 + card.body:GetStringHeight() + 12 + (extra or 0))
    ns.Theme.ApplyCard(card)
end

function HelpView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    cards = {
        welcome = newCard(L["Welcome"]),
        why = newCard(L["Where the reference comes from"]),
        howto = newCard(L["Keeping the reference fresh"]),
        score = newCard(L["Reading the equipment tab"]),
        faq = newCard(L["Frequent questions"]),
        support = newCard(L["Report something"]),
    }

    local support = cards.support

    support.bug = CreateFrame("Button", nil, support, "UIPanelButtonTemplate")
    support.bug:SetHeight(22)
    ns.Localize(support.bug, "Report a bug")
    support.bug:SetScript("OnClick", function()
        ns.Copy.Show(L["Bug report"], table.concat({
            "## Bug", "",
            "What I was doing:",
            "What happened:",
            "What I expected:",
            "", "## Environment", HelpView.Environment(),
        }, "\n"))
    end)

    support.idea = CreateFrame("Button", nil, support, "UIPanelButtonTemplate")
    support.idea:SetHeight(22)
    ns.Localize(support.idea, "Suggest an idea")
    support.idea:SetScript("OnClick", function()
        ns.Copy.Show(L["Suggestion"], table.concat({
            "## Idea", "",
            "What I would like:",
            "Why it would help:",
            "", "## Environment", HelpView.Environment(),
        }, "\n"))
    end)

    view.credits = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.credits:SetPoint("BOTTOMLEFT", 2, 2)
    view.credits:SetJustifyH("LEFT")
    ns.Localize(view.credits, "Reference measured from Warcraft Logs rankings, outside the game, and shipped with the addon")

    return view
end

function HelpView.Environment()
    local name = UnitName("player") or "?"
    local _, class = UnitClass("player")
    local version, build = GetBuildInfo()
    local _, equipped = GetAverageItemLevel()
    return table.concat({
        "GearProof " .. (ns.version or "?"),
        "Client " .. tostring(version) .. " (" .. tostring(build) .. ")",
        "Character: " .. name .. " — " .. tostring(class),
        "ilvl : " .. (equipped and math.floor(equipped + 0.5) or "?"),
        "Locale: " .. GetLocale(),
    }, "\n")
end

function HelpView.Refresh()
    if not view then return end

    local total = view:GetWidth()
    if not total or total < 200 then total = 640 end
    local columnWidth = math.floor((total - COLUMN_GAP * 2) / 3)

    -- Colonne 1.
    cards.welcome:ClearAllPoints()
    cards.welcome:SetPoint("TOPLEFT", 0, 0)
    fill(cards.welcome, columnWidth, table.concat({
        L["GearProof audits your gear against what the best players of your spec actually wear."],
        "",
        hex(COLORS.accent) .. L["Read live in game: enchants, gems, sockets, durability, class set."] .. "|r",
        "",
        hex(COLORS.accent) .. L["Compared to a measured reference: the top ranked players of your spec, enchant by enchant, with their adoption rate."] .. "|r",
        "",
        L["Nothing here is copied from a guide, and nothing is invented. A value that is not measured is shown as unmeasured."],
    }, "\n"))

    cards.why:ClearAllPoints()
    cards.why:SetPoint("TOPLEFT", cards.welcome, "BOTTOMLEFT", 0, -CARD_GAP)
    fill(cards.why, columnWidth, table.concat({
        L["The reference is taken from Warcraft Logs: the top 20 of your spec on the most recent encounters, and their real equipment."],
        "",
        L["The most recent encounters come first. Older ones are only used when the new ones do not have enough ranked players yet."],
        "",
        L["The reference is per spec. Pick another spec of your class in the header to see what the audit would say."],
    }, "\n"))

    -- Colonne 2.
    cards.howto:ClearAllPoints()
    cards.howto:SetPoint("TOPLEFT", cards.welcome, "TOPRIGHT", COLUMN_GAP, 0)
    -- Cette carte disait au joueur de lancer `specanalyser wcl meta --to-addon`.
    -- Personne sur CurseForge n'a cet outil : la proposition de valeur entiere etait
    -- inaccessible a 100 % du public vise. Le releve est LIVRE avec l'addon, date, et
    -- la carte decrit ce qui est reellement installe.
    local stamp = ns.Meta.Stamp() or {}
    local age = ns.Meta.AgeInDays()
    local freshness = age
        and string.format(L["Measured %d day(s) ago. A new one ships with each release."], age)
        or L["A new one ships with each release."]

    fill(cards.howto, columnWidth, table.concat({
        hex(COLORS.accent) .. L["What ships with the addon"] .. "|r",
        string.format(L["The measured reference for %d specialisations."], stamp.specs or 0),
        freshness,
        "",
        hex(COLORS.accent) .. L["What you add yourself"] .. "|r",
        L["Your own droptimizer, from raidbots.com. Copy your SimulationCraft string in the Equipment tab, run it, paste the report link back."],
        "",
        L["That is the only step that needs you. Without it the audit still works — it simply refuses to put a number on what it cannot measure."],
    }, "\n"))

    cards.score:ClearAllPoints()
    cards.score:SetPoint("TOPLEFT", cards.howto, "BOTTOMLEFT", 0, -CARD_GAP)
    fill(cards.score, columnWidth, table.concat({
        hex(COLORS.accent) .. L["The gauge"] .. "|r",
        L["It counts, it does not grade: fixes pending, and how many checked slots are clean. There is no score out of 100 — it would be four arbitrary penalties dressed up as a measurement."],
        "",
        hex(COLORS.accent) .. L["The stat bars"] .. "|r",
        L["The bar shows this stat's share of your own secondary budget, and the number on the right is the percentage from your character sheet. Hover for the points and the top-20 share."],
        "",
        hex(COLORS.accent) .. L["The priority line"] .. "|r",
        L["The order the top players actually run, with each share. Read once, not repeated on every row."],
    }, "\n"))

    -- Colonne 3.
    cards.faq:ClearAllPoints()
    cards.faq:SetPoint("TOPLEFT", cards.howto, "TOPRIGHT", COLUMN_GAP, 0)
    fill(cards.faq, columnWidth, table.concat({
        hex(COLORS.accent) .. L["Why does it not analyse my play?"] .. "|r",
        L["Since Midnight, combat events are secret values: displayable but unreadable by an addon. No addon can do it any more, so this one does not pretend to."],
        "",
        hex(COLORS.accent) .. L["Why two different weapon enchants?"] .. "|r",
        L["Because that is what the measurement says. Counting each hand separately hides the pairing: most of the top players run one of each, and the audit checks the combination, not each hand alone."],
        "",
        hex(COLORS.accent) .. L["Why is a trinket shown as unrated?"] .. "|r",
        L["A trinket is worth its proc, not its stat points. It stays unrated until one of your droptimizers covers it."],
        "",
        hex(COLORS.accent) .. L["No reference for my spec?"] .. "|r",
        L["That spec was not in the last sweep. It will be in a future release — the audit still checks what it can read on your gear."],
    }, "\n"))

    local support = cards.support
    support:ClearAllPoints()
    support:SetPoint("TOPLEFT", cards.faq, "BOTTOMLEFT", 0, -CARD_GAP)
    fill(support, columnWidth,
        L["Both buttons prepare a ready to paste text, with the technical details already filled in."],
        56)

    support.bug:ClearAllPoints()
    support.bug:SetWidth(columnWidth - PADDING * 2)
    support.bug:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", PADDING, 32)

    support.idea:ClearAllPoints()
    support.idea:SetWidth(columnWidth - PADDING * 2)
    support.idea:SetPoint("TOPLEFT", support.bug, "BOTTOMLEFT", 0, -4)
end
