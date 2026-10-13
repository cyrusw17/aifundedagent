# Quests, rituals and mystery items

Everything here is defined in `src/shared/Config/Quests.luau` and run by `src/server/Services/Quests.luau`.
Press **Q** (or click the quest card under the MAP / SHOP buttons) for the quest log. Progress saves in each save slot.

Quest gear is earned, never sold. No cash or Robux price buys a quest shovel, rake, glove, truck or relic.

## How it works

- Quests start on their own once the quests they need are done. Several run at once.
- The quest card under the menu buttons shows one quest's current step and the time of day. "Track" in the log picks
  which, and GO (or "Show the way" in the log) drops a waypoint on where the step sends you.
- A gold **!** floats over every place one of your quests needs, and only you see your own.
- Time of day matters for rituals. One full day is 20 real minutes. Dusk is 17:30 to 20:00, night 19:30 to 05:30,
  midnight 23:00 to 01:00 (about 1.7 real minutes).
- Offerings take needles from your **pocket** (click loose needles to pick them up), so keep some back from the bin.

## Meadow Farm (playable now)

| Quest | Steps | Reward |
|---|---|---|
| First Haul (Hank) | Lift a bale, sell a whole bale, break one open, pick up the needle that spills | $150 |
| Get a Grip | Wear Work Gloves or better, break 5 bales | $250 (pays back the Work Gloves) |
| Wheels | Buy a truck, sell 9 bales | $600 |
| Put Down Roots | Buy a plot, build a sorter, sell 10 sorted needles | $1,250 (half the plot) |
| The Wandering Scarecrow | Find him 5 times; he moves every 4 minutes between 6 fields | **Golden Shovel** (2x scoop) |
| The Tailor's Journal | Find 3 pages (near the pond, the north woods, west of the dealer), read them at the Old Barn | **Thread Rake** (pulls nearby loose needles into your pocket) |
| Old Bessie (Hank) | Barn key in the Old Barn, look under the tarp, bring a carburetor (Pine Mill), radiator (desert oasis camp) and seat spring (Snow Peak lodge), pay $2,500 | **Old Bessie** (pickup, top speed 52 vs 46) |

## Rituals (the mystery items)

| Ritual | What to do | Unlocks |
|---|---|---|
| The Scarecrow's Bargain | Find the Old Scarecrow's stone ring (north-west, past the dealer), set a bale on each of the 4 stones at dusk, give him 5 steel needles | **Scarecrow Gloves** (tier 2) and **Master Needle shard: Meadow** |
| The Midnight Needle | Drop 10 steel needles down the old well (north-east) at midnight | **Lucky Thimble** (30% chance a broken bale spills an extra needle) |
| The Signal | At night: find the crop circle (far north-east), then touch the 3 signal stones in Pine Forest, Homestead Valley and Haunted Grove | $5,000 |
| The Golden Hay Bale | Claim it in the crop circle at midnight (it only appears then) | **Golden Hay Bale** |
| Beacon Parts | Break bales until 3 glowing beacon parts pop out (1 in 120 per bale, guaranteed by 250) | **Star Beacon** |
| The Pattern | At midnight, lay bales on exactly tonight's pads in the crop circle (the sign post shows today's 3x3 sign) | $15,000 |
| The Corn Night Maze | After The Signal: at night, find the 3 glowing corn keys in the maze east of the plots, bring them to its heart | **Corn Moon Charm** (needed for The Offering) |
| The Offering | Offer 50 needles of every kind that grows in the world (the log lists them) | **Alien Collector** (100% sorter while its daily beam is up) and **Starbeam Collector** (beams down Star hay), both free to build; **Starweave Gloves** (tier 6); **Starlight Hauler** |

## Region quests (Stitched Isles)

Their places stand on the world map (`world` in `Config/Quests.luau` Spots), so they open as soon as the isles load.
A part tagged `QuestAnchor` with `SpotId` still moves a spot onto it, for hand placement in Studio.

| Quest | Where | Reward |
|---|---|---|
| The Frozen Door | Find a Frozen Bobbin in Snow Peak's frozen hay, open the stitched door high on the ridge | Frostbite Mitts (tier 3), shard |
| Eruption | Volcano crater rim at night, then break 20 bales of ashen hay | Magma Grips (tier 4), shard |
| Graveyard of Ships, The Captain's Log | The captain's ghost on Bobbin Rock at night, then 3 log pages on the rock | Kraken Gauntlets (tier 5), shard, Captain's Barge |
| The Buried Garage | The Buried Pyramid's door, 15 bales of desert grass, the mechanic at the oasis camp | Sandrunner (top speed 58), shard |
| Lanterns in the Fog | The 3 lanterns on the Haunted Grove road at night, then the crossroads at midnight | Ghost Hauler (night only, glows), shard |

## Daily bounties

Three a day from a pool of six (sell bales, break bales, pick up needles, sell sorted needles, sell loose hay, rake),
the same three for everyone, new at midnight UTC. Cash only: $150 to $1,200.

## Why the rewards are what they are

- **Early quests pay back part of what they asked you to buy, never all of it.** Prices come from
  `Config/Prices.luau` (a Meadow bale is about $47; hand hauling earns about $6,500 an hour). First Haul's $150 is
  three bales, Get a Grip refunds the $250 Work Gloves, Wheels pays a tenth of the pickup, Put Down Roots half the plot.
  Quest cash goes through `Bank.earn`, so running loans take their usual share.
- **Quest gear is a sidegrade or a small edge, never a new tier.** Quest gloves sit a little above the shop pair of the
  same tier. Quest trucks drive a little faster than the cash truck they are built on but carry the same bed.
- **Rituals give the mystery items and the Spindle shards.** Those are for the collection and later chapters, with
  one perk each at most (Lucky Thimble).
- **The alien gauntlet is the one big power reward** (the 100% sorter and the Star hay beacon), and it costs 50 of every needle kind in the world,
  so it stays an endgame goal (about 450 needles across nine kinds).

All numbers are placeholders to tune from playtests. Prices live in `Config/Prices.luau`; quest cash rewards follow
its numbers.
