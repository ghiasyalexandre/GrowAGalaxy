--!strict
-- Shows a "Your station" marker with the distance over the player's own
-- station beacon, visible from anywhere. Local to this client only.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ClientState = require(script.Parent.Parent.ClientState)

local HIDE_WITHIN = 90 -- studs; the marker hides when you're at your station
local UPDATE_INTERVAL = 0.25

local WaypointController = {}

local billboard: BillboardGui
local label: TextLabel
local trackedSlot: number? = nil

local function build()
	billboard = Instance.new("BillboardGui")
	billboard.Name = "StationWaypoint"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(180, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 14, 0)
	billboard.LightInfluence = 0
	billboard.Enabled = false

	label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 120)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard

	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Finds the beacon of the player's station once the region has replicated.
local function track()
	local slot = ClientState.mySlot()
	if slot == trackedSlot then
		return
	end
	trackedSlot = slot
	billboard.Adornee = nil :: any
	billboard.Enabled = false
	if slot == nil then
		return
	end
	task.spawn(function()
		local regions = Workspace:WaitForChild("Regions")
		local region = regions:WaitForChild(`Region_{slot}`, 30)
		local station = region and region:WaitForChild("Station", 30)
		local beacon = station and station:WaitForChild("Beacon", 30)
		if beacon and beacon:IsA("BasePart") and trackedSlot == slot then
			billboard.Adornee = beacon
			billboard.Enabled = true
		end
	end)
end

local function refresh()
	local beacon = billboard.Adornee
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (beacon and beacon:IsA("BasePart") and root and root:IsA("BasePart")) then
		return
	end
	local distance = (beacon.Position - root.Position).Magnitude
	label.Visible = distance > HIDE_WITHIN
	label.Text = `Your station\n{math.floor(distance)} studs`
end

function WaypointController.init()
	build()
	ClientState.regionsChanged:Connect(track)
end

function WaypointController.start()
	track()
	task.spawn(function()
		while true do
			refresh()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return WaypointController
