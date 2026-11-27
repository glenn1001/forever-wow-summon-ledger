# SummonLedger

A WoW: Forever addon for running a summoning service for the Cozy Sleeping Bag quest chain. It answers requests, invites Customers, checks their level, keeps the raid groups in order, takes payments with a gold ledger, gives Summoners a one-click "Summon next" button, and removes Customers once they reach the Final Stop.

The language used here (Customer, Staff, Stop, Batch, Shift, ...) is defined in [GLOSSARY.md](GLOSSARY.md). Design decisions are in [docs/adr](docs/adr).

## Install

The addon is the `SummonLedger` folder. Link it into the game once, from an **admin** Command Prompt:

```
mklink /J "D:\games\Battle.net\World of Warcraft\_forever_\Interface\AddOns\SummonLedger" "F:\media\hermes\projects\summon-ledger\SummonLedger"
```

Changes to the files then show up in game after `/reload`. Every Staff member needs the addon. Others can simply copy the folder into their `AddOns`.

## Setup per character

`/sl config` (or Esc > Options > AddOns > SummonLedger):

- **Role**: Advertiser, Summoner or Helper. **Stop**: which Stop this Summoner/Helper character is parked at.
- **Advertiser's character name**: Summoners and Helpers whisper their check-in to this name.
- Advertiser and Westfall Summoner: set the **Minimum payment**.
- Advertiser: invite mode (anyone or keywords), keywords, whisper texts.
- Summoner: a whisper per Stop, sent to the Customer on "Summon next" (empty = none). Westfall has a second text for Customers who already paid.
- The page only shows the settings for this character's role. With no role chosen, only the role selector is shown.
- Key Bindings > AddOns: bind **Summon next customer** (Summoners) and **Invite next from the waitlist** (Advertiser).

## Running a Shift

1. Advertiser: `/sl on`, open the panel with `/sl`.
2. Summoners and Helpers: `/sl on` once. The Shift stays on across relogs, and each character not yet in the raid whispers "`<Stop> <role> reporting for duty`" to the Advertiser 5 seconds after login. The Advertiser's addon invites them, converts to a raid, moves Staff to groups 5-8 and makes Summoners assistant.
3. Customers who whisper get the auto-reply and an invite (or a Waitlist spot when groups 1-2 are full). Below the Minimum level they're told and removed.
4. The Westfall Summoner presses **Summon next**: advance payers first, then the longest-waiting Customer in groups 1-2, as long as groups 3-4 have room.
5. On arrival in Westfall, unpaid Customers get a pay reminder and the raid gets one warning naming the Westfall Summoner. Paying the Minimum payment to the Advertiser or the Westfall Summoner moves them to groups 3-4.
6. The next Summoners summon paid Customers standing at the previous Stop. At Thoradin's Wall the Advertiser's addon thanks and removes them.
7. `/sl off` ends the Shift. `/sl ledger` shows totals, `/sl export` the CSV.

## Commands

`/sl` panel · `/sl on|off` · `/sl config` · `/sl ledger` · `/sl export` · `/sl next` · `/sl announce` · `/sl report` · `/sl reset-ledger`

## Tests

The game logic in `SummonLedger/Core/Rules.lua` is pure Lua. `tests/smoke.lua` loads the whole addon against a mocked WoW API and plays a service run:

```
lua5.1 tests/unit.lua
lua5.1 tests/smoke.lua
```

These don't replace testing in game. The mock only models what the addon calls.
