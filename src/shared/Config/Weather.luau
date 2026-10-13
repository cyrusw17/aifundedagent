--!strict
-- Weather by region: what can blow through each one and how it looks. Weather is visual plus a little grip on the
-- road (a wet or snowy truck speeds up and brakes slower); it never touches prices, needles or hay.
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

-- Each region's weather and how often it comes (weights). Regions not listed stay clear.
Weather.Regions = {
	meadow = { clear = 6, rain = 2, mist = 1 },
	shore = { clear = 5, rain = 2, mist = 2 },
	valley = { clear = 5, rain = 2, mist = 2 },
	homestead = { clear = 6, rain = 2 },
	spindle = { clear = 4, rain = 2, mist = 2 },
	pine = { clear = 4, rain = 3, mist = 2 },
	haunted = { fog = 5, mist = 2, rain = 1 },
	snow = { snow = 5, clear = 3, mist = 1 },
	volcano = { ash = 4, clear = 3 },
	desert = { clear = 5, dust = 3 },
	swamp = { fog = 4, mist = 3, rain = 2 },
	keys = { clear = 6, rain = 1, mist = 1 },
	bobbin = { clear = 5, mist = 2, rain = 1 },
	sky = { clear = 5, mist = 2 },
	cave = { clear = 1 },
} :: { [string]: { [string]: number } }

Weather.SpellMinutes = { 4, 8 } -- each region's weather lasts this long (real minutes) before it rolls again

return Weather
