--!strict
-- Trucks sold at the dealer (docs/ITEMS.md). Only the first one can be bought for now; the rest are on the lot
-- with a COMING SOON tag. Prices are placeholders.
export type Truck = {
	id: string,
	name: string,
	price: number,
	blurb: string,
	available: boolean,
	style: string, -- body shape for the part-built model: pickup, flatbed, box, hauler, semi
	paint: string, -- key in Rustic.luau
	length: number,
	maxSpeed: number, -- studs per second
	meshTurn: number?,
}

local Trucks: { Truck } = {
	{
		id = "rusty_pickup",
		name = "Rusty Pickup",
		price = 6000,
		blurb = "Your first truck. Pulls the Wagon Trailer.",
		available = true,
		style = "pickup",
		paint = "PaintRed",
		length = 19.1, -- bed holds 2 x 2 bales lengthwise (BUILD_REGISTRY.md), same as the Blender mesh
		meshTurn = 0, -- degrees; set to 180 if the imported mesh faces backwards
		maxSpeed = 46,
	},
	{
		id = "farm_flatbed",
		name = "Farm Flatbed",
		price = 25000,
		blurb = "Pulls up to a Small trailer.",
		available = false,
		style = "flatbed",
		paint = "PaintGreen",
		length = 16,
		maxSpeed = 48,
	},
	{
		id = "box_truck",
		name = "Box Truck",
		price = 90000,
		blurb = "Pulls up to a Medium trailer.",
		available = false,
		style = "box",
		paint = "PaintCream",
		length = 17,
		maxSpeed = 44,
	},
	{
		id = "heavy_hauler",
		name = "Heavy Hauler",
		price = 350000,
		blurb = "Pulls up to a Large trailer. Needs fuel.",
		available = false,
		style = "hauler",
		paint = "PaintYellow",
		length = 18,
		maxSpeed = 42,
	},
	{
		id = "semi_rig",
		name = "Semi Rig",
		price = 1500000,
		blurb = "Pulls the Double trailer on highways.",
		available = false,
		style = "semi",
		paint = "PaintBlue",
		length = 16,
		maxSpeed = 50,
	},
}

return Trucks
