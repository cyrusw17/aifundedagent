--!strict
-- Foreign objects: odd things that turn up when a bale bursts. Each broken bale rolls for one find (rarest first),
-- skipped for sorted bales. Click a find to keep it; it goes in your collection (saved with the slot) and the first
-- of each kind pays a finder's reward. oneIn is the chance per broken bale. prop names the Rustic Blender model
-- once there is one; until then the find is a simple part of size, color and material. Rewards live in Config/Prices.
local Prices = require(script.Parent.Prices)

return {
	DespawnSeconds = 300, -- an unclaimed find fades after this long
	PickupReach = 12,
	Items = {
		{
			id = "boot",
			name = "Old boot",
			oneIn = 50,
			reward = Prices.FinderRewards.boot,
			prop = "old_boot",
			size = { 0.9, 1.1, 1.6 },
			color = { 92, 74, 54 },
			material = "Leather",
		},
		{
			id = "horseshoe",
			name = "Horseshoe",
			oneIn = 150,
			reward = Prices.FinderRewards.horseshoe,
			prop = "horseshoe",
			size = { 1.1, 0.15, 1.1 },
			color = { 107, 94, 84 },
			material = "Metal",
		},
		{
			id = "key",
			name = "Rusty key",
			oneIn = 300,
			reward = Prices.FinderRewards.key,
			prop = "rusty_key",
			size = { 0.25, 0.08, 0.8 },
			color = { 140, 96, 62 },
			material = "Metal",
		},
		{
			id = "radio",
			name = "Old radio",
			oneIn = 600,
			reward = Prices.FinderRewards.radio,
			prop = "old_radio",
			size = { 1.4, 1, 0.7 },
			color = { 128, 105, 77 },
			material = "Wood",
		},
		{
			id = "ring",
			name = "Lost ring",
			oneIn = 1000,
			reward = Prices.FinderRewards.ring,
			prop = "lost_ring",
			size = { 0.4, 0.4, 0.1 },
			color = { 212, 175, 85 },
			material = "Metal",
		},
		{
			id = "fossil",
			name = "Fossil",
			oneIn = 2000,
			reward = Prices.FinderRewards.fossil,
			prop = "fossil",
			size = { 1.2, 0.3, 1 },
			color = { 196, 186, 166 },
			material = "Slate",
		},
	},
}
