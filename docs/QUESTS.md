# Quests, rituals and mystery items

Everything here is defined in `src/shared/Config/Quests.luau` and run by `src/server/Services/Quests.luau`.
Press **Q** (or click the tracker under the HUD) for the quest log. Progress saves in each save slot.

Quest gear is earned, never sold. No cash or Robux price buys a quest shovel, rake, glove, truck or relic.

## How it works

- Quests start on their own once the quests they need are done. Several run at once.
- The tracker under the HUD shows one quest's current step and the time of day. "Track" in the log picks which.
- A gold **!** floats over every place one of your quests needs, and only you see your own.
- Time of day matters for rituals. One full day is 20 real minutes. Dusk is 17:30 to 20:00, night 19:30 to 05:30,
  midnight 23:00 to 01:00 (about 1.7 real minutes).
- Offerings take needles from your **pocket** (click loose needles to pick them up), so keep some back from the bin.

## Meadow Farm (playable now)

| Quest | Steps | Reward |
|---|---|---|
| First Haul (Hank) | Lift a bale, sell a whole bale, break one open, pick up the needle that spills | $150 |
| Get a Grip | Wear Work Gloves or better, break 5 bales | $200 |
| Wheels | Buy a truck, sell 9 bales | $500 |
| Put Down Roots | Buy a plot, build a sorter, sell 10 sorted needles | $1,000 |
| The Wandering Scarecrow | Find him 5 times; he moves every 4 minutes between 6 fields | **Golden Shovel** (2x scoop) |
| The Tailor's Journal | Find 3 pages (near the pond, the north woods, west of the dealer), read them at the Old Barn | **Thread Rake** (pulls nearby loose needles into your pocket) |
| Old Bessie (Hank) | Barn key in the Old Barn, look under the tarp, bring a carburetor, radiator and seat spring, pay $2,500 | **Old Bessie** (pickup, top speed 52 vs 46) |

## Rituals (the mystery items)

| Ritual | What to do | Unlocks |
|---|---|---|
| The Scarecrow's Bargain | Find the Old Scarecrow's stone ring (north-west, past the dealer), set a bale on each of the 4 stones at dusk, give him 5 steel needles | **Scarecrow Gloves** (tier 2) and **Master Needle shard: Meadow** |
| The Midnight Needle | Drop 10 steel needles down the old well (north-east) at midnight | **Lucky Thimble** (30% chance a broken bale spills an extra needle) |
| The Signal | At night: find the crop circle (far north-east), touch the 3 signal stones | $2,000 |
| The Golden Hay Bale | Claim it in the crop circle at midnight (it only appears then) | **Golden Hay Bale** |
| Beacon Parts | Break bales until 3 glowing beacon parts pop out (1 in 120 per bale, guaranteed by 250) | **Star Beacon** |
| The Pattern | At midnight, lay bales on exactly tonight's pads in the crop circle (the sign post shows today's 3x3 sign) | $5,000 |
| The Offering | Offer 100 sorted needles of every type you can reach (only steel until more regions open) | **Starbeam Collector** (100% sorter, free to build), **Starweave Gloves** (tier 6), **Starlight Hauler** |

## Regions still being built

These wait until the "Full world map build" thread tags a part `QuestAnchor` with `SpotId` (and `Region`) for each
place. Until then their quest shows "Opens when ... is built".

| Quest | Region | Reward |
|---|---|---|
| The Frozen Door | Snow Peak | Frostbite Mitts (tier 3), shard |
| Eruption | Volcano | Magma Grips (tier 4), shard |
| Graveyard of Ships, The Captain's Log | Bobbin Rock | Kraken Gauntlets (tier 5), shard, Captain's Barge |
| The Buried Garage | Desert Dunes | Sandrunner (top speed 58), shard |
| Lanterns in the Fog | Haunted Grove | Ghost Hauler (night only, glows), shard |

The signal stones and Old Bessie's parts stand by the roads out of Meadow until their regions exist, then move to the
anchors.

Spot ids for anchors: `signal_pine`, `signal_valley`, `signal_grove`, `bessie_carb`, `bessie_radiator`,
`bessie_spring`, `snow_door`, `volcano_crater`, `graveyard_ghost`, `captains_log_1..3`, `pyramid_garage`,
`pyramid_mechanic`, `lantern_1..3`, `haunted_crossroads`.

## Daily bounties

Three a day from a pool of six (sell bales, break bales, pick up needles, sell sorted needles, sell loose hay, rake),
the same three for everyone, new at midnight UTC. Cash only: $150 to $1,200.

## Why the rewards are what they are

- **Early quests pay cash that shortens the next step, never skips it.** First Haul's $150 is about 12 bales of
  walking; Put Down Roots' $1,000 pays for a sorter upgrade, not a plot.
- **Quest gear is a sidegrade or a small edge, never a new tier.** Quest gloves sit a little above the shop pair of the
  same tier. Quest trucks drive a little faster than the cash truck they are built on but carry the same bed.
- **Rituals give the mystery items and the Spindle shards.** Those are for the collection and later chapters, with
  one perk each at most (Lucky Thimble).
- **The alien gauntlet is the one big power reward** (the 100% sorter), and it costs 100 of every reachable needle type,
  so it stays an endgame goal as more regions open.

All numbers are placeholders to tune from playtests. The "Economy and banking" thread owns prices; quest cash
rewards will follow its numbers.
