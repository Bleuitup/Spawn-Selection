-- SpawnSelector
-- lua/SpawnSelector/SpawnSelector_Server.lua
--
-- Server logic: the alien commander picks a starting tech point; the marines are
-- given a different (weighted-random) one. The picks are cached and applied when the
-- game's normal NS2Gamerules:ChooseTechPoint runs at round start.
--
-- Adapted from the NSL plugin (with permission):
-- https://github.com/xToken/NSL - lua/NSL/customspawns/server.lua - by Dragon

Script.Load("lua/SpawnSelector/SpawnSelector_Utility.lua")
Script.Load("lua/SpawnSelector/SpawnSelector_Shared.lua")

local kEnabled = true
local kSelectedMarineSpawn
local kSelectedAlienSpawn

local function ClearSelectedSpawns()
	kSelectedMarineSpawn = nil
	kSelectedAlienSpawn = nil
	local gameInfo = GetGameInfoEntity()
	if gameInfo then
		gameInfo:SetSelectedSpawn(Entity.invalidId)
	end
end

-- Override the vanilla tech point chooser so a cached selection wins. The cached
-- entity must still be present in the candidate list (it gets removed once chosen so
-- the other team can't reuse it) - otherwise fall through to the original logic.
local originalChooseTechPoint
originalChooseTechPoint = Class_ReplaceMethod("NS2Gamerules", "ChooseTechPoint",
	function(self, techPoints, teamNumber)

		if kEnabled then

			if teamNumber == kTeam1Index and kSelectedMarineSpawn and table.contains(techPoints, kSelectedMarineSpawn) then
				table.removevalue(techPoints, kSelectedMarineSpawn)
				return kSelectedMarineSpawn
			elseif teamNumber == kTeam2Index and kSelectedAlienSpawn and table.contains(techPoints, kSelectedAlienSpawn) then
				table.removevalue(techPoints, kSelectedAlienSpawn)
				return kSelectedAlienSpawn
			end

		end

		return originalChooseTechPoint(self, techPoints, teamNumber)

	end
)

-- Clear cached picks when a round ends so the next round starts fresh.
local originalEndGame
originalEndGame = Class_ReplaceMethod("NS2Gamerules", "EndGame",
	function(self, winningTeam)
		originalEndGame(self, winningTeam)
		ClearSelectedSpawns()
	end
)

-- Pick a marine tech point different from the alien's choice, weighted by GetChooseWeight().
local function PickMarineSpawn(alienTechPoint)

	local gameRules = GetGamerules()
	local techPoints = EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))

	local validTechPoints = { }
	local totalTechPointWeight = 0
	for _, currentTechPoint in ipairs(techPoints) do

		local teamNum = currentTechPoint:GetTeamNumberAllowed()
		if currentTechPoint ~= alienTechPoint and (teamNum == 0 or teamNum == kTeam1Index) and teamNum ~= 3 then
			table.insert(validTechPoints, currentTechPoint)
			totalTechPointWeight = totalTechPointWeight + currentTechPoint:GetChooseWeight()
		end

	end

	local chosenTechPointWeight = gameRules.techPointRandomizer:random(0, totalTechPointWeight)
	for _, currentTechPoint in ipairs(validTechPoints) do
		chosenTechPointWeight = chosenTechPointWeight - currentTechPoint:GetChooseWeight()
		if chosenTechPointWeight <= 0 then
			return currentTechPoint
		end
	end

	return validTechPoints[1]

end

-- Block the commander from voluntarily leaving the chair before the game starts. The logout
-- button, the Exit key, and the "logout" console command all route through OnCommandLogout, which
-- checks GetCommanderLogoutAllowed(). A forced Eject() / disconnect calls Commander:Logout()
-- directly and bypasses this gate, so server-side cleanup of a leaving commander still works.
local originalGetCommanderLogoutAllowed = GetCommanderLogoutAllowed
function GetCommanderLogoutAllowed()
	if kEnabled then
		local gamerules = GetGamerules()
		if gamerules and gamerules:GetGameState() < kGameState.Started then
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
		-- Valid alien-allowed pick: cache it and choose a different marine spawn.
		kSelectedAlienSpawn = tp
		kSelectedMarineSpawn = PickMarineSpawn(tp)
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
