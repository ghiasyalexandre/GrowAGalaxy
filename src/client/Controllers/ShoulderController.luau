--!strict
-- Over-the-shoulder camera. A tap of Alt (D-pad right on a gamepad) toggles
-- ClientState.shoulder. Flying, ShipController slides its chase camera to the
-- right; in the spacesuit this controller eases the Humanoid's CameraOffset
-- the same way. Local and cosmetic only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Input = require(script.Parent.Parent.Input)

local M = Config.Movement

local ShoulderController = {}

local offset = 0 -- smoothed suit offset, studs

function ShoulderController.start()
	Input.pressed:Connect(function(action)
		if action ~= "Shoulder" or ClientState.inspecting then
			return
		end
		ClientState.shoulder = not ClientState.shoulder
		ClientState.notify:Fire(
			if ClientState.shoulder
				then "Over-the-shoulder view on"
				else "Over-the-shoulder view off"
		)
	end)

	RunService.RenderStepped:Connect(function(dt)
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil then
			return
		end
		-- The ship camera does its own offset; the suit's comes from here.
		local wanted = if ClientState.shoulder and ClientState.mode == "suit"
			then M.SUIT_SHOULDER_OFFSET
			else 0
		offset += (wanted - offset) * (1 - math.exp(-M.SHOULDER_SMOOTHING * dt))
		if math.abs(offset - wanted) < 0.01 then
			offset = wanted
		end
		local current = humanoid.CameraOffset
		if math.abs(current.X - offset) > 0.001 then
			humanoid.CameraOffset = Vector3.new(offset, current.Y, current.Z)
		end
	end)
end

return ShoulderController
