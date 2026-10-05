--!strict
-- Ambient motion for world decorations, run on each client so the server
-- doesn't replicate every frame:
--
--   GaG_Spin   Parts or models with a SpinSpeed attribute (radians per
--              second) turn about the world's up axis through their pivot
--              (the ISS hologram, showroom ships, the raid beacon's rings).
--   GaG_Pulse  Parts whose Transparency breathes between their PulseFrom and
--              PulseTo attributes (the raid pads' light columns).
--
-- Reduced effects stops both (spinning things keep their latest angle).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)

local SPIN_TAG = "GaG_Spin"
local PULSE_TAG = "GaG_Pulse"
local PULSE_SPEED = 2.2 -- radians per second

type Spinner = { base: CFrame, speed: number }

local SpinController = {}

local spinners: { [Instance]: Spinner } = {}
local pulsers: { [BasePart]: true } = {}

local function pivotOf(instance: Instance): CFrame?
	if instance:IsA("PVInstance") then
		return (instance :: PVInstance):GetPivot()
	end
	return nil
end

local function addSpinner(instance: Instance)
	local base = pivotOf(instance)
	local speed = instance:GetAttribute("SpinSpeed")
	if base and type(speed) == "number" then
		spinners[instance] = { base = base, speed = speed }
	end
end

local function addPulser(instance: Instance)
	if instance:IsA("BasePart") then
		pulsers[instance] = true
	end
end

local function step()
	if ClientState.reducedEffects then
		return
	end
	local now = os.clock()
	for instance, spinner in spinners do
		if instance.Parent == nil then
			continue
		end
		local turned = CFrame.new(spinner.base.Position)
			* CFrame.Angles(0, (now * spinner.speed) % (2 * math.pi), 0)
			* spinner.base.Rotation;
		(instance :: PVInstance):PivotTo(turned)
	end
	local wave = 0.5 + 0.5 * math.sin(now * PULSE_SPEED)
	for part in pulsers do
		local from, to = part:GetAttribute("PulseFrom"), part:GetAttribute("PulseTo")
		if type(from) == "number" and type(to) == "number" then
			part.Transparency = from + (to - from) * wave
		end
	end
end

function SpinController.init() end

function SpinController.start()
	for _, instance in CollectionService:GetTagged(SPIN_TAG) do
		addSpinner(instance)
	end
	for _, instance in CollectionService:GetTagged(PULSE_TAG) do
		addPulser(instance)
	end
	CollectionService:GetInstanceAddedSignal(SPIN_TAG):Connect(addSpinner)
	CollectionService:GetInstanceRemovedSignal(SPIN_TAG):Connect(function(instance)
		spinners[instance] = nil
	end)
	CollectionService:GetInstanceAddedSignal(PULSE_TAG):Connect(addPulser)
	CollectionService:GetInstanceRemovedSignal(PULSE_TAG):Connect(function(instance)
		pulsers[instance :: BasePart] = nil
	end)
	RunService.RenderStepped:Connect(step)
end

return SpinController
