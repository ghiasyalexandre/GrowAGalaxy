--!strict
-- Cycles the ISS ship showroom: every Config.Ships.SHOWROOM_SECONDS the
-- podiums (IssBuilder's ShowroomPodiums) move one place along the ship
-- ladder, each still three places after the podium before it, so every ship
-- comes round in turn. Does nothing with a hand-built ISS that has no
-- podiums.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local IssBuilder = require(script.Parent.Parent.World.IssBuilder)

local ShowroomSystem = {}

function ShowroomSystem.start()
	local world = Workspace:FindFirstChild("World")
	local iss = world and world:FindFirstChild("ISS")
	local podiums = iss and iss:FindFirstChild("ShowroomPodiums", true)
	if podiums == nil then
		return
	end
	task.spawn(function()
		local step = 0
		while podiums.Parent do
			task.wait(Config.Ships.SHOWROOM_SECONDS)
			step += 1
			IssBuilder.dressShowroom(podiums, step)
		end
	end)
end

return ShowroomSystem
