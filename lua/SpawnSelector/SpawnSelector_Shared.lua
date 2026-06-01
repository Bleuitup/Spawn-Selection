-- SpawnSelector
-- lua/SpawnSelector/SpawnSelector_Shared.lua
--
-- Shared definitions: the spawn-selection network message and two synced GameInfo
-- fields the commander UI reads (whether selection is enabled, and the currently
-- selected tech point). Loaded on both client and server.
--
-- GameInfo extension pattern adapted from the NSL plugin (with permission):
-- https://github.com/xToken/NSL - lua/NSL/gameinfo/shared.lua - by Dragon

Script.Load("lua/SpawnSelector/SpawnSelector_Utility.lua")

-- Client -> Server: the alien commander's chosen tech point (-1 means "random / clear").
Shared.RegisterNetworkMessage("SpawnSelector_SelectSpawn", { techPointId = "entityid" })

-- Vanilla only defines TechPoint:GetTeamNumberAllowed() inside an "if Server then" block,
-- so the method does not exist on the client even though the allowedTeamNumber networkVar is
-- synced. Define a shared getter so the commander UI can read it client-side. (NSL does the same.)
function TechPoint:GetTeamNumberAllowed()
	return self.allowedTeamNumber
end

local networkVars =
{
	spawnSelectionEnabled = "boolean",
	spawnSelected = "entityid"
}

local originalGameInfoOnCreate
originalGameInfoOnCreate = Class_ReplaceMethod("GameInfo", "OnCreate",
	function(self)
		originalGameInfoOnCreate(self)

		if Server then
			self.spawnSelectionEnabled = true
			self.spawnSelected = Entity.invalidId
		end

	end
)

function GameInfo:GetSpawnSelectionEnabled()
	return self.spawnSelectionEnabled
end

function GameInfo:GetSelectedSpawn()
	return self.spawnSelected
end

if Server then

	function GameInfo:SetSpawnSelectionEnabled(enabled)
		self.spawnSelectionEnabled = enabled == true
	end

	function GameInfo:SetSelectedSpawn(techPointId)
		self.spawnSelected = techPointId
	end

end

Class_Reload("GameInfo", networkVars)

-- Countdown freeze.
-- Lock players in place for the start-of-round countdown (kGameState.Countdown) - and only then,
-- not during the brief PreGame that precedes it. Vanilla already freezes during the countdown
-- (Player:OnProcessMove zeroes the move and skips UpdateViewAngles when GetCountdownActive), so we
-- key our freeze off the Countdown game state directly to start exactly when the countdown does and
-- to hold even if another mod disturbs vanilla's path.
--
-- We deliberately do NOT reuse GetCountdownActive: that flag also drives the countdown zoom camera,
-- the third-person body draw and the "Game is starting" text - keying off it would risk starting
-- that animation early. Instead we freeze movement + actions via GetCanControl (HandleButtons
-- zeroes the move and strips inputs) and freeze the view via a no-op UpdateViewAngles. Runs shared
-- (client / predict / server) so movement prediction stays in sync. Gated on the synced enabled
-- flag so sv_spawnselect false reverts fully to vanilla.
local function GetIsCountdownFrozen(player)
	if player:GetIsOnPlayingTeam() then
		local gameInfo = GetGameInfoEntity()
		if gameInfo and gameInfo:GetSpawnSelectionEnabled() and gameInfo:GetState() == kGameState.Countdown then
			return true
		end
	end
	return false
end

local originalPlayerGetCanControl
originalPlayerGetCanControl = Class_ReplaceMethod("Player", "GetCanControl",
	function(self)
		if GetIsCountdownFrozen(self) then
			return false
		end
		return originalPlayerGetCanControl(self)
	end
)

local originalPlayerUpdateViewAngles
originalPlayerUpdateViewAngles = Class_ReplaceMethod("Player", "UpdateViewAngles",
	function(self, input)
		if GetIsCountdownFrozen(self) then
			return
		end
		return originalPlayerUpdateViewAngles(self, input)
	end
)
