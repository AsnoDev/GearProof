local _, ns = ...

local Sim = {}
ns.Sim = Sim

-- Gains simules, venant de tes propres droptimizers.
--
-- Quand un objet figure dans une simulation, sa valeur remplace l'estimation lineaire.
-- C'est la seule maniere honnete de chiffrer un bijou ou une piece d'ensemble : leur
-- valeur ne se reduit pas a des points de statistique.
--
-- DEUX sources, fusionnees :
--
--   1. `Data/Sim.lua`, ecrit hors du jeu par `specanalyser raidbots --to-addon`.
--   2. Le CSV du rapport, COLLE dans l'addon — voir `Sim.ImportCSV`. Il ne demande
--      aucun outil : c'est la seule voie praticable pour qui installe l'addon depuis
--      CurseForge, et elle donne exactement les memes chiffres.
--
-- Le collage prime a egalite : c'est le plus recent des deux, par construction.

--- Rapports charges depuis un fichier genere.
--- Retrocompatibilite : un Data/Sim.lua produit par l'ancien outil expose
--- `SpecAnalyserSim`.
local function fileReports()
    if type(GearProofSim) == "table" and next(GearProofSim) ~= nil then return GearProofSim end
    if type(SpecAnalyserSim) == "table" and next(SpecAnalyserSim) ~= nil then return SpecAnalyserSim end
    return nil
end

-- Nombre de rapports colles conserves, par personnage.
--
-- Chaque import pese quelques dizaines de kilo-octets : jusqu'a 400 objets portant six
-- champs chacun. Rien ne les supprimait, et les SavedVariables sont relues INTEGRALEMENT
-- a chaque demarrage du client. Un joueur qui refait son droptimizer chaque semaine
-- accumulait donc, saison apres saison, un fichier que WoW paie au chargement pour des
-- rapports qui decrivent un equipement qu'il n'a plus.
--
-- Quatre, parce qu'un droptimizer decrit TON equipement du moment : le troisieme d'avant
-- ne dit deja plus la verite sur toi. Ce n'est pas un historique, c'est un cache.
local KEEP_REPORTS = 4

--- Rapports colles par le joueur, conserves dans les SavedVariables.
---
--- Filtres sur le personnage connecte. Un droptimizer decrit UN personnage : un gain de
--- +2 % mesure sur ton voleur ne dit rien de ce que le meme anneau vaut sur ton paladin,
--- et les anneaux, colliers et bijoux sont precisement ce que deux classes se partagent.
--- La table portait deja `player` — elle n'etait simplement jamais lue, donc les rapports
--- de tous les personnages fusionnaient en silence.
---
--- Un rapport SANS `player` est conserve : c'est un import de l'outil Python, dont le
--- flux ne connait qu'un personnage a la fois.
local function pastedReports()
    local stored = ns.db and ns.db.sim
    if type(stored) ~= "table" then return nil end

    local me = UnitName("player")
    local mine, found = {}, false
    for id, report in pairs(stored) do
        if type(report) == "table" and (not report.player or report.player == me) then
            mine[id] = report
            found = true
        end
    end
    return found and mine or nil
end

--- Ne garde que les `KEEP_REPORTS` rapports les plus recents de CE personnage.
local function pruneReports()
    local stored = ns.db and ns.db.sim
    if type(stored) ~= "table" then return end

    local me = UnitName("player")
    local ordered = {}
    for id, report in pairs(stored) do
        if type(report) == "table" and report.player == me then
            table.insert(ordered, { id = id, stamp = report.stamp or 0 })
        end
    end
    if #ordered <= KEEP_REPORTS then return end

    table.sort(ordered, function(a, b) return a.stamp > b.stamp end)
    for index = KEEP_REPORTS + 1, #ordered do
        stored[ordered[index].id] = nil
        ns.Debug("rapport %s oublie (au-dela des %d gardes)", ordered[index].id, KEEP_REPORTS)
    end
end

--- Tous les rapports, quelle que soit leur provenance.
local function reports()
    local file, pasted = fileReports(), pastedReports()
    if not file then return pasted end
    if not pasted then return file end

    local merged = {}
    for id, report in pairs(file) do merged[id] = report end
    -- Un meme rapport importe des deux facons : le collage gagne. Il ne peut pas etre
    -- plus ancien que le fichier — le joueur vient de le faire.
    for id, report in pairs(pasted) do merged[id] = report end
    return merged
end

function Sim.Available()
    return reports() ~= nil
end

--- Gain simule d'un objet, en pourcentage, ou nil.
---
--- `itemLevel` n'est pas optionnel par confort : un droptimizer simule une VERSION precise
--- d'un objet. Le releve porte `[250033] = { percent = 0.71, ilvl = 282 }`, et sans
--- verification l'addon collait ce +0,71 % sur la version 272 deja portee — il proposait comme
--- amelioration l'objet qu'on a sur le dos. Un identifiant d'objet ne suffit pas a designer ce
--- qui a ete simule.
---
--- @param itemLevel number|nil niveau de l'objet interroge ; sans lui, on ne repond pas
function Sim.Percent(itemID, itemLevel)
    if not itemID or not Sim.Available() then return nil end

    -- Echec FERME. La version precedente acceptait quand le niveau etait inconnu, et cette
    -- porte de sortie a produit un « +4,25 % » sur un objet de niveau 44 alors que la
    -- simulation portait sur du 289. Une valeur simulee decrit un objet PRECIS a un niveau
    -- PRECIS : sans les deux, on ne repond pas.
    if not itemLevel or itemLevel <= 0 then return nil end

    local best, bestBaseline
    for _, report in pairs(reports() or {}) do
        local entry = (report.items or {})[itemID]
        local matches = entry and entry.ilvl and entry.ilvl == itemLevel
        if matches and entry.percent then
            -- A egalite, la simulation avec la plus grosse base est la plus recente.
            if not best or (report.baseline or 0) > (bestBaseline or 0) then
                best, bestBaseline = entry.percent, report.baseline or 0
            end
        end
    end
    return best
end

-- ------------------------------------------------------------ import par collage
--
-- Raidbots sert le tableau de resultats en CSV a une adresse publique, et cette adresse
-- est simplement CELLE DU RAPPORT plus le nom du fichier :
--   https://www.raidbots.com/simbot/report/<id>/data.csv
--
-- Ce fichier a longtemps ecrit https://www.raidbots.com/reports/<id>/data.csv — une forme
-- qui n'est documentee nulle part et que le site ne construit jamais lui-meme. La forme
-- ci-dessus est celle que Raidbots documente, et celle que son propre menu « Raw Files »
-- fabrique sur la page du rapport. On prend donc la forme que personne ne conteste plutot
-- que celle qu'il faudrait mesurer pour defendre.
--
-- Consequence directe sur l'interface : le joueur n'a plus a revenir chercher une adresse.
-- Celle qu'il a deja dans sa barre d'adresse, plus /data.csv, suffit — voir
-- `Droptimizer.lua`, dont l'etape 2 le dit maintenant AVANT qu'il ne parte.
--
-- Neuf kilo-octets pour un droptimizer complet — un `EditBox` les avale sans broncher,
-- la ou le `data.json` du meme rapport en fait 873. Un addon ne peut RIEN telecharger,
-- mais le joueur, lui, peut ouvrir une adresse et copier.
--
-- Le format, verifie sur un rapport reel :
--
--   name,dps_mean,dps_min,dps_max,dps_std_dev,dps_mean_std_dev
--   Asnodk,24058.74...                              <- la baseline, sans separateur
--   1308/2740/raid-mythic/249296/282/3368/main_hand///,27816.18...
--   zone/rencontre/difficulte/objet/ilvl/enchant/emplacement
--
-- Tout est dans le nom de profileset. La ligne sans `/` est le personnage nu : c'est la
-- reference contre laquelle chaque gain se calcule.

--- Adresse du CSV d'un rapport, depuis son lien ou son identifiant.
function Sim.ReportCSVURL(reference)
    if type(reference) ~= "string" then return nil end
    local id = reference:match("reports?/([%w%-]+)") or reference:match("^%s*([%w%-]+)%s*$")
    if not id or #id < 6 then return nil end
    return "https://www.raidbots.com/simbot/report/" .. id .. "/data.csv", id
end

-- Positions dans le nom de profileset. Nommees, jamais comptees a la main : c'est
-- exactement le genre de decalage qui a deja coute un export SimulationCraft entier.
local FIELD_INSTANCE, FIELD_ENCOUNTER, FIELD_DIFFICULTY = 1, 2, 3
local FIELD_ITEM, FIELD_ILVL, FIELD_SLOT = 4, 5, 7

--- Analyse le CSV d'un droptimizer et l'enregistre.
---
--- @return boolean ok, number|string nombre d'objets, ou la raison de l'echec
function Sim.ImportCSV(text, reference)
    if type(text) ~= "string" or #text < 40 then return false, "empty" end

    local baseline, items = nil, {}

    for line in text:gmatch("[^\r\n]+") do
        -- Le nom peut contenir des virgules ? Non : c'est un chemin en `/`. On coupe
        -- donc a la PREMIERE virgule, et le reste est numerique.
        local name, rest = line:match("^([^,]*),(.*)$")
        local dps = rest and tonumber(rest:match("^([%d%.%-]+)"))

        if name and dps then
            if not name:find("/", 1, true) then
                -- Ligne sans separateur : le personnage nu. C'est la baseline, et
                -- l'entete `name,dps_mean` ne passe pas ici — `dps_mean` n'est pas un
                -- nombre.
                baseline = baseline or dps
            else
                local fields = { strsplit("/", name) }
                local itemID = tonumber(fields[FIELD_ITEM])
                local ilvl = tonumber(fields[FIELD_ILVL])
                if itemID and ilvl then
                    -- Un objet peut apparaitre a plusieurs niveaux : on garde le
                    -- meilleur DPS pour chaque couple, comme le fait l'outil Python.
                    local kept = items[itemID]
                    if not kept or dps > kept.dps then
                        items[itemID] = {
                            dps = dps,
                            ilvl = ilvl,
                            slot = fields[FIELD_SLOT],
                            encounter = tonumber(fields[FIELD_ENCOUNTER]) or 0,
                            instance = tonumber(fields[FIELD_INSTANCE]) or 0,
                            difficulty = fields[FIELD_DIFFICULTY],
                        }
                    end
                end
            end
        end
    end

    if not baseline or baseline <= 0 then return false, "baseline" end

    local count = 0
    for _, item in pairs(items) do
        item.percent = (item.dps - baseline) / baseline * 100
        item.dps = math.floor(item.dps + 0.5)
        count = count + 1
    end
    if count == 0 then return false, "items" end

    local _, id = Sim.ReportCSVURL(reference or "")
    ns.db.sim = ns.db.sim or {}
    ns.db.sim[id or "pasted"] = {
        baseline = math.floor(baseline + 0.5),
        player = UnitName("player"),
        stamp = time(),
        items = items,
    }
    pruneReports()

    -- La FRAICHEUR d'un droptimizer ne depend pas du lien. Depuis que l'adresse du CSV se
    -- devine, le parcours par defaut ne fait plus coller de lien du tout : `ns.db.droptimizer`
    -- restait donc nil, `SimC.DroptimizerAge()` rendait nil, et l'appel de guilde comptait
    -- « aucun droptimizer » chez un joueur qui venait d'en importer un.
    ns.db.droptimizer = ns.db.droptimizer or {}
    if id then ns.db.droptimizer.id = id end
    ns.db.droptimizer.stamp = time()

    return true, count
end

-- Difficultes de Raidbots -> identifiants de difficulte du client. Le journal des aventures
-- ne rend pas le meme butin selon la difficulte : sans ce reglage, on lirait la table LFR.
local DIFFICULTY = {
    ["raid-lfr"] = 17,
    ["raid-normal"] = 14,
    ["raid-heroic"] = 15,
    ["raid-mythic"] = 16,
}

-- Le butin arrive APRES la selection de la rencontre, par evenement. Sans cette
-- invalidation, la premiere lecture — toujours vide — n'aurait jamais de seconde chance,
-- et les infobulles resteraient sur le niveau du modele.
--
-- Le nom de l'evenement porte une faute de frappe cote Blizzard, presente depuis dix
-- ans. On enregistre les deux orthographes : `ns.On` ignore proprement celle qui
-- n'existe pas.
for _, event in ipairs({ "EJ_LOOT_DATA_RECIEVED", "EJ_LOOT_DATA_RECEIVED" }) do
    ns.On(event, function()
        -- Seuls les resultats non vides sont en cache : un rafraichissement relit donc
        -- uniquement ce qui manquait encore. Il est debounce, une salve d'evenements ne
        -- coute qu'un rendu.
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end)
end

--- Lien COMPLET d'un objet de butin, bonus IDs compris, tel que le journal le connait.
---
--- C'est la reponse a « pourquoi l'Adventure Guide affiche le bon niveau et pas nous » :
--- `GameTooltip:SetItemByID` ne connait que le MODELE de l'objet, donc son niveau de
--- base — 44 sur une piece de raid. Le journal, lui, expose le butin reel de la
--- rencontre pour une difficulte donnee, avec les identifiants de bonus.
---
--- La lecture passe par `Journal.Loot`, et c'est ce qui change tout pour les PIECES
--- D'ENSEMBLE. Il y avait ici un second lecteur du journal, presque identique, a une
--- chose pres : il ne posait pas le filtre de butin. Or le journal ne montre les pieces
--- de classe que si l'on filtre sur une classe — sans filtre il rend le JETON, pas la
--- piece. Toutes les pieces de tier retombaient donc sur `SetItemByID` et affichaient 44,
--- pendant que les objets ordinaires, eux, avaient leur lien.
---
--- Deux lecteurs pour la meme donnee, divergeant sur un detail invisible : c'est la
--- duplication qui a coute le plus cher dans ce depot. Il n'en reste qu'un.
--- @return string|nil lien d'objet
--- Difficulte Raidbots -> identifiant de difficulte du client.
---
--- Expose parce que le canal de guilde doit la TRANSMETTRE : un nombre tient en deux
--- chiffres la ou « raid-mythic » en coute onze, sur un canal plafonne a 255 octets.
--- @param difficulty string|number la chaine Raidbots, ou deja un identifiant
--- @return number identifiant de difficulte du client
function Sim.DifficultyID(difficulty)
    if type(difficulty) == "number" then return difficulty end
    return DIFFICULTY[difficulty or ""] or 16
end

--- @param difficulty string|number chaine Raidbots ou identifiant de difficulte du client
function Sim.LootLink(encounterID, itemID, difficulty, instanceID)
    if not encounterID or not itemID then return nil end

    local difficultyID = Sim.DifficultyID(difficulty)

    local function find(classID, specID)
        for _, loot in ipairs(ns.Journal.Loot(instanceID, encounterID, difficultyID, classID, specID)) do
            if loot.id == itemID then return loot.link end
        end
        return nil
    end

    -- Filtre sur la classe d'abord : c'est le seul moyen de voir les pieces d'ensemble.
    local link = find(ns.Spec.ClassID(), ns.Spec.Selected())
    if link then return link end

    -- Puis SANS filtre. Un droptimizer peut couvrir un objet que le journal ne montre
    -- pas a cette specialisation ; retomber sur la liste complete evite de perdre un
    -- lien qu'on avait avant d'ajouter le filtre.
    return find(nil, nil)
end

--- Nom d'une rencontre depuis son identifiant de journal, ou nil.
---
--- Les noms de profileset de Raidbots portent l'instance et la rencontre du journal des
--- aventures. Le client sait les traduire : aucune table de boss n'est embarquee, et le nom
--- sort dans la langue du joueur.
function Sim.EncounterName(encounterID)
    if not encounterID or encounterID == 0 then return nil end
    if type(EJ_GetEncounterInfo) ~= "function" then return nil end
    local ok, name = pcall(EJ_GetEncounterInfo, encounterID)
    return (ok and type(name) == "string" and name ~= "") and name or nil
end

function Sim.InstanceName(instanceID)
    if not instanceID or instanceID == 0 then return nil end
    if type(EJ_GetInstanceInfo) ~= "function" then return nil end
    local ok, name = pcall(EJ_GetInstanceInfo, instanceID)
    return (ok and type(name) == "string" and name ~= "") and name or nil
end

--- Le rapport le plus recent, et sa date.
---
--- A egalite de date, la simulation dont la BASE est la plus grosse : meme convention que
--- `Sim.Percent`. Un rapport de fichier n'a aucune date — le generateur n'en ecrit pas —
--- donc il compte pour 0 et se fait toujours devancer par un collage.
--- @return table|nil rapport, number date (0 si inconnue)
local function newestReport()
    local newest, newestStamp, newestBaseline
    for _, report in pairs(reports() or {}) do
        local stamp, baseline = report.stamp or 0, report.baseline or 0
        if not newest or stamp > newestStamp
            or (stamp == newestStamp and baseline > newestBaseline) then
            newest, newestStamp, newestBaseline = report, stamp, baseline
        end
    end
    return newest, newestStamp or 0
end

--- Date du droptimizer le plus recent, ou nil quand aucun n'en porte.
--- @return number|nil
function Sim.NewestStamp()
    local _, stamp = newestReport()
    return stamp > 0 and stamp or nil
end

--- Instances du droptimizer le plus recent : le raid que le joueur fait EN CE MOMENT.
---
--- UN RAPPORT NE S'EFFACE PAS TOUT SEUL, et c'est ce qui a produit deux symptomes pour une
--- seule cause. `Data/Sim.lua`, ecrit hors du jeu, n'a meme pas de date, et il survit au
--- deploiement — par choix, c'est la donnee du joueur. Les boss d'une saison finie
--- restaient donc dans l'onglet Raid, melanges aux nouveaux et souvent AU-DESSUS : le tri
--- se fait sur le gain, et un gain de la saison passee peut etre plus gros. Comme la
--- rencontre selectionnee est persistante, elle restait collee sur un boss mort et
--- l'onglet avait l'air de ne pas se mettre a jour.
---
--- Ce qui filtre est l'INSTANCE, pas la date : un objet du raid courant simule dans un
--- rapport plus ancien compte toujours. Seuls les raids d'une autre saison disparaissent.
--- @return table|nil { [instanceID] = true }
local function currentInstances()
    local newest = newestReport()
    if not newest then return nil end

    local instances, found = {}, false
    for _, entry in pairs(newest.items or {}) do
        if entry.instance and entry.instance > 0 then
            instances[entry.instance] = true
            found = true
        end
    end
    return found and instances or nil
end

--- Gains simules regroupes par rencontre, chaque groupe trie par gain decroissant.
---
--- C'est la base de la vue « table de loot par boss » : l'ensemble des objets qu'un
--- droptimizer a simules POUR une rencontre est sa table de butin, telle que Raidbots l'a
--- vue. On ne fabrique donc aucune liste de butin, on lit celle qui a ete simulee.
---
--- Restreint au raid EN COURS — voir `currentInstances`.
---
--- @return table|nil { { encounter, instance, name, items = { { id, percent, slot, ilvl } } } }
function Sim.ByEncounter()
    if not Sim.Available() then return nil end

    local groups, order = {}, {}
    local best = {}
    local instances = currentInstances()

    for _, report in pairs(reports() or {}) do
        for itemID, entry in pairs(report.items or {}) do
            local instance, encounter = entry.instance or 0, entry.encounter or 0
            -- Une rencontre <= 0 est le seau « sans rencontre » de Raidbots : `-97` sur un
            -- rapport reel, pour des objets qui ne s'apparient a aucun boss du journal.
            -- Une ligne de boss sans nom n'apprend rien, et `Guild.LocalCard` les ecartait
            -- deja de son cote.
            local keep = encounter > 0 and (not instances or instances[instance])
            -- Un objet peut figurer dans plusieurs rapports : on garde le meilleur gain,
            -- comme ailleurs, plutot que le dernier lu.
            local kept = best[itemID]
            if keep and (not kept or (entry.percent or 0) > (kept.percent or 0)) then
                best[itemID] = { id = itemID, percent = entry.percent or 0,
                    slot = entry.slot, ilvl = entry.ilvl,
                    encounter = encounter, instance = instance,
                    difficulty = entry.difficulty }
            end
        end
    end

    for _, item in pairs(best) do
        local key = item.encounter
        if not groups[key] then
            groups[key] = {
                encounter = key,
                instance = item.instance,
                name = Sim.EncounterName(key),
                items = {},
            }
            table.insert(order, groups[key])
        end
        table.insert(groups[key].items, item)
    end

    for _, group in ipairs(order) do
        table.sort(group.items, function(a, b) return a.percent > b.percent end)
        group.best = group.items[1] and group.items[1].percent or 0
    end

    -- Les rencontres les plus payantes en tete : c'est la question que se pose un raid.
    table.sort(order, function(a, b) return a.best > b.best end)
    return #order > 0 and order or nil
end
