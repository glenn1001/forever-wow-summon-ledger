-- Smoke test: loads the whole addon against a mocked WoW API and plays through a service run.
-- Run from the repository root: lua5.1 tests/smoke.lua
-- The mock is deliberately small: it models the raid roster, invites, whispers, trades and timers.

local passed, failed = 0, 0
local function check(cond, label)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.write("FAIL " .. label, "\n")
    end
end

local REALM = "Realm"

-- Generic widget ----------------------------------------------------------------------
local Widget = {}
Widget.__index = function(self, key)
    local own = rawget(Widget, key)
    if own then
        return own
    end
    if not key:find("^%u") then
        return nil -- fields; only Method names get a no-op
    end
    return function()
        return nil
    end
end
function Widget.new(name)
    return setmetatable({ name = name, shown = true, scripts = {}, attributes = {}, text = "" }, Widget)
end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:SetShown(v) self.shown = v and true or false end
function Widget:IsShown() return self.shown end
function Widget:SetScript(k, fn) self.scripts[k] = fn end
function Widget:GetScript(k) return self.scripts[k] end
function Widget:SetAttribute(k, v) self.attributes[k] = v end
function Widget:GetAttribute(k) return self.attributes[k] end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:GetStringHeight() return 12 end
function Widget:GetChecked() return self.checked end
function Widget:SetChecked(v) self.checked = v end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:CreateFontString() return Widget.new() end
function Widget:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
function Widget:GetID() return 1 end

local eventFrames = {}
local handlerErrors = {}

local W -- world state

local function setupGlobals()
    W = {
        now = 100,
        timers = {},
        tickers = {},
        whispers = {},
        raidWarnings = {},
        invites = {},
        uninvites = {},
        promotes = {},
        moves = {},
        printed = {},
        inRaid = false,
        members = {}, -- { name, subgroup, level, zone, online, rank } ; [1] is the player
        combat = false,
        tradeMoney = 0,
        tradePartner = nil,
        target = nil,
    }
    eventFrames = {}

    _G.UIParent = Widget.new("UIParent")
    _G.ChatFontNormal = {}
    _G.UISpecialFrames = {}
    _G.StaticPopupDialogs = {}
    _G.SlashCmdList = {}
    _G.YES, _G.NO = "Yes", "No"
    _G.tinsert = table.insert
    _G.date, _G.time = os.date, os.time
    _G.wipe = function(t)
        for k in pairs(t) do
            t[k] = nil
        end
        return t
    end
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        local line = table.concat(parts, " ")
        table.insert(W.printed, line)
        if line:find("error in") then
            table.insert(handlerErrors, line)
        end
    end
    _G.CreateFrame = function(_, name)
        local f = Widget.new(name)
        f.shown = false
        table.insert(eventFrames, f)
        if name then
            _G[name] = f
        end
        return f
    end
    _G.Settings = {
        RegisterCanvasLayoutCategory = function()
            return { GetID = function() return 1 end }
        end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
    }
    _G.C_Timer = {
        After = function(delay, fn)
            table.insert(W.timers, { at = W.now + delay, fn = fn })
        end,
        NewTicker = function(interval, fn)
            table.insert(W.tickers, { interval = interval, fn = fn, next = W.now + interval })
        end,
    }
    _G.GetTime = function() return W.now end
    _G.GetNormalizedRealmName = function() return REALM end
    _G.GetRealmName = function() return REALM end
    _G.Ambiguate = function(name)
        return (name:gsub("%-" .. REALM .. "$", ""))
    end
    _G.issecretvalue = function() return false end
    _G.InCombatLockdown = function() return W.combat end
    _G.ERR_DECLINE_GROUP_S = "%s declines your group invitation."
    _G.ERR_ALREADY_IN_GROUP_S = "%s is already in a group."
    _G.ERR_TRADE_COMPLETE = "Trade complete."

    _G.UnitName = function(unit)
        if unit == "player" then
            return W.members[1].name
        elseif unit == "NPC" then
            return W.tradePartner
        elseif unit == "target" then
            return W.target
        end
        return nil
    end
    _G.IsInRaid = function() return W.inRaid end
    _G.IsInGroup = function() return #W.members > 1 end
    _G.GetNumGroupMembers = function() return #W.members end
    _G.GetRaidRosterInfo = function(i)
        local m = W.members[i]
        if not m then
            return nil
        end
        return m.name, m.rank, m.subgroup, m.level, "WARLOCK", "WARLOCK", m.zone, m.online
    end
    _G.UnitExists = function(unit)
        if unit == "player" then
            return true
        end
        local i = tonumber(unit:match("party(%d)"))
        return i and W.members[i + 1] ~= nil
    end
    _G.UnitIsGroupLeader = function(unit)
        return unit == "player" and W.members[1].rank == 2
    end
    _G.UnitIsGroupAssistant = function(unit)
        return unit == "player" and W.members[1].rank == 1
    end
    _G.UnitLevel = function() return 20 end
    _G.UnitIsConnected = function() return true end
    _G.SetRaidSubgroup = function(index, group)
        local count = 0
        for _, m in ipairs(W.members) do
            if m.subgroup == group then
                count = count + 1
            end
        end
        assert(count < 5, "moved into a full group")
        table.insert(W.moves, { name = W.members[index].name, to = group })
        W.members[index].subgroup = group
    end
    _G.GetTargetTradeMoney = function() return W.tradeMoney end
    _G.UnitDistanceSquared = function(unit)
        local m = W.members[tonumber(unit:match("raid(%d+)"))]
        if m and m.distance then
            return m.distance * m.distance, true
        end
        return 0, false
    end
    _G.C_PartyInfo = {
        InviteUnit = function(name) table.insert(W.invites, name) end,
        UninviteUnit = function(name) table.insert(W.uninvites, name) end,
        PromoteToAssistant = function(name)
            table.insert(W.promotes, name)
            for _, m in ipairs(W.members) do
                if m.name == name or m.name .. "-" .. REALM == name then
                    m.rank = 1
                end
            end
        end,
        ConvertToRaid = function() W.inRaid = true end,
    }
    _G.C_ChatInfo = {
        InChatMessagingLockdown = function() return false end,
        SendChatMessage = function(message, chatType, _, target)
            if chatType == "WHISPER" then
                table.insert(W.whispers, { to = target, text = message })
            elseif chatType == "RAID_WARNING" or chatType == "RAID" then
                table.insert(W.raidWarnings, message)
            end
        end,
    }
    _G.C_Spell = {
        GetSpellName = function(id)
            return id == 698 and "Ritual of Summoning" or "Other"
        end,
    }
end

local function fire(event, ...)
    for _, f in ipairs(eventFrames) do
        if f.events and f.events[event] and f.scripts.OnEvent then
            f.scripts.OnEvent(f, event, ...)
        end
    end
end

-- Advance the clock and run due timers/tickers.
local function advance(seconds)
    local target = W.now + seconds
    while true do
        local nextAt, nextTimer = math.huge, nil
        for i, t in ipairs(W.timers) do
            if t.at <= target and t.at < nextAt then
                nextAt, nextTimer = t.at, i
            end
        end
        for _, t in ipairs(W.tickers) do
            if t.next <= target and t.next < nextAt then
                nextAt, nextTimer = t.next, t
            end
        end
        if not nextTimer then
            break
        end
        W.now = nextAt
        if type(nextTimer) == "number" then
            local t = table.remove(W.timers, nextTimer)
            t.fn()
        else
            nextTimer.next = nextTimer.next + nextTimer.interval
            nextTimer.fn()
        end
    end
    W.now = target
end

local function loadAddon(playerName)
    setupGlobals()
    W.members[1] = { name = playerName, subgroup = 1, level = 60, zone = "Stormwind City", online = true, rank = 0 }
    _G.SummonLedgerDB, _G.SummonLedgerCharDB = nil, nil
    local ns = {}
    local toc = io.open("SummonLedger/SummonLedger.toc"):read("*a")
    for file in toc:gmatch("[^\r\n]+") do
        if not file:find("^##") and file:find("%.lua$") then
            local chunk = assert(loadfile("SummonLedger/" .. file:gsub("\\", "/")))
            chunk("SummonLedger", ns)
        end
    end
    fire("ADDON_LOADED", "SummonLedger")
    fire("PLAYER_LOGIN")
    return ns
end

local function memberByName(short)
    for i, m in ipairs(W.members) do
        if m.name == short then
            return m, i
        end
    end
end

-- A player accepts an invite: joins the lowest group with room (like the game does).
local function join(short, level, zone)
    local counts = {}
    for _, m in ipairs(W.members) do
        counts[m.subgroup] = (counts[m.subgroup] or 0) + 1
    end
    local group = 1
    while (counts[group] or 0) >= 5 do
        group = group + 1
    end
    if not W.inRaid then
        group = 1
    end
    table.insert(W.members, { name = short, subgroup = group, level = level or 20, zone = zone or "Elwynn Forest", online = true, rank = 0 })
    if #W.members == 2 then
        W.members[1].rank = 2 -- first acceptance makes the inviter party leader
    end
    fire("GROUP_ROSTER_UPDATE")
    advance(1)
end

local function leave(short)
    local _, i = memberByName(short)
    if i then
        table.remove(W.members, i)
        fire("GROUP_ROSTER_UPDATE")
        advance(1)
    end
end

local function whisperFrom(short, text)
    fire("CHAT_MSG_WHISPER", text, short .. "-" .. REALM)
    advance(0.5)
end

local function lastWhisperTo(short)
    for i = #W.whispers, 1, -1 do
        if W.whispers[i].to == short .. "-" .. REALM then
            return W.whispers[i].text
        end
    end
end

local function trade(short, copper)
    W.tradePartner = short
    W.tradeMoney = 0
    fire("TRADE_SHOW")
    W.tradeMoney = copper
    fire("TRADE_MONEY_CHANGED")
    fire("TRADE_ACCEPT_UPDATE", 1, 1)
    fire("UI_INFO_MESSAGE", 0, "Trade complete.")
    fire("TRADE_CLOSED")
    advance(1)
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

-- ===================================================================================
-- Advertiser run
-- ===================================================================================
do
    local ns = loadAddon("Adv")
    ns.char.role = "advertiser"
    ns.settings.minPayment = 10000

    whisperFrom("Early", "summon pls")
    check(#W.invites == 0, "nothing happens before the Shift starts")

    SlashCmdList.SUMMONLEDGER("on")
    check(ns.shiftOn(), "shift on")

    whisperFrom("Rando", "hello there")
    check(#W.invites == 0, "no keyword, no invite")

    whisperFrom("Cust1", "can I get a summon?")
    check(lastWhisperTo("Cust1") == ns.settings.texts.autoReply, "auto-reply sent")
    check(contains(W.invites, "Cust1-" .. REALM), "Cust1 invited")

    join("Cust1")
    advance(1)
    check(W.inRaid, "party converted to raid")
    advance(1)
    check(memberByName("Adv").subgroup >= 5, "Advertiser moved to staff groups")
    check(memberByName("Cust1").subgroup == 1, "Cust1 stays in group 1")

    whisperFrom("Lowbie", "summon")
    join("Lowbie", 10)
    advance(3)
    check(lastWhisperTo("Lowbie") and lastWhisperTo("Lowbie"):find("level 14"), "too-low whisper")
    check(contains(W.uninvites, "Lowbie-" .. REALM), "low level removed")
    leave("Lowbie")

    whisperFrom("Lock", "Westfall summoner reporting for duty")
    check(contains(W.invites, "Lock-" .. REALM), "Staff invited after check-in")
    check(lastWhisperTo("Lock") == nil, "Staff get no customer auto-reply")
    join("Lock", 60, "Westfall")
    advance(2)
    check(memberByName("Lock").subgroup >= 5, "Summoner placed in staff groups")
    check(contains(W.promotes, "Lock-" .. REALM), "Summoner promoted to assistant")
    check(ns.Advertiser.firstStopSummoner() == "Lock-" .. REALM, "Westfall Summoner remembered")

    for i = 2, 10 do
        whisperFrom("Cust" .. i, "inv for summon")
        join("Cust" .. i)
    end
    advance(2)
    local waiting = 0
    for _, m in ipairs(W.members) do
        if m.subgroup <= 2 then
            waiting = waiting + 1
        end
    end
    check(waiting == 10, "groups 1-2 full with 10 Customers (got " .. waiting .. ")")

    whisperFrom("Cust11", "summon")
    check(not contains(W.invites, "Cust11-" .. REALM), "11th not invited")
    check(lastWhisperTo("Cust11") and lastWhisperTo("Cust11"):find("#1"), "11th told waitlist position")
    check(ns.shiftState().waitlist[1] == "Cust11-" .. REALM, "11th on waitlist")

    -- Cust1 accepts the first summon and arrives in Westfall without paying.
    memberByName("Cust1").zone = "Westfall"
    advance(2.5)
    check(lastWhisperTo("Cust1") and lastWhisperTo("Cust1"):find("Lock"), "pay reminder names the Westfall Summoner")
    check(#W.raidWarnings == 1 and W.raidWarnings[1]:find("Lock"), "raid warning who to pay")
    memberByName("Cust2").zone = "Westfall"
    advance(2.5)
    check(#W.raidWarnings == 1, "raid warning only once per Batch")

    -- Cust1 pays the Advertiser in two parts.
    trade("Cust1", 5000)
    check(lastWhisperTo("Cust1") and lastWhisperTo("Cust1"):find("another 50s"), "underpaid whisper with the remaining amount")
    check(memberByName("Cust1").subgroup <= 2, "not moved after underpaying")
    trade("Cust1", 5000)
    advance(1)
    check(lastWhisperTo("Cust1") == ns.settings.texts.paid:gsub("{amount}", "50s"), "paid whisper mentions the amount of that trade")
    check(memberByName("Cust1").subgroup == 3, "Cust1 moved to the Paid groups")
    check(#ns.db.ledger == 2, "two ledger rows")

    -- Cust2 pays the Westfall Summoner (another client): the Summoner's addon moves them.
    memberByName("Cust2").subgroup = 3
    advance(2.5)
    check(ns.shiftState().paid["Cust2-" .. REALM], "move by another Staff member counts as paid")

    -- Joining while already in Westfall counts as arrived: pay reminder straight away.
    leave("Cust10")
    whisperFrom("Westy", "summon")
    join("Westy", 20, "Westfall")
    advance(3)
    check(lastWhisperTo("Westy") and lastWhisperTo("Westy"):find("trade 1g to Lock"), "pay reminder for a Customer already in Westfall")
    check(#W.raidWarnings == 1, "still one raid warning for the Batch")

    -- A spot opened in groups 1-2: invite next from the waitlist.
    SlashCmdList.SUMMONLEDGER("next")
    check(contains(W.invites, "Cust11-" .. REALM), "waitlist invite")
    check(lastWhisperTo("Cust11") == ns.settings.texts.spotOpen, "spot-open whisper")
    join("Cust11")
    advance(2)
    check(memberByName("Cust11").subgroup <= 2, "Cust11 placed in groups 1-2")

    -- Cust1 goes through the chain to the Final Stop.
    memberByName("Cust1").zone = "Loch Modan"
    advance(2.5)
    check(not contains(W.uninvites, "Cust1-" .. REALM), "not removed before the Final Stop")
    memberByName("Cust1").zone = "Arathi Highlands"
    advance(5)
    check(lastWhisperTo("Cust1") == ns.settings.texts.thanks, "thank-you at the Final Stop")
    check(contains(W.uninvites, "Cust1-" .. REALM), "removed at the Final Stop")

    -- Disconnect & rejoin of a paid Customer goes straight back to the Paid groups.
    leave("Cust2")
    whisperFrom("Cust2", "summon pls")
    join("Cust2")
    advance(2)
    check(memberByName("Cust2").subgroup >= 3 and memberByName("Cust2").subgroup <= 4, "paid rejoiner back in groups 3-4")

    -- Paying in advance from the Waitlist: invited straight away and placed in the Paid groups.
    whisperFrom("Cust13", "summon")
    whisperFrom("Cust14", "summon")
    check(ns.shiftState().waitlist[1] == "Cust14-" .. REALM, "Cust14 waits (Cust13 took the last spot)")
    trade("Cust14", 10000)
    check(contains(W.invites, "Cust14-" .. REALM), "advance payer invited from the waitlist")
    check(#ns.shiftState().waitlist == 0, "advance payer left the waitlist")
    join("Cust14")
    advance(2)
    local g = memberByName("Cust14").subgroup
    check(g == 3 or g == 4, "advance payer placed in groups 3-4 (got " .. g .. ")")

    local rowsBefore = #ns.db.ledger
    SlashCmdList.SUMMONLEDGER("off")
    local before = #W.invites
    whisperFrom("Cust12", "summon")
    check(#W.invites == before, "no invites after the Shift")
    trade("Cust3", 10000)
    check(#ns.db.ledger == rowsBefore, "no ledger rows outside a Shift")
    check(ns.Ledger.csv():find("Cust1%-Realm,5000,50s"), "csv has the trades")
end

-- ===================================================================================
-- Westfall Summoner run
-- ===================================================================================
do
    local ns = loadAddon("Lock")
    ns.char.role = "summoner"
    ns.char.stop = 1
    ns.settings.minPayment = 10000
    W.inRaid = true
    W.members[1].subgroup = 5
    W.members[1].rank = 1
    W.members[1].zone = "Westfall"
    local function add(name, group, zone)
        table.insert(W.members, { name = name, subgroup = group, level = 20, zone = zone, online = true, rank = 0 })
    end
    add("Adv", 5, "Stormwind City")
    add("A", 2, "Elwynn Forest")
    add("B", 1, "Elwynn Forest")
    add("Pre", 3, "Ironforge")
    SlashCmdList.SUMMONLEDGER("on")
    fire("GROUP_ROSTER_UPDATE")
    advance(1)

    local button = _G.SummonLedgerSummonButton
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target Pre\n/cast Ritual of Summoning", "advance payer summoned first")
    W.target = "Pre"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 698)
    memberByName("Pre").zone = "Westfall"
    memberByName("Pre").distance = 5
    advance(2.5)
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target B\n/cast Ritual of Summoning", "then group 1 before group 2 (snapshot order)")
    W.target = "B"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 698)
    memberByName("B").zone = "Westfall"
    memberByName("B").distance = 250 -- in Westfall, but not at the Summoner
    advance(2.5)
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target A\n/cast Ritual of Summoning", "B's summon still pending, A next")
    advance(125)
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target B\n/cast Ritual of Summoning", "B not delivered (out of range): offered again after the pending time")
    W.target = "B"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 698)
    memberByName("B").distance = 8
    advance(2.5)
    advance(125)
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target A\n/cast Ritual of Summoning", "B delivered within 30 yards: not offered again")

    trade("B", 10000)
    advance(1)
    check(memberByName("B").subgroup == 3 or memberByName("B").subgroup == 4, "Summoner moves the payer")
    check(lastWhisperTo("B") and lastWhisperTo("B"):find("Received 1g"), "paid whisper from the Summoner")

    trade("Adv", 500)
    check(lastWhisperTo("Adv") == nil, "no payment whispers to Staff")

end

-- ===================================================================================
-- Loch Modan Summoner: only paid Customers standing in Stonetalon
-- ===================================================================================
do
    local ns = loadAddon("Lock")
    ns.char.role = "summoner"
    ns.char.stop = 4
    W.inRaid = true
    W.members[1].subgroup = 5
    W.members[1].zone = "Loch Modan"
    table.insert(W.members, { name = "Unpaid", subgroup = 1, level = 20, zone = "Stonetalon Mountains", online = true, rank = 0 })
    table.insert(W.members, { name = "Ready", subgroup = 3, level = 20, zone = "Stonetalon Mountains", online = true, rank = 0 })
    SlashCmdList.SUMMONLEDGER("on")
    fire("GROUP_ROSTER_UPDATE")
    advance(1)
    local button = _G.SummonLedgerSummonButton
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target Ready\n/cast Ritual of Summoning", "Loch Modan summons the paid Customer from Stonetalon")
end

-- ===================================================================================
-- Helper check-in on login
-- ===================================================================================
do
    local ns = loadAddon("Helpy")
    W.members = { W.members[1] }
    ns.char.role = "helper"
    ns.char.stop = 2
    ns.char.advertiser = "Adv"
    ns.db.shift.on = true
    fire("PLAYER_ENTERING_WORLD", true, false)
    advance(6)
    check(W.whispers[1] and W.whispers[1].to == "Adv" and W.whispers[1].text == "Barrens helper reporting for duty", "automatic check-in whisper")
end

for _, line in ipairs(handlerErrors) do
    io.write(line, "\n")
end
check(#handlerErrors == 0, "no handler errors")

io.write(("%d passed, %d failed"):format(passed, failed), "\n")
os.exit(failed == 0 and 0 or 1)
