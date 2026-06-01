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

-- Pre-round freeze.
-- Vanilla freezes players (no movement, no view changes) only during kGameState.Countdown
-- (see Player:OnProcessMove, which keys off GetCountdownActive). We extend that freeze to the
-- preceding kGameState.PreGame so field players are rooted for the whole pre-round wait instead
-- of walking around / looking about while the spawn is being chosen. The commander is exempt so
-- they can still set up their base. This runs shared (client / predict / server) so movement
-- prediction stays in sync. Gated on the synced enabled flag so sv_spawnselect false fully reverts.
local originalPlayerGetCountdownActive
originalPlayerGetCountdownActive = Class_ReplaceMethod("Player", "GetCountdownActive",
	function(self)
		if self:GetIsOnPlayingTeam() and not self:GetIsCommander() then
			local gameInfo = GetGameInfoEntity()
			if gameInfo and gameInfo:GetSpawnSelectionEnabled() and gameInfo:GetState() == kGameState.PreGame then
				return true
			end
		end
		return originalPlayerGetCountdownActive(self)
	end
)
