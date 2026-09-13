local addonName, ns = ...

ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.1.0"

-- Tampon de la derniere copie vers le dossier de jeu, ecrit par `tools\deploy.cmd`.
-- Affiche dans la barre de titre : c'est ce qui permet de repondre seul a « je n'ai
-- aucun changement en jeu » — soit le tampon est celui de la derniere copie et le
-- probleme est ailleurs, soit il est plus ancien et le /reload a precede le
-- deploiement.
ns.build = (type(GearProofBuild) == "string" and GearProofBuild ~= "dev") and GearProofBuild or nil

-- Adresse du projet, LUE DANS LE .toc.
--
-- Elle vit a un seul endroit — `## X-Website` — et l'addon la recupere plutot que de la
-- redeclarer. Le bouton « Signaler un bug » fabriquait un rapport parfaitement formate
-- qui n'avait aucune destination : le joueur obtenait un texte impeccable et nulle part
-- ou le poser.
local function metadata(field)
    if not C_AddOns or not C_AddOns.GetAddOnMetadata then return nil end
    local ok, value = pcall(C_AddOns.GetAddOnMetadata, addonName, field)
    return (ok and type(value) == "string" and value ~= "") and value or nil
end

-- Meme traitement que `"dev"` plus haut : tant que le depot n'existe pas, le .toc porte
-- un gabarit. Afficher une adresse qui renvoie sur une 404 est pire que n'en afficher
-- aucune — le joueur suit le lien, ne trouve rien, et conclut que l'addon est abandonne.
ns.website = metadata("X-Website")
if ns.website and ns.website:find("REMPLACER", 1, true) then ns.website = nil end
ns.issues = ns.website and (ns.website .. "/issues") or nil

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
    ignoredSlots = {},
    shareWithGuild = false,
    -- Repli de la section « rien a signaler » de l'onglet Guilde. Une preference, donc
    -- elle survit au /reload — elle etait une variable de fichier.
    guildExpanded = false,
    language = "en",
    -- Droptimizers colles par le joueur, par identifiant de rapport. Ils vivent dans les
    -- SavedVariables et non dans `Data/Sim.lua` : ce fichier appartient a l'outil Python,
    -- et un import fait en jeu ne doit pas dependre de lui.
    sim = {},
}

ns.events = CreateFrame("Frame")
ns.handlers = {}

--- Abonne un gestionnaire a un evenement du client.
---
--- `RegisterEvent` leve une erreur Lua sur un nom d'evenement inconnu, et une erreur au
--- chargement d'un fichier interrompt tout ce qui suit dans ce fichier. Un evenement
--- retire par Blizzard doit couter la fonctionnalite qui en depend, pas l'addon.
function ns.On(event, handler)
    if not ns.handlers[event] then
        if not pcall(ns.events.RegisterEvent, ns.events, event) then
            ns.Debug("evenement inconnu, ignore : %s", event)
            return false
        end
        ns.handlers[event] = {}
    end
    table.insert(ns.handlers[event], handler)
    return true
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
    print("|cff8b6bffGearProof|r: " .. msg)
end

function ns.Debug(fmt, ...)
    if not GearProofDB or not GearProofDB.debug then return end
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

-- Version du SCHEMA des SavedVariables. Rien a voir avec `## Version` du .toc : elle ne
-- bouge que lorsque la FORME des donnees sauvegardees change.
--
-- Sans elle, la seule facon de faire evoluer la base etait `applyDefaults`, qui ne sait
-- qu'ajouter une cle absente. Renommer un reglage, changer le type d'une valeur ou
-- reparer une donnee ecrite de travers n'avait aucun endroit ou vivre — et une base
-- ecrite par une version future, retrogradee ensuite, etait lue comme si de rien n'etait.
--
-- Chaque migration mene de `version - 1` a `version`. Elles s'appliquent dans l'ordre, une
-- seule fois, et le numero est ecrit apres. Une migration ne doit JAMAIS supposer que la
-- precedente a laisse la base propre : elle valide ce qu'elle lit.
local SCHEMA = 1

-- Volontairement VIDE : aucune forme sauvegardee n'a change a ce jour. `sim` est indexe
-- par identifiant de rapport depuis son premier commit, et tout le reste n'a fait que
-- gagner des cles — ce dont `applyDefaults` s'acquitte deja.
--
-- Ce qui manquait n'est donc pas une migration, c'est l'endroit ou la prochaine se posera,
-- et le numero qui dit si elle a deja tourne. Ecrire une migration pour un changement qui
-- n'a pas eu lieu aurait ajoute du code non teste qui s'execute chez tout le monde.
--
-- Contrat : `migrations[N]` mene de `N - 1` a `N`, ne tourne qu'une fois, et ne suppose
-- JAMAIS que la precedente a laisse la base propre — elle valide ce qu'elle lit. Exemple :
--
--     [2] = function(db)
--         if type(db.ignoredSlots) ~= "table" then db.ignoredSlots = {} end
--     end,
local migrations = {}

--- Amene la base au schema courant. Retourne le nombre de migrations appliquees.
local function migrateSchema(db)
    -- Une base neuve est deja au schema courant : rien a migrer, et faire tourner les
    -- migrations dessus les obligerait toutes a gerer le cas « base vide ».
    local from = tonumber(db.schema)
    if not from then
        db.schema = next(db) and 1 or SCHEMA
        from = db.schema
    end

    -- Base ecrite par une version PLUS RECENTE. On ne touche a rien : les migrations ne
    -- savent qu'avancer, et deviner une transformation inverse detruirait des reglages.
    if from > SCHEMA then
        ns.Debug("base au schema %d, addon au schema %d — aucune migration", from, SCHEMA)
        return 0
    end

    local applied = 0
    for version = from + 1, SCHEMA do
        local migration = migrations[version]
        if migration then
            local ok, err = pcall(migration, db)
            if not ok then
                ns.Debug("migration %d en echec : %s", version, tostring(err))
            else
                applied = applied + 1
            end
        end
        db.schema = version
    end
    return applied
end

--- Reprend la base de l'ancien nom, une seule fois.
---
--- L'addon s'appelait SpecAnalyser. Renommer sans migrer aurait rendu a chaque testeur
--- une installation vierge : emplacements ignores oublies, poids de statistiques perdus,
--- droptimizer a recoller, position de fenetre a refaire.
---
--- L'ancienne base n'est PAS supprimee. Elle ne coute que quelques kilo-octets, et c'est
--- la seule porte de sortie si la migration se revele fausse.
local function migrateFromSpecAnalyser()
    if GearProofDB or type(SpecAnalyserDB) ~= "table" then return false end

    GearProofDB = CopyTable and CopyTable(SpecAnalyserDB) or {}
    if not CopyTable then
        for key, value in pairs(SpecAnalyserDB) do GearProofDB[key] = value end
    end
    GearProofDB.migratedFrom = "SpecAnalyser"
    return true
end

ns.On("ADDON_LOADED", function(loaded)
    if loaded ~= addonName then return end

    local migrated = migrateFromSpecAnalyser()
    GearProofDB = GearProofDB or {}

    -- Les migrations d'abord, les valeurs par defaut ensuite : une migration doit voir la
    -- base TELLE QU'ELLE A ETE ECRITE. Si `applyDefaults` passait avant, il remplirait les
    -- cles absentes et une migration ne saurait plus distinguer « ce reglage n'existait pas
    -- a l'epoque » de « le joueur l'a laisse a sa valeur par defaut ».
    local schemaSteps = migrateSchema(GearProofDB)
    applyDefaults(GearProofDB, defaults)
    ns.db = GearProofDB
    ns.ApplyLanguage()

    if schemaSteps > 0 then
        ns.Debug("schema migre en %d etape(s), maintenant %d", schemaSteps, GearProofDB.schema)
    end

    if migrated then
        ns.Print(ns.L["settings carried over from SpecAnalyser"])
    end
end)

-- Un changement de specialisation invalide tout l'audit : la reference releve change, les
-- poids changent, les enchantements attendus changent. On oublie le cache et l'apercu.
local function specChanged()
    ns.Spec.Invalidate()
    ns.Traits.Invalidate()
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

-- L'ARBRE DESSINE ETAIT FIGE A VIE. `Traits.Snapshot` met en cache — il lit deux cents
-- noeuds — et `Traits.Invalidate` existait sans qu'AUCUN appelant ne s'en serve : un joueur
-- qui deplacait un point gardait l'ancien arbre a l'ecran jusqu'a sa prochaine connexion,
-- rangs et branches choisies comprises. Rien ne le signalait, parce qu'un arbre perime
-- ressemble exactement a un arbre a jour.
--
-- Le changement de specialisation le remet a zero par `specChanged` ci-dessus ; celui-ci
-- couvre le cas bien plus frequent, un point deplace dans la meme specialisation.
ns.On("TRAIT_CONFIG_UPDATED", function()
    ns.Traits.Invalidate()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

-- La specialisation n'est pas toujours connue a PLAYER_LOGIN : sur un client lent ou au
-- premier lancement apres un patch, les donnees arrivent quelques secondes plus tard.
-- On repousse plutot que de conclure — annoncer « pas de releve pour cette spe » sur une
-- spe parfaitement relevee est le pire message possible a la connexion.
local function whenSpecKnown(action, attempt)
    attempt = attempt or 1
    if ns.Spec.Active() or attempt > 4 then
        action()
        return
    end
    ns.Debug("spec pas encore connue, tentative %d", attempt)
    C_Timer.After(attempt, function() whenSpecKnown(action, attempt + 1) end)
end

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
        whenSpecKnown(function()
            ns.Spec.Register()
            announceReference()
        end)
        C_Timer.After(3, function() ns.UI.Show("help") end)
        return
    end

    ns.Print("v%s loaded. |cff00B0FF/sa|r to open, |cff00B0FF/sa help|r for the commands.", ns.version)
    whenSpecKnown(function()
        -- Re-enregistrer : le premier appel a pu tomber avant que la spe soit connue,
        -- et l'outil Python lit cette table dans les SavedVariables.
        ns.Spec.Register()
        announceReference()
    end)

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

-- `/sa` reste en alias : c'est ce que les doigts connaissent, et le renommage n'a pas
-- a couter un reapprentissage.
-- Un objet demande a `RequestLoadItemDataByID` arrive par cet evenement. Sans lui, une
-- table de butin de raid resterait en « item:249296 » jusqu'au prochain geste du joueur.
--
-- Conditionne a une demande REELLEMENT en attente : l'evenement se declenche pour tout
-- objet que le client charge, y compris pour un autre addon.
ns.On("GET_ITEM_INFO_RECEIVED", function()
    if ns.ItemInfo.ConsumePending() and ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)

SLASH_GEARPROOF1 = "/gearproof"
SLASH_GEARPROOF2 = "/gp"
SLASH_GEARPROOF3 = "/sa"

-- Une seule commande affichee. La liste melangeait `/sa` et `/gp` selon la ligne, ce qui
-- se lit comme deux addons : `/gp` est la forme courte de ce produit, `/sa` un alias
-- garde pour ceux qui viennent de SpecAnalyser, mentionne une fois en bas.
local function usage()
    local c = "|cff00B0FF"
    ns.Print("commands:")
    print("  " .. c .. "/gp|r — open the window")
    print("  " .. c .. "/gp gear|r — gear audit in the chat")
    print("  " .. c .. "/gp reco|r — what to put on: stats, enchants, gems")
    print("  " .. c .. "/gp talents|r — the talent tree, raid or Mythic+")
    print("  " .. c .. "/gp items|r — trinkets by source, and crafted gear")
    print("  " .. c .. "/gp simc|r — copy the SimulationCraft string")
    print("  " .. c .. "/gp droptimizer|r — droptimizer link and result paste")
    print("  " .. c .. "/gp weights <Pawn string>|r — store your stat weights")
    print("  " .. c .. "/gp guild|r — guild roll call")
    print("  " .. c .. "/gp options|r — settings panel")
    print("  " .. c .. "/gp theme|r — cycle the skin")
    print("  " .. c .. "/gp lang <auto|en|fr>|r — interface language")
    print("  " .. c .. "/gp alerts|r — gear warning when entering an instance")
    print("  " .. c .. "/gp minimap|r — show or hide the minimap icon")
    print("  " .. c .. "/gp reload|r — reload the interface")
    print("  |cff808080/gearproof and /sa do the same|r")
end

-- La cle de SlashCmdList doit reprendre exactement le suffixe des globales SLASH_*.
SlashCmdList.GEARPROOF = function(input)
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
    elseif cmd == "reco" or cmd == "recommendations" or cmd == "conseils" then
        ns.UI.Show("reco")
    -- Les deux onglets ajoutes lors de l'allegement de Recommandations. Les cinq
    -- d'origine avaient leur commande ; ceux-la n'en avaient pas, donc la moitie de
    -- l'interface n'etait atteignable qu'a la souris.
    elseif cmd == "talents" or cmd == "talent" then
        ns.UI.Show("talent")
    elseif cmd == "items" or cmd == "objets" then
        ns.UI.Show("items")
    elseif cmd == "options" or cmd == "config" or cmd == "reglages" then
        ns.Options.Open()
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
