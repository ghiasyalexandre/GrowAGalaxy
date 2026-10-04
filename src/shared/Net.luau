--!strict
-- Typed access to every remote. The remotes themselves are declared in
-- default.project.json under ReplicatedStorage/Remotes, so they exist before
-- any script runs. Add new remotes in both places.
--
--   GetInitialState  RemoteFunction  client -> server  () -> Types.InitialState?
--   ProfileChanged   RemoteEvent     server -> client  (field: string, value: any)
--   RegionsChanged   RemoteEvent     server -> client  ({ Types.RegionInfo })

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

local Net = {
	GetInitialState = folder:WaitForChild("GetInitialState") :: RemoteFunction,
	ProfileChanged = folder:WaitForChild("ProfileChanged") :: RemoteEvent,
	RegionsChanged = folder:WaitForChild("RegionsChanged") :: RemoteEvent,
}

return Net
