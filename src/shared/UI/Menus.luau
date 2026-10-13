--!nonstrict
-- Keeps one full-screen menu (map, shop) open at a time and lets client scripts talk to each other.
-- Client only.
--   Menus.register("Map", function(open) panel.Visible = open end)
--   Menus.toggle("Map")    Menus.event("Help"):Fire()
local Menus = {}

local panels = {} -- name -> setOpen(bool)
local current = nil
local events = {}
Menus.changed = Instance.new("BindableEvent") -- (name or nil)

function Menus.register(name, setOpen)
	panels[name] = setOpen
	setOpen(false)
end

function Menus.open(name)
	if current == name then
		return
	end
	if current and panels[current] then
		panels[current](false)
	end
	current = panels[name] and name or nil
	if current then
		panels[current](true)
	end
	Menus.changed:Fire(current)
end

function Menus.close()
	if current and panels[current] then
		panels[current](false)
	end
	current = nil
	Menus.changed:Fire(nil)
end

function Menus.toggle(name)
	if current == name then
		Menus.close()
	else
		Menus.open(name)
	end
end

function Menus.current()
	return current
end

-- A shared BindableEvent by name, made on first use.
function Menus.event(name)
	local e = events[name]
	if not e then
		e = Instance.new("BindableEvent")
		events[name] = e
	end
	return e
end

return Menus
