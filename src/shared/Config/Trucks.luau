--!strict
-- Trucks sold at the dealer (docs/ITEMS.md). The ones not yet available wait on the lot with a COMING SOON tag.
-- Prices come from Config/Prices. Lengths match the Blender meshes (Config/Props.luau).
local Prices = require(script.Parent.Prices)
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
		price = Prices.Trucks.rusty_pickup,
		blurb = "Your first truck. Pulls the Wagon Trailer.",
		available = true,
		style = "pickup",
		paint = "PaintRed",
		length = 26.9, -- bed holds 3 x 3 bales a layer, lying lengthwise (BUILD_REGISTRY.md)
		meshTurn = 0, -- degrees; set to 180 if the imported mesh faces backwards
		maxSpeed = 46,
	},
	{
		id = "farm_flatbed",
		name = "Farm Flatbed",
		price = Prices.Trucks.farm_flatbed,
		blurb = "Wooden stake bed, 9 bales a layer. Pulls up to a Small trailer.",
		available = true,
		style = "flatbed",
		paint = "PaintGreen",
		length = 24.4,
		maxSpeed = 48,
	},
	{
		id = "box_truck",
		name = "Box Truck",
		price = Prices.Trucks.box_truck,
		blurb = "Tall box, 12 bales a layer, two layers. Pulls up to a Medium trailer.",
		available = true,
		style = "box",
		paint = "PaintCream",
		length = 29.4,
		maxSpeed = 44,
	},
	{
		id = "heavy_hauler",
		name = "Heavy Hauler",
		price = Prices.Trucks.heavy_hauler,
		blurb = "Steel tub, 15 bales a layer, two layers. Pulls up to a Large trailer.",
		available = true,
		style = "hauler",
		paint = "PaintYellow",
		length = 36,
		maxSpeed = 42,
	},
	{
		id = "semi_rig",
		name = "Semi Rig",
		price = Prices.Trucks.semi_rig,
		blurb = "Pulls the Double trailer on highways.",
		available = false,
		style = "semi",
		paint = "PaintBlue",
		length = 25.3,
		maxSpeed = 50,
	},
}

return Trucks
