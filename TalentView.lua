local _, ns = ...

local TalentView = {}
ns.TalentView = TalentView

local L = ns.L

-- Onglet Talents : l'ARBRE, comme en jeu, avec le choix du contenu.
--
-- La premiere version affichait deux listes — les builds, puis les talents par taux
-- d'adoption. « C'est peu clair » : une liste de noms ne dit pas ou un talent se trouve
-- dans l'arbre, ni ce qu'il coupe, ni ce qu'il ouvre. Un arbre se lit d'un coup d'oeil
-- parce que c'est la forme dans laquelle le joueur l'a appris.
--
-- CE QUI A ETE CORRIGE EN CHEMIN, ET QUI ETAIT GRAVE. Les noms de talents etaient resolus
-- par `C_Spell.GetSpellInfo`, en supposant que le `talentID` de Warcraft Logs etait un
-- identifiant de SORT. Il ne l'est pas — voir `Traits.lua`. Or `GetSpellInfo` rendait
-- quand meme un nom, celui d'un sort sans rapport : la liste affichait des noms FAUX mais
-- plausibles. Tout passe maintenant par `C_Traits`, qui est la source du client lui-meme.
--
-- L'ARBRE DESSINE EST CELUI DE LA SPE ACTIVE. Aucune API ne rend l'arbre d'une autre spe
-- sans y basculer. Quand la spe regardee n'est pas la spe jouee, on le dit et on retombe
-- sur la liste, qui reste vraie.
--
-- L'EXPORT est toujours propose, et le controle se fait au CLIC. Il etait masque tant que
-- le format n'etait pas verifie : le joueur ne voyait donc rien et n'avait aucun moyen de
-- savoir qu'une fonctionnalite existait. Quand le format ne correspond pas, la fenetre
-- rend les DEUX chaines — celle du client et la notre — parce qu'un « format non reconnu »
-- sans elles est un cul-de-sac que personne ne peut reparer.

local NODE = 30
local NODE_GAP = 6
-- Espace entre l'arbre principal et celui de heros. Assez large pour qu'on lise deux
-- dessins et non un seul qui deborde.
local HERO_GAP = 24
local SECTION_GAP = 18

local view, pools
local content = "raid"

local function hex(key)
    return ns.Theme.C(key)
end

-- ------------------------------------------------------------------- widgets

--- Une LIAISON entre deux noeuds.
---
--- `CreateLine` est le type de widget que Blizzard utilise pour son propre arbre : il se
--- pose par deux ancres et se charge de l'angle. Une texture pivotee ne ferait pas
--- l'affaire — `SetRotation` tourne l'image DANS sa region, pas la region.
local function newEdge()
    local line = view.content:CreateLine(nil, "BACKGROUND")
    line:SetThickness(2)
    return line
end

local function newNode()
    local button = CreateFrame("Button", nil, view.content, "BackdropTemplate")
    button:SetSize(NODE, NODE)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.rank = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.rank:SetPoint("BOTTOMRIGHT", 1, 0)

    return button
end

local function newText()
    local label = view.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    return label
end

local function resetNode(button)
    button.node, button.share, button.chosen = nil, nil, nil
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
end

local function hideTooltip()
    GameTooltip:Hide()
end

local function nodeOnEnter(self)
    local node = self.node
    if not node then return end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine((self.chosen and self.chosen.name) or node.name
        or ("#" .. tostring(node.id)))
    if self.pickedRank then
        GameTooltip:AddDoubleLine(L["taken by the top build"],
            string.format("%d/%d", self.pickedRank, node.maxRanks or 1),
            0.54, 0.54, 0.54, 0, 0.9, 0.46)
    else
        GameTooltip:AddLine(L["not taken by the top build"], 0.54, 0.54, 0.54)
    end
    -- L'ADOPTION est une mesure differente du build : elle compte tous les joueurs
    -- releves, pas seulement ceux du groupe dominant. Un talent que le build de tete
    -- ignore peut etre pris par la moitie du haut de tableau.
    if self.share then
        GameTooltip:AddDoubleLine(L["taken by"],
            string.format("%d%%", self.share * 100 + 0.5),
            0.54, 0.54, 0.54, 0.91, 0.91, 0.91)
    end
    GameTooltip:Show()
end

-- --------------------------------------------------------------------- rendu

local function text(top, width, value)
    local label = pools.text:Acquire()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", 2, top)
    label:SetWidth(width - 4)
    label:SetText(value)
    return top - math.ceil(label:GetStringHeight() or 14) - 4
end

local function heading(top, width, label)
    top = top - (top < 0 and SECTION_GAP or 0)
    return text(top, width, hex("link") .. label:upper() .. "|r") - 6
end

--- Adoption par identifiant du relevé, pour le contenu choisi.
local function shareByID()
    local out = {}
    for _, entry in ipairs(ns.Meta.Talents(content) or {}) do
        out[entry.id] = entry.share
    end
    return out
end

--- L'ARBRE. Rend le nouveau haut, ou nil quand il n'est pas dessinable.
---
--- Trois raisons de ne pas etre dessinable, toutes dites au joueur plutot que masquees :
--- le client ne rend pas d'arbre, la spe regardee n'est pas la spe jouee, ou le relevé
--- parle un espace d'identifiants que l'arbre ne reconnait pas.
--- @return number|nil top, string|nil raison
local function layoutTree(top, width)
    local builds = ns.Meta.Builds(content)
    local build = builds and builds[1]
    if not build or not build.nodes then return nil, L["The reference does not carry a full tree for this content."] end

    if ns.Spec.Selected() ~= ns.Spec.Active() then
        return nil, L["The tree can only be drawn for the spec you are playing."]
    end

    local shot = ns.Traits.Snapshot()
    if not shot then return nil, L["The client did not return a talent tree."] end

    local match = ns.Traits.Match(build.nodes)
    -- Une correspondance partielle est un signe de desynchronisation, pas un detail : la
    -- moitie de l'arbre serait fausse. On exige large plutot que d'afficher a moitie.
    if not match or match.matched < math.floor(match.total * 0.8) then
        return nil, L["The reference talent ids do not match this client's tree."]
    end

    local shares = shareByID()

    -- DEUX ARBRES, DEUX REPERES.
    --
    -- Les noeuds de heros portent un `subTree` et vivent dans un systeme de coordonnees
    -- qui leur est propre. Normalises avec le reste, ils atterrissaient en haut a droite,
    -- colles a l'arbre de spe — alors qu'en jeu ils sont en bas, au centre. On les sort
    -- donc du calcul principal et on leur donne leur propre bloc.
    local main, heroes = ns.Traits.SplitTrees(shot)
    if #main == 0 then return nil, L["The client did not return a talent tree."] end

    --- Etendue d'un groupe de noeuds.
    local function bounds(list)
        local minX, maxX, minY, maxY
        for _, node in ipairs(list) do
            minX = math.min(minX or node.x, node.x)
            maxX = math.max(maxX or node.x, node.x)
            minY = math.min(minY or node.y, node.y)
            maxY = math.max(maxY or node.y, node.y)
        end
        return minX, maxX, minY, maxY
    end

    --- Ecart le plus SERRE entre deux positions distinctes.
    ---
    --- Une taille de noeud fixe et une echelle calculee sur la largeur se contredisent des
    --- que l'arbre est dense : deux colonnes voisines finissent a douze pixels l'une de
    --- l'autre et les icones se recouvrent. La taille se plie donc a l'ecart le plus court.
    local function tightestGap(list)
        local tightest
        for index = 1, #list do
            for other = index + 1, #list do
                local gap = math.max(math.abs(list[index].x - list[other].x),
                                     math.abs(list[index].y - list[other].y))
                if gap > 0 then tightest = math.min(tightest or gap, gap) end
            end
        end
        return tightest
    end

    local minX, maxX, minY, maxY = bounds(main)
    if not minX or maxX == minX then
        return nil, L["The client did not return a talent tree."]
    end

    local usable = width - NODE - 8
    local scale = usable / (maxX - minX)
    local gap = tightestGap(main)
    local size = gap and math.max(14, math.min(NODE, gap * scale - 2)) or NODE

    top = heading(top, width, L["Talent tree"])
    -- « Top build : 0 % des meilleurs joueurs » : la ligne lisait `build.share`, qui
    -- n'existe plus depuis qu'on publie l'arbre du PREMIER AU SCORE et non un groupe. Elle
    -- affichait donc zero — un chiffre faux, et le pire genre : plausible.
    top = text(top, width, hex("muted")
        .. L["Mythic+ only. Hover a node for its adoption among the top players."] .. "|r")

    -- Position finale de chaque noeud, tous arbres confondus. Les liaisons s'y reperent
    -- ensuite sans avoir a savoir de quel arbre vient chaque extremite.
    local placed = {}
    local origin = top - 4
    for _, node in ipairs(main) do
        placed[node.id] = {
            x = 4 + (node.x - minX) * scale,
            y = origin - (node.y - minY) * scale,
        }
    end
    local bottom = origin - (maxY - minY) * scale - size

    -- L'ARBRE DE HEROS RETENU : celui que le build joue.
    --
    -- Une specialisation en propose plusieurs et n'en joue qu'un. Les afficher tous
    -- remplirait la page de noeuds eteints qui ne decrivent personne — c'est d'ailleurs la
    -- grille grise qui trainait au milieu. On garde celui ou le build a pris le plus de
    -- noeuds, et a defaut aucun.
    local bestTree, bestCount
    for subTree, list in pairs(heroes) do
        local taken = 0
        for _, node in ipairs(list) do
            if match.selection[node.id] then taken = taken + 1 end
        end
        if taken > 0 and (not bestCount or taken > bestCount) then
            bestTree, bestCount = subTree, taken
        end
    end

    --- LA COLONNE DU MILIEU, celle que le jeu laisse vide entre classe et specialisation.
    ---
    --- L'arbre de heros y vit — capture du jeu a l'appui : DEATH KNIGHT a gauche,
    --- SAN'LAYN au centre, BLOOD a droite. Le poser sous l'arbre, comme on le faisait,
    --- l'eloignait de sa place et allongeait la page pour rien.
    ---
    --- On ne devine pas la colonne : on cherche le plus grand TROU horizontal entre deux
    --- positions voisines de l'arbre principal. Quand il n'y en a pas de franc — un pas de
    --- grille suffit a l'expliquer — on retombe sous l'arbre, ou le dessin reste lisible.
    local function middleColumn()
        local xs, seen = {}, {}
        for _, node in ipairs(main) do
            if not seen[node.x] then seen[node.x] = true table.insert(xs, node.x) end
        end
        table.sort(xs)
        if #xs < 3 then return nil end

        local widest, at = 0, nil
        for index = 2, #xs do
            local hole = xs[index] - xs[index - 1]
            if hole > widest then widest, at = hole, index end
        end
        -- Le trou doit valoir NETTEMENT plus qu'un pas de grille, sinon ce n'est pas une
        -- colonne vide mais deux colonnes voisines.
        local step = tightestGap(main)
        if not step or widest < step * 2.5 then return nil end
        return xs[at - 1], xs[at]
    end

    local heroLabel
    if bestTree then
        local list = heroes[bestTree]
        local hminX, hmaxX, hminY, hmaxY = bounds(list)
        local span = math.max(1, hmaxX - hminX)
        local heroGap = tightestGap(list)

        -- Meme pas de grille que l'arbre principal : deux arbres a des echelles
        -- differentes sur la meme page ne se lisent pas comme un seul dessin.
        local heroScale = heroGap and (size + 4) / heroGap or scale
        local heroWidth = span * heroScale

        local leftX, rightX = middleColumn()
        local left, top0
        if leftX then
            -- Centre dans le trou, et aligne en HAUT de l'arbre : c'est la place du jeu.
            local holeLeft = 4 + (leftX - minX) * scale + size
            local holeRight = 4 + (rightX - minX) * scale
            left = math.max(4, holeLeft + (holeRight - holeLeft - heroWidth - size) / 2)
            top0 = origin
        else
            left = math.max(4, (width - heroWidth - size) / 2)
            bottom = bottom - HERO_GAP
            top0 = bottom
        end

        heroLabel = { top = top0, name = ns.Traits.SubTreeName(bestTree), left = left }
        top0 = top0 - 18

        for _, node in ipairs(list) do
            placed[node.id] = {
                x = left + (node.x - hminX) * heroScale,
                y = top0 - (node.y - hminY) * heroScale,
            }
        end
        local heroBottom = top0 - (hmaxY - hminY) * heroScale - size
        -- La page descend jusqu'au plus bas des deux dessins.
        if heroBottom < bottom then bottom = heroBottom end
    end

    if heroLabel then
        local label = pools.text:Acquire()
        label:ClearAllPoints()
        -- Le titre se pose AU-DESSUS de son arbre, pas a la marge : centre dans la
        -- colonne, il dit de quel dessin il parle.
        label:SetPoint("TOPLEFT", math.max(2, heroLabel.left), heroLabel.top)
        label:SetWidth(math.max(80, width - heroLabel.left))
        label:SetText(hex("link") .. (heroLabel.name or L["Hero talents"]):upper() .. "|r")
    end

    -- LES LIAISONS D'ABORD, sous les noeuds : posees apres, elles passeraient dessus.
    local dim = ns.Theme.RGB.muted or { 0.5, 0.5, 0.5 }
    local lit = ns.Theme.RGB.link or { 0, 0.7, 1 }
    for nodeID, from in pairs(placed) do
        local node = shot.nodes[nodeID]
        for _, targetID in ipairs((node and node.edges) or {}) do
            local to = placed[targetID]
            if to then
                local line = pools.edge:Acquire()
                line:ClearAllPoints()
                line:SetStartPoint("TOPLEFT", view.content, from.x + size / 2, from.y - size / 2)
                line:SetEndPoint("TOPLEFT", view.content, to.x + size / 2, to.y - size / 2)
                -- Une liaison ALLUMEE quand ses deux extremites sont prises : c'est le
                -- chemin que le build a reellement emprunte, et c'est ce qui fait lire
                -- l'arbre d'un coup d'oeil plutot que noeud par noeud.
                local live = match.selection[nodeID] and match.selection[targetID]
                local rgb = live and lit or dim
                line:SetColorTexture(rgb[1], rgb[2], rgb[3], live and 0.9 or 0.25)
                line:Show()
            end
        end
    end

    for nodeID, at in pairs(placed) do
        local node = shot.nodes[nodeID]
        local picked = match.selection[nodeID]
        local button = pools.node:Acquire()
        button:SetParent(view.content)
        button:ClearAllPoints()
        button:SetSize(size, size)
        button:SetPoint("TOPLEFT", at.x, at.y)

        -- L'ICONE DE LA BRANCHE PRISE sur un noeud a choix. La premiere entree servait
        -- pour tout le monde : le noeud s'allumait juste et portait l'icone de l'autre
        -- option.
        local chosen = picked and picked.entryID and node.entries[picked.entryID]
        button.icon:SetTexture((chosen and chosen.icon) or node.icon
            or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- PRIS ou PAS PRIS, et rien entre les deux : la couleur seule ne porte jamais
        -- l'information ici non plus, le rang l'ecrit en chiffres.
        button.icon:SetDesaturated(not picked)
        button.icon:SetAlpha(picked and 1 or 0.3)
        ns.Theme.ApplyCard(button, picked and ns.Theme.RGB.link or nil)

        local maxRanks = node.maxRanks or 1
        button.rank:SetText((picked and maxRanks > 1)
            and (hex("text") .. picked.rank .. "|r") or "")

        button.node = node
        button.chosen = chosen
        button.pickedRank = picked and picked.rank or nil
        button.share = picked and shares[picked.sourceID] or nil
        button:SetScript("OnEnter", nodeOnEnter)
        button:SetScript("OnLeave", hideTooltip)
        button:Show()
    end

    return bottom - NODE_GAP
end

-- Au-dela, la liste cesse d'etre lisible et l'ecart n'est plus « quelques talents » mais
-- « un autre build ». On le DIT plutot que de derouler quarante lignes.
local DIFF_LIMIT = 10

local DIFF_MARK = {
    take = "+", drop = "-", rank = "~", swap = "/",
}
local DIFF_LABEL = {
    take = "to take", drop = "to drop", rank = "other rank", swap = "other branch",
}

--- TON ARBRE CONTRE LE LEUR, ligne par ligne.
---
--- L'onglet dessinait l'arbre du haut de tableau et le coloriait par adoption, mais
--- comparer restait a la charge du joueur : icone par icone, sa propre fenetre de talents
--- ouverte a cote. La question qu'il se pose est « qu'est-ce que je change ? », et elle se
--- repond en une liste.
local function layoutDifferences(top, width)
    local builds = ns.Meta.Builds(content)
    local build = builds and builds[1]
    if not build or not build.nodes then return top end
    if ns.Spec.Selected() ~= ns.Spec.Active() then return top end

    local match = ns.Traits.Match(build.nodes)
    local diff = match and ns.Traits.Compare(match)

    top = heading(top - SECTION_GAP, width, L["Against your tree"])
    if not diff then
        return text(top, width, hex("good") .. L["Identical to the published tree."] .. "|r")
    end

    for index, entry in ipairs(diff) do
        if index > DIFF_LIMIT then
            return text(top - 2, width, hex("muted") .. string.format(
                L["and %d more — you are playing a different build"], #diff - DIFF_LIMIT)
                .. "|r")
        end
        local tint = (entry.kind == "take" and "link") or (entry.kind == "drop" and "bis")
            or "muted"
        -- Le RANG n'est ecrit que quand il porte l'information : « 1 -> 2 » sur un talent
        -- a plusieurs rangs, rien sur un talent binaire ou il ne dirait que « pris ».
        local detail = ns.L[DIFF_LABEL[entry.kind] or entry.kind]
        if entry.kind == "rank" then
            detail = string.format("%s %d -> %d", detail, entry.mine, entry.theirs)
        end
        top = text(top, width, string.format("%s%s|r  %s%s|r  %s%s|r",
            hex(tint), DIFF_MARK[entry.kind] or "?",
            hex("text"), entry.name or ("#" .. entry.id),
            hex("muted"), detail))
    end
    return top
end

--- CE QU'EST L'ARBRE AFFICHE, et a quel point il fait consensus.
---
--- Une liste de builds classes par adoption a existe ici. Elle n'a plus d'objet : mesure
--- sur dix specialisations, le groupe de tete rassemble de 5 % a 25 % des joueurs, et six
--- fois sur dix les vingt premiers jouent vingt arbres differents. Publier des parts dans
--- ces eaux-la revenait a presenter l'arbre d'un seul joueur comme un consensus.
---
--- Ce qui reste vrai tient en deux phrases : cet arbre est celui du premier au score, et
--- voici combien d'arbres differents on a comptes. Le second chiffre est exactement ce qui
--- empeche de lire le premier comme LE build de la specialisation.
local function layoutBuilds(top, width)
    local distinct, sample = ns.Meta.BuildSpread(content)
    if not distinct then
        return text(top, width, hex("muted") .. L["No build recorded for this content."] .. "|r")
    end

    top = heading(top, width, L["Builds"])
    top = text(top, width, hex("text")
        .. L["This tree is the one played by the best-ranked player."] .. "|r")
    return text(top - 2, width, hex("muted") .. string.format(
        L["%d different trees among the %d players measured"], distinct, sample) .. "|r")
end

-- ------------------------------------------------------------------- public

--- Ouvre la fenetre de copie avec la chaine d'import du build de tete.
---
--- LE BOUTON RESTE VISIBLE MEME QUAND IL NE PEUT PAS. Il etait masque tant que le format
--- n'etait pas verifie : le joueur ne voyait donc rien, et n'avait aucun moyen de savoir
--- qu'une fonctionnalite existait ni pourquoi elle manquait. Un bouton qui explique vaut
--- mieux qu'une absence qui se devine.
local function exportBuild()
    local text = ns.Meta.BuildImport(content)
    if text then
        ns.Copy.Show(L["Talent import string"], text)
        return
    end

    -- IL N'Y A PLUS DE SERIALISEUR DERRIERE CE BOUTON. L'addon reconstruisait la chaine a
    -- partir des noeuds, avec un format binaire retrouve en comparant des chaines reelles :
    -- un bit de difference et le jeu refusait tout, sans que rien ne puisse l'expliquer au
    -- joueur. Le relevé porte desormais la chaine telle que Raider.IO la publie, donc soit
    -- elle est la, soit le relevé ne la porte pas — et il n'y a pas de troisieme cas a
    -- diagnostiquer.
    ns.Print("%s%s|r", hex("bis"),
        L["The reference does not carry an import string for this content."])
end

function TalentView.Create(parent)
    if view then return view end

    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- LE CHOIX DU CONTENU, en tete, parce qu'il change tout le reste de la page. Deux
    -- boutons plutot qu'un menu : il n'y a que deux reponses.
    view.modes = {}
    for index, mode in ipairs({
        { key = "raid",   label = "Raid" },
        { key = "mythic", label = "Mythic+" },
    }) do
        local button = CreateFrame("Button", nil, view, "BackdropTemplate")
        button:SetSize(96, 22)
        button:SetPoint("TOPLEFT", (index - 1) * 100, -2)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.text:SetPoint("CENTER")
        button.key = mode.key
        button.label = mode.label
        button:SetScript("OnClick", function(self)
            content = self.key
            TalentView.Refresh()
        end)
        view.modes[index] = button
    end

    view.export = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.export:SetSize(180, 22)
    view.export:SetPoint("TOPLEFT", 210, -2)
    ns.Localize(view.export, "Copy import string")
    view.export:SetScript("OnClick", exportBuild)

    view.intro = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    view.intro:SetPoint("TOPLEFT", 400, -8)
    view.intro:SetJustifyH("LEFT")

    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetPoint("TOPLEFT", 0, -30)
    view.scroll:SetPoint("BOTTOMRIGHT", -28, 0)

    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(600, 1)
    view.scroll:SetScrollChild(view.content)
    ns.Theme.CleanScrollBar(view.scroll)

    pools = {
        edge = ns.Pool.New(newEdge),
        node = ns.Pool.New(newNode, resetNode),
        text = ns.Pool.New(newText),
    }

    return view
end

function TalentView.Refresh()
    if not view then return end
    ns.Pool.ResetAll(pools)

    -- LE SELECTEUR NE PROPOSE QUE CE QUE LE RELEVE PORTE. Le raid n'est plus releve : un
    -- bouton « Raid » ouvrirait un ecran dont tout le contenu serait l'explication de son
    -- propre vide. On ne cable pas « mythique+ uniquement » pour autant — c'est le relevé
    -- qu'on interroge, donc un relevé de raid qui reviendrait ferait reapparaitre le bouton
    -- sans qu'une ligne change ici.
    local available = ns.Meta.Contents()
    local offered = {}
    for _, key in ipairs(available) do offered[key] = true end

    -- Le contenu regarde doit exister. Sans ce repli, un onglet ouvert sur « Raid » avant
    -- une mise a jour du relevé resterait bloque sur un ecran vide.
    if not offered[content] then content = available[1] or "mythic" end

    local shown = 0
    for _, button in ipairs(view.modes) do
        if offered[button.key] and #available > 1 then
            -- Un seul contenu disponible : un selecteur a un bouton ne selectionne rien.
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", shown * 100, -2)
            shown = shown + 1
            local active = button.key == content
            ns.Theme.ApplyCard(button, active and ns.Theme.RGB.link or nil)
            button.text:SetText(
                (active and hex("link") or hex("muted")) .. L[button.label] .. "|r")
            button:Show()
        else
            button:Hide()
        end
    end

    -- Le bouton d'export suit : sans selecteur, il n'a plus a lui laisser la place.
    view.export:ClearAllPoints()
    view.export:SetPoint("TOPLEFT", shown * 100 + (shown > 0 and 10 or 0), -2)

    view.intro:SetWidth(math.max(120, (view:GetWidth() or 600) - 410))
    view.intro:SetText(hex("muted") .. (content == "mythic"
        and L["Talent trees played in Mythic+ dungeons."]
        or L["Talent trees played on raid bosses."]) .. "|r")

    local available = math.max(360, (view.scroll:GetWidth() or 700) - 8)
    local width = math.min(760, available)
    view.content:SetWidth(available)

    local top = 0
    if not ns.Meta.Available() then
        top = text(top, width, hex("muted")
            .. L["no top-build reference for this spec yet"] .. "|r")
    else
        local drawn, reason = layoutTree(top, width)
        if drawn then
            top = layoutDifferences(drawn, width)
        else
            -- L'ARBRE OU RIEN. Une liste de noms classes par adoption tenait lieu de repli :
            -- elle se lisait comme un choix de talents, alors qu'elle n'en etait pas un —
            -- les seize talents les plus pris de l'echantillon ne forment aucun build reel,
            -- et deux d'entre eux peuvent s'exclure. On DIT pourquoi l'arbre n'est pas la,
            -- et on ne publie rien d'autre.
            top = text(top, width, hex("bis") .. reason .. "|r")
        end
        top = layoutBuilds(top, width)
    end

    view.content:SetHeight(math.max(1, -top + 12))
end
