--!strict
-- While someone pilots a ship they become the ship: their character is
-- hidden on this client (every part and decal fully transparent through
-- LocalTransparencyModifier, which changes nothing for anyone else), and
-- shown again the moment they leave the pilot seat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PilotHideController = {}

local hidden: { [Model]: boolean } = {}

local function setHidden(character: Model, hide: boolean)
	local modifier = if hide then 1 else 0
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = modifier
		elseif item:IsA("Decal") then
			item.LocalTransparencyModifier = modifier
		end
	end
end

local function step()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character == nil or humanoid == nil then
			continue
		end
		local seat = humanoid.SeatPart
		local piloting = seat ~= nil and seat.Name == "PilotSeat"
		if piloting then
			-- Every frame: the default camera may reset the local character's.
			setHidden(character, true)
			hidden[character] = true
		elseif hidden[character] then
			setHidden(character, false)
			hidden[character] = nil
		end
	end
	for character in hidden do
		if character.Parent == nil then
			hidden[character] = nil
		end
	end
end

function PilotHideController.init() end

function PilotHideController.start()
	RunService.RenderStepped:Connect(step)
end

return PilotHideController
