-- Hive Spawn Selector
-- lua/HiveSpawnSelector/HiveSpawnSelector_Client.lua
--
-- Attaches the spawn-selection menu to the alien commander, and relays the commander's pick to
-- every alien team member as a chat-style message ("Your commander has selected X as your
-- spawn."). Adapted from NSL's NSLSystemMessage chat injection in lua/NSL/messages/client.lua,
-- without NSL's localization/message-id/league-name machinery - this mod only ships one message,
-- in English.

Script.Load("lua/HiveSpawnSelector/HiveSpawnSelector_Utility.lua")
Script.Load("lua/HiveSpawnSelector/HiveSpawnSelector_Shared.lua")

AddClientUIScriptForClass("AlienCommander", "HiveSpawnSelector/GUIHiveSpawnSelectorMenu")

-- Only the "[Hive Spawn Selector]" tag is magenta, unmistakable against the usual chat colors
-- (this used to be a dark, easy-to-miss blue-grey, 0.28, 0.36, 0.46) - the message itself stays
-- standard white so it reads like normal chat text. A two-line, team-colored version (alien
-- orange / marine light blue) was tried and reverted as too cluttered - see git history if this
-- comes up again, along with why per-word coloring within one line isn't possible at all
-- (vanilla's chat feed supports only one color for an entire message body - ns2/lua/GUIChat.lua).
local kAnnounceHeaderColor = Color(1, 0, 1, 1)
local kAnnounceTextColor = Color(1, 1, 1, 1)

-- Queued messages get merged into vanilla's chat feed the next time it polls - see
-- ns2/lua/Chat.lua's ChatUI_GetMessages/chatMessages for the color/header/color/message/... shape
-- being matched here.
local queuedChatMessages = { }

local originalChatUIGetMessages = ChatUI_GetMessages
function ChatUI_GetMessages()
	local messages = originalChatUIGetMessages()
	if #queuedChatMessages > 0 then
		table.copy(queuedChatMessages, messages, true)
		queuedChatMessages = { }
	end
	return messages
end

local function OnAnnounceMessage(message)

	local player = Client.GetLocalPlayer()
	if not player then
		return
	end

	local text
	local tp = Shared.GetEntity(message.techPointId)
	if tp and tp:isa("TechPoint") then
		text = string.format("Your commander has selected %s as your spawn.", tp:GetLocationName())
	else
		text = "Your commander has selected a random spawn."
	end

	-- Names every legal marine spawn for the pick, not just the one actually chosen - see
	-- AnnounceSelection in HiveSpawnSelector_Server.lua.
	if message.marineSpawnNames and message.marineSpawnNames ~= "" then
		local marineNames = { }
		for marineName in string.gmatch(message.marineSpawnNames, "[^,]+") do
			table.insert(marineNames, marineName)
		end

		if #marineNames == 1 then
			text = text .. string.format(" Marines will spawn in %s.", marineNames[1])
		elseif #marineNames > 1 then
			text = text .. string.format(" Marines will spawn in either %s.", table.concat(marineNames, ", "))
		end
	end

	table.insert(queuedChatMessages, kAnnounceHeaderColor)
	table.insert(queuedChatMessages, "[Hive Spawn Selector] ")
	table.insert(queuedChatMessages, kAnnounceTextColor)
	table.insert(queuedChatMessages, text)
	table.insert(queuedChatMessages, false)
	table.insert(queuedChatMessages, false)
	table.insert(queuedChatMessages, 0)
	table.insert(queuedChatMessages, 0)

	StartSoundEffect(player:GetChatSound())

end

Client.HookNetworkMessage("HiveSpawnSelector_Announce", OnAnnounceMessage)
