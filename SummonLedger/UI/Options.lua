-- Settings page (Esc > Options > AddOns > SummonLedger, or /sl config).
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

local refreshers = {}
local y = -8

local function changed()
    ns.fire("SL_SETTINGS_CHANGED")
end

local function header(text)
    y = y - 10
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    y = y - 26
end

local function note(text)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetWidth(560)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    y = y - math.max(16, fs:GetStringHeight() + 6)
end

-- Single-line text field. get() returns the shown text; set(text) stores it (return false to reject).
local function textField(label, width, get, set)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(label)
    y = y - 16
    local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetPoint("TOPLEFT", 22, y)
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
    y = y - 28
end

local function checkbox(label, get, set)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 16, y)
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
    y = y - 28
end

-- Button that cycles through a list of values.
local function cycler(label, values, labels, get, set)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 16, y - 4)
    fs:SetText(label)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(160, 22)
    b:SetPoint("TOPLEFT", 200, y)
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
    y = y - 30
end

local function build()
    local s, c = ns.settings, ns.char

    header("This character")
    note("Role and Stop are saved per character, so each Summoner character can belong to a different Stop.")
    cycler("Role", ns.ROLES, function(v)
        return ns.ROLE_LABELS[v]
    end, function()
        return c.role
    end, function(v)
        c.role = v
    end)
    local stopValues = {}
    for i = 1, #s.stops do
        stopValues[i] = i
    end
    cycler("Stop (Summoner/Helper)", stopValues, function(v)
        return s.stops[v] and s.stops[v].name or "?"
    end, function()
        return c.stop
    end, function(v)
        c.stop = v
    end)
    textField("Advertiser's character name (for check-in whispers)", 250, function()
        return c.advertiser or ""
    end, function(v)
        c.advertiser = Util.trim(v)
    end)

    header("Customers")
    textField("Minimum level", 60, function()
        return tostring(s.minLevel)
    end, function(v)
        local n = tonumber(v)
        if not n or n < 1 then
            return false
        end
        s.minLevel = math.floor(n)
    end)
    textField("Minimum payment (e.g. 1g 50s), used by the Advertiser and the Westfall Summoner", 120, function()
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
    checkbox("Invite anyone who whispers me (otherwise only whispers with a keyword)", function()
        return s.inviteAnyone
    end, function(v)
        s.inviteAnyone = v
    end)
    textField("Keywords (comma separated, whole words, not case sensitive)", 500, function()
        return s.keywords
    end, function(v)
        s.keywords = v
    end)
    checkbox("Invite from the waitlist automatically when a spot opens (otherwise use \"Invite next\")", function()
        return s.autoInviteWaitlist
    end, function(v)
        s.autoInviteWaitlist = v
    end)
    textField("Seconds before an unanswered invite expires", 60, function()
        return tostring(s.inviteTimeout)
    end, function(v)
        local n = tonumber(v)
        if not n or n < 10 then
            return false
        end
        s.inviteTimeout = math.floor(n)
    end)

    header("Stops")
    note("Zone names as shown in the raid roster (English client). Separate several zones with commas.")
    for i, stop in ipairs(s.stops) do
        textField(("Stop %d: %s - zone(s)"):format(i, stop.name), 400, function()
            return stop.zones
        end, function(v)
            if Util.trim(v) == "" then
                return false
            end
            stop.zones = v
        end)
    end

    header("Whispers")
    note("Placeholders in {braces} are filled in automatically. Long texts are sent as several whispers.")
    for _, info in ipairs(ns.TEXT_INFO) do
        local label = info.label .. (info.vars ~= "" and ("  |cff888888" .. info.vars .. "|r") or "")
        textField(label, 560, function()
            return s.texts[info.key] or ""
        end, function(v)
            s.texts[info.key] = v
        end)
    end

    content:SetHeight(-y + 20)
end

page:SetScript("OnShow", function()
    for _, refresh in ipairs(refreshers) do
        refresh()
    end
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
