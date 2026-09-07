local _, ns = ...

local Guild = {}
ns.Guild = Guild

local L = ns.L

-- Onglet Guilde : qui a simule, qui a des enchantements manquants.
--
-- Comment ca marche
-- -----------------
-- Chaque membre equipe de l'addon annonce une fiche compacte sur le canal addon de la
-- guilde : nom, spe, ilvl, nombre de correctifs d'equipement, identifiant de son dernier
-- droptimizer et sa date. Un officier demande la tournee, chacun repond, le tableau se
-- remplit.
--
-- Ce que l'addon NE fait PAS : lire les resultats de simulation. Raidbots est hors du jeu ;
-- l'addon partage l'identifiant du rapport, pas son contenu. L'agregation des resultats se
-- fait cote outil Python, qui sait interroger Raidbots.
--
-- Le partage est explicite : rien ne sort tant que `shareWithGuild` est faux.

-- Prefixe du canal de donnees. Il a change avec le nom de l'addon : un client de
-- l'ancienne version n'est plus entendu, ce qui est sans consequence — rien n'etait
-- publie.
local PREFIX = "GEARPROOF"
local REQUEST = "REQ"
local REPLY = "REP"
local ITEMS = "ITM"

-- Delai minimal entre deux tournees LANCEES par ce client.
local THROTTLE = 5

-- Delai minimal entre deux REPONSES de ce client.
--
-- THROTTLE ne protegeait que l'emetteur. A la reception d'un REQ, chacun refaisait un
-- audit d'equipement complet, un regroupement de ses gains simules et un envoi de
-- plusieurs messages — sans aucune borne. Un client en boucle, bogue ou malveillant,
-- mettait toute la guilde a genoux depuis un seul poste.
local REPLY_THROTTLE = 30

-- Bornes dures. Au-dela, la guilde a un probleme, pas nous : on cesse d'accumuler
-- plutot que de laisser une table grossir sur des donnees venues du reseau.
local MAX_ROSTER = 120
local MAX_CHUNKS = 40
local INCOMING_TTL = 30

-- Un message d'addon est plafonne a 255 octets par le client. Les gains par objet depassent
-- ce plafond, donc ils partent dans des messages distincts, decoupes sur des frontieres de
-- separateur pour qu'un morceau reste analysable seul.
--
-- A dire clairement, parce que la question s'est posee : ces messages passent par
-- `C_ChatInfo.SendAddonMessage` sur le canal "GUILD", qui est un canal de DONNEES. Rien
-- n'apparait dans le chat de guilde, ni pour l'emetteur ni pour les autres, et un joueur sans
-- l'addon ne voit rien du tout.
--
-- 200 etait un chiffre rond, pas un budget : `ITM~<nom>~<index>~<total>~` s'ajoute au
-- morceau, et un nom long faisait depasser les 255 octets — le client jetait alors le
-- message en silence. Le budget se calcule maintenant sur le nom reel.
local MESSAGE_LIMIT = 240

local roster, lastRequest, lastReply = {}, 0, 0
local incoming = {}

--- Nom de l'expediteur, sans le royaume. Un roster de guilde est mono-royaume.
local function whoSent(sender)
    if not sender or sender == "" then return nil end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, sender, "guild")
        if ok and short and short ~= "" then return short end
    end
    return (sender:gsub("%-.*$", ""))
end

--- Oublie les reassemblages qui ne se termineront jamais.
--- Sans cette purge, un emetteur qui annonce quatre morceaux et n'en envoie qu'un
--- laissait sa charge utile en memoire pour le reste de la session.
local function sweepIncoming()
    local now = GetTime()
    for name, pending in pairs(incoming) do
        if (now - (pending.at or 0)) > INCOMING_TTL then
            incoming[name] = nil
        end
    end
end

local function encode(value)
    return tostring(value or ""):gsub("[|~]", "")
end

--- Fiche du personnage courant, en une ligne compacte.
function Guild.LocalCard()
    local _, summary = ns.Gear.Scan()
    local _, equipped = GetAverageItemLevel()

    -- L'age du DROPTIMIZER, pas celui des poids de statistiques. Le champ s'appelait `simAge`
    -- et portait `Weights.AgeInDays()` : le tableau de guilde affichait donc la fraicheur
    -- d'une chaine Pawn en pretendant parler de simulation.
    local age = ns.SimC.DroptimizerAge()

    -- Rencontres couvertes par le droptimizer local. Ce sont des identifiants de journal, pas
    -- des resultats : aucun pourcentage ne quitte le poste, conformement a la consigne.
    local encounters = {}
    for _, group in ipairs(ns.Sim.ByEncounter() or {}) do
        if group.encounter and group.encounter > 0 then
            table.insert(encounters, group.encounter)
        end
    end
    table.sort(encounters)

    local specName = ""
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if getSpec and getInfo then
        local ok, index = pcall(getSpec)
        if ok and index then
            local fine, _, label = pcall(getInfo, index)
            if fine then specName = label or "" end
        end
    end

    return {
        name = UnitName("player") or "?",
        spec = specName,
        ilvl = equipped and math.floor(equipped + 0.5) or 0,
        fixes = summary.problems or 0,
        sim = (ns.db.droptimizer and ns.db.droptimizer.id) or "",
        simAge = age or -1,
        encounters = encounters,
    }
end

--- Fiche compacte, en un seul message.
---
--- Le champ nom ne sert plus qu'a la compatibilite : le recepteur l'ecrase par
--- l'expediteur du message, seule source qu'un tiers ne peut pas falsifier.
---
--- Le message est plafonne. La liste de rencontres grandit avec le nombre de boss
--- couverts par le droptimizer, et un message trop long est jete par le client en
--- silence : perdre la liste vaut mieux que perdre la fiche.
local function serialize(card)
    local head = table.concat({
        REPLY, encode(card.name), encode(card.spec), card.ilvl,
        card.fixes, encode(card.sim), card.simAge,
    }, "~")

    local encounters = table.concat(card.encounters or {}, ".")
    if #head + 1 + #encounters > MESSAGE_LIMIT then
        encounters = encounters:sub(1, math.max(0, MESSAGE_LIMIT - #head - 1)):match("^.*%.") or ""
        encounters = encounters:gsub("%.$", "")
    end

    return head .. "~" .. encounters
end

local function deserialize(message)
    local parts = { strsplit("~", message) }
    if parts[1] ~= REPLY then return nil end

    -- Le 8e champ est apparu apres coup : une fiche plus ancienne n'a pas de rencontres, ce
    -- qui doit rester lisible plutot que rejete.
    local encounters = {}
    for id in tostring(parts[8] or ""):gmatch("%d+") do
        table.insert(encounters, tonumber(id))
    end

    return {
        name = parts[2] or "?",
        spec = parts[3] or "",
        ilvl = tonumber(parts[4]) or 0,
        fixes = tonumber(parts[5]) or 0,
        sim = parts[6] or "",
        simAge = tonumber(parts[7]) or -1,
        encounters = encounters,
    }
end

--- Gains simules locaux, groupes par rencontre, en une chaine compacte.
---
--- Format : `encounter.instance.difficulte:itemID.centiemes.ilvl,...;encounter...:...`
--- Les centiemes evitent le point decimal et l'ambiguite de locale : 4,25 % s'ecrit 425.
---
--- Le niveau voyage avec : sans lui, l'interface retombe sur le niveau du modele d'objet,
--- qui ignore les identifiants de bonus et peut valoir 44 sur une piece de raid.
---
--- L'INSTANCE et la DIFFICULTE voyagent aussi, et c'est recent. Sans elles, l'onglet
--- Guilde appelait `Sim.LootLink` sans savoir dans quel raid ni a quelle difficulte
--- chercher : le journal des aventures ne rendait aucun lien, l'infobulle retombait sur
--- `SetItemByID`, et affichait le niveau du modele — le fameux 44 — juste a cote du niveau
--- simule, correct, de la ligne. Deux nombres contradictoires pour le meme objet.
---
--- Elles sont posees UNE fois par rencontre, pas par objet : quinze objets d'un meme boss
--- partagent forcement son instance et sa difficulte, et le canal est plafonne a 255 octets.
function Guild.SimPayload()
    local groups = ns.Sim.ByEncounter()
    if not groups then return "" end

    local blocks = {}
    for _, group in ipairs(groups) do
        local items = {}
        local difficulty
        for _, item in ipairs(group.items) do
            difficulty = difficulty or item.difficulty
            table.insert(items, string.format("%d.%d.%d",
                item.id, math.floor((item.percent or 0) * 100 + 0.5), item.ilvl or 0))
        end
        if #items > 0 then
            table.insert(blocks, string.format("%d.%d.%d:%s",
                group.encounter, group.instance or 0,
                ns.Sim.DifficultyID(difficulty), table.concat(items, ",")))
        end
    end
    return table.concat(blocks, ";")
end

--- Decoupe une charge utile sur des frontieres de separateur.
--- @param budget number octets disponibles pour le morceau, en-tete deduite
--- @return table|nil morceaux, ou nil si la charge utile ne tient pas dans la borne
local function chunkPayload(payload, budget)
    local chunks = {}
    budget = math.max(32, budget or 200)

    while #payload > budget do
        -- On coupe au dernier separateur avant la limite : un morceau tronque au milieu d'un
        -- couple objet/valeur produirait un nombre faux, pas une erreur visible.
        local cut = payload:sub(1, budget):match(".*[,;]")
        cut = cut and #cut or budget
        table.insert(chunks, payload:sub(1, cut))
        payload = payload:sub(cut + 1)

        -- Trop de morceaux : on n'envoie RIEN. Couper la liste en annoncant un total
        -- complet ferait assembler au recepteur une charge amputee qu'il croirait
        -- entiere — donc des gains faux, affiches sans le moindre signe.
        if #chunks >= MAX_CHUNKS then return nil end
    end
    if #payload > 0 then table.insert(chunks, payload) end
    return chunks
end

-- File d'envoi.
--
-- Le client plafonne le debit des messages addon et une deconnexion est le prix d'un
-- depassement. `sendSim` postait tous ses morceaux dans la meme frame : un gros
-- droptimizer en produit une vingtaine. Un message par tick suffit — une tournee de
-- guilde n'est pas une operation temps reel.
local outbox, ticker = {}, nil

local function pump()
    local message = table.remove(outbox, 1)
    if not message then
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, "GUILD")
    end
end

local function post(message)
    if #outbox >= MAX_CHUNKS + 4 then
        ns.Debug("file d'envoi saturee, message abandonne")
        return
    end
    table.insert(outbox, message)
    if not ticker then ticker = C_Timer.NewTicker(0.2, pump) end
end

local function sendSim()
    local payload = Guild.SimPayload()
    if payload == "" then return end

    -- `ITM~<index>~<total>~` : trois champs courts. Le nom ne voyage plus — il est pris
    -- sur l'expediteur du message, seule source qu'un tiers ne peut pas falsifier.
    local budget = MESSAGE_LIMIT - (#ITEMS + 10)
    local chunks = chunkPayload(payload, budget)
    if not chunks then
        ns.Debug("charge utile de %d octets au-dela de %d morceaux : rien n'est envoye",
            #payload, MAX_CHUNKS)
        return
    end

    for index, chunk in ipairs(chunks) do
        post(table.concat({ ITEMS, index, #chunks, chunk }, "~"))
    end
end

--- Reconstruit les gains d'un membre a partir de ses morceaux.
--- `name` est l'EXPEDITEUR du message, jamais un nom annonce dans la charge utile.
local function absorb(name, index, total, chunk)
    -- Bornes : `index` et `total` viennent du reseau. Un `total` de 100000 allouait
    -- autant d'entrees dans `parts` sur la foi d'un entier non verifie.
    if total < 1 or total > MAX_CHUNKS then return nil end
    if index < 1 or index > total then return nil end

    local pending = incoming[name]
    if not pending or pending.total ~= total then
        pending = { total = total, parts = {}, seen = 0 }
        incoming[name] = pending
    end
    pending.at = GetTime()

    if not pending.parts[index] then
        pending.parts[index] = chunk
        pending.seen = pending.seen + 1
    end
    if pending.seen < total then return nil end

    local payload = table.concat(pending.parts)
    incoming[name] = nil

    -- L'en-tete de bloc accepte les DEUX formes : `encounter:` et
    -- `encounter.instance.difficulte:`. Le canal de guilde met en presence des clients de
    -- versions differentes, et un membre reste au moins une session sur son ancienne
    -- version : refuser sa charge utile le ferait disparaitre du tableau sans un mot.
    local byEncounter = {}
    for head, list in payload:gmatch("([%d%.]+):([^;]+)") do
        local encounter, instance, difficulty = head:match("^(%d+)%.(%d+)%.(%d+)$")
        if not encounter then encounter = head:match("^(%d+)$") end

        local items = {}
        for itemID, centiemes, ilvl in list:gmatch("(%d+)%.(%d+)%.(%d+)") do
            items[tonumber(itemID)] = { percent = tonumber(centiemes) / 100, ilvl = tonumber(ilvl) }
        end

        if encounter then
            byEncounter[tonumber(encounter)] = {
                instance = tonumber(instance),
                difficulty = tonumber(difficulty),
                items = items,
            }
        end
    end
    return byEncounter
end

--- Demande a la guilde de se declarer.
function Guild.Request()
    if not IsInGuild() then
        ns.Print(L["you are not in a guild"])
        return false
    end
    if GetTime() - lastRequest < THROTTLE then return false end
    lastRequest = GetTime()

    roster = {}
    incoming = {}
    outbox = {}
    local card = Guild.LocalCard()
    -- Ses propres gains sont lus directement, sans passer par le canal.
    -- Meme FORME que ce que `absorb` reconstruit depuis le canal : instance et difficulte
    -- a cote des objets. Deux formes differentes selon la provenance obligeraient chaque
    -- lecteur a savoir d'ou vient la fiche.
    card.gains = {}
    for _, group in ipairs(ns.Sim.ByEncounter() or {}) do
        local items, difficulty = {}, nil
        for _, item in ipairs(group.items) do
            difficulty = difficulty or item.difficulty
            items[item.id] = { percent = item.percent, ilvl = item.ilvl }
        end
        card.gains[group.encounter] = {
            instance = group.instance,
            difficulty = ns.Sim.DifficultyID(difficulty),
            items = items,
        }
    end
    roster[card.name] = card

    post(REQUEST)
    return true
end

function Guild.Roster()
    local list = {}
    for _, card in pairs(roster) do table.insert(list, card) end
    table.sort(list, function(a, b)
        if a.fixes ~= b.fixes then return a.fixes > b.fixes end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

--- Une tournee est-elle en cours ?
---
--- Les reponses arrivent une par une et chacune redessine la vue. Un tri par urgence
--- ferait donc SAUTER les lignes sous les yeux pendant les cinq premieres secondes. Tant
--- que la tournee court, la vue trie par nom ; ensuite seulement par urgence.
function Guild.IsPolling()
    return (GetTime() - lastRequest) < THROTTLE
end

-- Age au-dela duquel un droptimizer ne decrit plus l'equipement actuel. Seuil d'AFFICHAGE :
-- un reset hebdomadaire suffit a perimer une simulation.
local STALE_DAYS = 7

--- Le roster, trie et qualifie, avec DEUX partitions du meme total.
---
--- Le mot « pret » a disparu de cette API, et c'est delibere. Il designait deux choses a
--- la fois — une simulation fraiche (`Summary.ready`) et « rien a corriger » — et l'ecran
--- affichait les deux sous le meme nom. Ici la fraicheur de simulation se dit `sim`, et
--- l'absence de tache se dit `clean`. Deux mots, deux sens.
---
--- INVARIANT : on ne rend un compte que s'il est exact sur TOUT le roster. Les deux
--- partitions somment donc chacune a `total`, et la vue peut les afficher cote a cote sans
--- qu'aucune paire de nombres ne se contredise. Les sous-etats a l'interieur d'un groupe
--- sont portes par le TRI et le GLYPHE, jamais par un sous-compte qui ne tomberait pas
--- juste — c'est exactement ce qui rendait l'ancien ecran illisible.
---
--- @return table { list, total, gear = { withFixes, clean }, sim = { missing, stale, fresh } }
function Guild.RosterState()
    local list = {}
    local state = {
        total = 0,
        gear = { withFixes = 0, clean = 0 },
        sim = { missing = 0, stale = 0, fresh = 0 },
    }

    for _, card in pairs(roster) do
        state.total = state.total + 1

        -- La colonne DROPTIMIZER mesure une FRAICHEUR, pas la possession d'un lien. Un
        -- joueur qui colle directement le CSV n'a aucun identifiant de rapport a diffuser :
        -- le compter « aucun droptimizer » dirait le contraire de ce qu'il vient de faire.
        -- Le lien ne decide plus que du chevron, qui ouvre le rapport quand il existe.
        local simState
        if (card.simAge or -1) < 0 then
            simState = "missing"
        elseif card.simAge >= STALE_DAYS then
            simState = "stale"
        else
            simState = "fresh"
        end
        state.sim[simState] = state.sim[simState] + 1

        local fixes = card.fixes or 0
        if fixes > 0 then
            state.gear.withFixes = state.gear.withFixes + 1
        else
            state.gear.clean = state.gear.clean + 1
        end

        -- Le glyphe de la ligne RECOPIE celui de la colonne qui a decide de son rang : la
        -- gouttiere ne porte jamais un alphabet a elle, sinon `!` finirait par vouloir dire
        -- deux choses selon la colonne ou on le lit.
        local glyph, rank
        if fixes > 0 then
            glyph, rank = "!", 1
        elseif simState == "missing" then
            glyph, rank = "x", 2
        elseif simState == "stale" then
            glyph, rank = "~", 3
        else
            glyph, rank = "+", 4
        end

        card.simState, card.glyph, card.rank = simState, glyph, rank
        card.needsWork = rank < 4
        table.insert(list, card)
    end

    -- Pendant la tournee, tri par NOM : les reponses arrivent une par une et chacune
    -- redessine la vue, donc un tri par urgence ferait sauter les lignes sous les yeux
    -- pendant les cinq premieres secondes.
    local polling = Guild.IsPolling()
    table.sort(list, function(a, b)
        if not polling then
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.rank == 1 and a.fixes ~= b.fixes then return a.fixes > b.fixes end
            -- A rang egal chez les perimes, le plus vieux droptimizer d'abord.
            if a.rank == 3 and a.simAge ~= b.simAge then return a.simAge > b.simAge end
        end
        return (a.name or "") < (b.name or "")
    end)

    state.list = list
    return state
end


--- Table de butin par rencontre, avec le classement des membres pour chaque objet.
---
--- Le classement descend du gain simule de chacun. Ces valeurs circulent sur le canal de
--- DONNEES de la guilde, invisible dans le chat : rien n'est affiche a personne qui n'ait
--- l'addon, et le partage reste opt-in.
--- @return table|nil { { encounter, name, items = { { id, best, members = { { name, spec, percent } } } } } }
function Guild.LootByEncounter()
    local groups, order = {}, {}

    for _, card in pairs(roster) do
        for encounter, block in pairs(card.gains or {}) do
            local group = groups[encounter]
            if not group then
                group = { encounter = encounter, name = ns.Sim.EncounterName(encounter),
                    items = {}, index = {} }
                groups[encounter] = group
                table.insert(order, group)
            end

            -- Instance et difficulte : le PREMIER membre qui les connait decide. Une fiche
            -- venue d'un client plus ancien ne les porte pas ; elle ne doit pas effacer
            -- celles d'un membre a jour, sans quoi le lien de butin se reperd.
            group.instance = group.instance or block.instance
            group.difficulty = group.difficulty or block.difficulty

            for itemID, gain in pairs(block.items or {}) do
                local item = group.index[itemID]
                if not item then
                    item = { id = itemID, members = {}, best = 0, ilvl = gain.ilvl,
                        instance = block.instance, difficulty = block.difficulty }
                    group.index[itemID] = item
                    table.insert(group.items, item)
                end
                item.ilvl = item.ilvl or gain.ilvl
                item.instance = item.instance or block.instance
                item.difficulty = item.difficulty or block.difficulty
                table.insert(item.members,
                    { name = card.name, spec = card.spec, percent = gain.percent })
                if gain.percent > item.best then item.best = gain.percent end
            end
        end
    end

    for _, group in ipairs(order) do
        group.index = nil
        group.best = 0
        for _, item in ipairs(group.items) do
            table.sort(item.members, function(a, b) return a.percent > b.percent end)
            if item.best > group.best then group.best = item.best end
        end
        -- Objets par meilleur gain de la guilde : ce qu'il faut viser en priorite.
        table.sort(group.items, function(a, b) return a.best > b.best end)
    end

    table.sort(order, function(a, b) return a.best > b.best end)
    return #order > 0 and order or nil
end

--- Resume texte du roster, pret a coller dans Discord.
function Guild.Export()
    local lines = { "GearProof — guild audit", "" }
    for _, card in ipairs(Guild.Roster()) do
        local sim = card.sim ~= "" and card.sim or "no sim"
        local age = card.simAge >= 0 and (card.simAge .. "d") or "-"
        table.insert(lines, string.format("%-16s %-12s ilvl %d  %d fix  sim %s (%s)",
            card.name, card.spec, card.ilvl, card.fixes, sim, age))
    end
    return table.concat(lines, "\n")
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

-- Reception.
--
-- Deux regles, tenues sans exception :
--
--   1. Le CANAL doit etre "GUILD". Le troisieme argument etait jete. Un message addon
--      chuchote avec le meme prefixe entrait donc par la meme porte, depuis n'importe
--      quel personnage du royaume.
--   2. Le nom qui fait foi est celui de l'EXPEDITEUR. Le roster etait indexe sur le nom
--      annonce dans la charge utile : n'importe qui pouvait ecraser la fiche de
--      n'importe quel membre, ou en inventer des milliers.
--
-- Le champ `name` de la fiche serialisee ne sert donc plus qu'a la compatibilite avec
-- les versions anterieures : il est lu, puis ecrase par l'expediteur.
ns.On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    if channel ~= "GUILD" then return end
    if type(message) ~= "string" then return end

    local who = whoSent(sender)
    if not who then return end

    if message == REQUEST then
        -- On ne repond que si le partage est explicitement autorise.
        if ns.db.shareWithGuild ~= true then return end

        -- Throttle en REPONSE. Sans lui, chaque REQ recu declenchait un audit complet,
        -- un regroupement des gains simules et une salve de messages, sans borne.
        local now = GetTime()
        if (now - lastReply) < REPLY_THROTTLE then return end
        lastReply = now

        post(serialize(Guild.LocalCard()))
        sendSim()
        return
    end

    -- Morceau de gains par objet.
    if message:sub(1, #ITEMS + 1) == ITEMS .. "~" then
        sweepIncoming()
        local _, index, total, chunk = strsplit("~", message, 4)
        local gains = absorb(who, tonumber(index) or 0, tonumber(total) or 0, chunk or "")
        if not gains then return end

        if roster[who] then
            roster[who].gains = gains
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        else
            -- Les gains sont arrives avant la fiche : on les garde pour elle, avec un
            -- horodatage pour que la purge puisse les oublier.
            incoming[who] = { resolved = gains, total = 0, parts = {}, seen = 0, at = GetTime() }
        end
        return
    end

    local card = deserialize(message)
    if not card then return end

    -- Nouvelle entree : la borne s'applique. Une fiche deja connue se met a jour, elle
    -- ne consomme pas de place supplementaire.
    if not roster[who] then
        local count = 0
        for _ in pairs(roster) do count = count + 1 end
        if count >= MAX_ROSTER then
            ns.Debug("roster plein (%d), fiche de %s ignoree", count, who)
            return
        end
    end

    card.name = who
    card.sender = sender

    -- Des gains arrives avant la fiche sont recuperes ici.
    local pending = incoming[who]
    if pending and pending.resolved then
        card.gains = pending.resolved
        incoming[who] = nil
    end

    roster[who] = card
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)
