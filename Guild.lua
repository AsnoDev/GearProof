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

-- LE DETAIL DES CORRECTIFS. Un type a part, jamais des champs de plus dans `REP`.
--
-- Deux raisons, et la seconde est la plus dure a rattraper. `REP` se termine par la liste
-- de rencontres, qui est TRONQUEE quand le message deborde : un champ intercale avant elle
-- serait relu comme un identifiant de rencontre par un client d'une autre version, et la
-- table de butin deviendrait fausse EN SILENCE. Un champ ajoute apres elle, lui, sort du
-- budget sans que rien ne le voie — `serialize` calcule la troncature sur l'en-tete seul,
-- et le client jette un message trop long sans un mot.
--
-- Un type inconnu, au contraire, est proprement ignore : un ancien client teste `ITM`,
-- echoue, tombe dans `deserialize` et rejette sur `parts[1] ~= REPLY`.
local EXTRA = "EXT"

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
-- Detail arrive avant sa fiche. Meme cas que les gains, meme remede.
local pendingDetail = {}
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

--- Retire les separateurs d'un champ.
---
--- LE `return` EST DELIBEREMENT EN DEUX TEMPS. `gsub` rend DEUX valeurs — la chaine et le
--- nombre de substitutions — et un appel en DERNIERE position d'un constructeur de table
--- les y verse toutes les deux. `{ TAG, encode(x) }` produisait donc un champ parasite
--- « 0 » sur le fil, invisible tant qu'aucun appelant ne mettait `encode` en dernier.
local function encode(value)
    local text = tostring(value or ""):gsub("[|~]", "")
    return text
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

-- Index d'emplacement -> lettre, et retour. Ce qui voyage est un NUMERO d'emplacement et
-- une lettre, pas un libelle : `Gear.SLOTS` est identique chez tout le monde, comme le
-- relevé lui-meme. Dix problemes tiennent dans soixante octets.
local PROBLEM_CODE = {
    empty = "v", enchant = "e", sockets = "s", durability = "d", oil = "o",
}
local CODE_PROBLEM = {}
for kind, code in pairs(PROBLEM_CODE) do CODE_PROBLEM[code] = kind end

--- Position d'un emplacement dans `Gear.SLOTS`, construite une fois.
local slotIndex
local function indexOfSlot(slot)
    if not slotIndex then
        slotIndex = {}
        for index, definition in ipairs(ns.Gear.SLOTS) do slotIndex[definition.slot] = index end
    end
    return slotIndex[slot]
end

--- Ce qui cloche chez MOI, sous forme d'index.
---
--- L'audit produit deja tout cela en local (`Gear.Scan`) ; seul le TOTAL voyageait, et un
--- officier lisait « ! 3 » sans pouvoir dire lesquels. On envoie donc les index, et c'est
--- le recepteur qui les detend contre SA copie du relevé — dans sa langue, sur la spe de
--- l'autre, sans rien demander de plus.
--- LE SAC EST DECIDE PAR L'EMETTEUR, et il ne peut pas en etre autrement : personne ne
--- voit le sac de personne. C'est le camarade qui repond « je l'ai deja », et c'est
--- precisement ce qu'aucun site ne pourra jamais dire.
---
--- TROIS ETATS, pas deux. « pas de reponse » n'est pas « il ne l'a pas » : le relevé ne
--- sait rattacher un objet qu'a 28 des 48 enchantements qu'il cite, et a aucune des huit
--- huiles. Afficher « a acheter » faute d'avoir pu verifier serait un mensonge poli.
--- @return table { { slot = index, kind = string, qty = number, owned = boolean|nil } }
function Guild.LocalDetail()
    local entries = ns.Gear.Scan()
    local found = {}

    -- L'objet qui corrigerait ce probleme, chez MOI, pour MA spe.
    local function fixableNow(slot, kind)
        local itemID
        if kind == "enchant" then
            local id = ns.Meta.Enchant(slot)
            itemID = id and ns.Meta.EnchantItem(id)
        elseif kind == "sockets" then
            itemID = ns.Meta.Gem()
        elseif kind == "oil" then
            local oils = ns.Meta.Oils()
            local best = oils and oils[1]
            itemID = best and ns.Meta.EnchantItem(best.id)
        end
        if not itemID then return nil end
        return ns.Bags.InBags(itemID)
    end
    for _, entry in ipairs(entries or {}) do
        local index = indexOfSlot(entry.slot)
        -- Une piece IGNOREE volontairement n'est pas un correctif : la signaler a la
        -- guilde reviendrait a denoncer un choix.
        if index and not entry.skipped and not entry.ignored then
            if entry.empty then
                table.insert(found, { slot = index, kind = "empty", qty = 1 })
            else
                if entry.missingEnchant then
                    table.insert(found, { slot = index, kind = "enchant", qty = 1,
                                          owned = fixableNow(entry.slot, "enchant") })
                end
                if (entry.emptySockets or 0) > 0 then
                    table.insert(found, { slot = index, kind = "sockets",
                                          qty = entry.emptySockets,
                                          owned = fixableNow(entry.slot, "sockets") })
                end
                if entry.damaged then
                    table.insert(found, { slot = index, kind = "durability", qty = 1 })
                end
                if entry.missingOil then
                    table.insert(found, { slot = index, kind = "oil", qty = 1,
                                          owned = fixableNow(entry.slot, "oil") })
                end
            end
        end
    end
    return found
end

--- Le message de detail : identite de spe, sceau du relevé, puis les index.
---
--- LE SCEAU N'EST PAS DECORATIF. Detendre un index contre un relevé d'un autre format
--- produirait du texte faux avec aplomb — un nom d'enchantement pris dans la mauvaise
--- table. Le recepteur compare, et s'il ne reconnait pas le format il n'en detend AUCUN.
local function serializeDetail(specID, detail)
    local stamp = ns.Meta.Stamp() or {}
    local head = table.concat({
        EXTRA, specID or 0, stamp.format or 0, encode(stamp.generatedAt or ""),
    }, "~")

    local parts = {}
    for _, item in ipairs(detail or {}) do
        local code = PROBLEM_CODE[item.kind]
        if code then
            -- « + » il l'a, « - » il ne l'a pas, RIEN quand on n'a pas pu verifier. Un
            -- caractere, trois etats, et l'absence garde son sens.
            local owned = (item.owned == true and "+") or (item.owned == false and "-") or ""
            table.insert(parts,
                item.slot .. code .. ((item.qty or 1) > 1 and item.qty or "") .. owned)
        end
    end

    -- Le budget se calcule sur l'en-tete REEL, pas sur un chiffre rond : c'est la faute qui
    -- faisait jeter les fiches aux noms longs.
    local codes = table.concat(parts, ",")
    if #head + 1 + #codes > MESSAGE_LIMIT then
        codes = codes:sub(1, math.max(0, MESSAGE_LIMIT - #head - 1)):match("^.*,") or ""
        codes = codes:gsub(",$", "")
    end
    return head .. "~" .. codes
end

--- « + » vu, « - » vu, rien du tout. Trois etats, ecrits en clair faute de pouvoir les
--- exprimer avec `and`/`or`.
local function ownedState(mark)
    if mark == "+" then return true end
    if mark == "-" then return false end
    return nil
end

--- Lecture d'un message de detail. Rend nil sur tout ce qui ne se relit pas exactement.
local function deserializeDetail(message)
    local tag, specID, format, date, codes = strsplit("~", message, 5)
    if tag ~= EXTRA then return nil end

    local found = {}
    for slot, code, qty, owned in string.gmatch(codes or "", "(%d+)(%a)(%d*)([+%-]?)") do
        local kind = CODE_PROBLEM[code]
        local index = tonumber(slot)
        if kind and index and ns.Gear.SLOTS[index] then
            table.insert(found, {
                slot = index, kind = kind, qty = tonumber(qty) or 1,
                -- Trois etats, et `and/or` NE SAIT PAS les exprimer : en Lua,
                -- `(x and false) or nil` rend nil, parce que `or` ne distingue pas `false`
                -- de `nil`. Le deuxieme etat s'effondrait donc sur le troisieme, et « il ne
                -- l'a pas » devenait « on n'a pas pu verifier ».
                owned = ownedState(owned),
            })
        end
    end

    return {
        specID = tonumber(specID) or nil,
        format = tonumber(format) or 0,
        --  ne fait que retirer les separateurs : il n'y a rien a defaire.
        generatedAt = date or "",
        detail = found,
    }
end

--- L'INDEX DEVIENT UNE PHRASE.
---
--- C'est le coeur du dispositif, et il tient a une propriete qu'aucun concurrent n'a : les
--- quarante blocs de `Data/Meta.lua` sont IDENTIQUES chez tous les membres. Le camarade
--- n'envoie donc pas « il me manque l'Enchantement de cape - Souffle du Neant » — il envoie
--- « emplacement 4, enchantement » — et c'est NOTRE client qui nomme, chiffre et traduit,
--- contre la reference de SA specialisation a lui.
---
--- Un site ne peut pas le faire : il ne verrait ni le sac ni la durabilite, et il aurait un
--- jour de retard. Un addon de roster ne peut pas le faire : il n'embarque pas de relevé.
---
--- SCEAU D'ABORD. Si le relevé d'en face n'est pas du meme format que le notre, on ne
--- detend AUCUN index : un nom pris dans la mauvaise table serait faux avec aplomb, et
--- rien ne le signalerait. On rend la raison plutot qu'une liste.
---
--- @return table|nil lignes { label, advice, share, kind, qty }, string|nil raison
function Guild.Explain(card)
    if not card or not card.detail or #card.detail == 0 then return nil end

    local mine = ns.Meta.Stamp() or {}
    local theirs = card.stamp or {}
    if (theirs.format or 0) ~= (mine.format or 0) then
        return nil, L["their reference is not in the format this addon reads"]
    end

    -- Sans identifiant de spe, on sait QUOI manque mais pas contre quelle population le
    -- mesurer. On rend quand meme les emplacements : c'est deja plus que le total.
    local reader = card.specID and ns.Meta.For(card.specID) or nil

    -- MON PROPRE OBJET SERT DE GABARIT. `Meta.EnchantName` sait nommer un enchantement de
    -- deux facons : par l'objet qui l'applique quand le relevé le connait, sinon en lisant
    -- l'infobulle d'un objet REEL dans lequel il injecte l'enchantement. La seconde voie
    -- couvre les vingt enchantements sur quarante-huit que le relevé ne sait pas rattacher
    -- a un objet — mais il lui faut un objet, n'importe lequel du bon emplacement.
    --
    -- Celui de l'AUTRE, on ne l'a pas : rien de son equipement ne voyage. Le notre suffit,
    -- puisque seul le champ d'enchantement compte.
    local worn = {}
    for _, entry in ipairs(ns.Gear.Scan() or {}) do
        if entry.link then worn[entry.slot] = entry.link end
    end

    local lines = {}
    for _, item in ipairs(card.detail) do
        local definition = ns.Gear.SLOTS[item.slot]
        if definition then
            local advice, share
            if reader then
                local template = worn[definition.slot]
                if item.kind == "enchant" then
                    local id, part = reader.Enchant(definition.slot)
                    advice, share = id and ns.Meta.EnchantName(template, id), part
                elseif item.kind == "sockets" then
                    local id, part = reader.Gem()
                    advice, share = id and ns.Meta.GemName(id), part
                elseif item.kind == "oil" then
                    local id, part = reader.Oil()
                    advice, share = id and ns.Meta.EnchantName(template, id), part
                end
            end
            table.insert(lines, {
                label = definition.label,
                kind = item.kind,
                qty = item.qty or 1,
                advice = advice,
                share = share,
                owned = item.owned,
            })
        end
    end

    return (#lines > 0) and lines or nil
end

--- Annonce spontanee : « j'ai du neuf ».
---
--- Le protocole est un APPEL/REPONSE, et c'est une bonne chose : personne n'emet en
--- continu, rien ne circule tant qu'on ne demande rien. Mais il laissait un trou —
--- celui qui rafraichit ses donnees reste affiche avec les anciennes jusqu'a la prochaine
--- tournee, c'est-a-dire au pire moment.
---
--- On emet donc la FICHE et le DETAIL, jamais les gains : c'est ce qui change l'etat lu
--- par un officier, et ca tient en deux messages courts. Les gains, eux, coutent jusqu'a
--- quarante morceaux — ils restent reserves a une vraie tournee.
---
--- Le meme verrou de partage et le meme etranglement que pour une reponse : une annonce
--- est une reponse dont le declencheur est « j'ai du neuf » au lieu de « on m'a demande ».
--- @return boolean vrai si quelque chose est parti
function Guild.Announce()
    if not IsInGuild() then return false end
    if ns.db.shareWithGuild ~= true then return false end

    local now = GetTime()
    if (now - lastReply) < REPLY_THROTTLE then return false end
    lastReply = now

    post(serialize(Guild.LocalCard()))
    post(serializeDetail(ns.Spec.Active(), Guild.LocalDetail()))
    return true
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
    pendingDetail = {}
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
        post(serializeDetail(ns.Spec.Active(), Guild.LocalDetail()))
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

    -- Detail des correctifs. Il peut arriver AVANT ou APRES la fiche : on le range dans la
    -- fiche quand elle est la, et on le garde de cote sinon — meme regle que les gains.
    if message:sub(1, #EXTRA + 1) == EXTRA .. "~" then
        local extra = deserializeDetail(message)
        if not extra then return end
        if roster[who] then
            roster[who].specID = extra.specID
            roster[who].stamp = { format = extra.format, generatedAt = extra.generatedAt }
            roster[who].detail = extra.detail
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        else
            pendingDetail[who] = extra
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

    -- Le detail aussi : les trois messages partent a la suite, mais rien ne garantit
    -- l'ordre d'arrivee.
    local extra = pendingDetail[who]
    if extra then
        card.specID = extra.specID
        card.stamp = { format = extra.format, generatedAt = extra.generatedAt }
        card.detail = extra.detail
        pendingDetail[who] = nil
    end

    roster[who] = card
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end)
