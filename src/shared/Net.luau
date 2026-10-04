--!strict
-- Typed access to every remote. The remotes themselves are declared in
-- default.project.json under ReplicatedStorage/Remotes, so they exist before
-- any script runs. Add new remotes in both places.
--
--   GetInitialState  RemoteFunction  client -> server  () -> Types.InitialState?
--   ProfileChanged   RemoteEvent     server -> client  (field: string, value: any)
--   RegionsChanged   RemoteEvent     server -> client  ({ Types.RegionInfo })
--   ShipRequest      RemoteEvent     client -> server  (action: "exit" | "dock")
--   ShipState        RemoteEvent     server -> client  (ship: Model?, info: Types.ShipInfo?)
--   SuitRecover      RemoteEvent     client -> server  () "Return to Station"
--   BeamInput        RemoteEvent     client -> server  (action: "start" | "aim" | "stop",
--                                                       aim: Vector3?) aim in ship space
--   Notify           RemoteEvent     server -> client  (text: string)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

local Net = {
	GetInitialState = folder:WaitForChild("GetInitialState") :: RemoteFunction,
	ProfileChanged = folder:WaitForChild("ProfileChanged") :: RemoteEvent,
	RegionsChanged = folder:WaitForChild("RegionsChanged") :: RemoteEvent,
	ShipRequest = folder:WaitForChild("ShipRequest") :: RemoteEvent,
	ShipState = folder:WaitForChild("ShipState") :: RemoteEvent,
	SuitRecover = folder:WaitForChild("SuitRecover") :: RemoteEvent,
	BeamInput = folder:WaitForChild("BeamInput") :: RemoteEvent,
	Notify = folder:WaitForChild("Notify") :: RemoteEvent,
}

return Net
