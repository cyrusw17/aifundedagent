# Needlewood economy: what everything costs, and why

Every price lives in one file, `src/shared/Config/Prices.luau`. The shops, sorters, land office, dealer, glove stand
and bank all read from it. `tools/economy_model.py` re-derives every table in this doc, so when a number changes you
re-run it rather than redo the maths by hand.

The earning rates below are estimates from the code (walk speeds, bale size, sorter speeds) and from guessed travel
distances. They are not playtest data. Each one is written down in the model so it can be checked and changed.

## The short version

- **A Meadow bale is worth $47 raw.** It holds 90 strands of hay at $0.50 ($45), plus 2 hidden needles that the public
  shop pays $1 each for.
- **Sorting is where the money is.** Those 2 needles are worth $100 each once sorted. A hand sieve makes a bale worth
  $75, and an optical sorter makes it $229. Richer regions hide more needles, and pricier ones.
- **Every price is "time at the stage you'd buy it".** Small upgrades cost minutes of work, big ones an hour or two,
  and machines pay themselves back on the V8 schedule.
- **The bank makes the big prices fair.** A used pickup costs $6,000, like a real one. You can't pay cash for it in your
  first 15 minutes, but you can put $1,200 down and let the bank lend the rest.
- **A first playthrough reaches the Semi in about 14 hours** of play (model, one player, buying in a sensible order).

## How prices are set

1. **Earning rate first.** For each stage of the game, the model works out how many bales a player moves per minute
   and what each bale is worth with the sorter they own. That gives dollars per hour at each stage.
2. **Then time to afford.** Gloves cost about 30 minutes of what you earn just before you need them. Trucks cost one to
   two hours, so they are real goals. Build pieces cost a few minutes, so building never stalls.
3. **Then payback.** A machine's price is how long you're willing to wait for it to pay for itself, times the extra
   money it makes. The targets are V8 Part C: hand sieve instant, shaker about 15 minutes, conveyor sorter about 30,
   magnet drum about 75, optical sorter about 3.5 hours.
4. **Then a sense check against real life**, where real life makes sense: a pickup costs about what a used pickup
   costs, a trailer about a quarter to a third of the truck that pulls it, and bigger land costs more per tile.

## The big fix: 2 needles a bale, not 18

Before this change a bale hid about 18 needles (90 strands, each with a 20% chance). A raw bale paid $63, a
hand-sieved one $315, and an optically sorted one about $1,700. The $50,000 optical sorter paid for itself in about 3
minutes and a player could climb the whole ladder in a couple of hours.

Now each hay type has one number, **needles per bale**, from the V8 table (`Prices.NeedlesPerBale`):

| Hay | Meadow | Pine | Desert | Snow | Swamp | Volcano | Cave | Sky | Haunted | Star |
|---|---|---|---|---|---|---|---|---|---|---|
| Needles per bale | 2 | 3 | 4 | 5 | 6 | 8 | 10 | 12 | 14 | 20 |

Richer hay pays twice: more needles, and needles worth more. When you break a bale with the shovel, a quarter of its
needles tumble out where you can see them (about 1 in every 2 bales), and you can pick those up for full price.

The sorters also lost their 20-second cap. Before, the hand sieve, shaker and conveyor sorter all took the same 20
seconds per bale, so upgrading didn't feel faster. Now each tier is twice as fast as the last: 2, 4, 8, 16 and 30 bales
a minute (30, 15, 7.5, 3.75 and 2 seconds a bale).

## What a bale is worth

| Region | Public shop | Hand sieve | Shaker table | Conveyor sorter | Magnet drum | Optical sorter |
|---|---|---|---|---|---|---|
| Meadow | $47 | $75 | $115 | $155 | $195 | $229 |
| Pine Forest | $48 | $94 | $160 | $227 | $292 | $349 |
| Desert | $49 | $129 | $241 | $353 | $465 | $560 |
| Snow Peak | $50 | $165 | $325 | $485 | $645 | $781 |
| Swamp | $51 | $198 | $402 | $606 | $810 | $983 |
| Volcano | $53 | $405 | $885 | $1,365 | $1,845 | $2,253 |
| Cave | $55 | $555 | $1,235 | $1,915 | $2,595 | $3,173 |
| Sky Island | $57 | $1,305 | $2,985 | $4,665 | $6,345 | $7,773 |
| Haunted Grove | $59 | $1,725 | $3,965 | $6,205 | $8,445 | $10,349 |

## What a player earns at each stage

Hand hauling assumes a bale is about 110 studs from the sell pad, carried at the loaded walk speed (7.4 bare, 9.1 with
Work Gloves) and walked back at 16. Trucks assume 9 seconds to load each bale by hand, 50 seconds of other work per trip,
and a round-trip drive from your plot (half a minute in Meadow, 3 to 8 minutes to the other regions).

| Stage | Bales/min hauled | Bales/min sorted | $/hour |
|---|---|---|---|
| 1. Hands, bare | 2.3 | 2.3 | $6,573 |
| 2. Hands, Work Gloves | 2.6 | 2.6 | $7,368 |
| 3. Pickup, public shop | 3.7 | 3.7 | $10,398 |
| 4. Pickup, plot + Hand sieve | 3.7 | 2.0 | $13,758 |
| 5. Pickup, Shaker table | 3.7 | 3.7 | $25,441 |
| 6. Flatbed, Shaker, Pine | 2.2 | 2.2 | $21,647 |
| 7. Flatbed, Conveyor sorter, Desert | 1.9 | 1.9 | $40,591 |
| 8. Box truck, Conveyor sorter, Snow | 3.1 | 3.1 | $90,494 |
| 9. Box truck, Magnet drum, Swamp | 3.1 | 3.1 | $151,134 |
| 10. Hauler, Magnet drum, Volcano | 3.9 | 3.9 | $436,625 |
| 11. Hauler, Optical, Cave | 3.9 | 3.9 | $750,901 |
| 12. Semi, Optical, Sky | 3.0 | 3.0 | $1,396,231 |

One thing this table shows: **loading by hand is the bottleneck.** A pickup only moves about 1.6 times as many bales as
walking, and the bigger trucks barely beat it in Meadow. Trucks earn their price on distance (the far regions), not on
size. V8's field bale chutes (park under one, pull a lever, a bed's worth drops in) would fix this, and are worth
building before the bigger trucks go on sale.

## The price list

### Trucks (Homestead Motors)

| Truck | Price | Why |
|---|---|---|
| Rusty Pickup | $6,000 | About what a real used pickup costs. 50 minutes of hand hauling in cash, or $1,200 down (about 10 minutes) with a truck loan. |
| Farm Flatbed | $25,000 | About an hour at the shaker-table stage, when Pine Forest opens up. |
| Box Truck | $90,000 | About two hours at the conveyor-sorter stage, before Snow Peak. |
| Heavy Hauler | $350,000 | About two hours at the magnet-drum stage, before Volcano. |
| Semi Rig | $1,500,000 | About two hours at the optical stage. The last truck. |

These were already the prices in code, and the model says they sit in the right places, so they stay.

### Trailers

| Trailer | Price | Why |
|---|---|---|
| Wagon Trailer | $1,500 | A quarter of the pickup. Two more bales a trip. |
| Small Trailer | $8,000 | About a third of the flatbed. |
| Medium Trailer | $30,000 | About a third of the box truck. |
| Large Trailer | $120,000 | About a third of the hauler. |
| Bale Rack | $200,000 | Taller walls, so it carries more layers. |

### Gloves (glove stand)

| Gloves | Was | Now | Why |
|---|---|---|---|
| Work Gloves | $250 | $250 | The first thing you buy, about 3 minutes in. |
| Leather Gloves | $1,500 | $8,000 | About 20 minutes at the shaker stage, just before the tier-2 hay of Desert and Snow. |
| Reinforced Gloves | $6,000 | $45,000 | About 30 minutes before Swamp's tier-3 hay. |
| Iron Gauntlets | $25,000 | $75,000 | About 30 minutes before Volcano and Cave. |
| Starlight Gloves | $150,000 | $400,000 | About 30 minutes before Sky Island and Haunted Grove. |

The old glove prices were far below the trucks of the same stage, so gloves would have been bought long before the
hay that needs them.

### Land (Land Office)

Every plot is now the same 12 x 10 tiles (the Land Office thread's change), so there is one price: **$2,500**
(`Prices.Plot`, was $1,500 in that change and $800 to $6,000 before it).

It is the first land goal, at about 45 minutes: roughly 15 minutes of pickup earnings once the pickup and wagon are
paid for. With a hand sieve and a short line ($3,600 in all) it lifts a bale from $47 to $75. A land loan brings it
forward to $500 down. $1,500 would arrive only a few minutes after the pickup, before the player has learned to haul.

**Plot expansion: $5,000 a row** (`Prices.PlotExpansion`, was $1,500 in Land's first version). A plot starts with its
back two rows locked (96 of 120 tiles), and each row adds 12 tiles. 96 tiles is plenty for the first line, so the rows
only matter when you build a second line, around the shaker-table stage, where $5,000 is about 12 minutes of earnings.
At $1,500 it would be a 4-minute afterthought; at $5,000 it is a small goal of its own.

### Building on your land

| Piece | Was | Now | Why |
|---|---|---|---|
| Conveyor belt | $20 | $25 | A few minutes of work buys a whole line. |
| Hay buyer | $150 | $400 | Every line ends in one, and it is where all your farm money comes from. |
| Parking pad | $100 | $250 | |
| Hay silo | $3,000 | $5,000 | Keeps a sorter fed while you are out hauling. About 12 minutes of work at the shaker stage. |

Removing a piece still refunds half its price.

### Needle sorters

Priced from the V8 payback targets, for Meadow hay with the sorter kept full:

| Sorter | Finds | Bales/min | Value/bale | Extra $/hour over the public shop | Was | Now | Payback |
|---|---|---|---|---|---|---|---|
| Hand sieve | 15% | 2 | $75 | $3,360 | $250 | $500 | 9 min |
| Shaker table | 35% | 4 | $115 | $16,320 | $1,500 | $4,000 | 15 min |
| Conveyor sorter | 55% | 8 | $155 | $51,840 | $5,000 | $25,000 | 29 min |
| Magnet drum | 75% | 16 | $195 | $142,080 | $15,000 | $175,000 | 74 min |
| Optical sorter | 92% | 30 | $229 | $327,600 | $50,000 | $1,100,000 | 201 min |

A solo player hauling about 4 bales a minute can't keep a magnet drum or optical sorter full on their own. With a silo
buffer, a crew, or richer hay, the payback gets much faster: an optical sorter on Cave hay pays back in about 12 minutes.

### Selling

| What | Pays | Why |
|---|---|---|
| Hay, any shop | $0.50 a strand | Cyrus's number. It makes a raw bale worth $45 of hay. |
| Needles found by the public shop | $1 each | Cyrus's number. Low on purpose, so owning a sorter is worth it. |
| Sorted needles (SELL NEEDLES pad) | $100 steel up to $5,000 cosmic | Unchanged from the needle table. |
| A needle you spot and pick up yourself | Full sorted value | It's rare (about 1 per 2 bales broken) and it is the first hook that shows what sorting is worth. |

### Finder's rewards (foreign objects in hay)

The first boot, horseshoe, key, radio, ring and fossil you find in a broken bale each pay a one-time reward
(`Prices.FinderRewards`). The rule is about $1 for every bale it takes on average to turn one up, with the two
rarest doubled because they are the finds players talk about: boot $50 (1 in 50 bales), horseshoe $150, key $300,
radio $600, ring $1,500 (1 in 1,000) and fossil $4,000 (1 in 2,000). They are a moment, not an income. All six
together come to $6,600, under an hour of pickup earnings, so they never change what a player can afford.

### The needle market

Each server keeps its own needle prices (`Services/Market.luau`, numbers in `Prices.Market`). Selling a needle type
pushes its price down, and the push fades by half every 10 minutes. A type nobody has sold lately pays up to 20% over
its list price, and a flooded one drops as far as 20% under, never further. The point is the V8 one: flooding steel
nudges players toward regions nobody else is farming, without ever making a needle worthless.

List price is set where a solo shaker-table farm sells steel (about 40 recent sales). Rarer needles sell in smaller
numbers, so they reach list price with fewer sales (a cosmic needle with 5). A board beside the hay shop's sell pad
shows today's price for every type, with an arrow. Every needle sale goes through `Needle.priceOf`, so pads, the
display wall and the ding pitch all follow the market. The earning tables above use list prices, since the swing
averages out.

### NPC buyer orders

A board on the west side of base camp shows three orders from local buyers, with new ones every 20 minutes
(`Services/Orders.luau`, numbers in `Prices.Orders`). Deliver on the pad beside it: set bales on it, or step on it with
needles in your pocket. Each unit pays straight away, up to the order's amount for each player, so nothing is lost
when the orders change.

| Order | Amount | Pays | Why |
|---|---|---|---|
| Hay bales | 8 to 16 | $71 each (1.5x the public shop) | Gives a no-plot player a better buyer than the shop |
| Sorted bales | 10 to 20 | $90 each (2x a hay buyer) | The sorting is already done, so the buyer pays for clean hay |
| Steel needles | 6 to 15 | $125 each (1.25x list) | A small premium; mutated needles stay in your pocket |

A full order is worth a few hundred to a thousand dollars more than selling normally. That is a 5 to 10 minute bonus at
the pickup stage, and a reason to haul somewhere other than your own line. Orders don't change the earning tables,
since they are capped per player.

## The bank: Meadow Savings & Loan

A stone-and-plank bank on the main road, east of the plot road, with a teller window. Press E at the window to open it.

**Wallet and bank.** Every sale pays into your wallet. Buying anything takes from your wallet first, then from your
bank balance, like paying with a debit card, so money in the bank is always spendable. The HUD shows both under your
cash.

**Savings interest.** Every 10 minutes, the bank pays interest on your balance: 1% on the first $10,000 and 0.5% on the
next $90,000, up to $550 a payment. It is only paid if you sold something in those 10 minutes, so it rewards saving
while you work and never pays an idle player. It is tiered upside down from a real bank on purpose: it gives a new farm
a real boost and stays small next to a big farm's income.

**Loans.** Two kinds, each for something you name:

| Loan | Covers | Fee | Repaid from |
|---|---|---|---|
| Truck loan | Trucks and trailers you don't own | 10% | 25% of each sale |
| Land loan | A plot, while you own none | 8% | 20% of each sale |

You need 20% of the price yourself. The bank deposits the other 80%, adds its fee once, and takes its share out of each
sale until the loan is paid. There are no due dates, no missed payments and no penalties, and you can pay the rest off
at the window any time. You can have one of each kind at a time. Worked example: the $6,000 Rusty Pickup with $1,200
down means borrowing $4,800 and paying back $5,280, a quarter of every sale until it's done (about two hours at pickup
earnings).

**Credit limit.** You can owe up to $5,000 plus twice everything this save has ever earned. A brand new farm can finance
the pickup once it has earned its down payment, and big loans come once you have a record of earning.

**History.** The last 40 transactions, with sales from the same place in the same half minute merged into one line.

**Saved per slot.** The wallet, bank balance, loans, lifetime earnings and history are all saved with the save slot.

**Test money.** With `InfiniteMoney` on, shops are free and the HUD shows the test balance as before. The wallet, bank,
loans and history underneath stay real and are saved, so the bank can be tested with real numbers. (Before this change,
anything earned while test money was on was thrown away.)

## A first playthrough

One player, buying in this order and spending everything as it comes in. Financed buys pay the down payment, and the
loan takes its share of sales after that.

| Buy | Price | Time to afford | Total play time | How |
|---|---|---|---|---|
| Work Gloves | $250 | 3 min | 0.1 h |  |
| Rusty Pickup | $6,000 | 10 min | 0.2 h | financed: $1,200 down |
| Wagon Trailer | $1,500 | 12 min | 0.4 h |  |
| Plot + Hand sieve + first line | $3,600 | 28 min | 0.9 h |  |
| Shaker table | $4,000 | 24 min | 1.3 h |  |
| Leather Gloves | $8,000 | 24 min | 1.7 h |  |
| Farm Flatbed | $25,000 | 12 min | 1.9 h | financed: $5,000 down |
| Small Trailer | $8,000 | 30 min | 2.4 h |  |
| Conveyor sorter | $25,000 | 93 min | 3.9 h |  |
| Hay silo | $5,000 | 10 min | 4.1 h |  |
| Box Truck | $90,000 | 41 min | 4.8 h | financed: $18,000 down |
| Reinforced Gloves | $45,000 | 40 min | 5.4 h |  |
| Medium Trailer | $30,000 | 27 min | 5.9 h |  |
| Magnet drum | $175,000 | 152 min | 8.4 h |  |
| Iron Gauntlets | $75,000 | 30 min | 8.9 h |  |
| Heavy Hauler | $350,000 | 28 min | 9.4 h | financed: $70,000 down |
| Large Trailer | $120,000 | 22 min | 9.8 h |  |
| Optical sorter | $1,100,000 | 188 min | 12.9 h |  |
| Starlight Gloves | $400,000 | 32 min | 13.4 h |  |
| Semi Rig | $1,500,000 | 24 min | 13.8 h | financed: $300,000 down |

Most steps land 10 to 40 minutes apart. The three long gaps are the conveyor sorter, magnet drum and optical sorter,
which are the big "save up for it" goals. Quests, bounties and the collection book should fill those gaps.

## Open choices for Cyrus

1. **Pickup price.** V8 proposed $600. With 90-strand bales a player earns about $110 a minute by hand, so $600 would be
   5 minutes. This doc keeps $6,000 and uses the bank so the pickup still arrives at about 15 minutes. One line in
   `Prices.Trucks` changes it.
2. **Length of the climb.** The model reaches the Semi in about 14 hours; V8 aimed for 40 or more. The lever is the late
   regions' needles per bale and needle values. Halving them roughly doubles the back half of the game.
3. **Needles per bale.** These are V8's numbers, which Cyrus hasn't approved yet. Each is one value in
   `Prices.NeedlesPerBale`.

## Where each number lives

| Number | In `Config/Prices.luau` | Read by |
|---|---|---|
| Hay and raw needle price | `HayPrice`, `RawNeedlePrice` | `Economy.luau` |
| Needles per bale, visible share | `NeedlesPerBale`, `VisibleNeedleShare` | `Config/Game` (`NeedleChancePerHay`, `VisibleNeedleChance`) |
| Sorted needle values | `Needles` | `Config/Needles` |
| Trucks, trailers | `Trucks`, `Trailers` | `Config/Trucks`, `Config/Trailers` |
| Gloves | `Gloves` | `Config/Gloves` |
| Plot, expansion rows, pieces, refund | `Plot`, `PlotExpansion`, `Pieces`, `RefundShare` | `Config/Land` |
| Sorter speeds | `SorterBalesPerMinute` | `Config/Sorters` |
| Bank terms | `Bank` | `Services/Bank.luau` |
| Finder's rewards | `FinderRewards` | `Config/Finds` (hay tools thread) |
| NPC orders | `Orders` | `Services/Orders.luau` |
| Needle market swing | `Market` | `Services/Market.luau` (through `Needle.priceOf`) |
| Hand-found needle share | `HandFoundNeedleShare` | Not wired yet: for the hay tools thread's pocket-needle sale at the public pad |
