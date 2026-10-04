--!strict
-- Moves a player's character on the server. Streams the destination in
-- first, then checks the same character is still alive before moving it.
-- Callers reset FlightGuard afterwards so the move isn't flagged.

local Teleport = {}

-- The character's root part, if the player is alive.
function Teleport.rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Yields while the area streams in. Returns false if the player respawned,
-- died or left in the meantime.
function Teleport.character(player: Player, goal: CFrame): boolean
	local character = player.Character
	pcall(function()
		player:RequestStreamAroundAsync(goal.Position)
	end)
	if character and player.Character == character and Teleport.rootOf(player) then
		character:PivotTo(goal)
		return true
	end
	return false
end

return Teleport
