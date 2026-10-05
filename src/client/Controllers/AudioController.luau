--!strict
-- Music and sound volume on this client.
--
--   Music  ReplicatedStorage/Assets/Music (assets/roblox/Music): SpaceMusic
--          loops as the game's music; while you're in a Death Star raid
--          (player attribute Raid) it crossfades to SpaceDisco, and back
--          afterwards. Each track keeps the volume saved in its .rbxm.
--   Groups Two SoundGroups, Music and SFX, scaled by your saved settings
--          (musicVolume, sfxVolume; the Settings panel). Every other sound
--          that plays in the world or the UI joins SFX.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local MAIN_TRACK = "SpaceMusic"
local BOSS_TRACK = "SpaceDisco"
local FADE = TweenInfo.new(2, Enum.EasingStyle.Quad)

local AudioController = {}

local musicGroup: SoundGroup
local sfxGroup: SoundGroup
local tracks: { [string]: { sound: Sound, volume: number } } = {}
local playing: string? = nil

local function group(name: string): SoundGroup
	local made = Instance.new("SoundGroup")
	made.Name = name
	made.Parent = SoundService
	return made
end

-- Every sound that isn't music plays through the SFX group. Stray copies
-- of the music tracks (e.g. placed in the world in Studio) are kept silent,
-- so the music never plays twice.
local function adopt(item: Instance)
	if not item:IsA("Sound") or item.SoundGroup == musicGroup then
		return
	end
	if item.Name == MAIN_TRACK or item.Name == BOSS_TRACK then
		item.Volume = 0
		item:Stop()
	elseif item.SoundGroup == nil then
		item.SoundGroup = sfxGroup
	end
end

local function loadTrack(name: string)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local music = assets and assets:FindFirstChild("Music")
	local source = music and music:FindFirstChild(name)
	if source == nil or not source:IsA("Sound") then
		warn(`[AudioController] No {name} track in ReplicatedStorage/Assets/Music`)
		return
	end
	local sound = source:Clone()
	-- Extra sounds saved inside the track's file aren't part of the music.
	for _, child in sound:GetChildren() do
		child:Destroy()
	end
	sound.Looped = true
	sound.SoundGroup = musicGroup
	local volume = sound.Volume
	sound.Volume = 0
	sound.Parent = SoundService
	tracks[name] = { sound = sound, volume = volume }
end

-- Fades to `name`, or does nothing if it's already playing.
local function playTrack(name: string)
	if playing == name then
		return
	end
	playing = name
	for trackName, track in tracks do
		if trackName == name then
			if not track.sound.IsPlaying then
				track.sound:Play()
			end
			TweenService:Create(track.sound, FADE, { Volume = track.volume }):Play()
		else
			local fade = TweenService:Create(track.sound, FADE, { Volume = 0 })
			fade.Completed:Once(function()
				if playing ~= trackName then
					track.sound:Pause()
				end
			end)
			fade:Play()
		end
	end
end

local function applyVolumes()
	local profile = ClientState.profile
	local settings = profile and profile.settings
	if settings then
		musicGroup.Volume = settings.musicVolume
		sfxGroup.Volume = settings.sfxVolume
	end
end

-- Live preview while a slider moves (the Settings panel saves on release).
function AudioController.preview(name: string, value: number)
	if name == "musicVolume" then
		musicGroup.Volume = value
	elseif name == "sfxVolume" then
		sfxGroup.Volume = value
	end
end

function AudioController.init()
	musicGroup = group("Music")
	sfxGroup = group("SFX")
end

function AudioController.start()
	for _, root in { Workspace :: Instance, SoundService, Players.LocalPlayer } do
		for _, item in root:GetDescendants() do
			adopt(item)
		end
		root.DescendantAdded:Connect(adopt)
	end
	loadTrack(MAIN_TRACK)
	loadTrack(BOSS_TRACK)
	applyVolumes()
	ClientState.profileChanged:Connect(function(field)
		if field == "settings" or field == "*" then
			applyVolumes()
		end
	end)
	local player = Players.LocalPlayer
	local function choose()
		playTrack(if player:GetAttribute("Raid") ~= nil then BOSS_TRACK else MAIN_TRACK)
	end
	player:GetAttributeChangedSignal("Raid"):Connect(choose)
	choose()
end

return AudioController
