local addonName, ns = ...

ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.1.0"

-- Depuis Midnight (12.0), COMBAT_LOG_EVENT_UNFILTERED est interdit aux addons et les
-- valeurs de combat sont des "secret values". Cet addon ne lit donc AUCUNE donnee de
-- combat : il declenche la journalisation fichier, enregistre des metadonnees de session,
-- et affiche les rapports calcules hors-jeu par l'outil Python.

local defaults = {
    minimapShown = true,
    minimapAngle = 200,
    seenIntro = false,
    theme = "dark",
    tooltip = true,
    gearAlerts = true,
    gearDetailCollapsed = true,
    ignoredSlots = {},
    shareWithGuild = false,
    language = "en",
    lastSeenReport = nil,
}

ns.events = CreateFrame("Frame")
ns.handlers = {}

function ns.On(event, handler)
    if not ns.handlers[event] then
        ns.handlers[event] = {}
        ns.events:RegisterEvent(event)
    end
    table.insert(ns.handlers[event], handler)
end

ns.events:SetScript("OnEvent", function(_, event, ...)
    local list = ns.handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            ns.Debug("handler error on %s: %s", event, tostring(err))
        end
    end
end)

function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    print("|cff8b6bffSpecAnalyser|r: " .. msg)
end

function ns.Debug(fmt, ...)
    if not SpecAnalyserDB or not SpecAnalyserDB.debug then return end
    ns.Print("|cff9d95b6[debug]|r " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
end

--- Copie non destructive des valeurs par defaut absentes de la base sauvegardee.
local function applyDefaults(db, source)
    for key, value in pairs(source) do
        if db[key] == nil then
            if type(value) == "table" then
                db[key] = {}
                applyDefaults(db[key], value)
            else
                db[key] = value
            end
        end
    end
end

ns.On("ADDON_LOADED", function(loaded)
    if loaded ~= addonName then return end
    SpecAnalyserDB = SpecAnalyserDB or {}
    applyDefaults(SpecAnalyserDB, defaults)
    ns.db = SpecAnalyserDB
    ns.ApplyLanguage()
end)

-- Un changement de specialisation invalide tout l'audit : la reference releve change, les
-- poids changent, les enchantements attendus changent. On oublie le cache et l'apercu.
local function specChanged()
    ns.Spec.Invalidate()
    ns.db.viewSpec = nil
    ns.Spec.Register()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

-- ACTIVE_TALENT_GROUP_CHANGED est le signal fiable pour ses propres talents ;
-- PLAYER_SPECIALIZATION_CHANGED se declenche aussi pour les membres du groupe.
ns.On("ACTIVE_TALENT_GROUP_CHANGED", specChanged)
ns.On("PLAYER_SPECIALIZATION_CHANGED", function(unit)
    if unit == "player" then specChanged() end
end)

ns.On("PLAYER_LOGIN", function()
    ns.Spec.Register()
    ns.Tooltip.Register()

    -- La reference est embarquee dans l'addon : l'annoncer des l'arrivee est ce qui remplace
    -- une page de configuration. Le joueur sait immediatement si l'addon a de quoi travailler
    -- pour SA specialisation, sans ouvrir quoi que ce soit.
    local function announceReference()
        if ns.Meta.Available() then
            local fights = ns.Meta.Fights()
            ns.Print("%s%s|r — %d %s, %s",
                ns.Theme.C("good"), ns.Spec.Name(ns.Spec.Selected()) or "?",
                ns.Meta.Sample(), ns.L["top players measured"],
                (#fights > 0 and table.concat(fights, ", ")) or ns.Meta.Source() or "?")
        elseif ns.Meta.AnyAvailable() then
            local stamp = ns.Meta.Stamp()
            ns.Print("%s%s|r%s",
                ns.Theme.C("bis"), ns.L["no top-build reference for this spec yet"],
                stamp and string.format("  (%d %s)", stamp.specs or 0,
                    ns.L["specs in the shipped reference"]) or "")
        else
            ns.Print("%s%s|r", ns.Theme.C("critical"), ns.L["no meta reference loaded"])
        end
    end

    -- First login: open the window on the help tab rather than hoping the player
    -- guesses a slash command.
    if not ns.db.seenIntro then
        ns.db.seenIntro = true
        ns.Print("installed. Nothing to configure — the measured reference ships with the addon.")
        announceReference()
        C_Timer.After(3, function() ns.UI.Show("help") end)
        return
    end

    ns.Print("v%s loaded. |cff00B0FF/sa|r to open, |cff00B0FF/sa help|r for the commands.", ns.version)
    announceReference()

    -- Rappel des poids de statistiques. Il ne se declenche QUE si des poids existent et ont
    -- vieilli : depuis que le repli derive du releve est supprime, leur absence est l'etat
    -- normal d'une installation neuve, et le rappeler a chaque connexion serait du harcelement
    -- pour quelque chose qui n'est pas casse.
    local age = ns.Weights.AgeInDays()
    if age and age >= 7 then
        C_Timer.After(6, function()
            ns.Print("|cffFFC107%s|r", ns.L["your stat weights are out of date — re-run a droptimizer"])
            print("  |cff00B0FFraidbots.com/simbot/droptimizer|r  ·  |cff00B0FF/sa droptimizer|r")
        end)
    end
end)

SLASH_SPECANALYSER1 = "/specanalyser"
SLASH_SPECANALYSER2 = "/sa"

local function usage()
    local c = "|cff00B0FF"
    ns.Print("commands:")
    print("  " .. c .. "/sa|r — open the window")
    print("  " .. c .. "/sa gear|r — gear audit in the chat")
    print("  " .. c .. "/sa simc|r — copy the SimulationCraft string")
    print("  " .. c .. "/sa droptimizer|r — droptimizer link and result paste")
    print("  " .. c .. "/sa weights <Pawn string>|r — store your stat weights")
    print("  " .. c .. "/sa guild|r — guild roll call")
    print("  " .. c .. "/sa theme|r — cycle the skin")
    print("  " .. c .. "/sa lang <auto|en|fr>|r — interface language")
    print("  " .. c .. "/sa alerts|r — gear warning when entering an instance")
    print("  " .. c .. "/sa minimap|r — show or hide the minimap icon")
    print("  " .. c .. "/sa reload|r — reload the interface")
end

-- La cle de SlashCmdList doit reprendre exactement le suffixe des globales SLASH_*.
SlashCmdList.SPECANALYSER = function(input)
    local cmd, arg = strsplit(" ", (input or ""):lower():gsub("^%s+", ""), 2)

    if cmd == "" or cmd == nil then
        ns.UI.Toggle()
    elseif cmd == "gear" or cmd == "stuff" then
        ns.UI.Show("gear")
        ns.Gear.PrintReport()
    elseif cmd == "guild" or cmd == "guilde" then
        ns.UI.Show("guild")
        ns.Guild.Request()
    elseif cmd == "droptimizer" or cmd == "drop" then
        ns.SimC.ShowDroptimizer()
    elseif cmd == "lang" or cmd == "langue" then
        local code = arg and arg:gsub("%s", "") or ""
        local valid = false
        for _, candidate in ipairs(ns.LANGUAGES) do
            if candidate == code then valid = true end
        end
        if not valid then
            ns.Print("languages: %s", table.concat(ns.LANGUAGES, ", "))
        else
            ns.db.language = code
            ns.ApplyLanguage()
            ns.Print(ns.L["language: %s"], ns.CurrentLanguage())
            ns.UI.Show()
        end
    elseif cmd == "reload" then
        ReloadUI()
    elseif cmd == "weights" or cmd == "poids" then
        if not arg or arg == "" then
            ns.Print(ns.Weights.Describe())
            print("  |cff00B0FF/sa weights ( Pawn: v1: \"Name\": Intellect=1, ... )|r")
        else
            local ok, name = ns.Weights.SetFromPawn(arg)
            if ok then
                ns.Print(ns.L["stat weights saved (%s)"], name)
                ns.UI.Refresh()
            else
                ns.Print(ns.L["unreadable Pawn string"])
            end
        end
    elseif cmd == "bags" or cmd == "sacs" then
        ns.UI.Show("gear")
    elseif cmd == "simc" then
        ns.SimC.Show()
    elseif cmd == "simcdiag" then
        ns.SimC.Diagnose()
    elseif cmd == "theme" or cmd == "habillage" then
        ns.Theme.Toggle()
        ns.UI.Show()
    elseif cmd == "alerts" or cmd == "alertes" then
        ns.db.gearAlerts = not (ns.db.gearAlerts ~= false)
        ns.Print("instance gear warning: %s",
            ns.db.gearAlerts and "|cff00E676on|r" or "|cffFFC107off|r")
    elseif cmd == "help" then
        ns.UI.Show("help")
        usage()
    elseif cmd == "minimap" then
        ns.MinimapButton.SetShown(ns.db.minimapShown == false)
        ns.Print("minimap icon: %s", ns.db.minimapShown and "shown" or "hidden")
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print("debug: %s", ns.db.debug and "on" or "off")
    else
        usage()
    end
end
