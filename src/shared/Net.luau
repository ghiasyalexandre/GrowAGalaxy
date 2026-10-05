--!strict
-- Typed access to every remote. The remotes themselves are declared in
-- default.project.json under ReplicatedStorage/Remotes, so they exist before
-- any script runs. Add new remotes in both places.
--
--   GetInitialState  RemoteFunction  client -> server  () -> Types.InitialState?
--   ProfileChanged   RemoteEvent     server -> client  (field: string, value: any)
--   RegionsChanged   RemoteEvent     server -> client  ({ Types.RegionInfo })
--   ShipRequest      RemoteEvent     client -> server  (action: "exit" | "dock" | "launch")
--   ShipState        RemoteEvent     server -> client  (ship: Model?, info: Types.ShipInfo?)
--   SuitRecover      RemoteEvent     client -> server  () "Return to Station"
--   BeamInput        RemoteEvent     client -> server  (action: "start" | "aim" | "stop",
--                                                       aim: Vector3?) aim in ship space
--   Notify           RemoteEvent     server -> client  (text: string)
--   StarRequest      RemoteFunction  client -> server  (action: "place" | "move" | "upgrade" |
--                                                       "evolve" | "buyPlanet" | "upgradePlanet",
--                                                       ...) -> (ok: boolean, message: string)
--   ShopRequest      RemoteFunction  client -> server  (action: "buyShip" | "selectShip" |
--                                                       "buyEquipment" | "expand", id: string?)
--                                                       -> (ok: boolean, message: string)
--   SettingChanged   RemoteEvent     client -> server  (name: "stabilization" | "reducedEffects" | "pvp",
--                                                       value: boolean)
--   Reward           RemoteEvent     server -> client  (kind: "collect" | "mine" | "achievement",
--                                                       amount: number, position: Vector3?,
--                                                       label: string?) celebrate earned Stardust
--   ShipDestroyed    RemoteEvent     server -> all      (pivot: CFrame, size: Vector3, paint: string,
--                                                       ownerUserId: number) draw the explosion
--   DailyRequest     RemoteFunction  client -> server  ("claim") -> (ok: boolean, message: string)
--   RaidRequest      RemoteEvent     client -> server  ("join", difficulty | "leave")
--   CustomizeRequest RemoteFunction  client -> server  ("paint" | "finish" | "showcase", shipId, value)
--                                                     -> (ok: boolean, message: string)
--   WorldEvent       RemoteEvent     server -> all     (kind: "swarm" | "swarmEnd", ...) world events
--   RaidEvent        RemoteEvent     server -> client  (kind: "bolt" | "charge" | "superlaser" |
--                                                       "bossDown" | "result", ...) raid effects

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
	StarRequest = folder:WaitForChild("StarRequest") :: RemoteFunction,
	ShopRequest = folder:WaitForChild("ShopRequest") :: RemoteFunction,
	SettingChanged = folder:WaitForChild("SettingChanged") :: RemoteEvent,
	Reward = folder:WaitForChild("Reward") :: RemoteEvent,
	ShipDestroyed = folder:WaitForChild("ShipDestroyed") :: RemoteEvent,
	DailyRequest = folder:WaitForChild("DailyRequest") :: RemoteFunction,
	RaidRequest = folder:WaitForChild("RaidRequest") :: RemoteEvent,
	RaidEvent = folder:WaitForChild("RaidEvent") :: RemoteEvent,
	CustomizeRequest = folder:WaitForChild("CustomizeRequest") :: RemoteFunction,
	WorldEvent = folder:WaitForChild("WorldEvent") :: RemoteEvent,
}

return Net
