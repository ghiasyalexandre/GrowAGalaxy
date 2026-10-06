--!strict
-- Server announcements in this server's chat (ChatAnnounce): Legendary and
-- Interstellar planet hatches (HatchSystem, Config.Eggs.CHAT_RARITY). Shown
-- as a coloured system message, with the TextChatService chat or, on the
-- legacy chat, through StarterGui's system message.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local ChatController = {}

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function show(text: string, color: string)
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local channels = TextChatService:FindFirstChild("TextChannels")
		local system = channels and channels:FindFirstChild("RBXSystem")
		if system and system:IsA("TextChannel") then
			system:DisplaySystemMessage(`<font color="{color}"><b>{escape(text)}</b></font>`)
		end
	else
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = text,
				Color = Color3.fromHex(color),
				Font = Enum.Font.GothamBold,
			})
		end)
	end
end

function ChatController.start()
	Net.ChatAnnounce.OnClientEvent:Connect(function(text: unknown, color: unknown)
		if type(text) == "string" and type(color) == "string" then
			local ok, problem = pcall(show :: any, text, color)
			if not ok then
				warn(`[ChatController] {problem}`)
			end
		end
	end)
end

return ChatController
