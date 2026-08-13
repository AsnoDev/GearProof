"""Charge des fichiers de l'addon dans un vrai interpreteur Lua 5.1.

Jusqu'ici la seule validation etait statique : luaparser lit la syntaxe, il n'execute
rien. Les fonctions les plus delicates du depot — le decoupage de chaine d'objet, la
decision d'appariement d'armes, le decoupage des messages de guilde — n'avaient donc
JAMAIS ete executees ailleurs que dans le jeu, ou une erreur coute un aller-retour de
plusieurs minutes et se manifeste comme un onglet vide.

`lupa` embarque Lua 5.1, la version exacte du client WoW. Ce n'est pas une approximation :
`unpack` est global, `table.unpack` n'existe pas, `#` et les motifs se comportent comme en
jeu.

Ce que ce module ne fait PAS : simuler WoW. Les stubs ci-dessous couvrent ce dont les
fonctions PURES ont besoin pour se charger, rien de plus. Tester une fonction qui lit
reellement l'equipement demanderait de simuler l'equipement, et on ne testerait alors que
la simulation.
"""

from __future__ import annotations

from pathlib import Path

from lupa import lua51

ADDON_ROOT = Path(__file__).resolve().parent.parent

# Surface d'API du client, reduite a ce que les fichiers charges touchent AU CHARGEMENT.
# Chaque entree est la parce qu'un fichier a echoue sans elle, jamais par anticipation.
WOW_STUB = r"""
-- Fonctions de chaine propres a WoW, absentes de la bibliotheque standard.
function strsplit(sep, text, limit)
    local out, start = {}, 1
    while true do
        if limit and #out == limit - 1 then
            table.insert(out, text:sub(start))
            break
        end
        local a, b = text:find(sep, start, true)
        if not a then
            table.insert(out, text:sub(start))
            break
        end
        table.insert(out, text:sub(start, a - 1))
        start = b + 1
    end
    return unpack(out)
end

function strtrim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

strjoin = function(sep, ...) return table.concat({...}, sep) end
strlower = string.lower
strupper = string.upper
strfind = string.find
strmatch = string.match
strsub = string.sub
strrep = string.rep
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

function CopyTable(source)
    local out = {}
    for key, value in pairs(source) do
        out[key] = type(value) == "table" and CopyTable(value) or value
    end
    return out
end

-- Horloge FIXE. Un test qui depend de l'heure reelle echoue un jour sans qu'on ait rien
-- change ; les tests qui ont besoin d'un temps le posent eux-memes.
GEARPROOF_TEST_TIME = 1000000
time = function() return GEARPROOF_TEST_TIME end
GetTime = function() return 0 end
date = function() return "2026-01-01" end

-- Cadres : de quoi survivre au chargement, sans rien dessiner.
local frame = {}
frame.__index = function() return function() end end
CreateFrame = function() return setmetatable({}, frame) end

UnitName = function() return "Testeur" end
UnitClass = function() return "Chasseur de demons", "DEMONHUNTER", 12 end
UnitRace = function() return "Elfe de la nuit", "NightElf", 4 end
UnitSex = function() return 2 end
UnitFactionGroup = function() return "Alliance", "Alliance" end
UnitLevel = function() return 80 end
GetLocale = function() return "frFR" end
GetBuildInfo = function() return "12.0.7", "60000", "2026-01-01", 120007 end
GetRealmName = function() return "Archimonde" end
GetAverageItemLevel = function() return 660, 658 end
IsInGuild = function() return false end
C_Timer = { After = function() end }
C_AddOns = { GetAddOnMetadata = function() return nil end }
C_Item = {}
C_Spell = {}
GameTooltip = setmetatable({}, frame)
SlashCmdList = {}
ReloadUI = function() end
print = function() end

-- Equipement. `GetInventorySlotInfo` rend un identifiant NUMERIQUE : du code qui en fait
-- une cle de table ou l'ajoute a un decalage doit recevoir un nombre, pas nil.
local SLOT_IDS = {
    HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5,
    WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10,
    Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14,
    BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17, TabardSlot = 19,
}
GetInventorySlotInfo = function(name)
    return SLOT_IDS[name] or 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head", true
end
GetInventoryItemLink = function() return nil end
GetInventoryItemTexture = function() return nil end
GetInventoryItemDurability = function() return nil end
GetInventoryItemID = function() return nil end
GetItemInfo = function() return nil end
GetItemIcon = function() return nil end
GetDetailedItemLevelInfo = function() return nil end
GetContainerNumSlots = function() return 0 end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function() return 577, "Havoc", "", "", nil, "AGILITY" end
GetNumSpecializations = function() return 3 end
GetProfessions = function() return nil end
GetProfessionInfo = function() return nil end
GetNumGuildMembers = function() return 0 end
GetGuildRosterInfo = function() return nil end
IsInRaid = function() return false end
IsInGroup = function() return false end
UnitGUID = function() return "Player-1-00000001" end
UnitIsUnit = function() return false end
IsPlayerSpell = function() return false end
BreakUpLargeNumbers = function(value) return tostring(value) end
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
               SendAddonMessage = function() end }
C_Container = { GetContainerNumSlots = function() return 0 end,
                GetContainerItemLink = function() return nil end,
                GetContainerItemInfo = function() return nil end }
C_EncounterJournal = {}
EJ_SelectInstance = function() end
EJ_SelectEncounter = function() end
EJ_SetDifficulty = function() end
EJ_SetLootFilter = function() end
EJ_GetNumLoot = function() return 0 end
EJ_GetLootInfoByIndex = function() return nil end
EJ_GetInstanceByIndex = function() return nil end
EJ_GetEncounterInfoByIndex = function() return nil end
EJ_GetCreatureInfo = function() return nil end
EJ_GetCurrentInstance = function() return nil end
EJ_GetDifficulty = function() return 14 end
EJ_GetLootFilter = function() return 0, 0 end
EJ_ClearSearch = function() end
InterfaceOptions_AddCategory = function() end
Settings = { RegisterCanvasLayoutCategory = function() return {} end,
             RegisterAddOnCategory = function() end,
             OpenToCategory = function() end }
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function()
    return { r = 0.6, g = 0.6, b = 0.6, hex = "|cff999999" }
end })
ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
UISpecialFrames = {}
UIParent = UIParent or nil
InCombatLockdown = function() return false end
IsAddOnLoaded = function() return false end
GetAddOnMetadata = function() return nil end
PlaySound = function() end
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
"""


def new_runtime(files: list[str], *, locale: bool = True, expose: dict | None = None,
                strict: bool = False):
    """Interpreteur Lua 5.1 avec l'API stub et les fichiers demandes, deja charges.

    Retourne `(lua, ns, locals_)` : `ns` est la table de namespace de l'addon, celle que
    les fichiers recoivent via `local _, ns = ...`.

    `expose` rend testables des fonctions `local` de portee fichier — `{"Guild.lua":
    ["chunkPayload"]}` — sans rien ajouter au code de production.

    Le truc : un `local` de portee fichier est encore VISIBLE a la fin du chunk. On
    concatene donc `return { chunkPayload = chunkPayload }` a la source avant de la
    compiler, et on lit la valeur rendue. La solution evidente aurait ete de poser des
    `ns.Guild.ChunkForTests = chunkPayload` dans les fichiers ; elle fait payer a tous les
    joueurs, dans l'addon livre, le cout d'un besoin de developpement.
    """
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(WOW_STUB)

    # Le stub strict ECRASE `CreateFrame` et `GameTooltip` du stub permissif : il connait
    # les methodes de chaque type de widget et leve sur tout le reste.
    if strict:
        lua.execute((ADDON_ROOT / "tools" / "wowstrict.lua").read_text(encoding="utf-8"))

    ns = lua.eval("{}")

    # `ns.L` : la cle EST le texte anglais, donc l'identite est une traduction valide.
    # Charger Locale.lua entier obligerait chaque test a le maintenir.
    if locale:
        lua.execute("GEARPROOF_NS = nil")
        lua.globals().GEARPROOF_NS = ns
        lua.execute("""
            GEARPROOF_NS.L = setmetatable({}, { __index = function(_, key) return key end })
            GEARPROOF_NS.Localize = function() end
            GEARPROOF_NS.Debug = function() end
            GEARPROOF_NS.Print = function() end
            GEARPROOF_NS.On = function() return true end
        """)

    compile_chunk = lua.eval("function(src, name) return assert(loadstring(src, name)) end")

    locals_ = {}
    for name in files:
        source = (ADDON_ROOT / name).read_text(encoding="utf-8")

        wanted = (expose or {}).get(name)
        if wanted:
            pairs = ", ".join(f"{key} = {key}" for key in wanted)
            source = f"{source}\nreturn {{ {pairs} }}\n"

        # Les fichiers d'addon recoivent (nomAddon, ns) en varargs.
        returned = compile_chunk(source, "@" + name)("GearProof", ns)

        for key in wanted or ():
            value = returned[key] if returned is not None else None
            if value is None:
                raise RuntimeError(
                    f"{name} : `local {key}` vaut nil a la fin du chunk — renomme, devenu "
                    "global, enferme dans une fonction, ou simplement PAS ENCORE AFFECTE. "
                    "Ce mecanisme capture une VALEUR, pas une reference : une table remplie "
                    "plus tard (dans un `Create`, par exemple) ne peut pas etre exposee "
                    "ainsi. Expose plutot une fonction, ou une table creee au chargement.")
            locals_[key] = value

    return lua, ns, locals_
