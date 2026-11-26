-- Thin wrappers around the WoW API. Every game call the addon makes goes through here,
-- with feature detection so a renamed function fails soft instead of throwing.
local _, ns = ...

local Util = ns.Util
local Api = {}
ns.Api = Api

local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end
Api.isSecret = isSecret

function Api.now()
    return GetTime()
end

function Api.realm()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("%s", "")
end

function Api.normalize(name, realm)
    if isSecret(name) or isSecret(realm) then
        return nil
    end
    return Util.normalizeName(name, realm, Api.realm())
end

function Api.playerName()
    local name, realm = UnitName("player")
    return Api.normalize(name, realm)
end

-- Short name for people on our own realm, Name-Realm otherwise.
function Api.displayName(fullName)
    if not fullName then
        return "?"
    end
    if Ambiguate then
        return Ambiguate(fullName, "none")
    end
    return Util.shortName(fullName)
end

function Api.inCombat()
    return InCombatLockdown()
end

function Api.inChatLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

local function sendChat(message, chatType, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, piece in ipairs(ns.Rules.splitMessage(message, 255)) do
        send(piece, chatType, nil, target)
    end
end

function Api.whisper(target, message)
    if not target or Util.trim(message) == "" then
        return false
    end
    if Api.inChatLockdown() then
        ns.print("Chat lockdown: can't whisper " .. Api.displayName(target))
        return false
    end
    sendChat(message, "WHISPER", target)
    return true
end

function Api.raidWarning(message)
    if Util.trim(message) == "" or not IsInRaid() or Api.inChatLockdown() then
        return false
    end
    local chatType = (Api.isLeader() or Api.isAssistant()) and "RAID_WARNING" or "RAID"
    sendChat(message, chatType)
    return true
end

function Api.invite(name)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    invite(name)
end

function Api.uninvite(name)
    local uninvite = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit
    uninvite(name)
end

function Api.promoteToAssistant(name)
    local promote = (C_PartyInfo and C_PartyInfo.PromoteToAssistant) or PromoteToAssistant
    promote(name)
end

function Api.convertToRaid()
    local convert = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
    convert()
end

function Api.isLeader()
    return UnitIsGroupLeader("player") and true or false
end

function Api.isAssistant()
    return UnitIsGroupAssistant("player") and true or false
end

function Api.canManageRaid()
    return IsInRaid() and (Api.isLeader() or Api.isAssistant())
end

function Api.setRaidSubgroup(index, group)
    SetRaidSubgroup(index, group)
end

-- Snapshot of the group as plain tables (see Rules.lua). In a party, everyone counts as group 1.
function Api.readRoster()
    local roster = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank, subgroup, level, _, _, zone, online = GetRaidRosterInfo(i)
            local full = name and Api.normalize(name)
            if full and not isSecret(subgroup) then
                local distance
                if UnitDistanceSquared then
                    local squared, checked = UnitDistanceSquared("raid" .. i)
                    if checked and squared and not isSecret(squared) and not isSecret(checked) then
                        distance = math.sqrt(squared)
                    end
                end
                roster[#roster + 1] = {
                    distance = distance, -- yards from me; nil = couldn't be measured
                    index = i,
                    name = full,
                    rank = (not isSecret(rank) and rank) or 0,
                    subgroup = subgroup,
                    level = (not isSecret(level) and level) or 0,
                    zone = (not isSecret(zone) and zone) or nil,
                    online = (not isSecret(online) and online) and true or false,
                }
            end
        end
    elseif IsInGroup() then
        local units = { "player", "party1", "party2", "party3", "party4" }
        for i, unit in ipairs(units) do
            if UnitExists(unit) then
                local name, realm = UnitName(unit)
                local full = Api.normalize(name, realm)
                if full then
                    roster[#roster + 1] = {
                        index = i,
                        name = full,
                        rank = UnitIsGroupLeader(unit) and 2 or 0,
                        subgroup = 1,
                        level = UnitLevel(unit) or 0,
                        zone = nil,
                        online = UnitIsConnected(unit) and true or false,
                    }
                end
            end
        end
    end
    return roster
end

function Api.summonSpellName()
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(ns.SUMMON_SPELL_ID)
    elseif GetSpellInfo then
        name = GetSpellInfo(ns.SUMMON_SPELL_ID)
    end
    return name or ns.SUMMON_SPELL_FALLBACK_NAME
end

function Api.dateString(t)
    return date("%Y-%m-%d %H:%M:%S", t or time())
end
