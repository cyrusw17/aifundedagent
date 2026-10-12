import json
I=[]
def add(c,rows):
    for r in rows:
        n,t,s,p,d=r
        I.append({"n":n,"c":c,"t":t,"s":s,"p":p,"d":d})

add("Hand tools",[
 ("Basic Shovel","Starter","Spawn","Free","Scoops 1 unit of hay at a time."),
 ("Wide Scoop","Common","Hub shop","$150","Scoops 2 units."),
 ("Garden Rake","Common","Hub shop","$400","Pulls loose hay in a wide arc, light on the arms."),
 ("Pitchfork","Uncommon","Hub shop","$1,200","Scoops 4 units, can lift small bales."),
 ("Steel Fork","Rare","Hub shop","$4,000","Scoops 6 units and strips more hay per swing."),
 ("Hay Hook","Uncommon","Hub shop","$900","Drags bales across the ground to a trailer."),
 ("Needle Tweezers","Common","Hub shop","$600","Pick needles out of a raw load by hand (slow)."),
 ("Silver Sieve Net","Uncommon","Hub shop","$2,500","Handheld sifter. Raises hand-sort recovery."),
 ("Magnet Wand","Rare","Hub shop","$3,500","Pulls steel needles from a load when waved over it."),
 ("Barrel Auger","Epic","Hub shop","$9,000","Drills a barrel's contents straight into a trailer."),
 ("Hay Vacuum Hose","Legendary","Hub shop","$30,000","Sucks hay from a barrel into your truck's tank."),
])
add("Carriers",[
 ("Wheelbarrow","Starter","Spawn","Free","Carries 6 scoops. Pushed on foot."),
 ("Two-Wheel Handcart","Common","Hub shop","$800","Carries 14 scoops. Pulled by hand."),
 ("Pull Wagon","Uncommon","Hub shop","$2,500","Carries 30 scoops. Slow on slopes."),
])
add("Trucks",[
 ("Rusty Pickup","Common","Hub dealer","$6,000","First truck. Pulls the Wagon Trailer."),
 ("Farm Flatbed","Uncommon","Hub dealer","$25,000","Pulls up to a Small trailer."),
 ("Box Truck","Rare","Hub dealer","$90,000","Pulls up to a Medium trailer."),
 ("Heavy Hauler","Epic","Hub dealer","$350,000","Pulls up to a Large trailer. Needs fuel."),
 ("Semi Rig","Legendary","Hub dealer","$1,500,000","Pulls the Double trailer on highways."),
 ("Starlight Hauler","Mythic","Alien quest","Quest","Cosmetic truck that glows. Same stats as Semi Rig."),
])
add("Boats",[
 ("Rowboat","Common","Harbor","$3,000","Calm water only. Fits the Drowned Rows entrance."),
 ("Sailboat","Rare","Harbor","$40,000","Open sea. Required for the far channels."),
 ("Cargo Barge","Epic","Harbor","$250,000","Carries a full trailer across water."),
])
add("Trailers",[
 ("Wagon Trailer","Common","Hub dealer","$2,000","3 barrels of hay."),
 ("Small Trailer","Uncommon","Hub dealer","$12,000","8 barrels."),
 ("Medium Trailer","Rare","Hub dealer","$60,000","20 barrels."),
 ("Large Trailer","Epic","Hub dealer","$240,000","45 barrels."),
 ("Double Trailer","Legendary","Hub dealer","$1,000,000","90 barrels in two linked beds."),
 ("Barrel Rack Trailer","Rare","Hub dealer","$75,000","Carries 30 whole barrels for refilling at base."),
])
add("Storage",[
 ("Hay Crate","Common","Workshop","$100","Holds 20 units of hay."),
 ("Mill Bin (Small)","Starter","Starts with Mill","Free","Holds 200 units."),
 ("Mill Bin (Medium)","Common","Mill upgrade","$1,500","Holds 800 units."),
 ("Mill Bin (Large)","Uncommon","Mill upgrade","$8,000","Holds 3,000 units."),
 ("Silo (Small)","Uncommon","Workshop","$12,000","Holds 8,000 units."),
 ("Silo (Large)","Rare","Workshop","$60,000","Holds 30,000 units."),
 ("Silo (Mega)","Epic","Workshop","$300,000","Holds 150,000 units."),
 ("Warehouse","Epic","Workshop","$500,000","Stores crates, barrels and needle trays."),
 ("Barrel Rack","Common","Workshop","$600","Stores 10 full barrels."),
 ("Needle Tray","Common","Workshop","$250","Holds 100 sorted needles of one type."),
 ("Needle Vault","Epic","Workshop","$150,000","Holds 10,000 needles of any type."),
])
add("Buildings",[
 ("Mill","Starter","Plot purchase","Included","Stores hay and feeds the sorter. Your first building."),
 ("Sorter Shed","Common","Workshop","$5,000","Housing for sorter machines."),
 ("Barn","Common","Workshop","$3,000","Cosmetic and extra crate storage."),
 ("Garage","Uncommon","Workshop","$20,000","Stores your truck and trailers safely."),
 ("Sell Depot","Rare","Workshop","$80,000","Private shop that pays better for sorted needles."),
 ("Needle Forge","Rare","Workshop","$40,000","Turns needles into building materials."),
 ("Workshop","Starter","Plot purchase","Included","Where you place blueprints and craft."),
 ("Museum","Epic","Workshop","$200,000","Displays foreign objects and artifacts for passive cash."),
 ("Observatory","Legendary","Workshop","$900,000","Shows the sky pattern for the alien ritual clue."),
 ("Greenhouse","Uncommon","Workshop","$18,000","Grows a small patch of hay for starter barrels."),
 ("Harbor Dock","Rare","Workshop","$50,000","Parks your boats at your plot."),
])
add("Plots",[
 ("Small Plot","Starter","Hub land office","$500","First plot. Fits a mill and a few machines."),
 ("Farm Plot","Common","Hub land office","$12,000","Four times the space."),
 ("Estate Plot","Rare","Hub land office","$150,000","Room for a full factory line and a house."),
 ("Ranch Plot","Epic","Hub land office","$1,200,000","Huge. Fits a private road loop."),
 ("Fence Post Set","Common","Workshop","$80","Marks your plot edge."),
 ("Road Tile","Common","Workshop","$10","Driveway and internal roads."),
])
add("Machines",[
 ("Hand Sieve","Starter","Mill","$300","Sorter tier 1. Recovers about 15% of needles."),
 ("Shaker Table","Common","Sorter Shed","$3,000","Tier 2. About 35% recovery."),
 ("Hopper Feeder","Common","Sorter Shed","$1,200","Feeds hay from a bin to a belt."),
 ("Conveyor (Straight)","Common","Sorter Shed","$50","Moves loads along a line."),
 ("Conveyor (Corner)","Common","Sorter Shed","$60","Turns a belt 90 degrees."),
 ("Conveyor (Ramp)","Common","Sorter Shed","$80","Lifts a belt up one level."),
 ("Splitter","Uncommon","Sorter Shed","$400","Divides a belt into two."),
 ("Merger","Uncommon","Sorter Shed","$400","Joins two belts into one."),
 ("Conveyor Sorter","Uncommon","Sorter Shed","$15,000","Tier 3. About 55% recovery."),
 ("Magnet Drum","Rare","Sorter Shed","$80,000","Tier 4. About 75% recovery. Pulls steel and bog."),
 ("Optical Sorter","Epic","Sorter Shed","$400,000","Tier 5. About 92% recovery. Finds glass and ice."),
 ("Needle Type Splitter","Rare","Sorter Shed","$25,000","Sends each needle type to its own bin."),
 ("Needle Bundler","Uncommon","Sorter Shed","$6,000","Packs needles into 10, 50 and 250 bundles."),
 ("Needle Polisher","Rare","Sorter Shed","$60,000","Chance to reveal a mutation on a sorted needle."),
 ("Hay Baler","Uncommon","Sorter Shed","$9,000","Makes hay bales for building and the ritual."),
 ("Hay Press","Rare","Sorter Shed","$45,000","Presses dense blocks for thatch building."),
 ("Alloy Mixer","Epic","Needle Forge","$120,000","Combines two needle types into a hybrid material."),
 ("Sorter Boost Oil","Uncommon","Consumable","$500","Runs a machine at double speed for ten minutes."),
 ("Alien Collector","Mythic","Alien quest","Quest","Tier 6. Pulls every needle from one haystack instantly."),
])
add("Hay types",[
 ("Meadow Hay","Common","Meadow barrels","","The basic hay. Few needles."),
 ("Pine Straw","Common","Pine Forest barrels","","Pine needles are hidden inside."),
 ("Dune Hay","Uncommon","Desert barrels","","Dry grass full of sand needles."),
 ("Frost Hay","Uncommon","Snow Peak barrels","","Frozen stalks with ice needles."),
 ("Bog Reed","Uncommon","Swamp barrels","","Wet reed with bog needles."),
 ("Ember Hay","Rare","Volcano barrels","","Warm hay with obsidian needles."),
 ("Crystal Hay","Rare","Cave barrels","","Glittering hay with geode needles."),
 ("Cloud Hay","Epic","Sky Island barrels","","Weightless hay with cloud needles."),
 ("Ghost Hay","Epic","Haunted Grove barrels","","Pale hay with phantom needles. Night only."),
 ("Golden Hay","Legendary","Drowned Rows maze","","One-time reward. Sorts into higher rarity needles."),
 ("Star Hay","Mythic","Alien Collector rewards","","Appears after the Collector. Cosmic needles."),
])
add("Needles",[
 ("Steel Needle","Common","Meadow","$100 sorted","Base value. Steel plate material."),
 ("Pine Needle","Common","Pine Forest","$110 sorted","Pine plank material."),
 ("Sand Needle","Uncommon","Desert","$140 sorted","Sand brick material."),
 ("Ice Needle","Uncommon","Snow Peak","$160 sorted","Ice glass material."),
 ("Bog Needle","Uncommon","Swamp","$170 sorted","Mossy stone material."),
 ("Obsidian Needle","Rare","Volcano","$300 sorted","Obsidian glass material."),
 ("Geode Needle","Rare","Cave","$340 sorted","Crystal material."),
 ("Cloud Needle","Epic","Sky Island","$700 sorted","Cloud material."),
 ("Phantom Needle","Epic","Haunted Grove","$800 sorted","Phantom material. Semi-see-through."),
 ("Cosmic Needle","Mythic","Star Hay","$5,000 sorted","Cosmic material. Glows."),
])
add("Mutations",[
 ("Giant","Uncommon","Needle Polisher","x2 value","The needle is larger."),
 ("Rainbow","Rare","Needle Polisher","x3 value","Shifting color."),
 ("Glitch","Epic","Needle Polisher","x4 value","Flickers and jumps."),
 ("Cosmic Mutation","Legendary","Needle Polisher","x10 value","Rarest mutation."),
])
add("Special needles",[
 ("Compass Needle","Rare","Found rarely","","Points to the nearest hidden thing."),
 ("Lumberjack Needle","Rare","Found rarely","","Stitches two loads into one so a big trailer fits."),
 ("Magnet Needle","Rare","Found rarely","","Pulls loose items to you."),
 ("Thread Needle","Epic","Found rarely","","Sets a teleport anchor at your plot."),
 ("Ghost Needle","Epic","Haunted Grove, night","","Cosmetic ghost trail."),
 ("Golden Needle","Legendary","Daily server event","","One per server per day."),
 ("Meteorite Needle","Mythic","Meteor shower","","Huge value and a comet trail. Not tradeable."),
])
fo={
 "Meadow":[("Brass Button","Common"),("Bent Nail","Common"),("Old Penny","Uncommon"),("Lost Thimble","Uncommon"),("Clay Marble","Rare"),("Farmer's Pocket Watch","Epic")],
 "Pine Forest":[("Pinecone Charm","Common"),("Resin Bead","Common"),("Hunter's Whistle","Uncommon"),("Rusty Hatchet Head","Uncommon"),("Bird Feather","Rare"),("Fossil Amber","Epic")],
 "Desert":[("Scarab Charm","Common"),("Bronze Key","Uncommon"),("Glass Bead","Common"),("Clay Tablet Shard","Uncommon"),("Camel Bell","Rare"),("Sun Medallion","Epic")],
 "Snow Peak":[("Frozen Toy Soldier","Common"),("Ice Locket","Uncommon"),("Skate Blade","Common"),("Snow Globe","Uncommon"),("Brass Compass","Rare"),("Mammoth Tooth","Epic")],
 "Swamp":[("Lily Seed Pod","Common"),("Frog Statuette","Uncommon"),("Fisher's Hook","Common"),("Lantern Glass","Uncommon"),("Fossil Fern","Rare"),("Swamp Pearl","Epic")],
 "Volcano":[("Meteor Chip","Uncommon"),("Obsidian Arrowhead","Common"),("Cooled Lava Egg","Uncommon"),("Miner's Token","Common"),("Ember Coin","Rare"),("Dragon Scale","Legendary")],
 "Cave":[("Glow Mushroom Cap","Common"),("Crystal Shard","Common"),("Pick Tip","Uncommon"),("Bat Wing Charm","Uncommon"),("Lost Lamp","Rare"),("Geode Heart","Epic")],
 "Sky Island":[("Cloud Pearl","Common"),("Feather Quill","Common"),("Kite Tail","Uncommon"),("Wind Chime Piece","Uncommon"),("Lightning Bottle","Rare"),("Storm Medal","Epic")],
 "Haunted Grove":[("Ghost Button","Common"),("Cracked Mirror","Uncommon"),("Music Box Key","Uncommon"),("Spectral Locket","Rare"),("Moth-Eaten Doll","Rare"),("Cursed Coin","Epic")],
}
for m,rows in fo.items():
    add("Foreign objects",[(n,t,m+" barrels","","Collection book item.") for n,t in rows])

add("Special items",[
 ("Starbeam Collector","Mythic","Alien quest","Quest","Pulls every needle out of one haystack. Once per day. Soulbound."),
 ("Maze Lantern","Rare","Straw Labyrinth reward","Quest","Widens your vision in the dark maze."),
 ("Chalk Line","Uncommon","Hub shop","$800","Draws a permanent line on the maze floor."),
 ("Thread Ball","Epic","Drowned Rows reward","Quest","Leaves a glowing thread trail you can follow back."),
 ("Sea Chart Piece (4)","Rare","Found in sea barrels","","Four pieces reveal the Drowned Rows entrance."),
 ("Cornhusk Key (3)","Epic","Corn Night Maze","","Three keys open the center Landing Pad."),
 ("Beacon Part: Glowing Button","Legendary","Rare drop, Sky Island","","Ritual part one."),
 ("Beacon Part: Bent Key","Legendary","Rare drop, Desert","","Ritual part two."),
 ("Beacon Part: Silver Coin","Legendary","Rare drop, Haunted Grove","","Ritual part three."),
 ("Pattern Scroll","Rare","Corn maze center","","Shows today's ritual shape. Works once."),
 ("Moon Sickle","Epic","Corn Night Maze secret","Quest","Cuts one shortcut through corn once per night."),
 ("Golden Hay Bale","Legendary","Drowned Rows","Quest","One-time bale. Part of the alien offering."),
 ("Weaver's Thimble","Mythic","Spindle summit","Quest","Doubles Golden Needle spawns for an hour a day."),
 ("Thread of Fate","Epic","Sunken Harbor","Quest","Re-roll one needle's rarity per day."),
])
add("Consumables",[
 ("Fuel Can","Common","Hub shop","$40","Refuels a truck or boat."),
 ("Repair Kit","Common","Hub shop","$120","Fixes truck damage."),
 ("Tire Patch","Common","Hub shop","$30","Fixes a flat tire on the road."),
 ("Lucky Clover","Uncommon","Bounty reward","","Fills 25% of your luck meter."),
 ("Combo Hourglass","Uncommon","Bounty reward","","Adds 30 seconds to your combo timer."),
 ("Lantern Oil","Common","Hub shop","$60","Refills the Maze Lantern."),
 ("Hint Scroll","Uncommon","Hub shop","$500","Shows a cryptic clue. No path or skip."),
 ("Barrel Refill Token","Uncommon","Daily bounty","","Refills one barrel. Never sold for Robux."),
])
add("Decor",[
 ("Scarecrow","Common","Workshop","$300","Decoration. Protects from crows in the maze event."),
 ("Weather Vane","Common","Workshop","$500","Decoration."),
 ("Windsock","Common","Workshop","$150","Decoration."),
 ("Garden Gnome","Uncommon","Workshop","$900","Decoration."),
 ("Mailbox","Common","Workshop","$80","Shows your daily mail."),
 ("Wind Chimes","Rare","Needle Forge","8 needles","Made of needles. Rings when you pass."),
 ("Lamp Post","Common","Workshop","$200","Light."),
 ("Banner","Common","Workshop","$120","Show your clan or hat."),
 ("Sign","Common","Workshop","$50","Custom text."),
 ("Door","Common","Workshop","$60","Opens and closes."),
 ("Gate","Common","Workshop","$90","Opens and closes."),
 ("Window Pane","Common","Workshop","$40","Glass. Fits a window frame."),
 ("Needle Statue","Epic","Needle Forge","200 needles","Sculpture made of any needle type."),
 ("Trophy Pedestal","Rare","Workshop","$5,000","Display one trophy."),
 ("Display Wall","Rare","Workshop","$20,000","Shows every needle type you own."),
 ("Fountain","Epic","Workshop","$60,000","Water feature."),
 ("Hay Bale Seat","Common","Workshop","$60","Seat."),
 ("Ritual Circle Mat","Epic","Alien quest","Quest","Marks where the ritual shape is laid out."),
])
add("Hats",[
 ("Straw Boater","Rare","Meadow set","","+5% bag capacity."),
 ("Lumberjack Beanie","Rare","Pine Forest set","","+5% scoop speed."),
 ("Pharaoh Headwrap","Rare","Desert set","","Needle sense range +10%."),
 ("Frost Ushanka","Rare","Snow Peak set","","Cold stamina regeneration."),
 ("Mossy Bog Hat","Rare","Swamp set","","Faint glints on loads."),
 ("Magma Hard-Hat","Rare","Volcano set","","Heat immunity."),
 ("Miner's Lamp Helmet","Rare","Cave set","","Wider light in mazes."),
 ("Cloud Halo","Rare","Sky Island set","","Longer glide."),
 ("Spectral Top Hat","Rare","Haunted Grove set","","See ghost needles at night."),
 ("Crown of Needles","Mythic","Endgame","","Aura and prestige title."),
 ("Corn King Crown","Epic","Corn Night Maze","","Cosmetic. Shows you finished the corn maze."),
 ("Captain's Tricorn","Epic","Drowned Rows","","Cosmetic. Shows you finished the sea maze."),
])
add("Pets",[
 ("Barn Cat","Common","Hub shop","$2,000","Sniffs out nearby needles."),
 ("Farm Dog","Uncommon","Hub shop","$5,000","Follows you and detects glints."),
 ("Crow","Rare","Corn maze event","","Rides on your shoulder. Stops crow attacks."),
 ("Pig","Uncommon","Hub shop","$8,000","Finds extra foreign objects."),
 ("Scarecrow Pal","Epic","Corn Night Maze","","Marks shrines for you."),
 ("Pincushion Heart","Epic","Swamp pond secret","","Sniffs out needles from far away."),
])

SH=[("Cube",8),("Slab",4),("Quarter slab",2),("Stair",6),("Corner stair",5),("Ramp",4),("Thin wall",4),("Pillar",8),("Arch",10),("Window frame",6),("Door frame",8),("Roof tile",3),("Roof ridge",2),("Fence post",1),("Fence rail",1),("Floor tile",2),("Round column",12),("Dome piece",14),("Beam",3),("Platform",6)]
MA=[("Thatch","hay",2,"#d9b84a"),("Straw bale","bale",.25,"#e6cf7a"),("Steel plate","steel needle",1,"#9aa6b2"),("Pine plank","pine needle",1,"#4c8a5a"),("Sand brick","sand needle",1,"#e8c070"),("Ice glass","ice needle",2,"#9fd8f0"),("Mossy stone","bog needle",2,"#7f9a55"),("Obsidian glass","obsidian needle",3,"#4a4a4a"),("Crystal","geode needle",4,"#b8a2f0"),("Cloud","cloud needle",4,"#e6f0fa"),("Phantom","phantom needle",6,"#a99ad0"),("Cosmic","cosmic needle",10,"#6a3fd0")]
data={"items":I,"shapes":[{"n":a,"u":b} for a,b in SH],"mats":[{"n":a,"unit":b,"per":c,"col":d} for a,b,c,d in MA]}
json.dump(data,open("items.json","w"),indent=1)

import math
md=["# Needlewood: full item list (placeholders)\n","Generated from design/items.json by design/build_items.py. All prices are placeholders to tune.\n"]
cats=[]
for it in I:
    if it["c"] not in cats: cats.append(it["c"])
for c in cats:
    md.append(f"\n## {c}\n\n| Item | Tier | Source | Cost | Notes |\n|---|---|---|---|---|")
    for it in I:
        if it["c"]==c: md.append(f"| {it['n']} | {it['t']} | {it['s']} | {it['p']} | {it['d']} |")
md.append("\n## Building blocks (hollow blueprints)\n\nPlace a block and it appears as a hollow template. Pour the matching needles (or hay) in to fill it solid. Cost = fill units x per-unit cost, rounded up.\n")
md.append("Per-unit cost: "+", ".join(f"{m['n']} {m['per']} {m['unit']}" for m in data['mats'])+"\n")
md.append("| Shape | Fill units | "+" | ".join(m['n'] for m in data['mats'])+" |\n|---|---|"+"---|"*len(data['mats']))
for s in data['shapes']:
    md.append(f"| {s['n']} | {s['u']} | "+" | ".join(str(math.ceil(s['u']*m['per'])) for m in data['mats'])+" |")
total=len(I)+len(SH)*len(MA)
md.append(f"\nTotal: {len(I)} items plus {len(SH)*len(MA)} block types ({len(SH)} shapes x {len(MA)} materials) = {total}.\n")
open("../docs/ITEMS.md","w").write("\n".join(md))
print(len(I),len(SH)*len(MA),total,len(cats))
