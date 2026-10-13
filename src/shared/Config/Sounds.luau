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
-- A sound that fails to load stays silent; the game keeps running.
return {
	BaleLift = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5, pitch = 0.7, distance = 50 },
	BaleSetDown = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, pitch = 0.6, distance = 60 },
	BaleBurst = { id = "rbxasset://sounds/splat.wav", volume = 0.8, pitch = 0.55, distance = 80 },
	Scoop = { id = "rbxasset://sounds/swoosh.wav", volume = 0.45, pitch = 1.3, distance = 40 },
	Rake = { id = "rbxasset://sounds/swoosh.wav", volume = 0.35, pitch = 0.9, distance = 40 },
	-- The ding plays higher for rarer needles: pitch rises by NeedlePitchPerTenfold each time the value is 10x.
	NeedleDing = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1.0, distance = 60 },
	NeedlePitchPerTenfold = 0.45,
	NeedleBaseValue = 100, -- a needle worth this much dings at the base pitch
	-- Played to the seller only, on every sale.
	CashRegister = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.6 },
	-- Loops while someone sits in a truck's driver seat. Pitch climbs with speed from idle to full.
	-- Placeholder: Roblox ships no engine sound, so this is a whoosh slowed right down into a low rumble. Swap in a
	-- "truck engine idle loop" id from the Toolbox and set the pitches back near 0.8 to 1.3.
	TruckEngine = { id = "rbxasset://sounds/Rocket whoosh 01.wav", volume = 0.3, distance = 90 },
	EngineIdlePitch = 0.16,
	EngineTopPitch = 0.42,
	EngineTopSpeed = 60, -- studs per second where the engine reaches its top pitch
	-- Q while driving (Vehicles.luau plays it on the truck so everyone near hears it). Placeholder: a ping pitched
	-- right down; swap in a "truck horn" id.
	TruckHorn = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, pitch = 0.32, distance = 140 },
}
