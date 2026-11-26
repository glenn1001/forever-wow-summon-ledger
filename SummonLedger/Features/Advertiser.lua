-- Advertiser automation: answering requests, invites, waitlist, Staff check-in, raid layout,
-- level check, the Westfall payment reminder and removing Customers at the Final Stop.
local _, ns = ...

local Api, Rules, Util = ns.Api, ns.Rules, ns.Util

local Advertiser = {}
ns.Advertiser = Advertiser

local known = nil -- name -> true: who was in the group at the previous roster update (nil = not read yet)
local prevZones = {} -- name -> zone, for arrival detection
local pendingInvites = {} -- Customer name -> time invited
local pendingStaff = {} -- Staff name -> time invited
local replied = {} -- name -> true: got the auto-reply this session
local levelChecked = {} -- name -> true
local removing = {} -- name -> true: being removed, ignore further updates
local landedOutside = {} -- name -> true: unpaid newcomer that landed outside groups 1-2 (not "paid")
local recentAction = {} -- "move:name" / "promote:name" -> time, so the 2 s poll doesn't repeat itself

Advertiser.problems = {}

local DECLINE_PATTERN = Util.patternFromFormat(ERR_DECLINE_GROUP_S)
local ALREADY_GROUPED_PATTERN = Util.patternFromFormat(ERR_ALREADY_IN_GROUP_S)

local function active()
    return ns.shiftOn() and ns.role() == "advertiser"
end

local function state()
    return ns.shiftState()
end

function Advertiser.isStaff(name)
    return name == Api.playerName() or state().staff[name] ~= nil
end

local function isPaid(name)
    return state().paid[name] == true
end

local function inGroup(name)
    for _, m in ipairs(Api.readRoster()) do
        if m.name == name then
            return true
        end
    end
    return false
end

local function waitlistPosition(name)
    for i, n in ipairs(state().waitlist) do
        if n == name then
            return i
        end
    end
    return nil
end

local function removeFromWaitlist(name)
    local pos = waitlistPosition(name)
    if pos then
        table.remove(state().waitlist, pos)
    end
end

function Advertiser.firstStopSummoner()
    for name, info in pairs(state().staff) do
        if info.stop == 1 and info.role == "summoner" then
            return name
        end
    end
    return nil
end

local function waitingFree(roster)
    return Rules.waitingFree(roster or Api.readRoster(), pendingInvites, Advertiser.isStaff)
end

local function inviteCustomer(name)
    pendingInvites[name] = Api.now()
    Api.invite(name)
end

-- Invite the first player on the Waitlist (button / keybind / auto).
function Advertiser.inviteNext()
    if not active() then
        ns.print("Start a Shift as Advertiser first (/sl on).")
        return
    end
    local name = state().waitlist[1]
    if not name then
        ns.print("The waitlist is empty.")
        return
    end
    if waitingFree() <= 0 then
        ns.print("No free spot in groups 1-2 yet.")
        return
    end
    table.remove(state().waitlist, 1)
    Api.whisper(name, ns.settings.texts.spotOpen)
    inviteCustomer(name)
    ns.fire("SL_UI_REFRESH")
end

function Advertiser.announcePayment()
    local summoner = Advertiser.firstStopSummoner()
    if not summoner then
        ns.print("No Westfall Summoner has checked in yet, so there's nobody to announce.")
        return
    end
    Api.raidWarning(Util.fill(ns.settings.texts.raidWarning, { summoner = Api.displayName(summoner) }))
    state().announced = true
end

local function handleCheckin(sender, text)
    local stopIndex, role = Rules.parseCheckin(text, ns.settings.stops)
    if not stopIndex then
        return false
    end
    state().staff[sender] = { stop = stopIndex, role = role }
    removeFromWaitlist(sender)
    pendingInvites[sender] = nil
    ns.print(("%s checked in as %s for %s."):format(Api.displayName(sender), role, ns.settings.stops[stopIndex].name))
    if inGroup(sender) then
        Advertiser.update()
    else
        pendingStaff[sender] = Api.now()
        Api.invite(sender)
    end
    ns.fire("SL_UI_REFRESH")
    return true
end

local function handleRequest(sender, text)
    if inGroup(sender) or pendingInvites[sender] then
        return
    end
    if not Rules.isRequest(text, ns.settings.inviteAnyone, ns.settings.keywords) then
        return
    end
    local texts = ns.settings.texts
    local position = waitlistPosition(sender)
    if position then
        Api.whisper(sender, Util.fill(texts.waitlist, { position = position }))
        return
    end
    if not replied[sender] then
        replied[sender] = true
        Api.whisper(sender, texts.autoReply)
    end
    if waitingFree() > 0 then
        inviteCustomer(sender)
    else
        table.insert(state().waitlist, sender)
        Api.whisper(sender, Util.fill(texts.waitlist, { position = #state().waitlist }))
    end
    ns.fire("SL_UI_REFRESH")
end

ns.on("CHAT_MSG_WHISPER", function(text, sender)
    if not active() or Api.isSecret(text) or Api.isSecret(sender) then
        return
    end
    sender = Api.normalize(sender)
    if not sender or sender == Api.playerName() then
        return
    end
    if handleCheckin(sender, text) then
        return
    end
    handleRequest(sender, text)
end)

ns.on("CHAT_MSG_SYSTEM", function(text)
    if not active() or Api.isSecret(text) then
        return
    end
    local who = (DECLINE_PATTERN and text:match(DECLINE_PATTERN)) or (ALREADY_GROUPED_PATTERN and text:match(ALREADY_GROUPED_PATTERN))
    if who then
        local name = Api.normalize(who)
        if name and (pendingInvites[name] or pendingStaff[name]) then
            pendingInvites[name] = nil
            pendingStaff[name] = nil
            ns.print(text)
            ns.fire("SL_UI_REFRESH")
        end
    end
end)

local function checkLevel(m)
    if levelChecked[m.name] then
        return
    end
    if (m.level or 0) <= 0 then
        -- Level not known yet right after joining; look again shortly.
        C_Timer.After(2, function()
            ns.debounce("advertiser", 0.1, Advertiser.update)
        end)
        return
    end
    levelChecked[m.name] = true
    if m.level < ns.settings.minLevel then
        removing[m.name] = true
        Api.whisper(m.name, Util.fill(ns.settings.texts.tooLow, { minLevel = ns.settings.minLevel }))
        C_Timer.After(1, function()
            Api.uninvite(m.name)
        end)
        ns.print(("%s is level %d: told them and removed them."):format(Api.displayName(m.name), m.level))
    end
end

local function handleArrival(arrival)
    local m = arrival.member
    if Advertiser.isStaff(m.name) or Rules.isStaffGroup(m.subgroup) or removing[m.name] then
        return
    end
    local stops = ns.settings.stops
    if arrival.stopIndex == 1 and Rules.isWaitingGroup(m.subgroup) then
        local summoner = Advertiser.firstStopSummoner()
        if not state().reminded[m.name] and summoner then
            state().reminded[m.name] = true
            Api.whisper(m.name, Util.fill(ns.settings.texts.payReminder, {
                price = Util.formatMoney(ns.settings.minPayment),
                summoner = Api.displayName(summoner),
            }))
        end
        if not state().announced and summoner then
            Advertiser.announcePayment()
        end
    elseif arrival.stopIndex == #stops and Rules.isPaidGroup(m.subgroup) then
        removing[m.name] = true
        state().paid[m.name] = nil
        Api.whisper(m.name, ns.settings.texts.thanks)
        C_Timer.After(3, function()
            Api.uninvite(m.name)
        end)
        ns.print(Api.displayName(m.name) .. " reached the Final Stop: thanked and removed.")
    end
end

-- True if this action was done less than `seconds` ago; otherwise records it as done now.
local function recent(key, seconds)
    local now = Api.now()
    if recentAction[key] and now - recentAction[key] < seconds then
        return true
    end
    recentAction[key] = now
    return false
end

function Advertiser.update()
    if not active() or not IsInGroup() then
        known = known and {} or nil
        return
    end
    if not IsInRaid() then
        if Api.isLeader() then
            Api.convertToRaid()
        end
        return -- the conversion triggers another roster update
    end

    local roster = Api.readRoster()
    local now = Api.now()
    local present = {}
    local newcomers = {}
    for _, m in ipairs(roster) do
        present[m.name] = true
        if known and not known[m.name] then
            newcomers[m.name] = true
        end
        pendingInvites[m.name] = nil
        pendingStaff[m.name] = nil
    end
    if not known then
        known = {} -- first read after login/reload: nobody counts as new
    end

    for name in pairs(known) do
        if not present[name] then
            levelChecked[name] = nil
            removing[name] = nil
            prevZones[name] = nil
            landedOutside[name] = nil
        end
    end
    known = present

    for name, at in pairs(pendingInvites) do
        if now - at > (ns.settings.inviteTimeout or 60) then
            pendingInvites[name] = nil
        end
    end
    for name, at in pairs(pendingStaff) do
        if now - at > 120 then
            pendingStaff[name] = nil
        end
    end

    for _, m in ipairs(roster) do
        if Rules.isWaitingGroup(m.subgroup) then
            landedOutside[m.name] = nil
        elseif newcomers[m.name] and not Advertiser.isStaff(m.name) and not isPaid(m.name) then
            landedOutside[m.name] = true
        end
    end

    -- Anyone in groups 3-4 who didn't just land there has paid (to me or to the Westfall Summoner).
    for _, m in ipairs(roster) do
        if Rules.isPaidGroup(m.subgroup) and not landedOutside[m.name] and not Advertiser.isStaff(m.name) and not removing[m.name] then
            state().paid[m.name] = true
            state().reminded[m.name] = nil
        end
    end

    for _, m in ipairs(roster) do
        if not Advertiser.isStaff(m.name) and not isPaid(m.name) and not Rules.isStaffGroup(m.subgroup) then
            checkLevel(m)
        end
    end

    for _, arrival in ipairs(Rules.detectArrivals(prevZones, roster, ns.settings.stops)) do
        handleArrival(arrival)
    end

    -- A Batch is over once the Paid groups have emptied again; the next one gets a new raid warning.
    local paidCount = Rules.countInGroups(roster, ns.PAID_GROUPS, function(m)
        return not removing[m.name]
    end)
    if paidCount > 0 then
        state().batchStarted = true
    elseif state().batchStarted then
        state().batchStarted = false
        state().announced = false
    end

    Advertiser.problems = {}
    if Api.isLeader() then
        for _, m in ipairs(roster) do
            local info = state().staff[m.name]
            if info and info.role == "summoner" and m.rank == 0 and m.online and not recent("promote:" .. m.name, 5) then
                Api.promoteToAssistant(m.name)
            end
        end
    end
    if Api.canManageRaid() then
        if Api.inCombat() then
            Advertiser.problems = { "In combat: group moves wait until combat ends." }
        else
            local moves, problems = Rules.planPlacement(roster, {
                isStaff = Advertiser.isStaff,
                isPaid = isPaid,
                newcomers = landedOutside,
            })
            Advertiser.problems = problems
            for _, mv in ipairs(moves) do
                if not recent("move:" .. mv.name, 3) then
                    Api.setRaidSubgroup(mv.index, mv.to)
                end
            end
        end
    else
        Advertiser.problems = { "You're not raid leader or assistant: nobody can be moved." }
    end

    if ns.settings.autoInviteWaitlist and #state().waitlist > 0 and waitingFree(roster) > 0 then
        Advertiser.inviteNext()
    end
    ns.fire("SL_UI_REFRESH")
end

ns.on("SL_CUSTOMER_PAID", function(name)
    -- Paid in advance from the Waitlist (or before even asking): invite now, placement puts them in 3-4.
    removeFromWaitlist(name)
    if not inGroup(name) and not pendingInvites[name] then
        inviteCustomer(name)
    end
    ns.debounce("advertiser", 0.1, Advertiser.update)
end)

local function scheduleUpdate()
    ns.debounce("advertiser", 0.3, Advertiser.update)
end

ns.on("GROUP_ROSTER_UPDATE", scheduleUpdate)
ns.on("PLAYER_REGEN_ENABLED", scheduleUpdate)
ns.on("SL_SHIFT_CHANGED", function(on)
    if on then
        known = nil
        prevZones, pendingInvites, pendingStaff, replied, levelChecked, removing = {}, {}, {}, {}, {}, {}
        landedOutside, recentAction = {}, {}
    end
    scheduleUpdate()
end)

-- Zones in the raid roster change without a GROUP_ROSTER_UPDATE, so poll for arrivals.
C_Timer.NewTicker(2, function()
    if active() and IsInRaid() then
        Advertiser.update()
    end
end)

-- For the panel: lists of names by status.
function Advertiser.overview()
    local roster = Api.readRoster()
    local o = { waiting = {}, paid = {}, staff = 0, waitlist = state().waitlist, pending = 0 }
    for _ in pairs(pendingInvites) do
        o.pending = o.pending + 1
    end
    for _, m in ipairs(roster) do
        if Rules.isWaitingGroup(m.subgroup) and not Advertiser.isStaff(m.name) then
            table.insert(o.waiting, { name = m.name, level = m.level, owing = state().reminded[m.name] == true, zone = m.zone })
        elseif Rules.isPaidGroup(m.subgroup) then
            table.insert(o.paid, { name = m.name, zone = m.zone })
        elseif Rules.isStaffGroup(m.subgroup) then
            o.staff = o.staff + 1
        end
    end
    o.free = waitingFree(roster)
    return o
end
