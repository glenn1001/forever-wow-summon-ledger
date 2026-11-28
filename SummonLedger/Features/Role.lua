-- Guessing a character's role and Stop (#5). The rule itself is Rules.guessRole.
local _, ns = ...

local Rules = ns.Rules

local Role = {}
ns.Role = Role

local function playerInfo()
    local class = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
    return { class = class, level = UnitLevel("player") or 0, zone = GetZoneText and GetZoneText() or "" }
end

-- overwrite = true: the Update role button (replaces a role that's already set).
-- overwrite = false: login or /reload (only fills in an empty role).
-- Returns true when a role was set.
function Role.guess(overwrite)
    if not overwrite and ns.char.role ~= "none" then
        return false
    end
    local info = playerInfo()
    local role, stopIndex = Rules.guessRole(info, ns.settings.stops)
    if not role then
        -- No guess: an empty role stays empty, a role that's already set is kept.
        ns.print(("Couldn't guess this character's role (level %d, %s). Choose it in /sl config, or press Update role at a Stop, in Stormwind or in Ironforge."):format(info.level, info.zone ~= "" and info.zone or "unknown zone"))
        return false
    end
    ns.char.role = role
    if stopIndex then
        ns.char.stop = stopIndex
    end
    local text = ns.ROLE_LABELS[role]
    if stopIndex then
        text = text .. " at " .. ns.settings.stops[stopIndex].name
    end
    ns.print("Role: " .. text .. ". Change it in /sl config.")
    ns.fire("SL_ROLE_CHANGED")
    ns.fire("SL_SETTINGS_CHANGED")
    return true
end

ns.on("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if not (isLogin or isReload) then
        return
    end
    -- Wait a moment: right after login the zone can still be empty. Runs before the Staff
    -- check-in (5 s), so a guessed Summoner or Helper checks in with the guessed role.
    local tries = 0
    local function attempt()
        if ns.char.role ~= "none" then
            return
        end
        tries = tries + 1
        if (GetZoneText() or "") == "" and tries < 3 then
            C_Timer.After(1, attempt)
            return
        end
        Role.guess(false)
    end
    C_Timer.After(1, attempt)
end)

Role.playerInfo = playerInfo
