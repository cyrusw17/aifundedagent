--!strict
-- The Rustic Blender props (blender/exports/rustic/*.glb). Import them into Studio once (see SETUP.md) and the game
-- swaps its part-built bale and tools for the meshes. Any prop that is missing falls back to the old parts.
return {
	-- Where the imported models live. Rojo leaves ServerStorage alone, so they survive syncs.
	Folder = "RusticProps",

	-- Every prop by its .glb file name. A model named after the file (hay_bale) or the Blender object (HayBale)
	-- both count, and only props listed here are looked for. The number is the prop's longest side in studs,
	-- measured from the .glb (0.28 m per stud), so it comes out the right size whatever unit Studio imported it in.
	-- Callers that stretch a prop over a part-built body pass their own size instead.
	Sizes = {
		-- Hay, tools and small props
		hay_bale = 4.6,
		round_bale = 3.7,
		basic_shovel = 2.7,
		wide_scoop = 2.8,
		garden_rake = 5.0,
		pitchfork = 5.3,
		steel_fork = 5.2,
		hay_hook = 1.3,
		hand_sieve = 5.9,
		silver_sieve_net = 3.7,
		magnet_wand = 3.9,
		needle_tweezers = 2.3,
		needle_tray = 3.0,
		sorter_boost_oil = 1.6,
		barrel_auger = 4.6,
		hay_vacuum_hose = 3.8,
		wheelbarrow = 5.5,
		hay_crate = 3.2,
		log = 5.1,
		fence_post_set = 12.6,
		road_tile = 6.0,
		-- Gloves: one right glove each, fingers +Y, back of hand -Z (GloveLooks.luau fits them to the hand)
		work_gloves = 1.9,
		leather_gloves = 1.9,
		reinforced_gloves = 1.9,
		iron_gauntlets = 1.9, -- not exported yet; falls back to the placeholder on the stand
		starlight_gloves = 1.9,
		-- Vehicles and trailers
		rusty_pickup = 27.5, -- the first truck (Vehicles.luau stretches it over the part-built truck)
		farm_flatbed = 24.4,
		box_truck = 29.4,
		semi_rig = 25.3,
		heavy_hauler = 36.0,
		starlight_hauler = 25.3,
		small_trailer = 15.8,
		medium_trailer = 30.3,
		large_trailer = 35.2,
		double_trailer = 39.0,
		bale_rack_trailer = 30.8,
		wagon_trailer = 11.6,
		pull_wagon = 11.3,
		two_wheel_handcart = 9.3,
		rowboat = 12.6,
		sailboat = 15.3,
		cargo_barge = 38.0,
		-- Conveyors and machines
		conveyor_straight = 6.2,
		conveyor_corner = 6.1,
		conveyor_ramp = 8.1,
		conveyor_sorter = 12.0,
		merger = 6.0,
		splitter = 6.2,
		needle_type_splitter = 8.5,
		optical_sorter = 12.0,
		magnet_drum = 11.8,
		shaker_table = 9.0,
		hopper_feeder = 10.6,
		hay_baler = 18.6,
		hay_press = 12.1,
		needle_bundler = 6.4,
		needle_polisher = 5.4,
		alloy_mixer = 10.5,
		alien_collector = 12.4,
		-- Buildings and storage
		bale_rack = 18.3,
		barn = 41.9,
		garage = 43.7,
		greenhouse = 28.3,
		harbor_dock = 52.0,
		mill = 37.9,
		mill_bin_large = 15.3,
		mill_bin_medium = 9.3,
		mill_bin_small = 4.6,
		museum = 34.0,
		needle_forge = 32.6,
		needle_vault = 7.1,
		observatory = 24.5,
		sell_depot = 27.9,
		silo_large = 36.5,
		silo_mega = 58.0,
		silo_small = 21.2,
		sorter_shed = 25.1,
		warehouse = 50.0,
		workshop = 24.4,
	},

	-- Held tools: how far below the hand the end of the handle sits.
	GripFromEnd = 0.6,
}
