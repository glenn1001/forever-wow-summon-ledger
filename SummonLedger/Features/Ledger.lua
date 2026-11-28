-- Account-wide ledger of gold received during Shifts, and what happens on a payment.
local _, ns = ...

local Api, Rules, Util = ns.Api, ns.Rules, ns.Util

local Ledger = {}
ns.Ledger = Ledger

function Ledger.add(from, copper)
    local row = {
        time = time(),
        date = Api.dateString(),
        shift = ns.db.shift.id,
        receiver = Api.playerName(),
        role = ns.role(),
        from = from,
        copper = copper,
    }
    table.insert(ns.db.ledger, row)
    return row
end

function Ledger.csv()
    return Rules.ledgerCsv(ns.db.ledger)
end

-- Totals per Shift, newest first: { { shift, copper, trades } }
function Ledger.summary()
    local byShift, order = {}, {}
    for _, row in ipairs(ns.db.ledger) do
        local key = row.shift or "?"
        if not byShift[key] then
            byShift[key] = { shift = key, copper = 0, trades = 0 }
            order[#order + 1] = byShift[key]
        end
        byShift[key].copper = byShift[key].copper + row.copper
        byShift[key].trades = byShift[key].trades + 1
    end
    local result = {}
    for i = #order, 1, -1 do
        result[#result + 1] = order[i]
    end
    return result
end

function Ledger.printSummary()
    local summary = Ledger.summary()
    if #summary == 0 then
        ns.print("The ledger is empty.")
        return
    end
    local total = 0
    ns.print("Ledger per Shift (newest first):")
    for i, s in ipairs(summary) do
        total = total + s.copper
        if i <= 10 then
            print(("  %s: %s from %d trade(s)"):format(s.shift, Util.formatMoney(s.copper), s.trades))
        end
    end
    print(("  Total: %s from %d Shift(s). /sl export for every trade."):format(Util.formatMoney(total), #summary))
end

-- Payment handling ------------------------------------------------------------------------

local Payments = {}
ns.Payments = Payments

local pendingMoves = {} -- name -> true: paid, but moving to a Paid group had to wait (combat, no rights, full)

-- Only the Advertiser and the Summoner of the First Stop move payers (see GLOSSARY.md).
local function takesPayment()
    return ns.role() == "advertiser" or ns.isFirstStopSummoner()
end

local function isStaffMember(name)
    if name == Api.playerName() then
        return true
    end
    if ns.role() == "advertiser" and ns.shiftState().staff[name] then
        return true
    end
    for _, m in ipairs(Api.readRoster()) do
        if m.name == name then
            return Rules.isStaffGroup(m.subgroup)
        end
    end
    return false
end

function Payments.tryPendingMoves()
    if not next(pendingMoves) or Api.inCombat() or not Api.canManageRaid() then
        return
    end
    local roster = Api.readRoster()
    local counts = Rules.groupCounts(roster)
    for _, m in ipairs(roster) do
        if pendingMoves[m.name] then
            if Rules.isWaitingGroup(m.subgroup) then
                local to = Rules.firstFreeGroup(counts, ns.PAID_GROUPS)
                if to then
                    Api.setRaidSubgroup(m.index, to)
                    counts[m.subgroup] = counts[m.subgroup] - 1
                    counts[to] = counts[to] + 1
                    pendingMoves[m.name] = nil
                end
            else
                pendingMoves[m.name] = nil
            end
        end
    end
end

ns.on("SL_TRADE_DONE", function(partner, copper)
    if not ns.shiftOn() then
        return
    end
    Ledger.add(partner, copper)
    ns.print(("Received %s from %s (recorded in the ledger)."):format(Util.formatMoney(copper), Api.displayName(partner)))

    if not takesPayment() or isStaffMember(partner) then
        return
    end
    local result = Rules.applyPayment(ns.shiftState().totals, partner, copper, ns.settings.minPayment)
    local texts = ns.settings.texts
    if result.status == "unset" then
        ns.print("|cffff8000Minimum payment isn't set, so nobody is moved. Set it in /sl config.|r")
    elseif result.status == "under" then
        Api.whisper(partner, Util.fill(texts.underpaid, {
            amount = Util.formatMoney(copper),
            remaining = Util.formatMoney(result.remaining),
        }))
    elseif result.status == "paid" then
        Api.whisper(partner, Util.fill(texts.paid, { amount = Util.formatMoney(copper) }))
        if ns.role() == "advertiser" then
            ns.shiftState().paid[partner] = true
            ns.fire("SL_CUSTOMER_PAID", partner)
        else
            pendingMoves[partner] = true
            Payments.tryPendingMoves()
        end
    end
end)

ns.on("GROUP_ROSTER_UPDATE", function()
    ns.debounce("payments", 0.5, Payments.tryPendingMoves)
end)
ns.on("PLAYER_REGEN_ENABLED", Payments.tryPendingMoves)
