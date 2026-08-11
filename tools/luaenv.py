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
"""


def new_runtime(files: list[str], *, locale: bool = True, expose: dict | None = None):
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
                    f"{name} : `local {key}` introuvable a la fin du chunk — "
                    "renomme, devenu global, ou enferme dans une fonction")
            locals_[key] = value

    return lua, ns, locals_
