-- Ledger window: totals per Shift plus the full ledger as CSV to copy (Ctrl+A, Ctrl+C).
local _, ns = ...

local Util = ns.Util

local Export = {}
ns.Export = Export

local frame = CreateFrame("Frame", "SummonLedgerExport", UIParent, "BackdropTemplate")
frame:SetSize(560, 420)
frame:SetPoint("CENTER")
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
tinsert(UISpecialFrames, "SummonLedgerExport") -- Esc closes it

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -16)
title:SetText("SummonLedger - Ledger")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
summary:SetPoint("TOPLEFT", 20, -44)
summary:SetPoint("TOPRIGHT", -20, -44)
summary:SetJustifyH("LEFT")

local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", 20, -110)
hint:SetText("CSV of every trade: click in the box, Ctrl+A, Ctrl+C, paste into a spreadsheet.")

local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 20, -128)
scroll:SetPoint("BOTTOMRIGHT", -36, 20)
local box = CreateFrame("EditBox", nil, scroll)
box:SetMultiLine(true)
box:SetFontObject(ChatFontNormal)
box:SetWidth(490)
box:SetAutoFocus(false)
box:SetScript("OnEscapePressed", function()
    frame:Hide()
end)
scroll:SetScrollChild(box)

function Export.show()
    local lines = {}
    local total = 0
    for i, s in ipairs(ns.Ledger.summary()) do
        total = total + s.copper
        if i <= 3 then
            lines[#lines + 1] = ("Shift %s: %s (%d trades)"):format(s.shift, Util.formatMoney(s.copper), s.trades)
        end
    end
    lines[#lines + 1] = "All Shifts: " .. Util.formatMoney(total)
    summary:SetText(table.concat(lines, "\n"))
    box:SetText(ns.Ledger.csv())
    frame:Show()
end
