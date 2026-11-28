-- Slash commands, key bindings and startup.
local _, ns = ...

BINDING_HEADER_SUMMONLEDGER = "SummonLedger"
_G["BINDING_NAME_CLICK SummonLedgerSummonButton:LeftButton"] = "Summon next customer"
BINDING_NAME_SUMMONLEDGER_INVITE_NEXT = "Invite next from the waitlist"
BINDING_NAME_SUMMONLEDGER_TOGGLE = "Show/hide the panel"

function SummonLedger_InviteNext()
    ns.Advertiser.inviteNext()
end

function SummonLedger_TogglePanel()
    ns.Panel.toggle()
end

local HELP = {
    "/sl - show/hide the panel",
    "/sl on | off - start or end your Shift (automation and ledger)",
    "/sl config - settings (role, Stop, prices, whispers)",
    "/sl ledger - totals per Shift   /sl export - full ledger as CSV",
    "/sl next - invite next from the waitlist (Advertiser)",
    "/sl announce - raid warning: who to pay (Advertiser)",
    "/sl report - report for duty to the Advertiser (Summoner/Helper)",
    "/sl reset-ledger - delete the whole ledger",
}

SLASH_SUMMONLEDGER1 = "/sl"
SLASH_SUMMONLEDGER2 = "/summonledger"
SlashCmdList.SUMMONLEDGER = function(input)
    local command = ns.Util.trim(input):lower()
    if command == "" then
        ns.Panel.toggle()
    elseif command == "on" then
        ns.startShift()
    elseif command == "off" then
        ns.stopShift()
    elseif command == "config" or command == "settings" then
        ns.Options.open()
    elseif command == "ledger" then
        ns.Ledger.printSummary()
    elseif command == "export" then
        ns.Export.show()
    elseif command == "next" then
        ns.Advertiser.inviteNext()
    elseif command == "announce" then
        ns.Advertiser.announcePayment()
    elseif command == "report" then
        ns.Summoner.reportForDuty()
    elseif command == "reset-ledger" then
        StaticPopup_Show("SUMMONLEDGER_RESET_LEDGER")
    else
        for _, line in ipairs(HELP) do
            print(line)
        end
    end
end

StaticPopupDialogs["SUMMONLEDGER_RESET_LEDGER"] = {
    text = "Delete every entry in the SummonLedger ledger? This can't be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        wipe(ns.db.ledger)
        ns.print("Ledger cleared.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

ns.on("PLAYER_LOGIN", function()
    ns.Panel.restorePosition()
    if ns.shiftOn() then
        -- The Shift is account-wide, so every character logs in on it: open the panel (#4).
        ns.Panel.show()
        ns.print("Your Shift is still on (" .. (ns.ROLE_LABELS[ns.role()] or "?") .. "). /sl off to end it.")
    end
    if ns.role() == "advertiser" or ns.isFirstStopSummoner() then
        if (ns.settings.minPayment or 0) <= 0 then
            ns.print("|cffff8000Minimum payment isn't set yet: /sl config|r")
        end
    end
end)
