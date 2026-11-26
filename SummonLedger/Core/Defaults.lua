local _, ns = ...

ns.ADDON_NAME = "SummonLedger"

-- Raid layout (see GLOSSARY.md). Fixed by design, not settings.
ns.WAITING_GROUPS = { 1, 2 }
ns.PAID_GROUPS = { 3, 4 }
ns.STAFF_GROUPS = { 5, 6, 7, 8 }
ns.GROUP_SIZE = 5

ns.ROLES = { "none", "advertiser", "summoner", "helper" }
ns.ROLE_LABELS = { none = "Not set", advertiser = "Advertiser", summoner = "Summoner", helper = "Helper" }

-- Ritual of Summoning. Matched by ID and by (localised) name, in case Forever uses another ID.
ns.SUMMON_SPELL_ID = 698
ns.SUMMON_SPELL_FALLBACK_NAME = "Ritual of Summoning"

-- How long a sent summon counts as "on its way" before the Customer may be summoned again.
ns.SUMMON_PENDING_SECONDS = 120

-- Account-wide settings (SummonLedgerDB.settings). Shared by every character of this player.
ns.ACCOUNT_DEFAULTS = {
    minLevel = 14,
    minPayment = 0, -- copper; 0 = not set yet (warned about, nobody is moved)
    inviteAnyone = false, -- false = only whispers containing a keyword
    keywords = "summon, summons, sum, inv, invite, bag, sleeping, cozy",
    autoInviteWaitlist = false,
    inviteTimeout = 60,
    stops = {
        { name = "Westfall", zones = "Westfall" },
        { name = "Barrens", zones = "The Barrens" },
        { name = "Stonetalon", zones = "Stonetalon Mountains" },
        { name = "Loch Modan", zones = "Loch Modan" },
        { name = "Thoradin's Wall", zones = "Arathi Highlands, Hillsbrad Foothills" },
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

-- Per-character settings (SummonLedgerCharDB).
ns.CHARACTER_DEFAULTS = {
    role = "none",
    stop = 1,
    advertiser = "",
}

-- Placeholders shown next to each text in the settings.
ns.TEXT_INFO = {
    { key = "autoReply", label = "Auto-reply to requests", vars = "" },
    { key = "tooLow", label = "Below minimum level", vars = "{minLevel}" },
    { key = "waitlist", label = "Put on waitlist", vars = "{position}" },
    { key = "spotOpen", label = "Invited from waitlist", vars = "" },
    { key = "paid", label = "Payment received", vars = "{amount}" },
    { key = "underpaid", label = "Payment too low", vars = "{amount} {remaining}" },
    { key = "payReminder", label = "Unpaid arrival in Westfall", vars = "{price} {summoner}" },
    { key = "raidWarning", label = "Raid warning: who to pay", vars = "{summoner}" },
    { key = "thanks", label = "Final Stop reached", vars = "" },
    { key = "checkin", label = "Staff check-in whisper", vars = "{stop} {role}" },
}
