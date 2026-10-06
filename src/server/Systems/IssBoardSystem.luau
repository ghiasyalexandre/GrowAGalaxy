--!strict
-- Fills in the ISS's live boards (parts tagged "GaG_IssBoard", built by
-- IssBuilder, with a SurfaceGui "Board" holding Title and Body labels):
--
--   Stardust   the Star Lounge leaderboard: the global top balances
--              (LeaderboardSystem.top), or, where the leaderboard data
--              store can't be read (Studio without API access), the richest
--              players in this server
--   HatchFeed  the Egg Lab's latest rare hatches in this server
--              (HatchSystem.feed, Config.Eggs.ANNOUNCE_RARITY and rarer)
--
-- Text set here replicates to every client. Nothing is read from players.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataSystem = require(script.Parent.DataSystem)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local HatchSystem = require(script.Parent.HatchSystem)
local LeaderboardSystem = require(script.Parent.LeaderboardSystem)

local P = Config.Planets
local L = Config.Leaderboard
local TAG = "GaG_IssBoard"
local REFRESH = 15 -- seconds between leaderboard board updates

local IssBoardSystem = {}

local function boards(kind: string): { TextLabel }
	local bodies: { TextLabel } = {}
	for _, part in CollectionService:GetTagged(TAG) do
		if part:GetAttribute("Board") == kind then
			local gui = part:FindFirstChild("Board")
			local body = gui and gui:FindFirstChild("Body")
			if body and body:IsA("TextLabel") then
				table.insert(bodies, body)
			end
		end
	end
	return bodies
end

local function setBody(kind: string, text: string, title: string?)
	for _, body in boards(kind) do
		body.Text = text
		local heading = body.Parent and body.Parent:FindFirstChild("Title")
		if title and heading and heading:IsA("TextLabel") then
			heading.Text = title
		end
	end
end

-- Escapes text for a RichText label.
local function plain(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function showLeaderboard()
	local entries = LeaderboardSystem.top()
	local title = "Top Stardust"
	if #entries == 0 then
		-- No global board here: this server's players instead.
		title = "Top Stardust in this server"
		for _, player in Players:GetPlayers() do
			local profile = DataSystem.getProfile(player)
			if profile then
				table.insert(
					entries,
					{ name = player.DisplayName, stardust = math.floor(profile.stardust) }
				)
			end
		end
		table.sort(entries, function(a, b)
			return a.stardust > b.stardust
		end)
	end
	local lines: { string } = {}
	for rank = 1, math.min(#entries, L.BOARD_SIZE) do
		local entry = entries[rank]
		local medal = if rank == 1
			then "#FFD36B"
			elseif rank == 2 then "#D8E0F0"
			elseif rank == 3 then "#E0A060"
			else "#9AA6C8"
		table.insert(
			lines,
			`<font color="{medal}"><b>{rank}.</b></font> {plain(entry.name)}  <font color="#FFD36B">{Format.abbreviate(
				entry.stardust
			)}</font>`
		)
	end
	setBody("Stardust", if #lines == 0 then "No one yet." else table.concat(lines, "\n"), title)
end

local function showFeed()
	local lines: { string } = {}
	for _, entry in HatchSystem.feed() do
		local def = P.BY_ID[entry.typeId]
		if def then
			local rarity = P.RARITIES[def.rarity]
			local ago = math.max(os.time() - entry.at, 0)
			local when = if ago < 60 then "just now" else `{ago // 60} min ago`
			table.insert(
				lines,
				`<b>{plain(entry.name)}</b> hatched <font color="{rarity.color}"><b>{def.displayName}</b> ({rarity.displayName})</font>  <font color="#9AA6C8">{when}</font>`
			)
		end
	end
	if #lines > 0 then
		setBody("HatchFeed", table.concat(lines, "\n"))
	end
end

function IssBoardSystem.start()
	HatchSystem.feedChanged:Connect(showFeed)
	task.spawn(function()
		while true do
			local ok, problem = pcall(showLeaderboard :: any)
			if not ok then
				warn(`[IssBoardSystem] leaderboard board failed: {problem}`)
			end
			-- Keeps "x min ago" current.
			pcall(showFeed)
			task.wait(REFRESH)
		end
	end)
end

return IssBoardSystem
