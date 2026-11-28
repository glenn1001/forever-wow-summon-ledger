-- Pure helpers: no WoW API calls, so they can be unit-tested outside the game.
local _, ns = ...

local Util = {}
ns.Util = Util

function Util.trim(s)
    if s == nil then
        return ""
    end
    local trimmed = tostring(s):gsub("^%s+", ""):gsub("%s+$", "")
    return trimmed
end

-- "a, B ,,c" -> { "a", "b", "c" }
function Util.splitList(s)
    local list = {}
    for part in tostring(s or ""):gmatch("[^,]+") do
        local item = Util.trim(part):lower()
        if item ~= "" then
            list[#list + 1] = item
        end
    end
    return list
end

-- Accepts "1g 50s 3c", "1g50s", "75s", "2" (plain number = gold), "2.5" (= 2g 50s), "15000c".
-- Returns copper, or nil when the text can't be read.
function Util.parseMoney(text)
    text = Util.trim(text):lower()
    if text == "" then
        return nil
    end
    local plain = tonumber(text)
    if plain then
        if plain < 0 then
            return nil
        end
        return math.floor(plain * 10000 + 0.5)
    end
    local total, matched = 0, false
    local rest = text:gsub("(%d+%.?%d*)%s*([gsc])", function(amount, unit)
        matched = true
        local n = tonumber(amount)
        if unit == "g" then
            total = total + n * 10000
        elseif unit == "s" then
            total = total + n * 100
        else
            total = total + n
        end
        return ""
    end)
    if not matched or Util.trim(rest) ~= "" then
        return nil
    end
    return math.floor(total + 0.5)
end

-- 15050 -> "1g 50s 50c", 0 -> "0c"
function Util.formatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if rest > 0 or #parts == 0 then
        parts[#parts + 1] = rest .. "c"
    end
    return table.concat(parts, " ")
end

-- Replaces {key} with vars[key]; unknown keys are left as they are.
function Util.fill(template, vars)
    return (tostring(template or ""):gsub("{(%w+)}", function(key)
        local value = vars and vars[key]
        if value == nil then
            return "{" .. key .. "}"
        end
        return tostring(value)
    end))
end

-- Always "Name-Realm", so names from whispers, trades and the roster compare equal.
function Util.normalizeName(name, realm, defaultRealm)
    if name == nil or name == "" then
        return nil
    end
    if name:find("-", 1, true) then
        return name
    end
    realm = (realm and realm ~= "") and realm or defaultRealm
    if realm == nil or realm == "" then
        return name
    end
    return name .. "-" .. realm:gsub("%s", "")
end

-- Name for the two values UnitName(unit) returns. In WoW: Forever there are no realms
-- (realm == "") and the second value is the character's last name: "First", "Last" -> "First Last",
-- which is how the raid roster and whisper senders write it. With realms: "Name-Realm".
function Util.unitFullName(name, second, realm)
    if name == nil or name == "" then
        return nil
    end
    if realm == nil or realm == "" then
        if second and second ~= "" then
            return name .. " " .. second
        end
        return name
    end
    return Util.normalizeName(name, second, realm)
end

function Util.shortName(fullName)
    if not fullName then
        return nil
    end
    return (fullName:gsub("%-.*$", ""))
end

-- Turns a GlobalStrings format like "%s declines your group invitation." into a Lua pattern.
function Util.patternFromFormat(format)
    if not format then
        return nil
    end
    local pattern = format:gsub("%%%d?%$?s", "\001")
    pattern = pattern:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    pattern = pattern:gsub("\001", "(.+)")
    return "^" .. pattern .. "$"
end

function Util.csvField(value)
    local s = tostring(value == nil and "" or value)
    if s:find('[,"\n]') then
        s = '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

function Util.shallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

-- Fills missing keys in target from defaults (recursively for tables). Existing values win.
function Util.mergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            Util.mergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end
