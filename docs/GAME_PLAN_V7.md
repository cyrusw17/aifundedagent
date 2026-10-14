# Needlewood V7: Mazes, alien gauntlet, blueprint building, item list

Full item list: docs/ITEMS.md (generated from design/items.json by design/build_items.py): 220 items across 19 types plus 240 block types (20 shapes x 12 materials) = 460.

## Mazes (playable in the concept board)
- Straw Labyrinth: 11x11, no fog, daily, about 2 min. Teaches the idea. Rewards a foreign object; once a Maze Lantern.
- The Drowned Rows (sea maze): 21x21 reed channels, mist radius 6, found with four Sea Chart pieces, about 15 min first time. One-time Golden Hay Bale, Thread Ball, Captain's Tricorn.
- Corn Night Maze: 41x41, opens only at night, vision radius 3, three Cornhusk Keys, three scarecrow shrines (checkpoints), dawn returns you to last shrine and keys are kept, crows peck your lantern out. Expected 3-6 nights of 10-15 min. Gate for the alien collector. Rewards: Pattern Scroll, Corn King Crown, Moon Sickle (secret).
- Rules: no paid skips, Hint Scrolls are cryptic only, progress always saves.

## Alien collector gauntlet (extremely hard, soulbound, once per day)
1. Signal: one night in five a crop circle glows in the Lonely Acres cornfield.
2. Corn Night Maze: three keys, reach the Landing Pad.
3. Drowned Rows: claim the one-time Golden Hay Bale.
4. Three beacon parts (Glowing Button from Sky Island, Bent Key from Desert, Silver Coin from Haunted Grove), each about 1 in 2,000 scoops.
5. Pattern: today's ritual shape is shown only on the Pattern Scroll at the maze center; lay hay bales in that shape on your plot at midnight.
6. Offering: 100 sorted needles of each of the 10 types plus the Golden Hay Bale. Reward: Starbeam Collector.
Expected first clear for a dedicated player: about two weeks.

## Blueprint building (hollow templates, like LT2 blueprints)
Place a block and it appears as a hollow template. Pour matching needles (or hay) in to fill it solid. Cost = ceil(fill units x per-unit cost). Per-unit costs: Thatch 2 hay, Straw bale 0.25 bale, Steel 1, Pine 1, Sand 1, Ice 2, Bog (mossy stone) 2, Obsidian 3, Crystal 4, Cloud 4, Phantom 6, Cosmic 10. Shape fill units range from 1 (fence post) to 14 (dome piece); cube is 8.

## Open questions
Can partially filled templates be walked through or damaged by others (private plots, so probably no)? Should templates auto-pull from your storage, or must you carry items? Is the maze night cycle shared per server or per player?
