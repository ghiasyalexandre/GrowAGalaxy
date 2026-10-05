--!strict
-- Ambient motion for world decorations, run on each client so the server
-- doesn't replicate every frame:
--
--   GaG_Spin   Parts or models with a SpinSpeed attribute (radians per
--              second) turn about the world's up axis through their centre
--              (a model's bounding-box centre, not its pivot, which an
--              imported model may have far off to one side): the ISS
--              hologram, showroom ships, the raid beacon's rings.
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

local SpinController = {}

-- Speed in radians per second, and where the model's centre sits relative to
-- its pivot (measured again whenever its part count changes, e.g. as parts
-- stream in), so it turns on the spot without drifting.
type Spinner = { speed: number, offset: Vector3?, parts: number }

local spinners: { [Instance]: Spinner } = {}
local pulsers: { [BasePart]: true } = {}

local function addSpinner(instance: Instance)
	local speed = instance:GetAttribute("SpinSpeed")
	if instance:IsA("PVInstance") and type(speed) == "number" then
		spinners[instance] = { speed = speed, offset = nil, parts = -1 }
	end
end

-- The point a spinner turns about, where it is now.
local function centerOf(instance: Instance, spinner: Spinner): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif not instance:IsA("Model") then
		return nil
	end
	local parts = #instance:GetDescendants()
	if parts == 0 then
		return nil
	end
	local pivot = instance:GetPivot()
	if parts ~= spinner.parts or spinner.offset == nil then
		spinner.parts = parts
		local box = instance:GetBoundingBox()
		spinner.offset = pivot:PointToObjectSpace(box.Position)
	end
	return pivot:PointToWorldSpace(spinner.offset :: Vector3)
end

local function addPulser(instance: Instance)
	if instance:IsA("BasePart") then
		pulsers[instance] = true
	end
end

local function step(dt: number)
	if ClientState.reducedEffects then
		return
	end
	local now = os.clock()
	for instance, spinner in spinners do
		-- Turned a little each frame from wherever it is now, so a model whose
		-- parts stream in late (or that the server moves) is never snapped
		-- back to an old position.
		local center = if instance.Parent then centerOf(instance, spinner) else nil
		if center then
			local pivot = CFrame.new(center)
			local turn = CFrame.Angles(0, spinner.speed * dt, 0);
			(instance :: PVInstance):PivotTo(
				pivot * turn * pivot:Inverse() * (instance :: PVInstance):GetPivot()
			)
		end
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
