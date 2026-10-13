--!strict
-- Hollow-blueprint block data. Cost = ceil(fillUnits * per-unit cost of the material).
local Blocks = {}

Blocks.Shapes = {
	{ id = "cube", units = 8 }, { id = "slab", units = 4 }, { id = "quarter_slab", units = 2 },
	{ id = "stair", units = 6 }, { id = "corner_stair", units = 5 }, { id = "ramp", units = 4 },
	{ id = "thin_wall", units = 4 }, { id = "pillar", units = 8 }, { id = "arch", units = 10 },
	{ id = "window_frame", units = 6 }, { id = "door_frame", units = 8 }, { id = "roof_tile", units = 3 },
	{ id = "roof_ridge", units = 2 }, { id = "fence_post", units = 1 }, { id = "fence_rail", units = 1 },
	{ id = "floor_tile", units = 2 }, { id = "round_column", units = 12 }, { id = "dome_piece", units = 14 },
	{ id = "beam", units = 3 }, { id = "platform", units = 6 },
}

Blocks.Materials = {
	thatch = { per = 2, input = "hay" },
	straw_bale = { per = 0.25, input = "bale" },
	steel = { per = 1, input = "steel" },
	pine = { per = 1, input = "pine" },
	sand = { per = 1, input = "sand" },
	ice = { per = 2, input = "ice" },
	mossy_stone = { per = 2, input = "bog" },
	obsidian = { per = 3, input = "obsidian" },
	crystal = { per = 4, input = "geode" },
	cloud = { per = 4, input = "cloud" },
	phantom = { per = 6, input = "phantom" },
	cosmic = { per = 10, input = "cosmic" },
}

function Blocks.fillCost(units: number, materialId: string): number
	local material = Blocks.Materials[materialId]
	assert(material, "unknown material " .. materialId)
	return math.max(1, math.ceil(units * material.per - 1e-9))
end

return Blocks
