--!nonstrict
-- Every piece of text floating in the world or painted on a board goes through here, so it all reads the same.
--
-- Floating labels (BillboardGui) are sized in studs, not pixels, so they shrink with distance like the thing they
-- label instead of staying a big fixed block on screen. Up close the text stops growing at a set pixel size, and
-- past MaxDistance it hides. White Gotham with a dark stroke (STYLE.md "UI and text").
--
--   local label = WorldLabel.billboard(part, "HAY SHOP", { kind = "sign", offset = Vector3.new(0, 6, 0) })
--   label.Text = "NEEDLE BIN\n4 needles" -- the label resizes itself when the text changes
--
-- Kinds: "sign" for buildings and places, "status" for machines, plots and counters, "tag" for people and pads.
--
-- Board text (SurfaceGui) is laid out in pixels per stud, so a long word shrinks to fit the board and a short one
-- stays a sensible size instead of filling it edge to edge.
--
--   WorldLabel.surface(board, "GARAGE", { Enum.NormalId.Front })
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("Theme"))

local WorldLabel = {}

WorldLabel.Kinds = {
	-- studs: height of one line in the world. maxPx: the most a line grows on screen. distance: hidden past this.
	sign = { studs = 1.5, maxPx = 26, distance = 110, font = Theme.Fonts.Title },
	status = { studs = 1.0, maxPx = 18, distance = 55, font = Theme.Fonts.Bold },
	tag = { studs = 0.8, maxPx = 16, distance = 35, font = Theme.Fonts.Bold },
}

local CHAR_WIDTH = 0.62 -- Gotham bold capitals, as a share of the line height
local LINE_GAP = 1.2

local function measure(text)
	local lines, longest = 0, 0
	for line in string.gmatch((text or "") .. "\n", "(.-)\n") do
		lines += 1
		longest = math.max(longest, utf8.len(line) or #line)
	end
	return math.max(lines, 1), math.max(longest, 1)
end

local function fitBillboard(gui, label, spec)
	local lines, longest = measure(label.Text)
	local h = spec.studs
	gui.Size = UDim2.new(longest * h * CHAR_WIDTH + h, 0, lines * h * LINE_GAP, 0)
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MaxTextSize = spec.maxPx
	end
end

-- A floating label above adornee (a BasePart or Attachment). Returns the TextLabel; set .Text to change it.
-- opts: offset (Vector3, studs above the part), kind ("sign" | "status" | "tag"), distance (override), color,
-- studs (line height override for far landmarks).
function WorldLabel.billboard(adornee, text, opts)
	opts = opts or {}
	local base = WorldLabel.Kinds[opts.kind or "status"] or WorldLabel.Kinds.status
	-- studs overrides the line height, for a landmark meant to be read from far away (a volcano, not a shop).
	local spec = { studs = opts.studs or base.studs, maxPx = base.maxPx, distance = base.distance, font = base.font }

	local gui = Instance.new("BillboardGui")
	gui.Name = "WorldLabel"
	gui.StudsOffset = opts.offset or Vector3.new(0, 4, 0)
	gui.MaxDistance = opts.distance or spec.distance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = spec.font
	label.TextScaled = true
	label.TextWrapped = false
	label.TextColor3 = opts.color or Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Theme.Colors.Ink
	label.TextStrokeTransparency = 0.15
	label.Text = text or ""
	label.Parent = gui
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = spec.maxPx
	constraint.MinTextSize = 1
	constraint.Parent = label

	fitBillboard(gui, label, spec)
	label:GetPropertyChangedSignal("Text"):Connect(function()
		fitBillboard(gui, label, spec)
	end)

	gui.Adornee = adornee
	gui.Parent = adornee
	return label
end

-- Text painted on a board. faces defaults to the front. opts: color (ink by default), maxStuds (tallest a line of
-- text may be, default 1.4), padding (share of the board kept clear around the text, default 0.08).
-- Returns the TextLabels, one per face.
function WorldLabel.surface(part, text, faces, opts)
	opts = opts or {}
	local labels = {}
	local lines = measure(text)
	local maxStuds = opts.maxStuds or 1.4
	local ppsStuds = 50
	for _, face in faces or { Enum.NormalId.Front } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "BoardText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = ppsStuds
		gui.LightInfluence = 1
		gui.Parent = part

		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = opts.font or Theme.Fonts.Title
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = opts.color or Theme.Colors.Ink
		label.Text = text or ""
		label.Parent = gui
		local pad = Instance.new("UIPadding")
		local share = UDim.new(opts.padding or 0.08, 0)
		pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = share, share, share, share
		pad.Parent = label
		local constraint = Instance.new("UITextSizeConstraint")
		-- One line is never taller than maxStuds, and lines share the board's height.
		local tall = math.min(maxStuds, part.Size.Y * 0.84 / (lines * 1.15))
		if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
			tall = math.min(maxStuds, part.Size.Z * 0.84 / (lines * 1.15))
		end
		constraint.MaxTextSize = math.max(8, math.floor(tall * ppsStuds))
		constraint.Parent = label
		table.insert(labels, label)
	end
	return labels
end

return WorldLabel
