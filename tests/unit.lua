-- Unit tests for the pure modules (Core/Util.lua, Core/Defaults.lua, Core/Rules.lua).
-- Run from the repository root: lua5.1 tests/unit.lua
local ns = {}
for _, file in ipairs({ "Util", "Defaults", "Rules" }) do
    assert(loadfile("SummonLedger/Core/" .. file .. ".lua"))("SummonLedger", ns)
end
local Util, Rules = ns.Util, ns.Rules

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local stops = ns.ACCOUNT_DEFAULTS.stops

local function member(index, name, subgroup, zone, extra)
    local m = { index = index, name = name .. "-Realm", subgroup = subgroup, zone = zone, online = true, level = 20, rank = 0 }
    for k, v in pairs(extra or {}) do
        m[k] = v
    end
    return m
end

-- Util ----------------------------------------------------------------------------------

test("parseMoney", function()
    eq(Util.parseMoney("1g 50s"), 15000)
    eq(Util.parseMoney("1g50s3c"), 15003)
    eq(Util.parseMoney("75s"), 7500)
    eq(Util.parseMoney("2"), 20000, "plain number is gold")
    eq(Util.parseMoney("2.5"), 25000)
    eq(Util.parseMoney("15000c"), 15000)
    eq(Util.parseMoney("abc"), nil)
    eq(Util.parseMoney("1g abc"), nil)
    eq(Util.parseMoney(""), nil)
end)

test("formatMoney", function()
    eq(Util.formatMoney(15050), "1g 50s 50c")
    eq(Util.formatMoney(10000), "1g")
    eq(Util.formatMoney(5000), "50s")
    eq(Util.formatMoney(0), "0c")
end)

test("fill", function()
    eq(Util.fill("Received {amount}, {missing}", { amount = "1g" }), "Received 1g, {missing}")
end)

test("normalizeName", function()
    eq(Util.normalizeName("Bob", nil, "Realm"), "Bob-Realm")
    eq(Util.normalizeName("Bob", "Other Realm", "Realm"), "Bob-OtherRealm")
    eq(Util.normalizeName("Bob-Else", nil, "Realm"), "Bob-Else")
    eq(Util.normalizeName(nil, nil, "Realm"), nil)
end)

test("patternFromFormat", function()
    local p = Util.patternFromFormat("%s declines your group invitation.")
    eq(("Bob declines your group invitation."):match(p), "Bob")
    eq(("Bob-Realm declines your group invitation."):match(p), "Bob-Realm")
    eq(("Bob joins the party."):match(p), nil)
end)

test("csv escaping", function()
    eq(Util.csvField('a,"b"'), '"a,""b"""')
    eq(Util.csvField("plain"), "plain")
end)

test("mergeDefaults keeps saved values", function()
    local saved = { minLevel = 20, texts = { paid = "custom" } }
    Util.mergeDefaults(saved, ns.ACCOUNT_DEFAULTS)
    eq(saved.minLevel, 20)
    eq(saved.texts.paid, "custom")
    eq(saved.texts.thanks, ns.ACCOUNT_DEFAULTS.texts.thanks)
    eq(#saved.stops, 5)
end)

-- Requests and check-in -------------------------------------------------------------------

test("isRequest with keywords", function()
    local kw = "summon, inv, sleeping bag"
    eq(Rules.isRequest("Hi, can I get a SUMMON?", false, kw), true)
    eq(Rules.isRequest("inv pls", false, kw), true)
    eq(Rules.isRequest("is this the sleeping bag thing", false, kw), true)
    eq(Rules.isRequest("invisible", false, kw), false, "whole words only")
    eq(Rules.isRequest("hello", false, kw), false)
    eq(Rules.isRequest("hello", true, kw), true, "invite anyone")
end)

test("parseCheckin", function()
    local stop, role = Rules.parseCheckin("Westfall summoner reporting for duty", stops)
    eq(stop, 1)
    eq(role, "summoner")
    stop, role = Rules.parseCheckin("loch modan HELPER reporting for duty!", stops)
    eq(stop, 4)
    eq(role, "helper")
    stop = Rules.parseCheckin("The Barrens summoner reporting for duty", stops)
    eq(stop, 2, "zone name also works")
    eq(Rules.parseCheckin("Thoradin's Wall summoner reporting for duty", stops), 5)
    eq(Rules.parseCheckin("Narnia summoner reporting for duty", stops), nil)
    eq(Rules.parseCheckin("Westfall tank reporting for duty", stops), nil)
    eq(Rules.parseCheckin("summon pls", stops), nil)
end)

test("stop zones", function()
    eq(Rules.stopIndexOfZone("Westfall", stops), 1)
    eq(Rules.stopIndexOfZone("Hillsbrad Foothills", stops), 5)
    eq(Rules.stopIndexOfZone("Arathi Highlands", stops), 5)
    eq(Rules.stopIndexOfZone("Stormwind City", stops), nil)
end)

-- Payments ------------------------------------------------------------------------------

test("applyPayment adds up per receiver", function()
    local totals = {}
    local r = Rules.applyPayment(totals, "A", 5000, 10000)
    eq(r.status, "under")
    eq(r.remaining, 5000)
    r = Rules.applyPayment(totals, "A", 5000, 10000)
    eq(r.status, "paid")
    r = Rules.applyPayment(totals, "A", 100, 10000)
    eq(r.status, "already")
    eq(Rules.applyPayment(totals, "B", 50000, 10000).status, "paid", "overpaying is just paid")
    eq(Rules.applyPayment({}, "C", 100, 0).status, "unset")
end)

-- Raid layout ---------------------------------------------------------------------------

test("planPlacement moves staff, payers and misplaced newcomers", function()
    local roster = {
        member(1, "Adv", 1),
        member(2, "Paid", 1),
        member(3, "New", 3),
        member(4, "Old", 2),
        member(5, "Summ", 2),
    }
    local staff = { ["Adv-Realm"] = true, ["Summ-Realm"] = true }
    local moves, problems = Rules.planPlacement(roster, {
        isStaff = function(n)
            return staff[n]
        end,
        isPaid = function(n)
            return n == "Paid-Realm"
        end,
        newcomers = { ["New-Realm"] = true },
    })
    eq(#problems, 0)
    eq(#moves, 4)
    local byName = {}
    for _, mv in ipairs(moves) do
        byName[mv.name] = mv.to
    end
    eq(byName["Adv-Realm"], 5)
    eq(byName["Summ-Realm"], 5)
    eq(byName["Paid-Realm"], 3)
    eq(byName["New-Realm"], 1)
    eq(byName["Old-Realm"], nil)
end)

test("planPlacement reports full Paid groups", function()
    local roster = {}
    for i = 1, 10 do
        roster[#roster + 1] = member(i, "P" .. i, i <= 5 and 3 or 4)
    end
    roster[#roster + 1] = member(11, "Late", 1)
    local moves, problems = Rules.planPlacement(roster, {
        isStaff = function()
            return false
        end,
        isPaid = function()
            return true
        end,
        newcomers = {},
    })
    eq(#moves, 0)
    eq(#problems, 1)
end)

test("waitingFree counts pending invites and ignores staff", function()
    local roster = { member(1, "Adv", 1), member(2, "C1", 1), member(3, "C2", 2) }
    local free = Rules.waitingFree(roster, { ["X-Realm"] = 1 }, function(n)
        return n == "Adv-Realm"
    end)
    eq(free, 10 - 2 - 1)
end)

-- Arrivals ------------------------------------------------------------------------------

test("detectArrivals only on zone changes into a Stop", function()
    local prev = {}
    local roster = { member(1, "A", 1, "Stormwind City"), member(2, "B", 1, "Westfall") }
    eq(#Rules.detectArrivals(prev, roster, stops), 0, "first sighting is not an arrival")
    roster[1].zone = "Westfall"
    roster[2].zone = "Westfall"
    local arrivals = Rules.detectArrivals(prev, roster, stops)
    eq(#arrivals, 1)
    eq(arrivals[1].member.name, "A-Realm")
    eq(arrivals[1].stopIndex, 1)
    roster[1].zone = "Hillsbrad Foothills"
    eq(Rules.detectArrivals(prev, roster, stops)[1].stopIndex, 5)
    roster[1].zone = "Arathi Highlands"
    eq(#Rules.detectArrivals(prev, roster, stops), 0, "moving between zones of the same Stop")
end)

-- Join order ----------------------------------------------------------------------------

test("assignJoinSeq: snapshot in raid order, then live, rejoin at the back", function()
    local seq = {}
    local roster = { member(3, "G2", 2), member(1, "G1a", 1), member(2, "G1b", 1), member(4, "Paid", 3) }
    local nextSeq = Rules.assignJoinSeq(roster, seq, 1)
    eq(seq["G1a-Realm"], 1)
    eq(seq["G1b-Realm"], 2)
    eq(seq["G2-Realm"], 3)
    eq(seq["Paid-Realm"], nil)
    table.insert(roster, member(5, "Late", 2))
    nextSeq = Rules.assignJoinSeq(roster, seq, nextSeq)
    eq(seq["Late-Realm"], 4)
    table.remove(roster, 2) -- G1a leaves
    nextSeq = Rules.assignJoinSeq(roster, seq, nextSeq)
    eq(seq["G1a-Realm"], nil)
    table.insert(roster, member(6, "G1a", 1))
    Rules.assignJoinSeq(roster, seq, nextSeq)
    eq(seq["G1a-Realm"], 5)
end)

-- Summon order --------------------------------------------------------------------------

local function ctx(stopIndex, extra)
    local c = { stopIndex = stopIndex, stops = stops, summoned = {}, joinSeq = {}, now = 1000 }
    for k, v in pairs(extra or {}) do
        c[k] = v
    end
    return c
end

test("First Stop: advance payers first, then longest waiting", function()
    local roster = {
        member(1, "W1", 1, "Elwynn Forest"),
        member(2, "W2", 1, "Stormwind City"),
        member(3, "Adv", 3, "Ironforge"),
        member(4, "OnChain", 4, "Loch Modan"),
    }
    local c = ctx(1, { joinSeq = { ["W1-Realm"] = 2, ["W2-Realm"] = 1 } })
    local target, info = Rules.nextSummonTarget(roster, c)
    eq(target.name, "Adv-Realm", "paid in advance goes first")
    eq(info.candidates, 3, "OnChain is already on the chain")
    c.summoned["Adv-Realm"] = { time = 999, arrived = false }
    target = Rules.nextSummonTarget(roster, c)
    eq(target.name, "W2-Realm", "lowest join number")
end)

test("First Stop: Waiting groups only while Paid groups have room", function()
    local roster = {}
    for i = 1, 9 do
        roster[#roster + 1] = member(i, "P" .. i, i <= 5 and 3 or 4, "Loch Modan")
    end
    roster[#roster + 1] = member(10, "W1", 1, "Elwynn Forest")
    roster[#roster + 1] = member(11, "W2", 1, "Elwynn Forest")
    roster[#roster + 1] = member(12, "Done", 2, "Westfall")
    local c = ctx(1, { joinSeq = { ["W1-Realm"] = 1, ["W2-Realm"] = 2 } })
    local target, info = Rules.nextSummonTarget(roster, c)
    eq(info.paidFree, 1)
    eq(target.name, "W1-Realm")
    eq(info.candidates, 1, "only one free Paid slot")
    c.summoned["W1-Realm"] = { time = 999, arrived = false }
    target, info = Rules.nextSummonTarget(roster, c)
    eq(target, nil, "W1's summon reserves the last slot")
    eq(info.paidFree, 0)
    c.now = 999 + ns.SUMMON_PENDING_SECONDS + 1
    target = Rules.nextSummonTarget(roster, c)
    eq(target.name, "W1-Realm", "expired summon frees the slot again")
end)

test("First Stop skips Customers already standing in Westfall and offline ones", function()
    local roster = {
        member(1, "There", 1, "Westfall"),
        member(2, "Off", 1, "Elwynn Forest", { online = false }),
    }
    local target, info = Rules.nextSummonTarget(roster, ctx(1))
    eq(target, nil)
    eq(info.atStop, 1)
end)

test("Later Stops: only paid Customers standing at the previous Stop", function()
    local roster = {
        member(1, "Unpaid", 1, "Stonetalon Mountains"),
        member(2, "Ready", 3, "Stonetalon Mountains"),
        member(3, "Behind", 3, "The Barrens"),
        member(4, "Here", 4, "Loch Modan"),
    }
    local target, info = Rules.nextSummonTarget(roster, ctx(4))
    eq(target.name, "Ready-Realm")
    eq(info.candidates, 1)
    eq(info.atStop, 1)
end)

-- Messages and ledger -------------------------------------------------------------------

test("splitMessage", function()
    local text = string.rep("word ", 120)
    local pieces = Rules.splitMessage(text, 255)
    eq(#pieces, 3)
    for _, p in ipairs(pieces) do
        assert(#p <= 255, "piece too long")
    end
    eq(#Rules.splitMessage("short", 255), 1)
end)

test("ledgerCsv", function()
    local csv = Rules.ledgerCsv({ { date = "2026-11-26 20:00:00", shift = "s1", receiver = "Me-Realm", from = "A-Realm", copper = 15000 } })
    eq(csv, "date,shift,receiver,from,copper,amount\n2026-11-26 20:00:00,s1,Me-Realm,A-Realm,15000,1g 50s")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
