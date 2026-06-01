-- SpawnSelector
-- lua/SpawnSelector/SpawnSelector_Server.lua
--
-- Server logic: the alien commander picks a starting tech point; the marines are given a
-- random legal partner spawn for it. The pick is applied at round start via
-- Server.teamSpawnOverride, the highest-priority spawn path in NS2Gamerules:ResetGame.
--
-- Adapted from the NSL plugin:
-- https://github.com/xToken/NSL - lua/NSL/customspawns/server.lua - by Dragon

Script.Load("lua/SpawnSelector/SpawnSelector_Utility.lua")
Script.Load("lua/SpawnSelector/SpawnSelector_Shared.lua")

local kEnabled = true
local kSelectedMarineSpawn
local kSelectedAlienSpawn

local function ClearSelectedSpawns()
	kSelectedMarineSpawn = nil
	kSelectedAlienSpawn = nil
	Server.teamSpawnOverride = nil
	local gameInfo = GetGameInfoEntity()
	if gameInfo then
		gameInfo:SetSelectedSpawn(Entity.invalidId)
	end
end

-- Apply the alien commander's pick via Server.teamSpawnOverride - the highest-priority spawn
-- mechanism in NS2Gamerules:ResetGame (checked before Server.spawnSelectionOverrides and before
-- ChooseTechPoint). Many competitive servers/maps populate Server.spawnSelectionOverrides with
-- fixed spawn pairs, which silently bypassed our earlier ChooseTechPoint override - that was the
-- cause of "picked X but spawned at Y". teamSpawnOverride wins over those, and is non-destructive:
-- we don't have to wipe the map's pairs, which still apply when there is no pick (random). Names
-- must be lowercase to match the comparison ResetGame does.
local function ApplyTeamSpawnOverride()
	if kEnabled and kSelectedAlienSpawn and kSelectedMarineSpawn then
		Server.teamSpawnOverride = { {
			marineSpawn = string.lower(kSelectedMarineSpawn:GetLocationName()),
			alienSpawn = string.lower(kSelectedAlienSpawn:GetLocationName())
		} }
	else
		Server.teamSpawnOverride = nil
	end
end

-- Clear cached picks when a round ends so the next round starts fresh.
local originalEndGame
originalEndGame = Class_ReplaceMethod("NS2Gamerules", "EndGame",
	function(self, winningTeam)
		originalEndGame(self, winningTeam)
		ClearSelectedSpawns()
	end
)

local function ResolveTechPointByName(lowerName)
	for _, tp in ipairs(EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))) do
		if string.lower(tp:GetLocationName()) == lowerName then
			return tp
		end
	end
	return nil
end

-- Pick a random VALID marine tech point for the alien's chosen hive. Maps define their legal
-- opposing start pairs via 'spawn_selection_override' map entities (Server.spawnSelectionOverrides),
-- so we pick randomly among the marine spawns the map pairs with the alien's pick. This keeps the
-- result both random AND a legal pairing - an illegal pairing makes ResetGame reject our override
-- and fall back to a random map pair (the "picked Smelting, marines got Turbine in the log but
-- spawned at Flow" case). If the map has no pair data, fall back to any random tech point that
-- isn't the alien's. Uses math.random (the old techPointRandomizer:random call kept returning the
-- first tech point, so the marine spawn was effectively fixed).
local function PickMarineSpawn(alienTechPoint)

	local alienName = string.lower(alienTechPoint:GetLocationName())

	if Server.spawnSelectionOverrides then
		local validMarineNames = { }
		for _, pair in ipairs(Server.spawnSelectionOverrides) do
			if pair.alienSpawn == alienName and pair.marineSpawn and pair.marineSpawn ~= alienName then
				table.insertunique(validMarineNames, pair.marineSpawn)
			end
		end
		if #validMarineNames > 0 then
			local marineTP = ResolveTechPointByName(validMarineNames[math.random(#validMarineNames)])
			if marineTP then
				return marineTP
			end
		end
	end

	-- Fallback: any random valid marine tech point that isn't the alien's pick.
	local validTechPoints = { }
	for _, tp in ipairs(EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))) do
		local teamNum = tp:GetTeamNumberAllowed()
		if tp ~= alienTechPoint and (teamNum == 0 or teamNum == kTeam1Index) and teamNum ~= 3 then
			table.insert(validTechPoints, tp)
		end
	end
	if #validTechPoints > 0 then
		return validTechPoints[math.random(#validTechPoints)]
	end
	return nil

end

-- Block the commander from voluntarily leaving the chair during the final countdown. The logout
-- button, the Exit key, and the "logout" console command all route through OnCommandLogout, which
-- checks GetCommanderLogoutAllowed(). A forced Eject() / disconnect calls Commander:Logout()
-- directly and bypasses this gate, so server-side cleanup of a leaving commander still works.
-- The lock only applies during the countdown - commanders may freely enter/leave chairs while
-- setting up during the rest of the pre-game.
local originalGetCommanderLogoutAllowed = GetCommanderLogoutAllowed
function GetCommanderLogoutAllowed()
	if kEnabled then
		local gamerules = GetGamerules()
		if gamerules and gamerules:GetGameState() == kGameState.Countdown then
			return false
		end
	end
	return originalGetCommanderLogoutAllowed()
end

local function OnSpawnSelectionMessage(client, message)

	if not kEnabled or not client or not message then
		return
	end

	local player = client:GetControllingPlayer()
	if not player then
		return
	end

	-- Only the alien commander may choose.
	if not (player:GetIsCommander() and player:GetTeamNumber() == kTeam2Index) then
		return
	end

	local tp = Shared.GetEntity(message.techPointId)
	if tp and tp:isa("TechPoint") and (tp:GetTeamNumberAllowed() == 0 or tp:GetTeamNumberAllowed() == kTeam2Index) then
		-- Valid alien-allowed pick: cache it, choose a different marine spawn, and install the
		-- override so it actually wins at round start.
		kSelectedAlienSpawn = tp
		kSelectedMarineSpawn = PickMarineSpawn(tp)
		ApplyTeamSpawnOverride()
		GetGameInfoEntity():SetSelectedSpawn(tp:GetId())
	else
		-- Random / clear request (or an invalid id) - revert to vanilla selection.
		ClearSelectedSpawns()
	end

end

Server.HookNetworkMessage("SpawnSelector_SelectSpawn", OnSpawnSelectionMessage)

-- Admin toggle. Defaults to enabled; "sv_spawnselect false" disables (UI hides, spawns vanilla).
local function SetSpawnSelectEnabled(client, enabledArg)

	if enabledArg ~= nil then
		kEnabled = enabledArg == "true" or enabledArg == "1"
	else
		kEnabled = not kEnabled
	end

	local gameInfo = GetGameInfoEntity()
	if gameInfo then
		gameInfo:SetSpawnSelectionEnabled(kEnabled)
	end

	if not kEnabled then
		ClearSelectedSpawns()
	end

	Shared.Message("SpawnSelector: alien spawn selection " .. (kEnabled and "ENABLED" or "DISABLED"))

end

CreateServerAdminCommand("Console_sv_spawnselect", SetSpawnSelectEnabled,
	"<true/false>, Enables or disables alien spawn selection (default enabled).")
