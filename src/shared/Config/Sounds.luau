--!strict
-- Every sound in the game, in one place. These start as Roblox's built-in sounds (rbxasset://) so they work with
-- nothing to upload. To use a Creator Store sound instead, paste its id as "rbxassetid://123456" over the id.
-- volume is 0..1 and pitch is a playback speed (1 = as recorded). distance is how far away it can be heard.
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
	TruckEngine = { id = "rbxasset://sounds/Rocket whoosh 01.wav", volume = 0.45, distance = 90 },
	EngineIdlePitch = 0.35,
	EngineTopPitch = 0.9,
	EngineTopSpeed = 60, -- studs per second where the engine reaches its top pitch
}
