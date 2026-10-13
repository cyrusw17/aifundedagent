--!nonstrict
-- The public hay sell shop, for players who don't own land yet. Back a truck up to the dock and step on UNLOAD,
-- or set bales and loose hay on the belt by hand. The belt carries it into the shop's buyer, which pays the hay
-- price but only $1 for each needle hidden in the hay. Players who buy land can build their own line from the
-- same pieces (Conveyors.luau and Machines.luau) with a needle sorter, and get the full needle price.
--
--   dock (truck) -> belt west -> turn south -> HAY SELL SHOP buyer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Factory = require(ReplicatedStorage.Shared.Config.Factory)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Data = require(script.Parent.Data)
local Conveyors = require(script.Parent.Conveyors)
local Machines = require(script.Parent.Machines)
local Dock = require(script.Parent.Dock)

local SellShop = {}

local T = Factory.TileSize
local ORIGIN = Vector3.new(48, 0, -40) -- ground corner of grid cell 0,0

function SellShop.build(worldFolder)
	local folder = Instance.new("Folder")
	folder.Name = "HaySellShop"
	folder.Parent = worldFolder or Workspace

	Machines.part(
		folder,
		"Slab",
		Vector3.new(T * 8, 0.2, T * 5),
		CFrame.new(ORIGIN + Vector3.new(T * 3.5, 0.1, T * 1)),
		Color3.fromRGB(150, 140, 125),
		Enum.Material.Concrete
	)

	local grid = Conveyors.newGrid(folder, ORIGIN)
	Conveyors.place(grid, 6, 0, "W", true) -- dock tile, open at the back for a truck
	Conveyors.run(grid, 5, 0, "W", 3)
	Conveyors.place(grid, 2, 0, "S")
	Conveyors.place(grid, 2, 1, "S")
	Conveyors.finish(grid)

	local buyer = Machines.hayBuyer(folder, Conveyors.frame(grid, 2, 2, "S"), "HAY SELL SHOP")
	Machines.sign(
		buyer.Base,
		("Drop hay on the belt\n$%.2f per hay, only $%d per needle"):format(Economy.HAY_PRICE, Economy.RAW_NEEDLE_PRICE),
		Vector3.new(0, 9, 0)
	)

	local dock = Conveyors.cellCenter(grid, 6, 0) + Vector3.new(T / 2, 0, 0)
	Dock.init(dock, Vector3.new(1, 0, 0))
	Machines.stepPad(folder, Conveyors.cellCenter(grid, 5, -1), Machines.Colors.pad, "UNLOAD TRUCK", function(player)
		if Dock.isBusy() then
			Data.toast(player, "Already unloading.")
		elseif Dock.hasCargo() then
			Dock.unload()
			Data.toast(player, "Unloading onto the belt.")
		else
			Data.toast(player, "Back a truck with hay up to the end of the belt first, or set bales on the belt by hand.")
		end
	end)
end

return SellShop
