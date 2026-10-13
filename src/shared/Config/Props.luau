--!strict
-- The Rustic Blender props (blender/exports/rustic/*.glb). Import them into Studio once (see SETUP.md) and the game
-- swaps its part-built bale and tools for the meshes. Any prop that is missing falls back to the old parts.
return {
	-- Where the imported models live. Rojo leaves ServerStorage alone, so they survive syncs.
	Folder = "RusticProps",

	-- Every prop by its .glb file name. A model named after the file (hay_bale) or the Blender object (HayBale)
	-- both count. The number is the prop's longest side in studs, so it comes out the right size whatever unit
	-- Studio imported it in.
	Sizes = {
		hay_bale = 4,
		round_bale = 3.7,
		basic_shovel = 2.8,
		wide_scoop = 2.9,
		garden_rake = 5,
		pitchfork = 5.3,
		hay_hook = 1.3,
		wheelbarrow = 5.6,
		hay_crate = 3.3,
		log = 5.1,
		rusty_pickup = 16, -- the first truck (Vehicles.luau stretches it over the part-built truck)
	},

	-- Held tools: how far below the hand the end of the handle sits.
	GripFromEnd = 0.6,
}
