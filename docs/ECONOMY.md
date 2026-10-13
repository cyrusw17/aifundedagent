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
- **A first playthrough reaches the Semi in about 15 hours** of play (model, one player, buying in a sensible order).

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
| 2b. Wheelbarrow, public shop | 4.7 | 4.7 | $13,257 |
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

### Wheelbarrow

**$1,000** (`Prices.Wheelbarrow`; the hay tools thread set $400). It carries 3 bales a push, so by the model it hauls
about 4.7 bales a minute to the sell pad, double what you carry by hand. Doubling your income is a big step, so it
should cost about 10 minutes of hand hauling, not 3. At $1,000 it lands about 12 minutes in, between Work Gloves and
the pickup.

One thing to fix in play, not in price: near camp the wheelbarrow outhauls the Rusty Pickup (4.7 bales a minute against
3.7), because the truck is loaded one bale at a time by hand. The pickup still wins on longer hauls (at 250 studs the
barrow drops to 2.8 a minute), which is every trip to your own plot and every other region. Letting the barrow tip its
3 bales into a truck bed, or V8's field bale chutes, would make the truck the clear upgrade again.

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

**Second farm: $60,000** (`Prices.SecondPlot`, Land's placeholder was $25,000). A save can own one more plot. Three
things set the price. First, hauling is the limit at almost every stage (the stage table sorts exactly what it hauls),
so a second line mostly buys room and a second region's sorter, not double income. Second, it should come after the
first plot is fully built out: plot, both rows and a conveyor sorter cost about $37,500, so a second farm has to cost
more or players would skip the rows. Third, each server has only six plots, so a second farm takes one from a player
who might join later; it should be a real commitment. $60,000 is about 90 minutes at the conveyor-sorter stage and
40 minutes at the box truck, a mid-game goal. $25,000 would arrive before the conveyor sorter and fill servers early.
There is no loan for it: the land loan only covers a first plot.

### Building on your land

| Piece | Was | Now | Why |
|---|---|---|---|
| Conveyor belt | $20 | $25 | A few minutes of work buys a whole line. |
| Hay buyer | $150 | $400 | Every line ends in one, and it is where all your farm money comes from. |
| Parking pad | $100 | $250 | |
| Hay silo | $3,000 | $5,000 | Keeps a sorter fed while you are out hauling. About 12 minutes of work at the shaker stage. |

Removing a piece still refunds half its price.

### Pieces and upgrades added by other threads (reviewed)

These were priced by the threads that built them. I checked each against the stage table and kept them; the reasons
are below so the whole list lives in one place.

| Piece | Price | Why it fits |
|---|---|---|
| Raised belt, ramps | $60, $150 each | Belts that cross a line. A few of them cost a few minutes; they are layout, not income. |
| Splitter, sort splitter | $300, $600 | Layout pieces. The sorting one costs more because it routes sorted bales away from plain ones. |
| Display wall | $1,000 | Shows off needles; no income. A small early sink. |
| Hay baler | $3,000 | Packs loose strands back into bales. A convenience you want early, about 25 minutes by hand. |
| Hay barn | $15,000 | Holds 150 bales to the silo's 60 ($100 a bale of storage against the silo's $83), so a long line can run while you are away. About 20 minutes at the conveyor-sorter stage, the point where lines get long enough to need it. |
| Needle vault | $6,000 | Stores needles with no parts. It also lets you hold a flooded needle type until the market recovers (prices fade back in about 10 minutes), worth at most 20% on what you hold. About 15 minutes at the shaker stage. |
| Hay press | $8,000 | Makes thatch for building, not money, so it is priced like a mid-game toy. |
| Needle polisher (bin upgrade) | $12,000 | +25% on up to 30 needles a minute. At the shaker stage it pays back in about 3 hours, and at the conveyor sorter in about 1.5, so it is a mid-game upgrade like the sorters. |
| Bin dividers (bin upgrade) | $1,500 | Sorts the bin by needle type. Tidiness, so it is cheap. |
| Alloy mixer | $20,000 | Turns needles into building alloy. Its cost is mostly the needles it eats, so the machine itself sits beside the conveyor sorter. |
| Decor: flowers, bench, lantern, scarecrow | $200, $350, $500, $900 | Looks only. Each is a few minutes of early income, so a new farm can look lived in. Later decor should cost more (a fountain or a windmill at $10,000 to $50,000) so rich players still have something to spend on. |
| Sorter oil | $250 a can | 10% faster for 25 bales. It only pays when the sorter holds the line back, so it is a small treat. |

Quest rewards (the five quest gloves, the Alien Collector, the Starbeam Collector) cost $0 because you earn them; they
can't be bought.

### Needle sorters

Priced from the V8 payback targets, for Meadow hay with the sorter kept full:

| Sorter | Finds | Bales/min | Value/bale | Extra $/hour over the public shop | Was | Now | Payback |
|---|---|---|---|---|---|---|---|
| Hand sieve | 15% | 2 | $75 | $3,360 | $250 | $500 | 9 min |
| Shaker table | 35% | 4 | $115 | $16,320 | $1,500 | $4,000 | 15 min |
| Conveyor sorter | 55% | 8 | $155 | $51,840 | $5,000 | $25,000 | 29 min |
| Magnet drum | 75% | 16 | $210 | $156,480 | $15,000 | $190,000 | 73 min |
| Optical sorter | 92% | 30 | $275 | $410,400 | $50,000 | $1,350,000 | 197 min |

The magnet drum grades its needles A (+10%) and the optical sorter grades them S (+25%) (`Prices.NeedleGrades`,
Conveyor's line simulator `tools/line_sim.py`). Grades made both machines pay back about 20% faster than the V8 targets
(67 and 161 minutes), so their prices went up to hold the targets: the magnet drum from $175,000 to $190,000 and the
optical sorter from $1.1M to $1.35M. Repricing beats rewriting the targets because the targets are what keep each
sorter a goal of similar weight at its stage; the grades still make the upgrade feel better per needle.

**Region machines.** Snow and Swamp hay can't be sorted until it goes through a thawing shed or a drying rack, and
Volcano hay sorts at a penalty without an ash sifter (Conveyor's `Services/Treat.luau`). Each is priced to pay back in
about 20 to 25 minutes of a solo haul (3 to 4 bales a minute) at the stage where you reach that region, not with a
full magnet drum, which a solo player can't feed. At the first prices ($10,000, $20,000 and $60,000) they paid back in
4 to 16 minutes at a realistic haul.

| Machine | Region | Your line when you get there | Extra $/hour at ~3.5 bales/min | Was | Now | Payback |
|---|---|---|---|---|---|---|
| Thawing shed | Snow Peak | Box truck, conveyor sorter | about $81,000 | $10,000 | $30,000 | 22 min |
| Drying rack | Swamp | Box truck, magnet drum | about $155,000 | $20,000 | $50,000 | 19 min |
| Ash sifter | Volcano | Heavy hauler, magnet drum | about $232,000 (lifts the penalty only) | $60,000 | $100,000 | 26 min |

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

You pay 20% of the price yourself when you take the loan. The bank then sets the whole price aside for you (your down
payment plus its 80%), adds its fee once, and takes its share out of each sale until the loan is paid. The money it
sets aside is for purchases only: shops spend it first, but it can't be withdrawn, traded at the trading post or used
for anything but buying. If you sell back something the loan paid for, the refund repays the loan before any of it
reaches you, and paying off early returns any loan money you haven't spent first. Without these rules a player could
borrow, cash the loan out to a second account and never sell anything again (the health check found this). There are no due dates, no missed payments and no penalties, and you can pay the rest off
at the window any time. You can have one of each kind at a time. Worked example: the $6,000 Rusty Pickup with $1,200
down means borrowing $4,800 and paying back $5,280, a quarter of every sale until it's done (about two hours at pickup
earnings).

**Credit limit.** You can owe up to $5,000 plus twice everything this save has ever earned. A brand new farm can finance
the pickup once it has earned its down payment, and big loans come once you have a record of earning.

**History.** The last 40 transactions, with sales from the same place in the same half minute merged into one line.

**Saved per slot.** The wallet, bank balance, loans, lifetime earnings and history are all saved with the save slot.

**Test money.** With `InfiniteMoney` on, shops are free and the HUD shows the test balance as before. The wallet, bank,
loans and history underneath stay real and are saved, so the bank can be tested with real numbers. (Before this change,
anything earned while test money was on was thrown away.) Test money is on in Roblox Studio only
(`InfiniteMoney = RunService:IsStudio()` in Config/Game), so a live server never hands out free money: a free purchase
followed by a remove-and-refund would mint real cash there. That is a safe default while Cyrus decides how test money
should work, and easy to reverse: set it back to `true` (everyone, everywhere) or `false` (nobody) in Config/Game.

## Travel fares (for the rest of the map)

The world map thread charges these at boarding (PR #25), per truck (trailers ride free). A fare should be felt but should never
decide whether a trip is worth making, so each is under 5% of what the trip carries.

| Trip | Fare | Why |
|---|---|---|
| Public ferry (to Thimble Keys or Bobbin Rock) | $250 a truck with trailer, each way | Under 5% of a box-truck load of Snow hay |
| Captain's Barge | Free | Earned by quest |
| Zeppelin to Sky Island | $1,000 a trip | Under 5% of a pickup load of Sky hay ($1,300 to $7,800 a bale) |
| Roads, including the Longstitch Highway | Free | Driving is already the cost |

## Robux prices

Recorded in `Prices.Robux` so every price lives in one file. The store waits until the cash economy has been
playtested (backlog rule). These are V8's prices, kept because they sit in the usual range for Roblox tycoons (a
99 R$ impulse buy, 149 to 299 R$ passes, and trucks rising with tier). That range is design judgement, not data.

- **Trucks:** Homestead Classic 399, Timber Wolf 4x4 799, Midnight Express 1,199, Prairie Schooner 1,799 and Founders'
  Semi 2,499 R$. Each one matches the stats of its cash tier exactly. One fix to V8: V8 gives the Timber Wolf "better
  grip on dirt", which would make it stronger than the cash Flatbed. It should look lifted but drive the same.
- **Passes:** VIP 249, Auto-Dock 299, Big Silo 199, Paint Studio 149, Plot Themes 199 and Truck Radio 99 R$. Auto-Dock
  and Big Silo are convenience with a cash match: you can step on UNLOAD yourself, and build a second $5,000 silo.
- **Other:** Harvest Pass premium track 499 R$, a server boost 99 R$, and a private server 100 R$ a month.
- No item gives cash, needles, sorter tiers or quest skips, and nothing is random.

## A first playthrough

One player, buying in this order and spending everything as it comes in. Financed buys pay the down payment, and the
loan takes its share of sales after that.

| Buy | Price | Time to afford | Total play time | How |
|---|---|---|---|---|
| Work Gloves | $250 | 3 min | 0.1 h |  |
| Wheelbarrow | $1,000 | 9 min | 0.2 h |  |
| Rusty Pickup | $6,000 | 6 min | 0.3 h | financed: $1,200 down |
| Wagon Trailer | $1,500 | 12 min | 0.5 h |  |
| Plot + Hand sieve + first line | $3,600 | 28 min | 1.0 h |  |
| Shaker table | $4,000 | 24 min | 1.4 h |  |
| Leather Gloves | $8,000 | 24 min | 1.8 h |  |
| Farm Flatbed | $25,000 | 12 min | 2.0 h | financed: $5,000 down |
| Small Trailer | $8,000 | 30 min | 2.5 h |  |
| Conveyor sorter | $25,000 | 93 min | 4.0 h |  |
| Hay silo | $5,000 | 10 min | 4.2 h |  |
| Box Truck | $90,000 | 41 min | 4.9 h | financed: $18,000 down |
| Reinforced Gloves | $45,000 | 40 min | 5.5 h |  |
| Medium Trailer | $30,000 | 27 min | 6.0 h |  |
| Magnet drum | $190,000 | 162 min | 8.7 h |  |
| Iron Gauntlets | $75,000 | 30 min | 9.2 h |  |
| Heavy Hauler | $350,000 | 28 min | 9.6 h | financed: $70,000 down |
| Large Trailer | $120,000 | 22 min | 10.0 h |  |
| Optical sorter | $1,350,000 | 223 min | 13.7 h |  |
| Starlight Gloves | $400,000 | 32 min | 14.3 h |  |
| Semi Rig | $1,500,000 | 24 min | 14.7 h | financed: $300,000 down |

Most steps land 10 to 40 minutes apart. The three long gaps are the conveyor sorter, magnet drum and optical sorter,
which are the big "save up for it" goals. Quests, bounties and the collection book should fill those gaps.

### Checked against the pacing simulator

Conveyor's `tools/pacing_sim.py` plays a new save second by second on the real Meadow layout and configs (20 seeded
maps). Its medians land 13 to 23% ahead of the table above: Work Gloves at 2 minutes, Wheelbarrow 9, Pickup on a loan
15, Wagon 23, Plot with a sieve and first line 50, Shaker 71, Leather Gloves 92, Flatbed 104, Small trailer 127, and
the conveyor sorter after 3 hours. Ahead is the safe side, so no prices changed. Two gaps were looked at on purpose:

- **Work Gloves at 2 minutes (target was 6).** Kept. The "6 minutes" came from rounding the table to 0.1 h. The first
  purchase should land almost at once: it teaches the shop loop and makes the next bale feel lighter right away.
  Raising it to $500 to reach 6 minutes would push every later step back for no gain.
- **The plot at 50 minutes (CEO target 35 to 45).** Kept at $2,500. The simulator buys the plot with cash and doesn't
  model bale toss or field chutes, both of which speed up truck loading, so the real game lands nearer 43 minutes. A
  player who takes the land loan ($500 down, allowed alongside the truck loan) gets there in about 35. Cutting the plot
  to $2,000 would gain about 3 minutes and make the first land feel cheap next to a $1,500 wagon.

Re-run `python3 tools/pacing_sim.py` after any change to an early price.

## Open choices for Cyrus

1. **Pickup price.** V8 proposed $600. With 90-strand bales a player earns about $110 a minute by hand, so $600 would be
   5 minutes. This doc keeps $6,000 and uses the bank so the pickup still arrives at about 15 minutes. One line in
   `Prices.Trucks` changes it.
2. **Length of the climb.** The model reaches the Semi in about 15 hours; V8 aimed for 40 or more. The lever is the late
   regions' needles per bale and needle values. Halving them roughly doubles the back half of the game.
3. **Needles per bale.** These are V8's numbers, which Cyrus hasn't approved yet. Each is one value in
   `Prices.NeedlesPerBale`.

## Region events

Map's region events (`Prices.RegionEvents`) run one at a time, every 30 minutes, for 5 minutes. They drop extra bales
of the region's hay with more needles in them (`boost`), and never pay cash directly. An event should be worth a detour
for whoever reaches it first, about 5 to 10 minutes of income at the stage where that region opens, and it shouldn't
beat a steady haul over an hour. A raw event bale is worth hay plus needles × boost × sorted value:

| Event | Hay | Bales | Boost | Worth sorted | Extra over normal bales | Stage income | Minutes of income |
|---|---|---|---|---|---|---|---|
| Hay Fever (Shore) | Meadow | 10 | 1.5x | $3,450 | $1,000 | $25k/h (shaker) | 8 |
| Low Tide (Swamp) | Swamp | 10 | 1.5x | $15,750 | $5,100 | $151k/h | 6 |
| Meteor Shower (Valley, nights) | Meadow | 8 | 3x | $5,160 | $3,200 | $25k/h | 12 |
| Windfall (Pine) | Pine | 12 | 1.5x | $6,480 | $1,980 | $22k/h | 18 |
| Sandstorm (Desert) | Desert | 10 | 2x | $11,650 | $5,600 | $41k/h | 17 |
| Avalanche (Snow) | Snow | 10 | 2x | $16,450 | $8,000 | $90k/h | 11 |
| Eruption (Volcano) | Volcano | 10 | 2.5x | $60,450 | $36,000 | $437k/h | 8 |

Two changes from Map's first numbers. The Meteor Shower went from 6 bales at 2.5x to 8 at 3x, because it only happens
at night and was the weakest event in the game. The Eruption went from 8 bales to 10, because the Volcano is the
hardest region to reach and 8 bales was under 7 minutes of income there. The rest stay as Map set them.

## Thimble Keys and Bobbin Rock

Map's two ferry islands get their own hay and needles, so a ferry trip is worth its fare:

| Hay | Region | Glove tier | Weight | Needles/bale | Needle | Sorted value | Bale sorted |
|---|---|---|---|---|---|---|---|
| Bog reed | Swamp | 3 | 2.4 | 6 | Bog | $170 | $1,065 |
| **Sea grass** | **Thimble Keys** | 3 | 2.2 | 6 | **Coral** | **$220** | **$1,365** |
| Ashen hay | Volcano | 4 | 3.0 | 8 | Obsidian | $300 | $2,445 |
| **Thread grass** | **Bobbin Rock** | 4 | 3.2 | 9 | **Brass** | **$320** | **$2,925** |
| Crystal hay | Cave | 4 | 3.4 | 10 | Geode | $340 | $3,445 |

Sea grass beats Swamp's bog reed by about 28% a bale and is lighter. That's the ferry's reward: the $250 fare each way
is under 2% of a box-truck load, but the crossing takes time, so the island has to pay a little better than the
mainland beside it. Bobbin Rock fits between Volcano and Cave on value and weight, as an island alternative to the
crater.

## Region secrets

Map's four one-time secrets (`Prices.Secrets`) pay once per save slot through `Bank.earn`. Map's first numbers were
$2,000 to $3,000, which is under 30 seconds of income in those regions, so finding one felt like nothing. The rule now:
a secret is worth the trip on its own. For a player who walks there early it's about the price of the next mid-game
buy, and for one who arrives on schedule it's a few minutes of income. Secrets behind a gate pay more.

| Secret | Where | What gates it | Reward |
|---|---|---|---|
| Ember Cache | Volcano crater | Tier 4 gloves ($75,000 Iron Gauntlets) | $40,000 |
| Lost Kite | Under Sky Island's rim | $1,000 zeppelin fare | $25,000 |
| Geode Heart | Crystal Cave far wall | Reaching the cave | $20,000 |
| Captain's Lantern | Ghost Isle | Night only; walkable early | $15,000 |

## Wet hay

The Hay thread's rain soaks a bale left in the open for 20 seconds: it weighs 1.5x and its hay sells at 60%
(`Prices.WetHayShare`) until it dries, 150 seconds after the rain stops or at once on a drying rack. Needles are
untouched, so the loss is only on the hay:

| Bale | Dry, sorted | Wet, sorted | Loss |
|---|---|---|---|
| Meadow | $245 | $227 | 7% |
| Swamp | $1,065 | $1,047 | 2% |
| Sold raw at the public shop (Meadow) | $47 | $29 | 38% |

That's the right size. It hurts most at the very start, when hay is all you sell, which teaches parking under cover
early; later it's a nudge, and waiting out the rain costs nothing. It doesn't change the drying rack's price: at the
Swamp stage, rescuing $18 a bale is under 2% of the bale, while the rack's real value is letting Bog reed be sorted
at all.

## Golden bales

The Hay thread's golden field bales (`Prices.GoldenBale`) are 1 field bale in 150, glinting, announced, with 3x the
needles. On average that adds (3 − 1) / 150 = 1.3% to needle income, which is too small to change any stage's
earnings or the timeline, so the odds and the multiplier stay as built. What matters is the moment:

| Hay | Plain bale, sorted | Golden bale, sorted | Golden bale sold raw at the public shop |
|---|---|---|---|
| Meadow (2 needles) | $245 | $645 | $51 |
| Desert (4) | $605 | $1,725 | $57 |
| Volcano (8) | $2,445 | $7,245 | $69 |

A golden bale only pays off if you sort it or break it by hand (hand-found needles pay full value), never if you sell
it raw. That's the right lesson for a new player: the first golden bale shows them what sorting is worth. On a rich
field the two boosts stack (2x × 3x = 6x), which is still a single bale.

## The trading post

Land's trading post settles every trade through `Bank.settleTrade(a, b, terms)`. It takes the cash each side offers,
charges each side a fee, and writes a line to both histories ("Trade with Sam: gave 3 Cosmic needles, got $2,000").
The fee (`Prices.Trade`) is $25 plus 5% of the cash, paid only by a side that hands over cash. A side that only
gives items pays nothing, so swaps and gifts are free and a brand-new player can always hand a friend a needle.
Cash-for-needles deals pay something like the market's spread, and big cash transfers between accounts carry a real
cost. Cash moves wallet to wallet (taking from
the bank if the wallet is short) and doesn't count as earnings, so it takes no loan share and adds no credit. If either
side can't pay, nothing moves and the post cancels the trade. Trading is free while InfiniteMoney is on.

## Where each number lives

| Number | In `Config/Prices.luau` | Read by |
|---|---|---|
| Hay and raw needle price | `HayPrice`, `RawNeedlePrice` | `Economy.luau` |
| Needles per bale, visible share | `NeedlesPerBale`, `VisibleNeedleShare` | `Config/Game` (`NeedleChancePerHay`, `VisibleNeedleChance`) |
| Sorted needle values | `Needles` | `Config/Needles` |
| Wheelbarrow | `Wheelbarrow` | `Services/Wheelbarrow.luau` (hay tools thread) |
| Trucks, trailers | `Trucks`, `Trailers` | `Config/Trucks`, `Config/Trailers` |
| Gloves | `Gloves` | `Config/Gloves` |
| Trade fee | `Trade` | `Services/Bank` (settleTrade) |
| Region events | `RegionEvents` | `Services/RegionEvents` |
| Region secrets | `Secrets` | `Services/Wilds` |
| Wet hay | `WetHayShare` | `Config/Game` (WetPriceFactor) |
| Golden bales | `GoldenBale` | `Config/Game` → `Services/Bales` |
| Plot, expansion rows, second farm, pieces, decor, refund | `Plot`, `PlotExpansion`, `SecondPlot`, `Pieces`, `RefundShare` | `Config/Land` |
| Sorter speeds | `SorterBalesPerMinute` | `Config/Sorters` |
| Bank terms | `Bank` | `Services/Bank.luau` |
| Finder's rewards | `FinderRewards` | `Config/Finds` (hay tools thread) |
| Travel fares | `Travel` | `Services/Ferry.luau` (world map thread, PR #25) |
| Robux store | `Robux` | Not wired yet (store waits on playtests) |
| NPC orders | `Orders` | `Services/Orders.luau` |
| Needle market swing | `Market` | `Services/Market.luau` (through `Needle.priceOf`) |
| Hand-found needle share | `HandFoundNeedleShare` | Not wired yet: for the hay tools thread's pocket-needle sale at the public pad |
