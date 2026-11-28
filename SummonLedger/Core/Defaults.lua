local _, ns = ...

ns.ADDON_NAME = "SummonLedger"

-- Raid layout (see GLOSSARY.md). Fixed by design, not settings.
ns.WAITING_GROUPS = { 1, 2 }
ns.PAID_GROUPS = { 3, 4 }
ns.STAFF_GROUPS = { 5, 6, 7, 8 }
ns.GROUP_SIZE = 5

ns.ROLES = { "none", "advertiser", "summoner", "helper" }
ns.ROLE_LABELS = { none = "Not set", advertiser = "Advertiser", summoner = "Summoner", helper = "Helper" }

-- Role guessing (#5): where the Advertiser usually stands, and the levels that decide.
ns.ADVERTISER_ZONES = { "Stormwind City", "Ironforge" }
ns.SUMMONER_MIN_LEVEL = 20 -- Ritual of Summoning is learned at 20
ns.MAX_LEVEL = 60

-- Ritual of Summoning. Matched by ID and by (localised) name, in case Forever uses another ID.
ns.SUMMON_SPELL_ID = 698
ns.SUMMON_SPELL_FALLBACK_NAME = "Ritual of Summoning"

-- Soul Shard, Ritual of Summoning's reagent. Used only if the cast-count API is missing.
ns.SOUL_SHARD_ITEM_ID = 6265
-- Warn the Summoner when this few summons are left.
ns.LOW_SUMMONS_WARNING = 3

-- How long a sent summon counts as "on its way" before the Customer may be summoned again.
ns.SUMMON_PENDING_SECONDS = 120

-- A summon is delivered once the Customer is in the Stop's zone AND this close to the Summoner.
ns.ARRIVAL_RANGE_YARDS = 30

-- Account-wide settings (SummonLedgerDB.settings). Shared by every character of this player.
-- Everything is account-wide except a character's role and Stop (issue #6).
ns.ACCOUNT_DEFAULTS = {
    advertiser = "", -- the Advertiser's character name, for check-in whispers
    minLevel = 14,
    minPayment = 0, -- copper; 0 = not set yet (warned about, nobody is moved)
    inviteAnyone = false, -- false = only whispers containing a keyword
    keywords = "summon, summons, sum, inv, invite, bag, sleeping, cozy",
    autoInviteWaitlist = false,
    inviteTimeout = 60,
    -- summonText: whispered by the Summoner on "Summon next" (empty = no whisper).
    -- summonTextPaid (First Stop only): used instead for Customers who already paid.
    stops = {
        {
            name = "Westfall",
            zones = "Westfall",
            summonText = "Summoning you to Westfall, please accept! After the summon, trade {price} to {summoner}, then follow the raid markers to complete the quest.",
            summonTextPaid = "Summoning you to Westfall, please accept! Then follow the raid markers to complete the quest.",
        },
        { name = "Barrens", zones = "The Barrens", summonText = "" },
        {
            name = "Stonetalon",
            zones = "Stonetalon Mountains",
            summonText = "Summoning you to Stonetalon, please accept! The quest here has 2 parts: follow the raid markers for both.",
        },
        { name = "Loch Modan", zones = "Loch Modan", summonText = "" },
        { name = "Thoradin's Wall", zones = "Arathi Highlands, Hillsbrad Foothills", summonText = "" },
    },
    texts = {
        autoReply = "Hi! We summon you through the whole Cozy Sleeping Bag chain: Westfall, Barrens, Stonetalon, Loch Modan and Thoradin's Wall. Accept the raid invite and stay online. Pay after your first summon to Westfall (or trade me now), then accept every summon.",
        tooLow = "Sorry, the Cozy Sleeping Bag chain can only be started from level {minLevel}. Come back when you've reached it!",
        waitlist = "We're full right now. You're #{position} on the waitlist; you'll get an invite as soon as a spot opens.",
        spotOpen = "A spot opened up, sending you a raid invite now!",
        paid = "Received {amount}, thank you! You'll be moved to the paid group and receive all summons shortly.",
        underpaid = "Received {amount}, thanks! That's not enough for the summoning package yet: please trade another {remaining}.",
        payReminder = "Welcome to Westfall! Please trade {price} to {summoner} to get the rest of your summons.",
        raidWarning = "Arrived in Westfall? Trade your payment to {summoner}!",
        thanks = "You've arrived at Thoradin's Wall. Thank you for using our summoning service, good luck with the last step!",
        checkin = "{stop} {role} reporting for duty",
    },
}

-- Per-character settings (SummonLedgerCharDB): only what differs between one player's characters.
ns.CHARACTER_DEFAULTS = {
    role = "none",
    stop = 1,
}

-- Placeholders shown next to each text in the settings; `use` = who needs it ("payment" = takes payments).
ns.TEXT_INFO = {
    { key = "autoReply", label = "Auto-reply to requests", vars = "", use = "advertiser" },
    { key = "tooLow", label = "Below minimum level", vars = "{minLevel}", use = "advertiser" },
    { key = "waitlist", label = "Put on waitlist", vars = "{position}", use = "advertiser" },
    { key = "spotOpen", label = "Invited from waitlist", vars = "", use = "advertiser" },
    { key = "paid", label = "Payment received", vars = "{amount}", use = "payment" },
    { key = "underpaid", label = "Payment too low", vars = "{amount} {remaining}", use = "payment" },
    { key = "payReminder", label = "Unpaid arrival in Westfall", vars = "{price} {summoner}", use = "advertiser" },
    { key = "raidWarning", label = "Raid warning: who to pay", vars = "{summoner}", use = "advertiser" },
    { key = "thanks", label = "Final Stop reached", vars = "", use = "advertiser" },
    { key = "checkin", label = "Staff check-in whisper", vars = "{stop} {role}", use = "staff" },
}
