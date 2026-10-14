--!strict
-- Every sound in the game, in one place. These start as Roblox's built-in sounds (rbxasset://) so they work with
-- nothing to upload. To use a Creator Store sound instead, paste its id as "rbxassetid://123456" over the id.
-- volume is 0..1 and pitch is a playback speed (1 = as recorded). distance is how far away it can be heard.
--
-- Picking real sounds (Studio > Toolbox > Audio, filter to Roblox-made sounds so they are free to use in any game;
-- right-click a result > Copy Asset ID). Good searches for each:
--   BaleLift      "hay rustle" or "cloth lift"            BaleSetDown   "heavy thud" or "sack drop"
--   BaleBurst     "hay bale break" or "straw rustle"      Scoop         "shovel dig dirt"
--   Rake          "rake leaves" or "rake gravel"          NeedleDing    "small bell ding" or "metal ping"
--   CashRegister  "cash register"                         TruckEngine   "truck engine idle loop" (must loop cleanly)
--   TruckHorn     "truck horn" or "old car horn"
-- A sound that fails to load stays silent; the game keeps running. An empty id ("") is silent on purpose: Cyrus
-- hated the electronic ping placeholder (2026-10-14), so the ding, the till and the horn wait for real Toolbox ids.
return {
	BaleLift = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5, pitch = 0.7, distance = 50 },
	BaleSetDown = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, pitch = 0.6, distance = 60 },
	BaleBurst = { id = "rbxasset://sounds/splat.wav", volume = 0.8, pitch = 0.55, distance = 80 },
	Scoop = { id = "rbxasset://sounds/swoosh.wav", volume = 0.45, pitch = 1.3, distance = 40 },
	Rake = { id = "rbxasset://sounds/swoosh.wav", volume = 0.35, pitch = 0.9, distance = 40 },
	-- The ding plays higher for rarer needles: pitch rises by NeedlePitchPerTenfold each time the value is 10x.
	NeedleDing = { id = "", volume = 0.6, pitch = 1.0, distance = 60 },
	NeedlePitchPerTenfold = 0.45,
	NeedleBaseValue = 100, -- a needle worth this much dings at the base pitch
	-- Played to the seller only, on every sale.
	CashRegister = { id = "", volume = 0.5, pitch = 1.6 },
	-- Loops while someone sits in a truck's driver seat. Pitch climbs with speed from idle to full.
	-- Placeholder: Roblox ships no engine sound, so this is a whoosh slowed right down into a low rumble. Swap in a
	-- "truck engine idle loop" id from the Toolbox and set the pitches back near 0.8 to 1.3.
	TruckEngine = { id = "rbxasset://sounds/Rocket whoosh 01.wav", volume = 0.3, distance = 90 },
	EngineIdlePitch = 0.16,
	EngineTopPitch = 0.42,
	EngineTopSpeed = 60, -- studs per second where the engine reaches its top pitch
	-- X while driving (Vehicles.luau plays it on the truck so everyone near hears it). Silent until a "truck horn" id
	-- goes here.
	TruckHorn = { id = "", volume = 0.8, pitch = 0.32, distance = 140 },

	-- Region ambience (RegionAmbience.client.luau): two quiet loops under everything, mixed per region as you walk or
	-- drive in. Placeholders from the default character sounds (the falling-wind and the swimming-water loops);
	-- swap in "wind ambience loop" and "waves loop" / "rain loop" ids from the Toolbox.
	AmbientWind = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.14, pitch = 0.45 },
	AmbientWater = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.1, pitch = 0.55 },
	-- Per region: wind and water as a share of their volume, and the wind's pitch (low = a hollow moan).
	-- Rain anywhere adds water (the weather's patter).
	RegionAmbience = {
		meadow = { wind = 0.35, water = 0, windPitch = 0.45 },
		shore = { wind = 0.4, water = 0.8, windPitch = 0.45 },
		valley = { wind = 0.3, water = 0.35, windPitch = 0.45 },
		ridge = { wind = 0.55, water = 0.05, windPitch = 0.6 },
		homestead = { wind = 0.25, water = 0, windPitch = 0.45 },
		spindle = { wind = 0.7, water = 0, windPitch = 0.4 },
		pine = { wind = 0.55, water = 0, windPitch = 0.4 },
		haunted = { wind = 0.6, water = 0.2, windPitch = 0.3 },
		snow = { wind = 1, water = 0, windPitch = 0.5 },
		volcano = { wind = 0.7, water = 0, windPitch = 0.32 },
		desert = { wind = 0.8, water = 0, windPitch = 0.55 },
		swamp = { wind = 0.2, water = 0.7, windPitch = 0.35 },
		keys = { wind = 0.45, water = 1, windPitch = 0.5 },
		bobbin = { wind = 0.8, water = 0.7, windPitch = 0.4 },
		sky = { wind = 1, water = 0, windPitch = 0.6 },
		cave = { wind = 0.4, water = 0.15, windPitch = 0.22 },
	},
}
