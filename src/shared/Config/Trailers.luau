--!strict
-- Trailers that hitch behind a truck (Vehicles.luau). Sizes follow the Blender beds in BUILD_REGISTRY.md and
-- blender/props/vehicles.py: the inside of the bed holds `along` x `across` bales a layer, the floor top is 3.5 (the
-- conveyor dock's belt height), and the walls are `wall` tall. Axles are offsets behind the bed's center, so the
-- tongue always carries a little weight. Prices are placeholders.
export type Trailer = {
	id: string,
	name: string,
	price: number,
	along: number, -- bales lengthwise per layer (4.6 each)
	across: number, -- bales across per layer (3.2 each)
	length: number?, -- inside length when it is not along x 4.6 + 0.8
	wall: number,
	wheel: number, -- wheel radius; the wheel top stays under the bed floor
	axles: { number },
	tongue: number, -- from the bed's front to the coupler
	color: string, -- key in Rustic.luau for the sides
}

local Trailers: { Trailer } = {
	{
		id = "wagon_trailer",
		name = "Wagon Trailer",
		price = 1500,
		along = 1,
		across = 2,
		wall = 2.6,
		wheel = 1.4,
		axles = { -1.6, 1.6 },
		tongue = 4.5,
		color = "PaintGreen",
	},
	{
		id = "small_trailer",
		name = "Small Trailer",
		price = 8000,
		along = 2,
		across = 2,
		wall = 2.6,
		wheel = 1.2,
		axles = { 0.8 },
		tongue = 4.0,
		color = "Wood",
	},
	{
		id = "medium_trailer",
		name = "Medium Trailer",
		price = 30000,
		along = 5,
		across = 2,
		length = 24,
		wall = 2.6,
		wheel = 1.4,
		axles = { 4.0, 7.2 },
		tongue = 4.5,
		color = "Wood",
	},
	{
		id = "large_trailer",
		name = "Large Trailer",
		price = 120000,
		along = 6,
		across = 3,
		wall = 5.4,
		wheel = 1.4,
		axles = { 5.0, 8.4, 11.8 },
		tongue = 5.0,
		color = "Wood",
	},
	{
		id = "bale_rack_trailer",
		name = "Bale Rack",
		price = 200000,
		along = 5,
		across = 2,
		wall = 8,
		wheel = 1.4,
		axles = { 4.6, 7.8, 11.0 },
		tongue = 5.0,
		color = "Metal",
	},
}

return Trailers
