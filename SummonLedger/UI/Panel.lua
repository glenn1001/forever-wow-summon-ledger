-- The movable status panel (/sl). Shows the Shift switch and, per role, the relevant buttons and lists.
local _, ns = ...

local Api, Util = ns.Api, ns.Util

local Panel = {}
ns.Panel = Panel

local panel = CreateFrame("Frame", "SummonLedgerPanel", UIParent, "BackdropTemplate")
panel:SetSize(320, 380)
panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0, 0, 0, 0.85)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    ns.db.panel = { point = point, relativePoint = relativePoint, x = x, y = y }
end)
panel:SetClampedToScreen(true)
panel:Hide()

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("SummonLedger")

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local updateRoleButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
updateRoleButton:SetSize(90, 20)
updateRoleButton:SetPoint("TOPRIGHT", -30, -8)
updateRoleButton:SetText("Update role")
updateRoleButton:SetScript("OnClick", function()
    ns.Role.guess(true)
end)
Panel.updateRoleButton = updateRoleButton

local roleText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
roleText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

local function makeButton(label, width, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local shiftButton = makeButton("Start Shift", 110, function()
    if ns.shiftOn() then
        ns.stopShift()
    else
        ns.startShift()
    end
end)
shiftButton:SetPoint("TOPLEFT", 10, -48)

local configButton = makeButton("Settings", 70, function()
    ns.Options.open()
end)
configButton:SetPoint("LEFT", shiftButton, "RIGHT", 4, 0)

local ledgerButton = makeButton("Ledger", 70, function()
    ns.Export.show()
end)
ledgerButton:SetPoint("LEFT", configButton, "RIGHT", 4, 0)

-- Role-specific buttons, all on the second row.
local inviteNextButton = makeButton("Invite next", 100, function()
    ns.Advertiser.inviteNext()
end)
inviteNextButton:SetPoint("TOPLEFT", 10, -74)

local announceButton = makeButton("Announce payment", 130, function()
    ns.Advertiser.announcePayment()
end)
announceButton:SetPoint("LEFT", inviteNextButton, "RIGHT", 4, 0)

local reportButton = makeButton("Report for duty", 120, function()
    ns.Summoner.reportForDuty()
end)
reportButton:SetPoint("TOPLEFT", 10, -74)

local body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
body:SetPoint("TOPLEFT", 12, -130)
body:SetPoint("BOTTOMRIGHT", -12, 10)
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
body:SetWordWrap(true)

local function colorName(name, color)
    return "|cff" .. color .. Api.displayName(name) .. "|r"
end

local function advertiserBody()
    local o = ns.Advertiser.overview()
    local lines = {}
    local summoner = ns.Advertiser.firstStopSummoner()
    lines[#lines + 1] = "Westfall Summoner: " .. (summoner and colorName(summoner, "ffd100") or "|cffff8000none checked in|r")
    lines[#lines + 1] = ("Free in groups 1-2: %d   Pending invites: %d   Staff: %d"):format(math.max(o.free, 0), o.pending, o.staff)
    lines[#lines + 1] = ""
    local waitlist = {}
    for i, name in ipairs(o.waitlist) do
        if i > 8 then
            waitlist[#waitlist + 1] = "..."
            break
        end
        waitlist[#waitlist + 1] = Api.displayName(name)
    end
    lines[#lines + 1] = ("|cffffd100Waitlist (%d):|r %s"):format(#o.waitlist, table.concat(waitlist, ", "))
    local waiting = {}
    for _, c in ipairs(o.waiting) do
        local color = c.owing and "ff4040" or "ffffff"
        waiting[#waiting + 1] = colorName(c.name, color) .. " (" .. (c.level or "?") .. ")"
    end
    lines[#lines + 1] = ("|cffffd100Waiting, groups 1-2 (%d):|r %s"):format(#o.waiting, table.concat(waiting, ", "))
    lines[#lines + 1] = "  |cffff4040red|r = arrived in Westfall but not paid yet"
    local paid = {}
    for _, c in ipairs(o.paid) do
        paid[#paid + 1] = Api.displayName(c.name) .. (c.zone and (" |cff888888" .. c.zone .. "|r") or "")
    end
    lines[#lines + 1] = ("|cffffd100Paid, groups 3-4 (%d):|r %s"):format(#o.paid, table.concat(paid, ", "))
    for _, problem in ipairs(ns.Advertiser.problems or {}) do
        lines[#lines + 1] = "|cffff8000" .. problem .. "|r"
    end
    return table.concat(lines, "\n")
end

local function summonerBody()
    local stop, index = ns.myStop()
    local target, info = ns.Summoner.status()
    local lines = {
        ("My Stop: |cffffd100%s|r (%d of %d)"):format(stop and stop.name or "?", index, #ns.settings.stops),
        "Next: " .. (target and colorName(target.name, "00ff00") or "|cff888888nobody|r"),
        "Summons left: " .. (function()
            local left = ns.Summoner.summonsLeft()
            if left == nil then
                return "|cff888888unknown|r"
            elseif left == 0 then
                return "|cffff40400 - out of Soul Shards|r"
            elseif left <= ns.LOW_SUMMONS_WARNING then
                return "|cffff8000" .. left .. "|r"
            end
            return tostring(left)
        end)(),
        ("Still to summon here: %d   Delivered: %d"):format(info.candidates, info.delivered),
        ("Delivered = has been within %d yards of you here (walking away afterwards is fine)."):format(ns.ARRIVAL_RANGE_YARDS),
    }
    if index == 1 then
        lines[#lines + 1] = ("Free Paid-group slots: %d"):format(math.max(info.paidFree, 0))
    end
    local state = ns.Summoner.logoffState()
    if state.state == "ready" then
        lines[#lines + 1] = "|cff00ff00Everyone has been summoned here: you can log off.|r"
    elseif state.state == "unpaid" then
        lines[#lines + 1] = "|cffff4040Payment missing from: " .. ns.Summoner.namesList(state.unpaid) .. "|r"
    else
        lines[#lines + 1] = "|cff888888Log off: Shift+click to log off before everyone is summoned.|r"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Bind a key to \"Summon next customer\" (Key Bindings > AddOns)."
    return table.concat(lines, "\n")
end

function Panel.refresh()
    if not panel:IsShown() or not ns.db then
        return
    end
    local role = ns.role()
    local stop = ns.myStop()
    local shift = ns.shiftOn() and "|cff00ff00Shift on|r" or "|cffff4040Shift off|r"
    local roleLabel = ns.ROLE_LABELS[role] or role
    if role == "summoner" or role == "helper" then
        roleLabel = roleLabel .. " at " .. (stop and stop.name or "?")
    end
    roleText:SetText(roleLabel .. " - " .. shift)
    shiftButton:SetText(ns.shiftOn() and "End Shift" or "Start Shift")

    inviteNextButton:SetShown(role == "advertiser")
    announceButton:SetShown(role == "advertiser")
    reportButton:SetShown(role == "summoner" or role == "helper")

    local summonButton = ns.Summoner.button
    local logoffButton = ns.Summoner.logoffButton
    local logoffState = role == "summoner" and ns.Summoner.logoffState() or nil
    if not InCombatLockdown() then
        if role == "summoner" or role == "helper" then
            logoffButton:SetParent(panel)
            logoffButton:ClearAllPoints()
            logoffButton:SetPoint("TOPLEFT", 10, -100)
            -- Westfall: hidden while someone summoned hasn't paid. Elsewhere: greyed out while
            -- Customers can still be summoned (it stays clickable: Shift+click forces it).
            logoffButton:SetShown(not (logoffState and logoffState.state == "unpaid"))
            logoffButton:SetAlpha((logoffState and logoffState.state == "busy") and 0.5 or 1)
        else
            logoffButton:Hide()
        end
        if role == "summoner" then
            summonButton:SetParent(panel)
            summonButton:ClearAllPoints()
            summonButton:SetPoint("LEFT", reportButton, "RIGHT", 4, 0)
            summonButton:Show()
        else
            summonButton:Hide()
        end
    end

    if role == "advertiser" then
        body:SetText(advertiserBody())
    elseif role == "summoner" then
        body:SetText(summonerBody())
    elseif role == "helper" then
        body:SetText("Helpers only click the summoning portal.\nCheck-in happens automatically on login during a Shift.")
    else
        body:SetText("Choose this character's role in Settings.")
    end
end

-- Open the panel. The Summon next button (secure) lives on it, so showing it in combat would be
-- blocked: then it opens as soon as combat ends.
local showAfterCombat = false
function Panel.show()
    if InCombatLockdown() then
        showAfterCombat = true
        return
    end
    showAfterCombat = false
    panel:Show()
    Panel.refresh()
end

ns.on("PLAYER_REGEN_ENABLED", function()
    if showAfterCombat then
        Panel.show()
    end
end)

function Panel.toggle()
    if InCombatLockdown() then
        ns.print("Can't open or close the panel in combat.")
        return
    end
    panel:SetShown(not panel:IsShown())
    Panel.refresh()
end

function Panel.restorePosition()
    local p = ns.db.panel
    if p then
        panel:ClearAllPoints()
        panel:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
    end
end

ns.on("SL_UI_REFRESH", Panel.refresh)
ns.on("SL_SHIFT_CHANGED", Panel.refresh)
ns.on("SL_SETTINGS_CHANGED", Panel.refresh)
