local _, ns = ...

local Spec = {}
ns.Spec = Spec

-- Specialisations de la classe jouee. L'audit s'appuie sur un releve par spe : il faut donc
-- savoir laquelle regarder, et pouvoir en regarder une autre sans changer de spe en jeu.
--
-- Les trois familles Get*Info* DIVERGENT a partir de la position 6. On ecrit chaque position
-- en clair plutot que de reutiliser un motif d'un appel a l'autre :
--   GetSpecializationInfoForClassID    -> id, name, desc, icon, role, recommended, ...
--   GetSpecializationInfoByID          -> id, name, desc, icon, role, classFile, className
--   C_SpecializationInfo.GetSpecializationInfo -> specID, name, desc, icon, role, primaryStat
local SpecInfo = C_SpecializationInfo

local cache

local function getSpecIndex()
    -- Le global GetSpecialization est deprecie depuis 11.2.0 : le namespace d'abord.
    local getter = (SpecInfo and SpecInfo.GetSpecialization) or GetSpecialization
    if not getter then return nil end
    local ok, index = pcall(getter)
    return ok and index or nil
end

local function numSpecs(classID)
    local getter = (SpecInfo and SpecInfo.GetNumSpecializationsForClassID)
        or GetNumSpecializationsForClassID
    if not getter or not classID then return 0 end
    local ok, count = pcall(getter, classID)
    return (ok and count) or 0
end

--- Reconstruit la liste des specialisations de la classe jouee.
local function build()
    -- UnitClass : 1 = nom traduit, 2 = jeton majuscule, 3 = identifiant numerique.
    local className, classFile, classID = UnitClass("player")
    if not classID then return nil end

    local list = {}
    for index = 1, numSpecs(classID) do
        if type(GetSpecializationInfoForClassID) == "function" then
            local results = { pcall(GetSpecializationInfoForClassID, classID, index) }
            -- results[1] est le booleen de pcall : les valeurs commencent a 2.
            local id, name, _, icon, role = results[2], results[3], results[4], results[5], results[6]
            if results[1] and id then
                table.insert(list, { id = id, index = index, name = name, icon = icon, role = role })
            end
        end
    end

    local activeIndex = getSpecIndex()
    local active
    for _, entry in ipairs(list) do
        if entry.index == activeIndex then active = entry.id end
    end

    return {
        classID = classID,
        classFile = classFile,
        className = className,
        list = list,
        active = active,
        activeIndex = activeIndex,
    }
end

--- Etat courant, reconstruit a la demande.
---
--- Un etat PARTIEL n'est jamais mis en cache. Les donnees de specialisation ne sont pas
--- toujours pretes juste apres la connexion : `build()` rendait alors une table avec
--- `active = nil` et une liste vide, et cette table restait en cache jusqu'au prochain
--- changement de spe — donc, en pratique, jusqu'au `/reload`. L'addon annoncait « pas de
--- releve pour cette specialisation » pour le reste de la session, sur une spe
--- parfaitement relevee. On retente au prochain appel plutot que de figer une reponse
--- qu'on sait fausse.
function Spec.Info()
    if cache then return cache end

    local built = build()
    if not built or not built.active or #built.list == 0 then return built end

    cache = built
    return cache
end

function Spec.Invalidate()
    cache = nil
end

--- Specialisations de la classe jouee.
function Spec.List()
    local info = Spec.Info()
    return (info and info.list) or {}
end

--- Identifiant de la specialisation reellement active.
function Spec.Active()
    local info = Spec.Info()
    return info and info.active or nil
end

--- Identifiant numerique de la classe jouee.
--- Sert au filtre de butin du journal des aventures : `EJ_SetLootFilter` prend une
--- classe et une specialisation, et fait tout le travail de restriction d'armure.
function Spec.ClassID()
    local info = Spec.Info()
    return info and info.classID or nil
end

-- Jeton de classe du client -> slug Warcraft Logs. Le jeton ne depend pas de la langue,
-- c'est pour ca qu'on part de lui et non du nom affiche.
local CLASS_SLUGS = {
    DEATHKNIGHT = "DeathKnight",
    DEMONHUNTER = "DemonHunter",
    DRUID = "Druid",
    EVOKER = "Evoker",
    HUNTER = "Hunter",
    MAGE = "Mage",
    MONK = "Monk",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
}

--- Slug de classe tel que Warcraft Logs l'ecrit.
function Spec.ClassSlug()
    local info = Spec.Info()
    return info and CLASS_SLUGS[info.classFile or ""] or nil
end

--- Specialisation regardee : celle choisie, sinon l'active.
function Spec.Selected()
    local chosen = ns.db and ns.db.viewSpec
    if chosen then
        for _, entry in ipairs(Spec.List()) do
            if entry.id == chosen then return chosen end
        end
        -- Choix devenu invalide (changement de personnage) : on l'oublie.
        ns.db.viewSpec = nil
    end
    return Spec.Active()
end

--- Role de la specialisation REGARDEE : "TANK", "HEALER" ou "DAMAGER".
---
--- `Spec.List()` portait deja `role`, lu de `GetSpecializationInfoForClassID`, et
--- personne ne s'en servait. Consequence : l'addon comparait un soigneur et un tank au
--- meme etalon qu'un DPS, avec les memes unites.
---
--- Le role de la spe REGARDEE, pas de la spe active : l'apercu d'une autre spe doit dire
--- ce que l'audit dirait pour elle, role compris.
--- @return string|nil
function Spec.Role(specID)
    specID = specID or Spec.Selected()
    if not specID then return nil end

    local info = Spec.Info()
    for _, entry in ipairs(info and info.list or {}) do
        if entry.id == specID then return entry.role end
    end
    return nil
end

--- Le tank est le seul role dont l'affichage change : la colonne de droite lui ajoute
--- endurance et armure. Un raccourci `IsHealer` a existe ici sans consommateur — le role
--- soigneur se lit dans le RELEVE (`Meta.Role`), pas sur le client, parce que ce qui
--- compte est la metrique sur laquelle le haut de tableau a ete classe.
function Spec.IsTank(specID)
    return Spec.Role(specID) == "TANK"
end

--- Regarde-t-on autre chose que sa propre specialisation ?
function Spec.IsPreview()
    local selected = Spec.Selected()
    return selected ~= nil and selected ~= Spec.Active()
end

--- Choisit la specialisation a regarder. `nil` revient a l'active.
function Spec.Select(specID)
    if not ns.db then return false end
    if specID == nil or specID == Spec.Active() then
        ns.db.viewSpec = nil
        return true
    end
    for _, entry in ipairs(Spec.List()) do
        if entry.id == specID then
            ns.db.viewSpec = specID
            return true
        end
    end
    return false
end

--- Nom d'une specialisation, la regardee par defaut.
function Spec.Name(specID)
    specID = specID or Spec.Selected()
    for _, entry in ipairs(Spec.List()) do
        if entry.id == specID then return entry.name end
    end
    if specID and type(GetSpecializationInfoByID) == "function" then
        -- GetSpecializationInfoByID : id, name, desc, icon, role, classFile, className.
        local results = { pcall(GetSpecializationInfoByID, specID) }
        if results[1] then return results[3] end
    end
    return nil
end

--- Enregistre la table des specialisations dans les SavedVariables.
---
--- L'outil Python en a besoin : Warcraft Logs designe une spe par un slug (« Devourer »),
--- l'addon par un identifiant Blizzard, et aucune table publique ne relie les deux pour une
--- spe introduite par l'extension en cours. Le jeu, lui, connait les deux. On les depose
--- donc ici et le Python les relit avec son parseur de SavedVariables.
function Spec.Register()
    local info = Spec.Info()
    if not info or not ns.db then return end

    local list = {}
    for _, entry in ipairs(info.list) do
        table.insert(list, { id = entry.id, index = entry.index, name = entry.name })
    end

    ns.db.specs = {
        classID = info.classID,
        classFile = info.classFile,
        className = info.className,
        active = info.active,
        list = list,
    }
end
