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
-- FOREVER = true models WoW: Forever: no realms, characters have a first and last name.
-- UnitName returns "First", "Last"; roster and whisper senders say "First Last" (issue #2).
local FOREVER = false
local function full(short)
    return FOREVER and short or (short .. "-" .. REALM)
end
local function splitName(n)
    if FOREVER and n then
        local first, last = n:match("^(%S+) (.+)$")
        if first then
            return first, last
        end
    end
    return n
end

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
function Widget:SetAlpha(a) self.alpha = a end
function Widget:GetAlpha() return self.alpha or 1 end

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
    _G.GetNormalizedRealmName = function() return FOREVER and "" or REALM end
    _G.GetRealmName = function() return FOREVER and "" or REALM end
    _G.Ambiguate = function(name)
        return (name:gsub("%-" .. REALM .. "$", ""))
    end
    _G.issecretvalue = function() return false end
    _G.InCombatLockdown = function() return W.combat end
    _G.IsShiftKeyDown = function() return W.shift == true end
    _G.ERR_DECLINE_GROUP_S = "%s declines your group invitation."
    _G.ERR_ALREADY_IN_GROUP_S = "%s is already in a group."
    _G.ERR_TRADE_COMPLETE = "Trade complete."

    local function unitIndex(unit)
        local name
        if unit == "player" then
            return 1
        elseif unit == "NPC" then
            name = W.tradePartner
        elseif unit == "target" then
            name = W.target
        else
            return tonumber(unit:match("^raid(%d+)$"))
        end
        for i, m in ipairs(W.members) do
            if m.name == name then
                return i
            end
        end
    end
    _G.UnitName = function(unit)
        if unit == "player" then
            return splitName(W.members[1].name)
        elseif unit == "NPC" then
            return splitName(W.tradePartner)
        elseif unit == "target" then
            return splitName(W.target)
        end
        return nil
    end
    _G.UnitIsUnit = function(a, b)
        local ia, ib = unitIndex(a), unitIndex(b)
        return ia ~= nil and ia == ib
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
    _G.UnitLevel = function(unit)
        if unit == "player" then
            return W.members[1].level
        end
        return 20
    end
    _G.UnitClassBase = function(unit)
        return unit == "player" and (W.members[1].class or "WARRIOR") or "WARRIOR"
    end
    _G.GetZoneText = function()
        return W.members[1].zone or ""
    end
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
                if m.name == name or full(m.name) == name then
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
    W.shards = 5
    _G.C_Spell = {
        GetSpellName = function(id)
            return id == 698 and "Ritual of Summoning" or "Other"
        end,
        GetSpellCastCount = function(spell)
            return spell == "Ritual of Summoning" and W.shards or 0
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

-- savedDB / savedCharDB: SavedVariables as if left by an earlier session (nil = first install).
local function loadAddon(playerName, forever, savedDB, savedCharDB, inCombat)
    FOREVER = forever and true or false
    setupGlobals()
    W.combat = inCombat and true or false
    W.members[1] = { name = playerName, subgroup = 1, level = 60, zone = "Stormwind City", online = true, rank = 0 }
    _G.SummonLedgerDB, _G.SummonLedgerCharDB = savedDB, savedCharDB
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
    fire("CHAT_MSG_WHISPER", text, full(short))
    advance(0.5)
end

local function lastWhisperTo(short)
    for i = #W.whispers, 1, -1 do
        if W.whispers[i].to == full(short) then
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
    check(lastWhisperTo("Pre") == ns.settings.stops[1].summonTextPaid, "paid Customer gets the Westfall 'already paid' whisper")
    local whisperCount = #W.whispers
    button.scripts.PreClick(button) -- key down + key up both fire PreClick
    check(#W.whispers == whisperCount, "no duplicate summon whisper")
    W.target = "Pre"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 698)
    memberByName("Pre").zone = "Westfall"
    memberByName("Pre").distance = 5
    advance(2.5)
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target B\n/cast Ritual of Summoning", "then group 1 before group 2 (snapshot order)")
    check(lastWhisperTo("B") and lastWhisperTo("B"):find("trade 1g to Lock, then follow the raid markers"), "unpaid Customer told to pay the Summoner")
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
    memberByName("B").distance = 500 -- walks off to do the quest step
    advance(130)
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target A\n/cast Ritual of Summoning", "B walked away: still delivered")

    -- Walked up to the Summoner without a summon: counts as delivered too, also after leaving.
    table.insert(W.members, { name = "Walker", subgroup = 1, level = 20, zone = "Westfall", online = true, rank = 0, distance = 10 })
    fire("GROUP_ROSTER_UPDATE")
    advance(2.5)
    memberByName("Walker").distance = 600
    advance(2.5)
    local _, info = ns.Summoner.status()
    check(info.delivered >= 3, "Walker counted as delivered (Pre, B, Walker)")
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target A\n/cast Ritual of Summoning", "Walker not offered after walking away")

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
    check(lastWhisperTo("Ready") == nil, "empty Stop message: no whisper")
    ns.settings.stops[4].summonText = "Summoning you to {stop}!"
    advance(130)
    button.scripts.PreClick(button)
    check(lastWhisperTo("Ready") == "Summoning you to Loch Modan!", "Stop message with placeholder")

    -- Summons left = Ritual of Summoning cast count (Soul Shards).
    W.shards = 4
    fire("BAG_UPDATE_DELAYED")
    advance(1)
    check(button:GetText() == "Summon next (4)", "button shows summons left")
    check(ns.Summoner.summonsLeft() == 4, "summons left tracked")
    local printedBefore = #W.printed
    W.shards = 3
    fire("BAG_UPDATE_DELAYED")
    advance(1)
    check(W.printed[#W.printed]:find("Only 3 summon"), "low-shard warning")
    W.shards = 0
    fire("BAG_UPDATE_DELAYED")
    advance(1)
    check(W.printed[#W.printed]:find("out of Soul Shards"), "out-of-shards warning")
    check(#W.printed > printedBefore, "warnings printed")

    -- Settings show only what this role uses.
    local function shown(key)
        for _, k in ipairs(ns.Options.visibleKeys()) do
            if k == key then
                return true
            end
        end
        return false
    end
    ns.char.role = "none"
    check(shown("role") and shown("noRole") and not shown("minLevel") and not shown("advertiserName") and #ns.Options.visibleKeys() == 3, "no role: only the role selector")
    ns.char.role = "advertiser"
    check(shown("minLevel") and shown("minPayment") and shown("text:autoReply") and shown("zones:1"), "advertiser settings")
    check(not shown("advertiserName") and not shown("summonText:1") and not shown("stop"), "advertiser: no Summoner settings")
    ns.char.role = "summoner"
    ns.char.stop = 4
    check(shown("advertiserName") and shown("summonText:3") and shown("zones:1") and shown("text:checkin"), "summoner settings")
    check(not shown("minLevel") and not shown("minPayment") and not shown("text:autoReply"), "summoner (not Westfall): no minimum level or payment")
    ns.char.stop = 1
    check(shown("minPayment") and shown("text:paid"), "Westfall Summoner sets the minimum payment")
    ns.char.role = "helper"
    check(shown("advertiserName") and shown("stop") and not shown("summonText:1") and not shown("zones:1") and not shown("minPayment"), "helper settings")
end

-- ===================================================================================
-- Helper check-in on login
-- ===================================================================================
do
    local ns = loadAddon("Helpy")
    W.members = { W.members[1] }
    ns.char.role = "helper"
    ns.char.stop = 2
    ns.settings.advertiser = "Adv"
    ns.db.shift.on = true
    fire("PLAYER_ENTERING_WORLD", true, false)
    advance(6)
    check(W.whispers[1] and W.whispers[1].to == "Adv" and W.whispers[1].text == "Barrens helper reporting for duty", "automatic check-in whisper")
end

-- ===================================================================================
-- WoW: Forever names (issue #2): first + last name, no realms
-- ===================================================================================
do
    local ns = loadAddon("Adv Lord", true)
    ns.char.role = "advertiser"
    ns.settings.minPayment = 10000
    SlashCmdList.SUMMONLEDGER("on")
    check(ns.Api.playerName() == "Adv Lord", "Forever: own name is 'First Last' (got " .. tostring(ns.Api.playerName()) .. ")")

    whisperFrom("Ilsirdur Bank", "summon please")
    check(contains(W.invites, "Ilsirdur Bank"), "Forever: Customer invited by roster-style name")
    join("Ilsirdur Bank")
    advance(2)
    check(W.inRaid, "Forever: converted to raid")
    check(memberByName("Adv Lord").subgroup >= 5, "Forever: Advertiser recognises themselves as Staff (group " .. memberByName("Adv Lord").subgroup .. ")")
    check(memberByName("Ilsirdur Bank").subgroup <= 2, "Forever: Customer waits in groups 1-2")

    trade("Ilsirdur Bank", 10000)
    advance(2)
    check(lastWhisperTo("Ilsirdur Bank") and lastWhisperTo("Ilsirdur Bank"):find("Received 1g"), "Forever: paid whisper")
    local g = memberByName("Ilsirdur Bank").subgroup
    check(g == 3 or g == 4, "Forever: paying the Advertiser moves the Customer to groups 3-4 (group " .. g .. ")")
    check(ns.db.ledger[1].from == "Ilsirdur Bank" and ns.db.ledger[1].receiver == "Adv Lord", "Forever: ledger has full names")
end

do
    local ns = loadAddon("Lock Smith", true)
    ns.char.role = "summoner"
    ns.char.stop = 1
    ns.settings.minPayment = 10000
    W.inRaid = true
    W.members[1].subgroup = 5
    W.members[1].rank = 1
    W.members[1].zone = "Westfall"
    table.insert(W.members, { name = "Adv Lord", subgroup = 5, level = 60, zone = "Stormwind City", online = true, rank = 2 })
    table.insert(W.members, { name = "Ilsirdur Bank", subgroup = 1, level = 20, zone = "Elwynn Forest", online = true, rank = 0 })
    table.insert(W.members, { name = "Other Guy", subgroup = 1, level = 20, zone = "Elwynn Forest", online = true, rank = 0 })
    SlashCmdList.SUMMONLEDGER("on")
    fire("GROUP_ROSTER_UPDATE")
    advance(1)

    local button = _G.SummonLedgerSummonButton
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target Ilsirdur Bank\n/cast Ritual of Summoning", "Forever: summon targets 'First Last'")
    W.target = "Ilsirdur Bank"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 698)
    button.scripts.PreClick(button)
    check(button:GetAttribute("macrotext") == "/target Other Guy\n/cast Ritual of Summoning", "Forever: summoned Customer is pending, next one offered")

    trade("Ilsirdur Bank", 10000)
    advance(1)
    local g = memberByName("Ilsirdur Bank").subgroup
    check(g == 3 or g == 4, "Forever: paying the Westfall Summoner moves the Customer to groups 3-4 (group " .. g .. ")")
end

-- ===================================================================================
-- Issue #6: account-wide settings, only role and Stop per character
-- ===================================================================================
do
    -- An Advertiser name saved per character by 0.1.x moves to the account settings.
    setupGlobals()
    W.members[1] = { name = "Helpy", subgroup = 1, level = 60, zone = "Westfall", online = true, rank = 0 }
    _G.SummonLedgerDB = { settings = { minLevel = 20, texts = { paid = "custom paid" } } }
    _G.SummonLedgerCharDB = { role = "helper", stop = 2, advertiser = " Adv " }
    local ns = {}
    local toc = io.open("SummonLedger/SummonLedger.toc"):read("*a")
    for file in toc:gmatch("[^\r\n]+") do
        if not file:find("^##") and file:find("%.lua$") then
            assert(loadfile("SummonLedger/" .. file:gsub("\\", "/")))("SummonLedger", ns)
        end
    end
    fire("ADDON_LOADED", "SummonLedger")
    check(SummonLedgerDB.settings.advertiser == "Adv", "#6: Advertiser name migrated to the account")
    check(SummonLedgerCharDB.advertiser == nil, "#6: per-character Advertiser name removed")
    check(SummonLedgerDB.settings.minLevel == 20 and SummonLedgerDB.settings.texts.paid == "custom paid", "#6: existing account settings kept")
    local keys = {}
    for k in pairs(SummonLedgerCharDB) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    check(table.concat(keys, ",") == "role,stop", "#6: only role and Stop per character (got " .. table.concat(keys, ",") .. ")")

    -- A second character on the same account: shares the settings, keeps its own role/Stop,
    -- and an account Advertiser name isn't overwritten by an older per-character one.
    local accountDB = SummonLedgerDB
    setupGlobals()
    W.members[1] = { name = "Locky", subgroup = 1, level = 60, zone = "Westfall", online = true, rank = 0 }
    _G.SummonLedgerDB = accountDB
    _G.SummonLedgerCharDB = { role = "summoner", stop = 1, advertiser = "Old Name" }
    ns = {}
    for file in toc:gmatch("[^\r\n]+") do
        if not file:find("^##") and file:find("%.lua$") then
            assert(loadfile("SummonLedger/" .. file:gsub("\\", "/")))("SummonLedger", ns)
        end
    end
    fire("ADDON_LOADED", "SummonLedger")
    check(ns.settings.advertiser == "Adv", "#6: account Advertiser name wins over an old per-character one")
    check(ns.char.role == "summoner" and ns.char.stop == 1, "#6: role and Stop stay per character")
    ns.settings.texts.paid = "changed once"
    check(accountDB.settings.texts.paid == "changed once", "#6: a text changed on one character is the account's text")
end

-- ===================================================================================
-- Issue #4: open the panel on login while the Shift is on
-- ===================================================================================
do
    local ns = loadAddon("Adv")
    check(not _G.SummonLedgerPanel:IsShown(), "#4: Shift off: panel stays closed on login")
    ns.char.role = "advertiser"
    SlashCmdList.SUMMONLEDGER("on")
    check(_G.SummonLedgerPanel:IsShown(), "#4: starting a Shift opens the panel")
    local accountDB = SummonLedgerDB

    -- Another character of the same account logs in (or /reload): still on the Shift, panel opens.
    ns = loadAddon("Locky", false, accountDB, { role = "summoner", stop = 2 })
    check(ns.shiftOn(), "#4: the Shift is account-wide: another character is on it too")
    check(_G.SummonLedgerPanel:IsShown(), "#4: Shift on: panel opens on login")

    -- Logging in while in combat: opens when combat ends.
    ns = loadAddon("Helpy", false, accountDB, { role = "helper", stop = 3 }, true)
    check(not _G.SummonLedgerPanel:IsShown(), "#4: in combat: panel waits")
    W.combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(_G.SummonLedgerPanel:IsShown(), "#4: panel opens after combat")

    -- /sl off on any character ends it for all of them.
    SlashCmdList.SUMMONLEDGER("off")
    ns = loadAddon("Adv", false, accountDB, { role = "advertiser", stop = 1 })
    check(not ns.shiftOn() and not _G.SummonLedgerPanel:IsShown(), "#4: Shift ended on one character: off and closed on the others")
end

-- ===================================================================================
-- Issue #5: guess role and Stop
-- ===================================================================================
do
    local function login(name, class, level, zone, charDB)
        local ns = loadAddon(name, false, nil, charDB)
        W.members[1].class, W.members[1].level, W.members[1].zone = class, level, zone
        fire("PLAYER_ENTERING_WORLD", true, false)
        advance(2)
        return ns
    end
    local function lastPrint()
        return W.printed[#W.printed] or ""
    end

    local ns = login("Locky", "WARLOCK", 25, "Westfall")
    check(ns.char.role == "summoner" and ns.char.stop == 1, "#5: warlock 25 in Westfall -> Summoner at Westfall")
    check(lastPrint():find("Role: Summoner at Westfall"), "#5: the guess is printed")

    ns = login("Helpy", "PRIEST", 12, "Loch Modan")
    check(ns.char.role == "helper" and ns.char.stop == 4, "#5: level 12 in Loch Modan -> Helper at Loch Modan")

    ns = login("Adv", "PALADIN", 60, "Ironforge")
    check(ns.char.role == "advertiser", "#5: Ironforge -> Advertiser")

    ns = login("Set", "WARLOCK", 30, "The Barrens", { role = "advertiser", stop = 1 })
    check(ns.char.role == "advertiser" and ns.char.stop == 1, "#5: login never overwrites a role that's set")

    ns = login("Lost", "WARLOCK", 30, "Elwynn Forest")
    check(ns.char.role == "none", "#5: no guess: role stays empty")
    check(lastPrint():find("Couldn't guess"), "#5: no guess: hint printed")
    -- Moving to a Stop and pressing Update role guesses again.
    W.members[1].zone = "Stonetalon Mountains"
    ns.Panel.updateRoleButton:GetScript("OnClick")()
    check(ns.char.role == "summoner" and ns.char.stop == 3, "#5: Update role after moving -> Summoner at Stonetalon")

    -- Update role overwrites a role that's already set.
    ns = login("Set", "WARLOCK", 30, "The Barrens", { role = "advertiser", stop = 1 })
    SlashCmdList.SUMMONLEDGER("role")
    check(ns.char.role == "summoner" and ns.char.stop == 2, "#5: Update role overwrites (Advertiser -> Summoner at Barrens)")
    -- ... but keeps it when no guess is possible.
    W.members[1].zone = "Elwynn Forest"
    SlashCmdList.SUMMONLEDGER("role")
    check(ns.char.role == "summoner" and ns.char.stop == 2, "#5: Update role without a guess keeps the role")

    -- Empty zone right after login: retried until the zone is known.
    ns = loadAddon("Slow", false)
    W.members[1].class, W.members[1].level, W.members[1].zone = "WARLOCK", 40, ""
    fire("PLAYER_ENTERING_WORLD", true, false)
    advance(1.5)
    W.members[1].zone = "Loch Modan"
    advance(2)
    check(ns.char.role == "summoner" and ns.char.stop == 4, "#5: zone unknown at first: guessed once it's known")

    -- A guessed Helper on Shift checks in with the guessed role.
    local accountDB = { shift = { on = true }, settings = { advertiser = "Adv" } }
    ns = loadAddon("Newbie", false, accountDB, nil)
    W.members = { W.members[1] }
    W.members[1].class, W.members[1].level, W.members[1].zone = "MAGE", 10, "The Barrens"
    fire("PLAYER_ENTERING_WORLD", true, false)
    advance(6)
    local w = W.whispers[#W.whispers]
    check(w and w.to == "Adv" and w.text == "Barrens helper reporting for duty", "#5: guessed Helper reports for duty (got " .. tostring(w and w.text) .. ")")
end

-- ===================================================================================
-- Issue #11: Log off button
-- ===================================================================================
do
    local function summonerAt(stop, customers)
        local ns = loadAddon("Lock")
        ns.char.role = "summoner"
        ns.char.stop = stop
        ns.settings.minPayment = 10000
        W.inRaid = true
        W.members[1].subgroup, W.members[1].rank, W.members[1].zone = 5, 1, ns.settings.stops[stop].zones:match("^[^,]+")
        for _, c in ipairs(customers) do
            table.insert(W.members, { name = c[1], subgroup = c[2], level = 20, zone = c[3], online = true, rank = 0 })
        end
        SlashCmdList.SUMMONLEDGER("on")
        fire("GROUP_ROSTER_UPDATE")
        advance(1)
        return ns
    end
    local function press(button)
        button.scripts.PreClick(button)
        return button:GetAttribute("macrotext")
    end
    local function lastPrint()
        return W.printed[#W.printed] or ""
    end

    -- Loch Modan: one paid Customer waiting in Stonetalon.
    local ns = summonerAt(4, { { "Ready", 3, "Stonetalon Mountains" } })
    local logoff = _G.SummonLedgerLogoffButton
    ns.Panel.show()
    check(logoff:IsShown() and logoff:GetAlpha() == 0.5, "#11: greyed out while someone can still be summoned")
    check(press(logoff) == "" and #W.raidWarnings == 0, "#11: plain click while busy: no log off, no raid warning")
    check(lastPrint():find("Shift%+click"), "#11: tells you to Shift+click")
    W.shift = true
    check(press(logoff) == "/camp", "#11: Shift+click forces the log off")
    check(W.raidWarnings[1] == "Loch Modan team is logging off. The Thoradin's Wall team logs in any moment now: stay online and accept the next summon!", "#11: raid warning names this and the next Stop (got " .. tostring(W.raidWarnings[1]) .. ")")
    W.shift = false

    -- Summon the last one: it's pending, so everyone has been summoned.
    local summon = _G.SummonLedgerSummonButton
    press(summon)
    W.target = "Ready"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 698)
    press(summon)
    check(lastPrint():find("Everyone has been summoned to Loch Modan"), "#11: done message (got " .. lastPrint() .. ")")
    ns.Panel.refresh()
    check(logoff:IsShown() and logoff:GetAlpha() == 1, "#11: ready: not greyed out")
    advance(10)
    local warnings = #W.raidWarnings
    check(press(logoff) == "/camp" and #W.raidWarnings == warnings + 1, "#11: ready: click logs off with one raid warning")
    press(logoff)
    check(#W.raidWarnings == warnings + 1, "#11: key down + up: still one raid warning")

    -- Final Stop: the separate message, {next} = Westfall.
    ns = summonerAt(5, {})
    press(_G.SummonLedgerLogoffButton)
    check(W.raidWarnings[#W.raidWarnings] == "Thoradin's Wall team is logging off: that was the last summon. Thanks for using our summoning service, and good luck with the last step!", "#11: Final Stop message")
    ns.settings.texts.logoffFinal = "{stop} done, {next} next"
    advance(10)
    press(_G.SummonLedgerLogoffButton)
    check(W.raidWarnings[#W.raidWarnings] == "Thoradin's Wall done, Westfall next", "#11: Final Stop {next} is Westfall")

    -- Westfall: hidden until everyone summoned has paid.
    ns = summonerAt(1, { { "Payer", 1, "Elwynn Forest" } })
    logoff = _G.SummonLedgerLogoffButton
    press(_G.SummonLedgerSummonButton)
    W.target = "Payer"
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 698)
    ns.Panel.show()
    check(not logoff:IsShown(), "#11: Westfall: hidden while a summoned Customer hasn't paid")
    press(_G.SummonLedgerSummonButton)
    check(lastPrint():find("Payment is missing from: Payer"), "#11: Westfall: says who hasn't paid (got " .. lastPrint() .. ")")
    W.shift = true
    check(press(logoff) == "", "#11: Westfall unpaid: Shift+click doesn't force it")
    W.shift = false
    trade("Payer", 10000)
    advance(1)
    ns.Panel.refresh()
    check(logoff:IsShown(), "#11: Westfall: shown once everyone has paid")
    check(press(logoff) == "/camp", "#11: Westfall: logs off after payment")

    -- Helper: plain /camp, no raid warning.
    ns = loadAddon("Helpy")
    ns.char.role = "helper"
    local before = #W.raidWarnings
    check(press(_G.SummonLedgerLogoffButton) == "/camp" and #W.raidWarnings == before, "#11: Helper: /camp without raid warning")
end

for _, line in ipairs(handlerErrors) do
    io.write(line, "\n")
end
check(#handlerErrors == 0, "no handler errors")

io.write(("%d passed, %d failed"):format(passed, failed), "\n")
os.exit(failed == 0 and 0 or 1)
