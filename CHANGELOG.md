# Changelog

## 0.1.1 - 2026-11-28 (hotfix)

- Fixed: Customers who paid the Minimum payment weren't moved to groups 3-4 (#2). In WoW: Forever, characters have a first and last name and there are no realms. The addon built names as `First-Last`, while the raid roster says `First Last`. It now uses the roster's form everywhere: for your own character, the trade partner and the summon target.
- Ledger rows from 0.1.0 still hold the old `First-Last` names.

## 0.1.0 - 2026-11-26 (beta)

First playable version.

- Advertiser: answers requests (any whisper or keywords only), auto-invites, converts the party to a raid, keeps a Waitlist with an "Invite next" button, checks the Minimum level after joining, invites Staff who report for duty and places them in groups 5-8, promotes Summoners to assistant.
- Raid layout: Waiting groups 1-2, Paid groups 3-4, Staff groups 5-8.
- Payments: trades to the Advertiser or the Westfall Summoner that reach the Minimum payment move the Customer to groups 3-4. The Customer is whispered what was received, or how much is still missing.
- Westfall: free summon for groups 1-4, a pay reminder and one raid warning per Batch for unpaid Customers.
- Summoner: one-click "Summon next" button with a key binding, the summon order per Stop, a whisper per Stop, delivered summons (within 30 yards, sticky), summons left (Soul Shards).
- Final Stop: the Advertiser thanks and removes Customers.
- Account-wide gold ledger during Shifts, with `/sl ledger` and a CSV export.
- Settings page that only shows the settings of the character's role.
