-- Detects completed trades and the gold the other player put in.
-- Fires SL_TRADE_DONE(partnerName, copper) once a trade with money has completed.
local _, ns = ...

local Api = ns.Api

local trade = nil -- { partner, copper } while a trade window is open (kept briefly after closing)

local function readMoney()
    if not trade then
        return
    end
    local copper = GetTargetTradeMoney()
    if copper and not Api.isSecret(copper) then
        trade.copper = copper
    end
end

ns.on("TRADE_SHOW", function()
    local name, realm = UnitName("NPC")
    trade = { partner = Api.normalize(name, realm), copper = 0, done = false }
end)

ns.on("TRADE_MONEY_CHANGED", readMoney)
ns.on("TRADE_ACCEPT_UPDATE", readMoney)

local function complete()
    if not trade or trade.done then
        return
    end
    trade.done = true
    if trade.partner and trade.copper > 0 then
        ns.fire("SL_TRADE_DONE", trade.partner, trade.copper)
    end
end

ns.on("UI_INFO_MESSAGE", function(_, message)
    if ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
        complete()
    end
end)

ns.on("TRADE_CLOSED", function()
    -- "Trade complete" arrives around the time the window closes; forget the trade a bit later.
    local closing = trade
    C_Timer.After(2, function()
        if trade == closing then
            trade = nil
        end
    end)
end)
