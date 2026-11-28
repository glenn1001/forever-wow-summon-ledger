-- Settings page (Esc > Options > AddOns > SummonLedger, or /sl config).
-- Only the role selector is always shown; every other row belongs to the roles that use it.
-- Changing the role (or Stop) re-lays out the page.
local _, ns = ...

local Util = ns.Util

local Options = {}
ns.Options = Options

local category
local page = CreateFrame("Frame")
page:Hide()

local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(600, 1200)
scroll:SetScrollChild(content)

local rows = {} -- { key, frame, height, visible() }
local refreshers = {}

-- Visibility rules ------------------------------------------------------------------------

local function role()
    return ns.char.role
end

local VISIBLE = {
    always = function()
        return true
    end,
    none = function()
        return role() == "none"
    end,
    advertiser = function()
        return role() == "advertiser"
    end,
    summoner = function()
        return role() == "summoner"
    end,
    staff = function() -- Summoners and Helpers
        return role() == "summoner" or role() == "helper"
    end,
    stops = function() -- zone names: whoever recognises Stops by zone
        return role() == "advertiser" or role() == "summoner"
    end,
    payment = function() -- the Advertiser and the Summoner of the First Stop take payments
        return role() == "advertiser" or (role() == "summoner" and ns.char.stop == 1)
    end,
}

function Options.layout()
    local y = -8
    for _, r in ipairs(rows) do
        if r.visible() then
            r.frame:ClearAllPoints()
            r.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            r.frame:Show()
            y = y - r.height
        else
            r.frame:Hide()
        end
    end
    content:SetHeight(-y + 20)
end

-- Keys of the rows currently shown (used by the tests).
function Options.visibleKeys()
    local keys = {}
    for _, r in ipairs(rows) do
        if r.visible() then
            keys[#keys + 1] = r.key
        end
    end
    return keys
end

local function changed()
    Options.layout()
    ns.fire("SL_SETTINGS_CHANGED")
end

-- Row builders ----------------------------------------------------------------------------

local function row(key, height, visibility)
    local f = CreateFrame("Frame", nil, content)
    f:SetSize(580, height)
    rows[#rows + 1] = { key = key, frame = f, height = height, visible = VISIBLE[visibility] }
    return f
end

local function header(key, text, visibility)
    local f = row(key, 36, visibility)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 16, -10)
    fs:SetText(text)
end

local function note(key, text, visibility)
    local lines = math.ceil(#text / 95)
    local f = row(key, lines * 13 + 6, visibility)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 16, 0)
    fs:SetWidth(560)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
end

-- Single-line text field. get() returns the shown text; set(text) stores it (return false to reject).
local function textField(key, label, width, visibility, get, set)
    local f = row(key, 44, visibility)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, 0)
    fs:SetText(label)
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", 22, -16)
    box:SetAutoFocus(false)
    box:SetMaxLetters(1000)
    local function save(self)
        if set(self:GetText()) == false then
            ns.print("Invalid value for \"" .. label .. "\", kept the old one.")
        end
        self:SetText(get())
        self:SetCursorPosition(0)
        changed()
    end
    box:SetScript("OnEnterPressed", function(self)
        save(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", save)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(get())
        self:ClearFocus()
    end)
    refreshers[#refreshers + 1] = function()
        box:SetText(get())
        box:SetCursorPosition(0)
    end
end

local function checkbox(key, label, visibility, get, set)
    local f = row(key, 28, visibility)
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, 0)
    local labelText = cb.Text or cb.text
    if type(labelText) == "table" and labelText.SetText then
        labelText:SetText(label)
    end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        changed()
    end)
    refreshers[#refreshers + 1] = function()
        cb:SetChecked(get())
    end
end

-- Button that cycles through a list of values.
local function cycler(key, label, visibility, values, labels, get, set)
    local f = row(key, 30, visibility)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, -4)
    fs:SetText(label)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(160, 22)
    b:SetPoint("TOPLEFT", 200, 0)
    b:SetScript("OnClick", function()
        local current = get()
        local nextIndex = 1
        for i, v in ipairs(values) do
            if v == current then
                nextIndex = i % #values + 1
            end
        end
        set(values[nextIndex])
        b:SetText(labels(values[nextIndex]))
        changed()
    end)
    refreshers[#refreshers + 1] = function()
        b:SetText(labels(get()))
    end
end

local function textRow(info)
    local s = ns.settings
    local label = info.label .. (info.vars ~= "" and ("  |cff888888" .. info.vars .. "|r") or "")
    textField("text:" .. info.key, label, 560, info.use, function()
        return s.texts[info.key] or ""
    end, function(v)
        s.texts[info.key] = v
    end)
end

local function textsFor(use)
    for _, info in ipairs(ns.TEXT_INFO) do
        if info.use == use then
            textRow(info)
        end
    end
end

-- The page --------------------------------------------------------------------------------

local function build()
    local s, c = ns.settings, ns.char

    header("h:character", "This character", "always")
    cycler("role", "Role", "always", ns.ROLES, function(v)
        return ns.ROLE_LABELS[v]
    end, function()
        return c.role
    end, function(v)
        c.role = v
    end)
    note("noRole", "Choose a role to see its settings. Only role and Stop are saved per character; every other setting is shared by all characters on this account.", "none")
    local stopValues = {}
    for i = 1, #s.stops do
        stopValues[i] = i
    end
    cycler("stop", "Stop", "staff", stopValues, function(v)
        return s.stops[v] and s.stops[v].name or "?"
    end, function()
        return c.stop
    end, function(v)
        c.stop = v
    end)
    textField("advertiserName", "Advertiser's character name, all characters on this account (for check-in whispers)", 250, "staff", function()
        return s.advertiser or ""
    end, function(v)
        s.advertiser = Util.trim(v)
    end)
    textsFor("staff")

    header("h:customers", "Customers", "advertiser")
    textField("minLevel", "Minimum level", 60, "advertiser", function()
        return tostring(s.minLevel)
    end, function(v)
        local n = tonumber(v)
        if not n or n < 1 then
            return false
        end
        s.minLevel = math.floor(n)
    end)
    checkbox("inviteAnyone", "Invite anyone who whispers me (otherwise only whispers with a keyword)", "advertiser", function()
        return s.inviteAnyone
    end, function(v)
        s.inviteAnyone = v
    end)
    textField("keywords", "Keywords (comma separated, whole words, not case sensitive)", 500, "advertiser", function()
        return s.keywords
    end, function(v)
        s.keywords = v
    end)
    checkbox("autoInviteWaitlist", "Invite from the waitlist automatically when a spot opens (otherwise use \"Invite next\")", "advertiser", function()
        return s.autoInviteWaitlist
    end, function(v)
        s.autoInviteWaitlist = v
    end)
    textField("inviteTimeout", "Seconds before an unanswered invite expires", 60, "advertiser", function()
        return tostring(s.inviteTimeout)
    end, function(v)
        local n = tonumber(v)
        if not n or n < 10 then
            return false
        end
        s.inviteTimeout = math.floor(n)
    end)
    textsFor("advertiser")

    header("h:payment", "Payment", "payment")
    textField("minPayment", "Minimum payment (e.g. 1g 50s)", 120, "payment", function()
        return s.minPayment > 0 and Util.formatMoney(s.minPayment) or ""
    end, function(v)
        if Util.trim(v) == "" then
            s.minPayment = 0
            return
        end
        local copper = Util.parseMoney(v)
        if not copper then
            return false
        end
        s.minPayment = copper
    end)
    textsFor("payment")

    header("h:summon", "Summon whispers", "summoner")
    note("summonNote", "Whispered to the Customer when you press \"Summon next\". Leave a Stop empty to send nothing. Placeholders: {price} {summoner} {stop}.", "summoner")
    for i, stop in ipairs(s.stops) do
        textField("summonText:" .. i, ("%s"):format(stop.name), 560, "summoner", function()
            return stop.summonText or ""
        end, function(v)
            stop.summonText = v
        end)
        if i == 1 then
            textField("summonTextPaid:1", stop.name .. ", Customer already paid", 560, "summoner", function()
                return stop.summonTextPaid or ""
            end, function(v)
                stop.summonTextPaid = v
            end)
        end
    end

    header("h:stops", "Stop zones", "stops")
    note("stopsNote", "Zone names as shown in the raid roster (English client). Separate several zones with commas.", "stops")
    for i, stop in ipairs(s.stops) do
        textField("zones:" .. i, ("Stop %d: %s - zone(s)"):format(i, stop.name), 400, "stops", function()
            return stop.zones
        end, function(v)
            if Util.trim(v) == "" then
                return false
            end
            stop.zones = v
        end)
    end

    Options.layout()
end

page:SetScript("OnShow", function()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
    Options.layout()
end)

ns.on("SL_LOADED", function()
    build()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(page, "SummonLedger")
        Settings.RegisterAddOnCategory(category)
    end
end)

function Options.open()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        ns.print("Settings panel unavailable.")
    end
end
