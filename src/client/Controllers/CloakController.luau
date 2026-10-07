--!strict
-- While you're cloaked (player attribute Cloaked, CloakSystem), the server
-- makes your character and ship fully invisible for everyone, you included.
-- So you don't lose yourself, this client shows them faintly, for you only
-- (a local change the server never sends to others).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)

local GHOST = 0.75 -- how see-through you look to yourself
local ORIGINAL = "GaG_CloakTransparency"

local CloakController = {}

local function ghost(root: Instance?)
	if root == nil then
		return
	end
	for _, item in root:GetDescendants() do
		local original = item:GetAttribute(ORIGINAL)
		if
			type(original) == "number"
			and original < 1
			and (item:IsA("BasePart") or item:IsA("Decal"))
		then
			local thing = item :: any
			if thing.Transparency ~= GHOST then
				thing.Transparency = GHOST
			end
		end
	end
end

function CloakController.start()
	local player = Players.LocalPlayer
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.25 or player:GetAttribute("Cloaked") ~= true then
			return
		end
		elapsed = 0
		-- Flying, the pilot is already hidden inside the ship (PilotHideController).
		if ClientState.mode ~= "ship" then
			ghost(player.Character)
		end
		ghost(ClientState.ship)
	end)
end

return CloakController
