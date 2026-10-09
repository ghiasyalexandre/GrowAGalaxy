--!strict
-- Rider ships (the hoverboard): while the local player sits in a pilot seat
-- marked Rider, a looping standing pose plays at Action priority over the
-- seat's sit pose, so they surf the board standing up. The pose is the
-- character's own idle animation (from its Animate script); it plays on the
-- owner's Animator, so everyone sees it. It stops when they leave the seat.

local Players = game:GetService("Players")

local RiderController = {}

local R15_IDLE = "rbxassetid://507766388"

local track: AnimationTrack? = nil

local function stop()
	if track then
		track:Stop(0.2)
		track:Destroy()
		track = nil
	end
end

local function idleId(character: Model): string
	local animate = character:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	local animation = idle and idle:FindFirstChildOfClass("Animation")
	if animation and animation.AnimationId ~= "" then
		return animation.AnimationId
	end
	return R15_IDLE
end

local function update(character: Model, humanoid: Humanoid)
	local seat = humanoid.SeatPart
	local riding = seat ~= nil and seat.Name == "PilotSeat" and seat:GetAttribute("Rider") == true
	if not riding then
		stop()
		return
	end
	if track then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = idleId(character)
	local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
	if ok and loaded then
		loaded.Priority = Enum.AnimationPriority.Action
		loaded.Looped = true
		loaded:Play(0.2)
		track = loaded
	end
end

local function watch(character: Model)
	stop()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		update(character, humanoid)
	end)
	update(character, humanoid)
end

function RiderController.init() end

function RiderController.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		task.spawn(watch, character)
	end)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return RiderController
