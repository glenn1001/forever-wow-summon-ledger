-- Pure decision logic. Takes plain tables (a roster snapshot, settings, state) and returns decisions.
-- No WoW API calls here, so everything can be unit-tested with tests/run.lua.
--
-- Roster member: { index, name ("Name-Realm"), subgroup, level, zone, online, rank }
local _, ns = ...

local Util = ns.Util
local Rules = {}
ns.Rules = Rules

local function inList(value, list)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

function Rules.isWaitingGroup(subgroup)
    return inList(subgroup, ns.WAITING_GROUPS)
end

function Rules.isPaidGroup(subgroup)
    return inList(subgroup, ns.PAID_GROUPS)
end

function Rules.isStaffGroup(subgroup)
    return inList(subgroup, ns.STAFF_GROUPS)
end

function Rules.groupCounts(roster)
    local counts = { 0, 0, 0, 0, 0, 0, 0, 0 }
    for _, m in ipairs(roster) do
        if m.subgroup and counts[m.subgroup] then
            counts[m.subgroup] = counts[m.subgroup] + 1
        end
    end
    return counts
end

function Rules.firstFreeGroup(counts, groups)
    for _, g in ipairs(groups) do
        if (counts[g] or 0) < ns.GROUP_SIZE then
            return g
        end
    end
    return nil
end

function Rules.countInGroups(roster, groups, filter)
    local n = 0
    for _, m in ipairs(roster) do
        if inList(m.subgroup, groups) and (not filter or filter(m)) then
            n = n + 1
        end
    end
    return n
end

-- Is this whisper a request for the service?
function Rules.isRequest(text, inviteAnyone, keywords)
    if inviteAnyone then
        return true
    end
    local lower = tostring(text or ""):lower()
    for _, keyword in ipairs(Util.splitList(keywords)) do
        local escaped = keyword:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
        if lower:find("%f[%w]" .. escaped .. "%f[%W]") then
            return true
        end
    end
    return false
end

local function zoneList(stop)
    return Util.splitList(stop and stop.zones or "")
end

function Rules.zoneMatchesStop(zone, stop)
    if not zone or zone == "" then
        return false
    end
    return inList(zone:lower(), zoneList(stop))
end

-- Is this member standing at the Summoner (in the Stop's zone and within range)?
-- m.distance is nil when the game couldn't measure it (e.g. another continent): not at the Summoner.
function Rules.isAtSummoner(m, stop)
    return Rules.zoneMatchesStop(m.zone, stop) and m.distance ~= nil and m.distance <= ns.ARRIVAL_RANGE_YARDS
end

-- Index of the Stop whose zone this is, or nil.
function Rules.stopIndexOfZone(zone, stops)
    for i, stop in ipairs(stops) do
        if Rules.zoneMatchesStop(zone, stop) then
            return i
        end
    end
    return nil
end

-- "Westfall summoner reporting for duty" -> 1, "summoner". Matches a Stop by name or by one of its zones.
function Rules.parseCheckin(text, stops)
    local lower = Util.trim(text):lower():gsub("[%.!]+$", "")
    local stopText, role = lower:match("^(.-)%s+(%a+)%s+reporting%s+for%s+duty$")
    if not stopText or (role ~= "summoner" and role ~= "helper") then
        return nil
    end
    stopText = Util.trim(stopText)
    for i, stop in ipairs(stops) do
        if stopText == Util.trim(stop.name):lower() or inList(stopText, zoneList(stop)) then
            return i, role
        end
    end
    return nil
end

-- Guess a character's role from class, level and zone (#5). The zone decides first:
--   in a Stop zone: warlock of level 20+ = Summoner, anyone else = Helper, at that Stop;
--   in Stormwind City / Ironforge: Advertiser;
--   elsewhere: level 60 = Advertiser, otherwise no guess.
-- c = { class = "WARLOCK", level = 25, zone = "Westfall" }. Returns role, stopIndex (nil, nil = no guess).
function Rules.guessRole(c, stops)
    local stopIndex = Rules.stopIndexOfZone(c.zone, stops)
    if stopIndex then
        if c.class == "WARLOCK" and (c.level or 0) >= ns.SUMMONER_MIN_LEVEL then
            return "summoner", stopIndex
        end
        return "helper", stopIndex
    end
    local zone = tostring(c.zone or ""):lower()
    for _, z in ipairs(ns.ADVERTISER_ZONES) do
        if zone == z:lower() then
            return "advertiser", nil
        end
    end
    if (c.level or 0) >= ns.MAX_LEVEL then
        return "advertiser", nil
    end
    return nil, nil
end

-- Payments to one receiver add up within a Shift. Payments to different Staff don't (ADR 0001).
-- totals: name -> { copper, paid }. Returns { status = "paid"|"under"|"already"|"unset", total, remaining }.
function Rules.applyPayment(totals, name, copper, minPayment)
    local entry = totals[name]
    if not entry then
        entry = { copper = 0, paid = false }
        totals[name] = entry
    end
    entry.copper = entry.copper + copper
    if entry.paid then
        return { status = "already", total = entry.copper, remaining = 0 }
    end
    if not minPayment or minPayment <= 0 then
        return { status = "unset", total = entry.copper, remaining = 0 }
    end
    if entry.copper >= minPayment then
        entry.paid = true
        return { status = "paid", total = entry.copper, remaining = 0 }
    end
    return { status = "under", total = entry.copper, remaining = minPayment - entry.copper }
end

-- Customers still needed in the Waiting groups. In a party (no raid yet) every member counts as waiting.
function Rules.waitingFree(roster, pendingInvites, isStaff)
    local used = 0
    for _, m in ipairs(roster) do
        if not isStaff(m.name) and Rules.isWaitingGroup(m.subgroup) then
            used = used + 1
        end
    end
    local pending = 0
    for _ in pairs(pendingInvites) do
        pending = pending + 1
    end
    return #ns.WAITING_GROUPS * ns.GROUP_SIZE - used - pending
end

-- Advertiser's raid layout. ctx = { isStaff(name), isPaid(name), newcomers = { [name] = true } }
-- Returns a list of moves { name, index, from, to } and a list of problems (strings).
function Rules.planPlacement(roster, ctx)
    local counts = Rules.groupCounts(roster)
    local moves, problems = {}, {}

    local function move(m, groups, why)
        local to = Rules.firstFreeGroup(counts, groups)
        if not to then
            problems[#problems + 1] = why
            return
        end
        counts[m.subgroup] = counts[m.subgroup] - 1
        counts[to] = counts[to] + 1
        moves[#moves + 1] = { name = m.name, index = m.index, from = m.subgroup, to = to }
    end

    for _, m in ipairs(roster) do
        if ctx.isStaff(m.name) then
            if not Rules.isStaffGroup(m.subgroup) then
                move(m, ns.STAFF_GROUPS, "Staff groups 5-8 are full: can't place " .. m.name)
            end
        elseif ctx.isPaid(m.name) then
            if Rules.isWaitingGroup(m.subgroup) then
                move(m, ns.PAID_GROUPS, "Paid groups 3-4 are full: " .. m.name .. " has paid but waits in group " .. m.subgroup)
            end
        elseif ctx.newcomers[m.name] and not Rules.isWaitingGroup(m.subgroup) then
            move(m, ns.WAITING_GROUPS, "Waiting groups 1-2 are full: new Customer " .. m.name .. " stays in group " .. m.subgroup)
        end
    end
    return moves, problems
end

-- Zone changes since the previous snapshot. prevZones: name -> zone. Updates prevZones in place.
-- Returns { { member, from, to, stopIndex } }. Offline members and first sightings are not arrivals.
function Rules.detectArrivals(prevZones, roster, stops)
    local arrivals = {}
    for _, m in ipairs(roster) do
        if m.online and m.zone and m.zone ~= "" then
            local before = prevZones[m.name]
            if before and before ~= m.zone then
                local stopIndex = Rules.stopIndexOfZone(m.zone, stops)
                if stopIndex and stopIndex ~= Rules.stopIndexOfZone(before, stops) then
                    arrivals[#arrivals + 1] = { member = m, from = before, to = m.zone, stopIndex = stopIndex }
                end
            end
            prevZones[m.name] = m.zone
        end
    end
    return arrivals
end

-- Summoner's join order for the Waiting groups. Members already in groups 1-2 when first seen get
-- numbers in raid order (group, then slot), which is the tie-break for "joined at the same time".
-- joinSeq: name -> number. Returns the next free sequence number.
function Rules.assignJoinSeq(roster, joinSeq, nextSeq)
    local present, fresh = {}, {}
    for _, m in ipairs(roster) do
        present[m.name] = true
        if Rules.isWaitingGroup(m.subgroup) and not joinSeq[m.name] then
            fresh[#fresh + 1] = m
        end
    end
    table.sort(fresh, function(a, b)
        if a.subgroup ~= b.subgroup then
            return a.subgroup < b.subgroup
        end
        return a.index < b.index
    end)
    for _, m in ipairs(fresh) do
        joinSeq[m.name] = nextSeq
        nextSeq = nextSeq + 1
    end
    for name in pairs(joinSeq) do
        if not present[name] then
            joinSeq[name] = nil -- left the raid: a rejoin goes to the back of the line
        end
    end
    return nextSeq
end

-- Is a summon to this Customer still "on its way" (or has it arrived)?
local function summonActive(entry, now)
    return entry ~= nil and (entry.arrived or now - entry.time < ns.SUMMON_PENDING_SECONDS)
end

-- Who should this Summoner summon next?
-- ctx = { stopIndex, stops, summoned = name -> { time, arrived }, joinSeq, now }
-- summoned[name].arrived is sticky: once a Customer has been with me, walking away doesn't undo it.
-- Returns the member (or nil) and info { candidates, paidFree, delivered }.
function Rules.nextSummonTarget(roster, ctx)
    local stops, stopIndex, now = ctx.stops, ctx.stopIndex, ctx.now
    local stop = stops[stopIndex]
    local info = { candidates = 0, paidFree = 0, delivered = 0 }
    if not stop then
        return nil, info
    end

    for _, m in ipairs(roster) do
        local entry = ctx.summoned[m.name]
        if (Rules.isWaitingGroup(m.subgroup) or Rules.isPaidGroup(m.subgroup)) and entry and entry.arrived then
            info.delivered = info.delivered + 1
        end
    end

    local function eligible(m)
        return m.online and not summonActive(ctx.summoned[m.name], now)
    end

    local candidates = {}
    if stopIndex == 1 then
        -- The First Stop summon is free: groups 1-4 qualify, even Customers already somewhere in
        -- Westfall (they may be far from the start). Paid in advance goes first, except Customers
        -- already further along the chain (standing at a later Stop).
        for _, m in ipairs(roster) do
            local at = Rules.stopIndexOfZone(m.zone, stops)
            if Rules.isPaidGroup(m.subgroup) and eligible(m) and (at == nil or at == 1) then
                candidates[#candidates + 1] = m
            end
        end
        -- Unpaid Customers I summoned keep a Paid-group slot reserved until they pay.
        local reserved = 0
        for _, m in ipairs(roster) do
            if Rules.isWaitingGroup(m.subgroup) and summonActive(ctx.summoned[m.name], now) then
                reserved = reserved + 1
            end
        end
        info.paidFree = #ns.PAID_GROUPS * ns.GROUP_SIZE - Rules.countInGroups(roster, ns.PAID_GROUPS) - reserved
        local waiting = {}
        for _, m in ipairs(roster) do
            if Rules.isWaitingGroup(m.subgroup) and eligible(m) then
                waiting[#waiting + 1] = m
            end
        end
        table.sort(waiting, function(a, b)
            local sa, sb = ctx.joinSeq[a.name] or math.huge, ctx.joinSeq[b.name] or math.huge
            if sa ~= sb then
                return sa < sb
            end
            return a.index < b.index
        end)
        -- Advance payers already sit in the Paid groups, so only paidFree limits the Waiting groups.
        for i = 1, math.min(#waiting, math.max(info.paidFree, 0)) do
            candidates[#candidates + 1] = waiting[i]
        end
    else
        -- Every later summon needs the Package paid: groups 3-4 only.
        local previous = stops[stopIndex - 1]
        for _, m in ipairs(roster) do
            if Rules.isPaidGroup(m.subgroup) and eligible(m) and Rules.zoneMatchesStop(m.zone, previous) then
                candidates[#candidates + 1] = m
            end
        end
    end

    info.candidates = #candidates
    return candidates[1], info
end

-- Can this Summoning team log off at its Stop (#11)? ctx is the same as for nextSummonTarget.
-- Returns { state, remaining, unpaid, info }:
--   "ready"  nobody is left to summon here (pending Customers don't count),
--   "busy"   Customers can still be summoned here (Shift+click forces the log off),
--   "unpaid" Westfall only: everyone is summoned, but some summoned Customers (delivered or still
--            pending) haven't paid yet, i.e. are still in groups 1-2. Names in `unpaid`.
function Rules.logoffState(roster, ctx)
    local _, info = Rules.nextSummonTarget(roster, ctx)
    local result = { remaining = info.candidates, unpaid = {}, info = info }
    if ctx.stopIndex == 1 then
        for _, m in ipairs(roster) do
            local entry = ctx.summoned[m.name]
            if Rules.isWaitingGroup(m.subgroup) and entry and (entry.arrived or summonActive(entry, ctx.now)) then
                result.unpaid[#result.unpaid + 1] = m.name
            end
        end
    end
    if result.remaining > 0 then
        result.state = "busy"
    elseif #result.unpaid > 0 then
        result.state = "unpaid"
    else
        result.state = "ready"
    end
    return result
end

-- The next Stop after this one. After the Final Stop the team relogs to the First Stop.
function Rules.nextStopIndex(stopIndex, stops)
    if stopIndex >= #stops then
        return 1
    end
    return stopIndex + 1
end

-- Splits a chat message into pieces of at most maxLen bytes, preferring spaces.
function Rules.splitMessage(text, maxLen)
    maxLen = maxLen or 255
    local pieces = {}
    text = Util.trim(text)
    while #text > maxLen do
        local cut = maxLen
        local space = text:sub(1, maxLen + 1):match(".*()%s")
        if space and space > maxLen / 2 then
            cut = space - 1
        end
        pieces[#pieces + 1] = Util.trim(text:sub(1, cut))
        text = Util.trim(text:sub(cut + 1))
    end
    if text ~= "" then
        pieces[#pieces + 1] = text
    end
    return pieces
end

-- Ledger rows -> CSV text.
function Rules.ledgerCsv(rows)
    local lines = { "date,shift,receiver,from,copper,amount" }
    for _, r in ipairs(rows) do
        lines[#lines + 1] = table.concat({
            Util.csvField(r.date),
            Util.csvField(r.shift),
            Util.csvField(r.receiver),
            Util.csvField(r.from),
            Util.csvField(r.copper),
            Util.csvField(Util.formatMoney(r.copper)),
        }, ",")
    end
    return table.concat(lines, "\n")
end
