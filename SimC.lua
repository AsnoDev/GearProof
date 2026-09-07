local _, ns = ...

local SimC = {}
ns.SimC = SimC

-- Export au format SimulationCraft, construit a partir des chaines d'objets.
--
-- Le format est calque sur celui de l'addon officiel, verifie ligne par ligne sur un
-- export reel : entete en commentaires, bloc personnage, une ligne par emplacement
-- precedee du nom et de l'ilvl, puis `### Gear from Bags`.
--
-- Ce qui n'est PAS exporte : le bloc `### Additional Character Info` (monnaies de
-- surclassement, `slot_high_watermarks`, hauts faits). Il ne sert qu'a l'Upgrade Finder
-- de Raidbots ; le droptimizer et une simulation simple n'en ont pas besoin.

local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }

-- Lignes de metier -> jetons SimulationCraft. On passe par l'identifiant et non par le
-- nom affiche : le nom est traduit, l'identifiant non.
-- DONNEE DE PATCH : verifiee contre 12.0.7, PAS ENCORE REVUE pour 12.1.0.
local PROFESSIONS = {
    [171] = "alchemy",
    [164] = "blacksmithing",
    [333] = "enchanting",
    [202] = "engineering",
    [182] = "herbalism",
    [773] = "inscription",
    [755] = "jewelcrafting",
    [165] = "leatherworking",
    [186] = "mining",
    [393] = "skinning",
    [197] = "tailoring",
}

local STAT_INTELLECT = LE_UNIT_STAT_INTELLECT or 4

--- "NightElf" -> "night_elf", "BloodElf" -> "blood_elf"
local function toToken(text)
    if not text or text == "" then return "unknown" end
    local spaced = text:gsub("(%l)(%u)", "%1_%2")
    return spaced:lower():gsub("[^%w_]", "")
end

--- Specialisation active.
--- @return string|nil nom, string|nil role Blizzard, number|nil statistique principale
local function specInfo()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if not getSpec or not getInfo then return nil end
    local ok, index = pcall(getSpec)
    if not ok or not index then return nil end

    -- GetSpecializationInfo : id, nom, description, icone, role, statistique principale.
    local results = { pcall(getInfo, index) }
    if not results[1] then return nil end
    return results[1 + 2], results[1 + 5], results[1 + 6]
end

--- Jeton `role=` de SimulationCraft, deduit et non code en dur.
--- Devourer est une spe d'Intelligence : la regle rend bien `spell`, sans cas particulier.
local function roleToken(role, primaryStat)
    if role == "TANK" then return "tank" end
    if primaryStat == STAT_INTELLECT then return "spell" end
    return "attack"
end

--- "alchemy=66/enchanting=28", ou nil si le personnage n'a pas de metier principal.
local function professionLine()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
        return nil
    end
    local ok, first, second = pcall(GetProfessions)
    if not ok then return nil end

    local parts = {}
    for _, index in ipairs({ first or false, second or false }) do
        if index then
            -- GetProfessionInfo : nom, texture, rang, rang max, sorts, offset, ligne.
            local fine = { pcall(GetProfessionInfo, index) }
            local rank, skillLine = fine[1 + 3], fine[1 + 7]
            local token = PROFESSIONS[skillLine or 0]
            if fine[1] and token and rank then
                table.insert(parts, string.format("%s=%d", token, rank))
            end
        end
    end

    if #parts == 0 then return nil end
    return table.concat(parts, "/")
end

--- Chaine de talents.
---
--- Sans elle, SimulationCraft simule un personnage SANS TALENTS : il n'a pas de liste de
--- priorites et se contente d'attaquer. C'est ce qui a produit 8 186 DPS au lieu de 68 984 —
--- un facteur huit, avec un equipement pourtant correctement lu. Un export sans talents ne
--- doit donc jamais partir silencieusement.
---
--- `C_ClassTalents` a change de nom plusieurs fois : on essaie chaque voie connue plutot que
--- de dependre d'une seule.
local function talentString()
    if not C_Traits then return nil end

    local configID
    for _, getter in ipairs({
        C_ClassTalents and C_ClassTalents.GetActiveConfigID,
        C_Traits.GetActiveConfigID,
        C_SpecializationInfo and C_SpecializationInfo.GetActiveConfigID,
    }) do
        if type(getter) == "function" then
            local ok, value = pcall(getter)
            if ok and value then
                configID = value
                break
            end
        end
    end
    if not configID then return nil end

    for _, exporter in ipairs({
        C_Traits.GenerateInspectImportString,
        C_Traits.GenerateImportString,
    }) do
        if type(exporter) == "function" then
            local ok, value = pcall(exporter, configID)
            if ok and type(value) == "string" and #value > 20 then return value end
        end
    end
    return nil
end

--- Une ligne d'objet. `parsed` vient de `ItemLink.Parse` ou d'une entree de `Gear.Scan`.
--- L'ordre des champs suit celui de l'addon officiel.
local function itemLine(slotToken, parsed)
    if not slotToken or not parsed or not parsed.itemID or parsed.itemID == 0 then return nil end

    local parts = { string.format("%s=,id=%d", slotToken, parsed.itemID) }

    if parsed.enchantID and parsed.enchantID > 0 then
        table.insert(parts, "enchant_id=" .. parsed.enchantID)
    end

    local gems = parsed.gemIDs or parsed.gems
    if gems and #gems > 0 then
        table.insert(parts, "gem_id=" .. table.concat(gems, "/"))
    end
    if parsed.bonuses and #parsed.bonuses > 0 then
        table.insert(parts, "bonus_id=" .. table.concat(parsed.bonuses, "/"))
    end
    if parsed.contentTuning then
        table.insert(parts, "content_tuning=" .. parsed.contentTuning)
    end
    if parsed.craftedStats and #parsed.craftedStats > 0 then
        table.insert(parts, "crafted_stats=" .. table.concat(parsed.craftedStats, "/"))
    end
    if parsed.craftingQuality then
        table.insert(parts, "crafting_quality=" .. parsed.craftingQuality)
    end

    return table.concat(parts, ",")
end

--- "# Devouring Reaver's Intake (272)"
local function itemComment(name, itemLevel)
    if not name then return nil end
    if itemLevel and itemLevel > 0 then
        return string.format("# %s (%d)", name, itemLevel)
    end
    return "# " .. name
end

--- Emplacement SimulationCraft d'un objet des sacs.
local function bagSlotToken(slotName)
    for _, definition in ipairs(ns.Gear.SLOTS) do
        if definition.slot == slotName then return definition.simc end
    end
    return nil
end

--- Section `### Gear from Bags`, en commentaires comme le fait l'addon officiel.
local function bagLines()
    if not ns.Bags or not ns.Bags.Candidates then return {} end

    local ok, candidates = pcall(ns.Bags.Candidates)
    if not ok or type(candidates) ~= "table" then return {} end

    local lines, seen = {}, {}
    for _, definition in ipairs(ns.Gear.SLOTS) do
        for _, candidate in ipairs(candidates[definition.slot] or {}) do
            -- Un anneau des sacs remonte pour les deux emplacements de doigt : une seule
            -- ligne suffit, comme dans l'export officiel.
            if not seen[candidate.link] then
                seen[candidate.link] = true
                local line = itemLine(bagSlotToken(definition.slot), ns.ItemLink.Parse(candidate.link))
                if line then
                    local facts = candidate.facts or {}
                    table.insert(lines, "#")
                    local comment = itemComment(facts.name, facts.itemLevel)
                    if comment then table.insert(lines, comment) end
                    table.insert(lines, "# " .. line)
                end
            end
        end
    end

    if #lines == 0 then return {} end
    table.insert(lines, 1, "### Gear from Bags")
    table.insert(lines, 1, "")
    return lines
end

--- Construit la chaine complete.
function SimC.Build()
    local entries = ns.Gear.Scan()
    local name = UnitName("player") or "Unknown"
    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    local realm = GetRealmName() or ""
    local region = REGIONS[GetCurrentRegion and GetCurrentRegion() or 3] or "eu"
    local spec, role, primaryStat = specInfo()

    local version, build, _, toc = GetBuildInfo()

    local lines = {
        string.format("# %s - %s - %s - %s/%s",
            name, spec or "?", date("%Y-%m-%d %H:%M"), region:upper(), realm),
        string.format("# GearProof %s", ns.version or "?"),
        string.format("# WoW %s.%s, TOC %s", version or "?", build or "?", toc or "?"),
        "",
        string.format("%s=\"%s\"", toToken(classFile), name),
        "level=" .. (UnitLevel("player") or 0),
        "race=" .. toToken(raceFile),
        "region=" .. region,
        "server=" .. toToken(realm),
        "role=" .. roleToken(role, primaryStat),
    }

    local trades = professionLine()
    if trades then table.insert(lines, "professions=" .. trades) end
    if spec then table.insert(lines, "spec=" .. toToken(spec)) end

    -- Ce qui manque est collecte, pas ignore : un profil incomplet sime a un huitieme du vrai
    -- resultat sans que rien ne le signale.
    local missing = {}

    local talents = talentString()
    if talents then
        table.insert(lines, "")
        table.insert(lines, "talents=" .. talents)
    else
        table.insert(missing, "talents")
    end

    if not spec then table.insert(missing, "spec") end

    table.insert(lines, "")

    local exported = 0
    for _, entry in ipairs(entries) do
        local line = itemLine(entry.simc, entry)
        if line then
            local comment = itemComment(entry.name, entry.itemLevel)
            if comment then table.insert(lines, comment) end
            table.insert(lines, line)
            exported = exported + 1
        end
    end

    if exported < 10 then table.insert(missing, "gear") end

    for _, line in ipairs(bagLines()) do
        table.insert(lines, line)
    end

    return table.concat(lines, "\n"), missing
end

--- L'addon SimulationCraft officiel est-il charge ?
local function officialLoaded()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(isLoaded) ~= "function" then return false end
    local ok, loaded = pcall(isLoaded, "SimulationCraft")
    return ok and loaded and true or false
end

--- Chaine produite par l'addon SimulationCraft officiel, ou nil.
---
--- On ne peut pas lancer un programme depuis un addon, mais on peut appeler un autre addon.
--- Quand l'officiel est la, sa chaine vaut mieux que la mienne : elle est celle que
--- SimulationCraft et Raidbots attendent, et Raidbots la reconnait — ce qui fait disparaitre
--- l'avertissement « Input is not from the SimulationCraft addon » sans falsifier la ligne de
--- provenance, ce que je refuse de faire.
---
--- Les points d'entree sont sondes, pas supposes : c'est l'API d'un tiers, elle peut changer.
function SimC.FromOfficial()
    if not officialLoaded() then return nil end

    -- Voie 1 : une fonction publique de l'addon, si elle existe.
    local addon = _G.Simulationcraft
    if type(addon) == "table" then
        for _, name in ipairs({ "GetSimcProfile", "BuildSimcProfile", "PrintSimcProfile" }) do
            local method = addon[name]
            if type(method) == "function" then
                local ok, value = pcall(method, addon)
                if ok and type(value) == "string" and #value > 200 then return value, name end
            end
        end
    end

    -- Cherche un champ de saisie contenant un profil, parmi les globals du jeu.
    --
    -- On balaie plutot que de nommer : le diagnostic sur une installation reelle a montre que
    -- l'addon n'expose ni global `Simulationcraft`, ni commande contenant SIM, et que son
    -- cadre de copie n'existe PAS avant la premiere utilisation. Deviner un nom a echoue deux
    -- fois ; on reconnait donc le profil a son contenu.
    -- Un profil SimulationCraft contient toujours une ligne `level=` et une ligne
    -- d'objet : deux marqueurs valent mieux qu'un seuil de longueur.
    local function readsAsProfile(object)
        if type(object) ~= "table" or not object.GetText then return nil end
        local ok, value = pcall(object.GetText, object)
        if ok and type(value) == "string"
            and value:find("level=", 1, true) and value:find("=,id=", 1, true) then
            return value
        end
        return nil
    end

    -- Noms observes sur des installations reelles. On les essaie AVANT de balayer :
    -- parcourir `_G` coute une trentaine de milliers d'iterations, et la boucle
    -- s'executait a chaque tentative de declenchement.
    local KNOWN = {
        "SimcEditBox", "SimulationCraftEditBox", "SimcCopyFrameScroll",
        "SimulationcraftFrameEditBox",
    }

    local function findProfile()
        for _, name in ipairs(KNOWN) do
            local value = readsAsProfile(_G[name])
            if value then return value, name end
        end

        -- Repli : balayage. Le diagnostic sur une installation reelle a montre que
        -- l'addon n'expose ni global `Simulationcraft`, ni commande contenant SIM, et
        -- que son cadre de copie n'existe PAS avant la premiere utilisation. Deviner un
        -- nom a echoue deux fois ; on reconnait donc le profil a son contenu.
        for name, object in pairs(_G) do
            if type(name) == "string"
                and (name:find("Simc") or name:find("Simulation")) then
                local value = readsAsProfile(object)
                if value then return value, name end
            end
        end
        return nil
    end

    -- Voie 2 : declencher l'addon, puis lire son champ de copie.
    --
    -- Son seul point d'entree observe est son lanceur LibDataBroker, `SimcLDB` : c'est le clic
    -- dessus qui construit le profil et cree la fenetre. La commande slash, elle, n'est pas
    -- enregistree dans SlashCmdList sur cette installation.
    local triggers = {}

    local ldb = _G.SimcLDB
    if type(ldb) == "table" and type(ldb.OnClick) == "function" then
        table.insert(triggers, function() ldb.OnClick(nil, "LeftButton") end)
    end

    local handler = SlashCmdList
        and (SlashCmdList.SIMC or SlashCmdList.SIMULATIONCRAFT or SlashCmdList.SIMULATIONCRAFTADDON)
    if type(handler) == "function" then
        table.insert(triggers, function() handler("") end)
    end

    -- Avant de declencher quoi que ce soit : peut-etre que le profil est deja la, d'une
    -- utilisation precedente. Inutile de reveiller un addon tiers pour rien.
    local existing, where = findProfile()
    if existing then return existing, where end

    for _, trigger in ipairs(triggers) do
        pcall(trigger)
        local value, name = findProfile()
        if value then
            -- Sa fenetre reste OUVERTE.
            --
            -- On la fermait de force, en remontant sa chaine de parents jusqu'a UIParent
            -- pour appeler Hide dessus. C'est l'interface d'un autre addon : la manipuler
            -- au motif qu'elle nous gene est le genre de geste qui casse au premier
            -- changement chez lui, et qui surprend le joueur — il a vu une fenetre
            -- s'ouvrir, elle disparait toute seule. La notre s'affiche par-dessus, en
            -- FULLSCREEN_DIALOG, ce qui suffit.
            return value, name
        end
    end

    return nil
end

--- Diagnostic : dit ce qui a ete TROUVE, au lieu d'echouer en silence.
--- Deux hypotheses fausses de suite sur cette API : mieux vaut mesurer que deviner.
function SimC.Diagnose()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    for _, folder in ipairs({ "SimulationCraft", "Simulationcraft", "simulationcraft" }) do
        local ok, loaded = pcall(isLoaded, folder)
        ns.Print("addon \"%s\" : %s", folder,
            (ok and loaded) and "|cff00E676charge|r" or "|cff8A8A8Aabsent|r")
    end

    local addon = _G.Simulationcraft
    ns.Print("global Simulationcraft : %s", type(addon))
    if type(addon) == "table" then
        local names = {}
        for key, value in pairs(addon) do
            if type(value) == "function" then table.insert(names, key) end
        end
        table.sort(names)
        ns.Print("  methodes : %s", table.concat(names, ", "))
    end

    local keys = {}
    for key in pairs(SlashCmdList or {}) do
        if key:find("SIM") then table.insert(keys, key) end
    end
    ns.Print("SlashCmdList contenant SIM : %s",
        #keys > 0 and table.concat(keys, ", ") or "aucune")

    -- Cadres du jeu dont le nom commence par Simc : c'est la que vit son champ de copie.
    local function listFrames()
        local frames = {}
        for name in pairs(_G) do
            if type(name) == "string" and (name:find("Simc") or name:find("Simulation")) then
                table.insert(frames, name)
            end
        end
        table.sort(frames)
        return frames
    end

    ns.Print("globals Simc*/Simulation* AVANT : %s", table.concat(listFrames(), ", "))

    -- Le cadre de copie est cree paresseusement : on declenche l'addon puis on recompte.
    local ldb = _G.SimcLDB
    ns.Print("SimcLDB : %s   OnClick : %s", type(ldb),
        type(ldb) == "table" and type(ldb.OnClick) or "-")
    if type(ldb) == "table" and type(ldb.OnClick) == "function" then
        pcall(ldb.OnClick, nil, "LeftButton")
        ns.Print("globals APRES clic LDB : %s", table.concat(listFrames(), ", "))
    end

    local value, where = SimC.FromOfficial()
    if value then
        ns.Print("|cff00E676profil recupere|r via %s (%d caracteres)", where, #value)
    else
        ns.Print("|cffFF4D4Daucun profil recupere|r")
    end
end

--- Ouvre la fenetre de copie avec la chaine.
function SimC.Show()
    -- L'officiel d'abord, quand il est la.
    local fromOfficial, via = SimC.FromOfficial()
    if fromOfficial then
        ns.Print("%s%s|r (%s)", ns.Theme.C("good"),
            ns.L["using the SimulationCraft addon's own export"], via)
        ns.Copy.Show(ns.L["SimulationCraft string — paste it on raidbots.com"], fromOfficial)
        return
    end

    local text, missing = SimC.Build()

    -- Un profil sans talents sime a un huitieme du vrai resultat, et Raidbots ne le dit pas :
    -- il rend un chiffre, simplement faux. Autant le signaler avant le collage.
    if #missing > 0 then
        ns.Print("|cffFF4D4D%s|r %s",
            ns.L["incomplete SimC export — the simulation will be wrong:"],
            table.concat(missing, ", "))
    end

    -- Sans l'addon officiel, ma chaine est un export de secours. Le dire vaut mieux que de
    -- laisser croire qu'elle est equivalente.
    if not officialLoaded() then
        ns.Print("|cff8A8A8A%s|r", ns.L["install the SimulationCraft addon for an authoritative export"])
    end

    ns.Copy.Show(ns.L["SimulationCraft string — paste it on raidbots.com"], text)
end

--- Traite un collage de droptimizer, quel qu'il soit.
---
--- Le joueur ne devrait pas avoir a savoir CE qu'il colle. Trois choses peuvent arriver
--- dans cette boite, et une seule sert a remplir l'onglet Raid :
---
---   1. le CSV du rapport      -> import reel des gains par objet
---   2. le lien du rapport     -> on rend l'adresse du CSV, a ouvrir et copier
---   3. une chaine Pawn        -> poids de statistiques
---
--- On essaie le CSV EN PREMIER : c'est le seul qui apporte la donnee, et c'est aussi le
--- plus reconnaissable. Un lien ne peut rien telecharger — WoW l'interdit — donc le
--- reconnaitre sert uniquement a donner l'etape suivante.
--- @return boolean accepte, string|nil nature : "csv", "link" ou "pawn"
---
--- La NATURE compte : l'appelant doit savoir ce qu'il vient de recevoir, pas le deduire
--- d'un etat global. `Droptimizer.Submit` le deduisait de `Sim.Available()`, vrai des
--- qu'un rapport existe — donc un joueur qui en avait deja un et collait un NOUVEAU lien
--- voyait la fenetre se fermer sans jamais voir l'etape suivante.
function SimC.HandlePaste(text)
    if type(text) ~= "string" or text == "" then
        ns.Print(ns.L["nothing readable in that paste"])
        return false
    end

    local reference = (ns.db.droptimizer and ns.db.droptimizer.id) or ""
    local ok, result = ns.Sim.ImportCSV(text, reference)
    if ok then
        ns.Print("%s%s|r", ns.Theme.C("good"),
            string.format(ns.L["droptimizer imported: %d items"], result))
        if ns.UI and ns.UI.RefreshNow then ns.UI.RefreshNow() end
        return true, "csv"
    end

    local url = ns.Sim.ReportCSVURL(text)
    if url and SimC.SetDroptimizer(text) then
        ns.Print(ns.L["droptimizer report stored"])
        -- Deuxieme etape dans la MEME fenetre : l'adresse est pre-remplie et
        -- selectionnee, prete pour un Ctrl+C. Le joueur part la chercher, revient,
        -- remplace le contenu par ce qu'il a copie, et valide avec le meme bouton.
        --
        -- Cette etape passait par `Copy.Show`, une fenetre d'AFFICHAGE sans bouton :
        -- on y collait ses donnees et il n'y avait rien pour les envoyer.
        ns.Copy.Prompt(ns.L["Droptimizer report"],
            ns.L["Open this address, select everything, copy — then replace this text with what you copied and validate"],
            SimC.HandlePaste, url)
        return true, "link"
    end

    if ns.Weights.SetFromPawn(text) then
        ns.Print(ns.L["stat weights saved (%s)"], "Pawn")
        if ns.UI and ns.UI.RefreshNow then ns.UI.RefreshNow() end
        return true, "pawn"
    end

    ns.Print(ns.L["nothing readable in that paste"])
    return false
end

--- Ouvre la boite de collage du droptimizer.
function SimC.PromptImport()
    ns.Copy.Prompt(ns.L["Droptimizer report"],
        ns.L["Paste the Raidbots report link, or the report data"],
        SimC.HandlePaste)
end

local DROPTIMIZER_URL = "https://www.raidbots.com/simbot/droptimizer"

--- Lien du droptimizer, chaine SimC, puis collage du rapport en retour.
--- Un addon ne peut ni ouvrir un navigateur ni recevoir de donnees du web : le lien se
--- copie, le resultat se colle.
function SimC.ShowDroptimizer()
    ns.Copy.Show("Droptimizer", DROPTIMIZER_URL)
end

--- Enregistre l'identifiant d'un rapport Raidbots.
---
--- CE QUE CETTE FONCTION NE FAIT PAS : importer les gains simules. Un addon ne peut
--- emettre aucune requete reseau — WoW l'interdit, il n'y a pas d'API pour ca et il n'y
--- en aura pas. Coller un lien ne peut donc rien telecharger.
---
--- Ce qui est enregistre, c'est l'IDENTIFIANT et sa date. Il sert a deux choses reelles :
--- la tournee de guilde le diffuse pour qu'un officier voie qui a une simulation
--- recente, et l'interface affiche sa fraicheur. C'est utile, mais ce n'est PAS ce que
--- « coller un droptimizer » laisse croire.
---
--- Les gains par objet arrivent par `Data/Sim.lua`, ecrit hors du jeu :
---   specanalyser raidbots <lien> --to-addon
--- puis /reload. L'onglet Raid depend de ce fichier, pas de cet identifiant.
function SimC.SetDroptimizer(text)
    if not text then return false end
    local id = text:match("reports?/([%w%-]+)") or text:match("^%s*([%w%-]+)%s*$")
    if not id or #id < 6 then return false end

    ns.db.droptimizer = { id = id, stamp = time() }
    return true, id
end

--- Age du rapport en jours, ou nil.
function SimC.DroptimizerAge()
    local stored = ns.db.droptimizer
    if not stored or not stored.stamp then return nil end
    return math.floor((time() - stored.stamp) / 86400)
end
