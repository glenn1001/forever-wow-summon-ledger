# The raid layout is the only shared state between Staff addons

Status: accepted

Each Staff member's addon keeps its own state and never syncs with other copies over addon messages. The only thing they share is what every client can already see: who is in the raid, in which raid group, and in which zone. Being in a Paid group *is* the "paid" status. A Customer's progress through the Stops is read from their current zone.

We considered making the Advertiser's addon authoritative and broadcasting the waitlist, join times and payments over raid addon messages. We rejected it. Summoners relog between characters at every Stop, so any synced state would need a hand-over and recovery protocol whenever an authority logs out. The roster survives relogs for free.

## Consequences

- Join times are local guesses. When a Summoner logs in, their addon gives every Customer already in the Waiting groups the same join time. After that it records real join times only for Customers who join later.
- Payments are not summed across Staff. Each receiver checks only trades made to themselves against the Minimum payment.
- Raid warnings and whispers come from whichever addon has the local knowledge (e.g. only the Advertiser knows who checked in as Summoner of the First Stop).
