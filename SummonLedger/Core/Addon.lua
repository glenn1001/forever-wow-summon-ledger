-- Event bus, saved variables and the Shift switch.
local ADDON_NAME, ns = ...

local Util = ns.Util

local frame = CreateFrame("Frame")
local handlers = {}
local internal = {}

-- ns.on("GROUP_ROSTER_UPDATE", fn) for game events; ns.on("SL_TRADE_DONE", fn) for our own messages.
function ns.on(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not event:find("^SL_") then
            frame:RegisterEvent(event)
        end
    end
    table.insert(handlers[event], fn)
end

function ns.fire(event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then
            ns.print("|cffff4040error in " .. event .. ":|r " .. tostring(err))
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    ns.fire(event, ...)
end)

function ns.print(message)
    print("|cff66ccffSummonLedger|r: " .. tostring(message))
end

-- Debounced call: many GROUP_ROSTER_UPDATEs in a burst result in one call.
function ns.debounce(key, delay, fn)
    if internal[key] then
        return
    end
    internal[key] = true
    C_Timer.After(delay, function()
        internal[key] = nil
        fn()
    end)
end

local function freshShiftState()
    return {
        totals = {}, -- name -> { copper, paid }: payments to me this Shift
        paid = {}, -- name -> true: Customers seen in/moved to the Paid groups (Advertiser)
        staff = {}, -- name -> { stop, role }: Staff who checked in (Advertiser)
        waitlist = {}, -- ordered names
        reminded = {}, -- name -> true: got the Westfall pay reminder
        announced = false, -- raid warning sent for the current Batch
    }
end

ns.on("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then
        return
    end
    SummonLedgerDB = SummonLedgerDB or {}
    SummonLedgerCharDB = SummonLedgerCharDB or {}
    local db = SummonLedgerDB
    db.settings = Util.mergeDefaults(db.settings or {}, ns.ACCOUNT_DEFAULTS)
    db.ledger = db.ledger or {}
    db.shift = db.shift or { on = false }
    db.shift.state = db.shift.state or freshShiftState()
    Util.mergeDefaults(db.shift.state, freshShiftState())
    ns.db = db
    ns.settings = db.settings
    ns.char = Util.mergeDefaults(SummonLedgerCharDB, ns.CHARACTER_DEFAULTS)
    -- 0.1.x kept the Advertiser's name per character: the first character that logs in moves it
    -- to the account-wide settings, every character drops its own copy.
    if ns.char.advertiser ~= nil then
        if Util.trim(db.settings.advertiser) == "" and Util.trim(ns.char.advertiser) ~= "" then
            db.settings.advertiser = Util.trim(ns.char.advertiser)
        end
        ns.char.advertiser = nil
    end
    ns.fire("SL_LOADED")
end)

function ns.shiftOn()
    return ns.db ~= nil and ns.db.shift.on
end

function ns.shiftState()
    return ns.db.shift.state
end

function ns.role()
    return ns.char and ns.char.role or "none"
end

function ns.myStop()
    return ns.settings.stops[ns.char.stop], ns.char.stop
end

function ns.isFirstStopSummoner()
    return ns.role() == "summoner" and ns.char.stop == 1
end

function ns.startShift()
    if ns.db.shift.on then
        ns.print("Shift is already on.")
        return
    end
    ns.db.shift = { on = true, id = date("%Y-%m-%d %H:%M"), startedAt = time(), state = freshShiftState() }
    ns.print("Shift started (" .. ns.ROLE_LABELS[ns.role()] .. "). Automation is on.")
    if ns.role() == "none" then
        ns.print("No role set for this character yet: /sl config")
    end
    ns.fire("SL_SHIFT_CHANGED", true)
end

function ns.stopShift()
    if not ns.db.shift.on then
        ns.print("Shift is already off.")
        return
    end
    ns.db.shift.on = false
    ns.db.shift.endedAt = time()
    ns.print("Shift ended. Automation is off.")
    ns.fire("SL_SHIFT_CHANGED", false)
end
