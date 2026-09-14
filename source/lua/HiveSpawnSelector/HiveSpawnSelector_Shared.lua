-- Hive Spawn Selector
-- lua/HiveSpawnSelector/HiveSpawnSelector_Shared.lua
--
-- Shared definitions: the spawn-selection network message and two synced GameInfo
-- fields the commander UI reads (whether selection is enabled, and the currently
-- selected tech point). Loaded on both client and server.
--
-- GameInfo extension pattern adapted from the NSL plugin:
-- https://github.com/xToken/NSL - lua/NSL/gameinfo/shared.lua - by Dragon

Script.Load("lua/HiveSpawnSelector/HiveSpawnSelector_Utility.lua")

-- Client -> Server: the alien commander's chosen tech point (-1 means "random / clear").
Shared.RegisterNetworkMessage("HiveSpawnSelector_SelectSpawn", { techPointId = "entityid" })

-- Server -> alien team: relays the commander's pick as a team chat message (-1 means the pick
-- was cleared / random). marineSpawnNames is a comma-separated list of every legal marine spawn
-- for the pick (not just the one actually chosen - see AnnounceSelection), empty when not
-- applicable. See HiveSpawnSelector_Server.lua's AnnounceSelection and HiveSpawnSelector_Client.lua's
-- OnAnnounceMessage.
Shared.RegisterNetworkMessage("HiveSpawnSelector_Announce", { techPointId = "entityid", marineSpawnNames = "string (256)" })

-- Vanilla only defines TechPoint:GetTeamNumberAllowed() inside an "if Server then" block,
-- so the method does not exist on the client even though the allowedTeamNumber networkVar is
-- synced. Define a shared getter so the commander UI can read it client-side. (NSL does the same.)
function TechPoint:GetTeamNumberAllowed()
	return self.allowedTeamNumber
end

local networkVars =
{
	spawnSelectionEnabled = "boolean",
	spawnSelected = "entityid",
	-- Comma-separated lowercase location names of the alien-legal spawns for this round, as
	-- decided by Shine's CustomSpawns plugin when it's present and configured for the current map
	-- (see HiveSpawnSelector_Server.lua). Empty otherwise, in which case the client falls back to
	-- GetTeamNumberAllowed().
	legalAlienSpawns = "string (256)"
}

local originalGameInfoOnCreate
originalGameInfoOnCreate = Class_ReplaceMethod("GameInfo", "OnCreate",
	function(self)
		originalGameInfoOnCreate(self)

		if Server then
			self.spawnSelectionEnabled = true
			self.spawnSelected = Entity.invalidId
			self.legalAlienSpawns = ""
		end

	end
)

function GameInfo:GetSpawnSelectionEnabled()
	return self.spawnSelectionEnabled
end

function GameInfo:GetSelectedSpawn()
	return self.spawnSelected
end

function GameInfo:GetLegalAlienSpawns()
	return self.legalAlienSpawns
end

if Server then

	function GameInfo:SetSpawnSelectionEnabled(enabled)
		self.spawnSelectionEnabled = enabled == true
	end

	function GameInfo:SetSelectedSpawn(techPointId)
		self.spawnSelected = techPointId
	end

	function GameInfo:SetLegalAlienSpawns(commaSeparatedNames)
		self.legalAlienSpawns = commaSeparatedNames or ""
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
