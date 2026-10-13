--!strict
-- Weather by region: what can blow through each one and how it looks. Weather is visual plus a little grip on the
-- road (a wet or snowy truck speeds up and brakes slower). Rain also soaks bales left out under the open sky
-- (Bales.luau, Config/Game WetWeather): heavier and cheaper hay until it dries. It never touches needles.
-- The server (Services/Weather.luau) rolls each region's weather every few minutes and the client
-- (Weather.client.luau) draws the one you stand in.
--
-- Kinds:
--   tint / density   the haze it brings (added to the day's own haze, see DayNightSky.client)
--   grip             truck acceleration and braking, 1 = dry
--   fall             particles around the camera: color, size, speed (studs/s down), drift (sideways), rate
--   cloud            0..1 how much the sky clouds over
export type Kind = {
	name: string,
	tint: Color3,
	density: number,
	grip: number,
	cloud: number,
	fall: { color: Color3, size: number, speed: number, drift: number, rate: number, streak: boolean }?,
}

local rgb = Color3.fromRGB

local Weather = {}

Weather.Kinds = {
	clear = { name = "Clear", tint = rgb(200, 210, 220), density = 0, grip = 1, cloud = 0.25 },
	rain = {
		name = "Rain",
		tint = rgb(130, 140, 150),
		density = 0.12,
		grip = 0.8,
		cloud = 0.85,
		fall = { color = rgb(190, 205, 220), size = 0.12, speed = 90, drift = 4, rate = 400, streak = true },
	},
	snow = {
		name = "Snow",
		tint = rgb(225, 232, 240),
		density = 0.2,
		grip = 0.7,
		cloud = 0.8,
		fall = { color = rgb(250, 250, 255), size = 0.35, speed = 9, drift = 5, rate = 260, streak = false },
	},
	dust = {
		name = "Dust",
		tint = rgb(214, 172, 118),
		density = 0.22,
		grip = 0.9,
		cloud = 0.3,
		fall = { color = rgb(210, 170, 120), size = 0.5, speed = 2, drift = 30, rate = 160, streak = false },
	},
	fog = { name = "Fog", tint = rgb(150, 160, 140), density = 0.32, grip = 0.95, cloud = 0.7 },
	ash = {
		name = "Ash",
		tint = rgb(110, 90, 80),
		density = 0.2,
		grip = 0.9,
		cloud = 0.9,
		fall = { color = rgb(90, 84, 80), size = 0.3, speed = 6, drift = 6, rate = 180, streak = false },
	},
	mist = { name = "Mist", tint = rgb(205, 215, 225), density = 0.14, grip = 1, cloud = 0.5 },
} :: { [string]: Kind }

-- Each region's everyday weather and how often it comes (weights): the haze and mist that give it its mood. Regions
-- not listed stay clear. Rain, snow and dust come as fronts (below), one at a time.
Weather.Regions = {
	meadow = { clear = 6, mist = 1 },
	shore = { clear = 5, mist = 2 },
	valley = { clear = 5, mist = 2 },
	homestead = { clear = 6, mist = 1 },
	spindle = { clear = 4, mist = 2 },
	pine = { clear = 4, mist = 2 },
	haunted = { fog = 5, mist = 2 },
	snow = { clear = 3, mist = 1 },
	volcano = { ash = 4, clear = 3 },
	desert = { clear = 6 },
	swamp = { fog = 4, mist = 3 },
	keys = { clear = 6, mist = 1 },
	bobbin = { clear = 5, mist = 2 },
	sky = { clear = 5, mist = 2 },
	cave = { clear = 1 },
} :: { [string]: { [string]: number } }

Weather.SpellMinutes = { 4, 8 } -- each region's everyday weather lasts this long (real minutes) before it rolls again

-- Fronts (map #25): the weather that matters. Only one front is on the map at a time. The sky over its region
-- clouds over for FrontWarnSeconds first and the server announces it, so players can get loose hay under a roof
-- (rain soaks bales left out, Bales.luau and Config/Game WetWeather). Region events (RegionEvents.luau) that bring
-- their own weather count as the front while they run.
export type Front = { region: string, kind: string, weight: number, text: string }
Weather.Fronts = {
	{ region = "meadow", kind = "rain", weight = 3, text = "Clouds are building over Meadow Farm: rain in a minute. Get loose hay under a roof." },
	{ region = "swamp", kind = "rain", weight = 3, text = "Rain is coming to the Swamp in a minute. Cover any hay you have out there." },
	{ region = "snow", kind = "snow", weight = 2, text = "Snow is coming to Snow Peak in a minute. Roads get slippery." },
	{ region = "desert", kind = "dust", weight = 2, text = "A dust storm is blowing into the Desert Dunes in a minute." },
} :: { Front }
Weather.FrontWarnSeconds = 60
Weather.FrontMinutes = { 3, 5 } -- how long a front lasts once it arrives
Weather.FrontGapMinutes = { 4, 9 } -- clear spell between fronts

-- Thunderstorm (Addiction push H7): about once an hour the whole server gets a storm for a few minutes. It is
-- announced StormWarnSeconds ahead, darkens every sky with lightning, and multiplies the needle mutation odds by
-- StormMutationOdds while it lasts (Weather.needleOdds, read by Needle's roll). It doesn't rain on hay by itself.
Weather.StormEveryMinutes = { 50, 70 } -- gap from one storm's end to the next storm's warning
Weather.StormMinutes = 3
Weather.StormWarnSeconds = 60
Weather.StormMutationOdds = 5
Weather.StormText = "A thunderstorm is rolling in! In 60 seconds, mutated needles are 5x as likely for 3 minutes."
Weather.StormStartText = "Thunderstorm! Mutated needles are 5x as likely for 3 minutes."
-- Weather kinds that make a needle found out in them roll the "Wet" mutation (Weather.needleOdds).
Weather.WetKinds = { rain = true }

return Weather
