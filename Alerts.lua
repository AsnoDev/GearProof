local _, ns = ...

local Alerts = {}
ns.Alerts = Alerts

local L = ns.L

-- Rappel d'equipement a l'entree en instance. Mieux vaut l'apprendre avant le premier
-- pull qu'apres. Aucune journalisation ici : on lit l'equipement, rien d'autre.

local THROTTLE = 120
local lastAlert = 0

local function describe(summary)
    local parts = {}
    if summary.missingEnchants > 0 then
        table.insert(parts, string.format(L["%d missing enchant(s)"], summary.missingEnchants))
    end
    if summary.emptySockets > 0 then
        table.insert(parts, string.format(L["%d empty socket(s)"], summary.emptySockets))
    end
    if summary.emptySlots > 0 then
        table.insert(parts, string.format(L["%d empty slot(s)"], summary.emptySlots))
    end
    if summary.damaged > 0 then
        table.insert(parts, string.format(L["%d damaged piece(s)"], summary.damaged))
    end
    return table.concat(parts, ", ")
end

--- Verifie l'equipement et alerte si besoin. `force` ignore l'anti-spam.
function Alerts.Check(force)
    if ns.db.gearAlerts == false then return end

    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "party" and instanceType ~= "raid" then return end

    local now = GetTime()
    if not force and (now - lastAlert) < THROTTLE then return end

    local _, summary = ns.Gear.Scan()
    if summary.problems == 0 then return end

    lastAlert = now
    local message = "SpecAnalyser : " .. describe(summary)
    ns.Print("|cffe3a45c%s|r — |cff9d95b6/sa|r", message)

    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
    end
end

ns.On("PLAYER_ENTERING_WORLD", function()
    -- Les donnees d'objet arrivent apres le chargement de zone.
    C_Timer.After(4, function() Alerts.Check() end)
end)
