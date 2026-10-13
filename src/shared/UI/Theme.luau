--!strict
-- The one look for every screen and every piece of floating text: Rustic colors (STYLE.md) and one font family.
-- Change a color or a size here and every panel, button and world label follows.
local Theme = {}

Theme.Colors = {
	Ink = Color3.fromRGB(40, 34, 28), -- text on paper, outlines
	InkSoft = Color3.fromRGB(92, 80, 64), -- secondary text on paper
	Paper = Color3.fromRGB(214, 202, 172), -- panel background (weathered cream)
	Card = Color3.fromRGB(230, 220, 194), -- cards inside a panel
	CardDim = Color3.fromRGB(196, 184, 156),
	Wood = Color3.fromRGB(92, 74, 54), -- HUD plates and title bars
	WoodLight = Color3.fromRGB(128, 105, 77),
	Hay = Color3.fromRGB(189, 168, 112),
	Cream = Color3.fromRGB(240, 232, 212), -- text on wood
	Green = Color3.fromRGB(87, 107, 71), -- go, buy, owned
	Red = Color3.fromRGB(133, 61, 48), -- stop, errors
	Blue = Color3.fromRGB(82, 100, 118),
	Muted = Color3.fromRGB(150, 140, 120), -- disabled
	Picked = Color3.fromRGB(176, 146, 82), -- the selected tab or piece
	Cash = Color3.fromRGB(196, 222, 150),
	Shade = Color3.new(0, 0, 0),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
}

-- Text sizes in pixels for screen UI.
Theme.Text = {
	Title = 20,
	Heading = 16,
	Body = 14,
	Small = 12,
	Button = 14,
}

Theme.Radius = 8
Theme.Stroke = 2
Theme.Pad = 12

return Theme
