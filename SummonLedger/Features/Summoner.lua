-- Summoner automation: join order, the one-click "Summon next" secure button, tracking sent summons.
-- Also the Staff check-in whisper for Summoners and Helpers.
local _, ns = ...

local Api, Rules, Util = ns.Api, ns.Rules, ns.Util

local Summoner = {}
ns.Summoner = Summoner

-- Local to this login on purpose (ADR 0001): a relog starts a fresh join order.
local joinSeq = {}
local nextSeq = 1
local summoned = {} -- name -> { time, arrived }
local lastInfo = { candidates = 0, paidFree = 0, atStop = 0 }
local lastTarget = nil
local whispered = {} -- name -> time of the last summon whisper (a key press fires PreClick twice)
local SUMMON_WHISPER_COOLDOWN = 30

local function active()
    return ns.shiftOn() and ns.role() == "summoner"
end

function Summoner.next()
    local roster = Api.readRoster()
    local target, info = Rules.nextSummonTarget(roster, {
        stopIndex = ns.char.stop,
        stops = ns.settings.stops,
        summoned = summoned,
        joinSeq = joinSeq,
        now = Api.now(),
    })
    lastInfo = info
    lastTarget = target
    return target, info
end

function Summoner.status()
    return lastTarget, lastInfo
end

function Summoner.update()
    if not active() or not IsInRaid() then
        return
    end
    local roster = Api.readRoster()
    nextSeq = Rules.assignJoinSeq(roster, joinSeq, nextSeq)
    local stop = ns.myStop()
    local present = {}
    for _, m in ipairs(roster) do
        present[m.name] = true
        -- Delivered once they've stood at me (Stop's zone, within range), summoned or not. That sticks:
        -- they walk off to do the quest step. A summon that never gets here expires after
        -- SUMMON_PENDING_SECONDS and they're offered again.
        if (Rules.isWaitingGroup(m.subgroup) or Rules.isPaidGroup(m.subgroup)) and Rules.isAtSummoner(m, stop) then
            local entry = summoned[m.name]
            if entry then
                entry.arrived = true
            else
                summoned[m.name] = { time = Api.now(), arrived = true }
            end
        end
    end
    for name in pairs(summoned) do
        if not present[name] then
            summoned[name] = nil
        end
    end
    Summoner.next()
    ns.fire("SL_UI_REFRESH")
end

-- Whisper the Stop's summon message to the Customer being summoned. Empty message = no whisper.
function Summoner.whisperSummonText(target)
    local stop, index = ns.myStop()
    if not stop or not target then
        return
    end
    local text = stop.summonText
    if index == 1 and Rules.isPaidGroup(target.subgroup) then
        text = stop.summonTextPaid
    end
    if Util.trim(text) == "" then
        return
    end
    local now = Api.now()
    if whispered[target.name] and now - whispered[target.name] < SUMMON_WHISPER_COOLDOWN then
        return
    end
    whispered[target.name] = now
    local price = (ns.settings.minPayment or 0) > 0 and Util.formatMoney(ns.settings.minPayment) or "the price"
    Api.whisper(target.name, Util.fill(text, {
        price = price,
        summoner = Api.displayName(Api.playerName()),
        stop = stop.name,
    }))
end

-- The secure button. Its macro is rewritten right before each click (allowed outside combat).
local button = CreateFrame("Button", "SummonLedgerSummonButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
button:SetSize(150, 26)
button:SetText("Summon next")
button:RegisterForClicks("AnyUp", "AnyDown")
button:SetAttribute("type", "macro")
button:SetAttribute("macrotext", "")
button:Hide()
Summoner.button = button

button:SetScript("PreClick", function(self)
    if InCombatLockdown() then
        return
    end
    if not active() then
        self:SetAttribute("macrotext", "")
        ns.print("Start a Shift as Summoner first (/sl on).")
        return
    end
    local target = Summoner.next()
    if not target then
        self:SetAttribute("macrotext", "")
        ns.print("Nobody to summon right now.")
        return
    end
    self:SetAttribute("macrotext", "/target " .. Api.displayName(target.name) .. "\n/cast " .. Api.summonSpellName())
    Summoner.whisperSummonText(target)
end)

local function onSummonCast(unit, _, spellID)
    if unit ~= "player" or not active() or Api.isSecret(spellID) then
        return
    end
    if spellID ~= ns.SUMMON_SPELL_ID then
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        if name ~= Api.summonSpellName() then
            return
        end
    end
    local name, realm = UnitName("target")
    local full = Api.normalize(name, realm)
    if full then
        summoned[full] = { time = Api.now(), arrived = false }
        Summoner.update()
    end
end
ns.on("UNIT_SPELLCAST_SUCCEEDED", onSummonCast)
ns.on("UNIT_SPELLCAST_CHANNEL_START", onSummonCast)

local function scheduleUpdate()
    ns.debounce("summoner", 0.3, Summoner.update)
end
ns.on("GROUP_ROSTER_UPDATE", scheduleUpdate)
ns.on("SL_SHIFT_CHANGED", scheduleUpdate)

C_Timer.NewTicker(2, function()
    if active() and IsInRaid() then
        Summoner.update()
    end
end)

-- Check-in ------------------------------------------------------------------------------

function Summoner.reportForDuty()
    local role = ns.role()
    if role ~= "summoner" and role ~= "helper" then
        ns.print("Only Summoners and Helpers report for duty. Set the role in /sl config.")
        return
    end
    local advertiser = Util.trim(ns.char.advertiser)
    if advertiser == "" then
        ns.print("Set the Advertiser's name in /sl config first.")
        return
    end
    local stop = ns.myStop()
    local text = Util.fill(ns.settings.texts.checkin, { stop = stop and stop.name or "?", role = role })
    if Api.whisper(advertiser, text) then
        ns.print("Reported for duty to " .. advertiser .. ".")
    end
end

ns.on("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if not (isLogin or isReload) then
        return
    end
    -- Give the roster a moment to load, then check in if this character isn't in the raid yet.
    C_Timer.After(5, function()
        local role = ns.role()
        if ns.shiftOn() and (role == "summoner" or role == "helper") and not IsInRaid() then
            Summoner.reportForDuty()
        end
    end)
end)
