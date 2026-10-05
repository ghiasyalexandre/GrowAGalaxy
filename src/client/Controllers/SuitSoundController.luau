--!strict
-- What floating sounds like (Config.Movement SUIT_SOUND*). Purely cosmetic,
-- on every client, for every character.
--
-- Roblox's default character sounds (RbxCharacterSounds puts them in each
-- character's HumanoidRootPart) are made for walking: footsteps, jumps,
-- landings, the falling wind. Nobody walks in zero-g, so those are silenced
-- (kept at volume 0 even when the default script changes them). The death
-- sound is left alone.
--
-- Instead each character carries a looping "SuitThrust" hiss whose volume and
-- pitch follow how fast it floats; it's silent while seated (ships have their
-- own engine feel) and when dead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local M = Config.Movement

local DEFAULT_SOUNDS = {
	Running = true,
	Climbing = true,
	Jumping = true,
	Landing = true,
	FreeFalling = true,
	GettingUp = true,
	Swimming = true,
	Splash = true,
}
local FADE = 6 -- how fast volume and pitch follow the speed

type Suit = { humanoid: Humanoid, root: BasePart, sound: Sound, level: number }

local SuitSoundController = {}

local suits: { [Model]: Suit } = {}

local function silence(sound: Instance)
	if not sound:IsA("Sound") or not DEFAULT_SOUNDS[sound.Name] then
		return
	end
	sound.Volume = 0
	sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if sound.Volume ~= 0 then
			sound.Volume = 0
		end
	end)
end

local function track(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	if not character:IsDescendantOf(game) then
		return
	end
	for _, child in root:GetChildren() do
		silence(child)
	end
	root.ChildAdded:Connect(silence)

	if M.SUIT_SOUND == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "SuitThrust"
	sound.SoundId = M.SUIT_SOUND
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = M.SUIT_SOUND_PITCH[1]
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 80
	sound.Parent = root
	sound:Play()
	suits[character] = { humanoid = humanoid, root = root, sound = sound, level = 0 }
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			suits[character] = nil
		end
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(track, character)
	end)
	if player.Character then
		task.spawn(track, player.Character)
	end
end

local function step(dt: number)
	local blend = math.min(dt * FADE, 1)
	for character, suit in suits do
		if suit.root.Parent ~= character then
			suits[character] = nil
			continue
		end
		local floating = suit.humanoid.Health > 0 and suit.humanoid.SeatPart == nil
		local speed = if floating then suit.root.AssemblyLinearVelocity.Magnitude else 0
		local target = math.clamp(speed / M.SUIT_MAX_SPEED, 0, 1)
		suit.level += (target - suit.level) * blend
		local low, high = M.SUIT_SOUND_PITCH[1], M.SUIT_SOUND_PITCH[2]
		suit.sound.Volume = M.SUIT_SOUND_VOLUME * suit.level
		suit.sound.PlaybackSpeed = low + (high - low) * suit.level
	end
end

function SuitSoundController.init() end

function SuitSoundController.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	RunService.Heartbeat:Connect(step)
end

return SuitSoundController
